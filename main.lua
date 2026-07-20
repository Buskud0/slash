local config = require "config"
local Input = require "input"
local Player = require "player"
local Physics = require "physics"
local Network = require "network"
local Renderer = require "renderer"
local Server = require "server"
local Chat = require "chat"
local Bot = require "bot"

-- Game orchestration state
local game_state = "connecting"
local connection_retry_timer = 0.2

-- Local player data
local local_player = Player.new()

-- Bot list
local bots = {}
local bots_enabled = false

-- Network player data
local network_players = {}
local my_id = nil

-- Tracks the last attack_id processed from each player to prevent multiple hits from the same attack
local last_hit_by = {}

-- Tracks the last attack_id that hit a specific guest player from the local player
local last_hit_targets = {}

-- Love2D Initial Load callback
function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    Network.init()
end

-- Calculates the tip coordinates of a player's sword for collision checking.
local function get_sword_tip(player)
    local center_x = player.x + (config.SPRITE_SIZE / 2)
    local center_y = player.y + (player.height / 2)
    local timer = player.attack_timer
    local at = player.attack_type
    local face = player.view_facing or player.facing

    if at == "stab_left" or at == "stab_right" or at == "stab_up" or at == "stab_down" then
        local duration = config.STAB_DURATION
        local progress = (duration - math.abs(timer)) / duration
        local radius = math.sin(progress * math.pi) * config.STAB_LENGTH
        local tip_x = center_x + math.cos(face) * radius
        local tip_y = center_y + math.sin(face) * radius
        return tip_x, tip_y, face

    elseif at == "swing_up_left" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = math.pi - progress * (math.pi / 2)
        local tip_x = center_x + math.cos(sweep) * config.SWING_LENGTH
        local tip_y = center_y + math.sin(sweep) * config.SWING_LENGTH
        return tip_x, tip_y, 3 * math.pi / 4

    elseif at == "swing_up_right" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = progress * (math.pi / 2)
        local tip_x = center_x + math.cos(sweep) * config.SWING_LENGTH
        local tip_y = center_y + math.sin(sweep) * config.SWING_LENGTH
        return tip_x, tip_y, math.pi / 4

    elseif at == "swing_down_left" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = math.pi + progress * (math.pi / 2)
        local tip_x = center_x + math.cos(sweep) * config.SWING_LENGTH
        local tip_y = center_y + math.sin(sweep) * config.SWING_LENGTH
        return tip_x, tip_y, -3 * math.pi / 4

    elseif at == "swing_down_right" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = -progress * (math.pi / 2)
        local tip_x = center_x + math.cos(sweep) * config.SWING_LENGTH
        local tip_y = center_y + math.sin(sweep) * config.SWING_LENGTH
        return tip_x, tip_y, -math.pi / 4

    else
        return center_x, center_y, player.facing
    end
end

local function check_line_collision(cx, cy, tx, ty, bx, by, bw, bh)
    for i = 1, 3 do
        local t = i / 3
        local px = cx + (tx - cx) * t
        local py = cy + (ty - cy) * t
        
        if px >= bx and px <= bx + bw and py >= by and py <= by + bh then
            return true
        end
    end
    return false
end

local function check_collisions()
    local bx = local_player.x
    local by = local_player.y
    local bw = config.SPRITE_SIZE
    local bh = local_player.height
    
    for id, p in pairs(network_players) do
        if id ~= my_id and p.attack_timer and math.abs(p.attack_timer) > 0 then
            local attack_id = p.attack_id or 0
            if last_hit_by[id] ~= attack_id then
                local tx, ty, contact_angle = get_sword_tip(p)
                local cx = p.x + (config.SPRITE_SIZE / 2)
                local cy = p.y + (p.height / 2)
                
                if check_line_collision(cx, cy, tx, ty, bx, by, bw, bh) then
                    last_hit_by[id] = attack_id
                    Physics.apply_knockback(local_player, contact_angle)
                    
                    local at = p.attack_type or ""
                    local damage = config.SWING_DAMAGE
                    if at:sub(1, 4) == "stab" then
                        damage = config.STAB_DAMAGE
                    end
                    Physics.take_damage(local_player, damage)
                    break
                end
            end
        end
    end

    -- Bot collisions: network players hitting bots
    for id, p in pairs(network_players) do
        if p.attack_timer and math.abs(p.attack_timer) > 0 then
            local attack_id = p.attack_id or 0
            local hit_key = id .. "_bots"
            if last_hit_by[hit_key] ~= attack_id then
                for bi, bot in ipairs(bots) do
                    local bx2 = bot.x
                    local by2 = bot.y
                    local bw2 = config.SPRITE_SIZE
                    local bh2 = bot.height
                    local tx, ty, contact_angle = get_sword_tip(p)
                    local cx = p.x + (config.SPRITE_SIZE / 2)
                    local cy = p.y + (p.height / 2)
                    if check_line_collision(cx, cy, tx, ty, bx2, by2, bw2, bh2) then
                        last_hit_by[hit_key] = attack_id
                        local at = p.attack_type or ""
                        local damage = config.SWING_DAMAGE
                        if at:sub(1, 4) == "stab" then
                            damage = config.STAB_DAMAGE
                        end
                        Physics.apply_knockback(bot, contact_angle)
                        Physics.take_damage(bot, damage)
                        break
                    end
                end
            end
        end
    end

    -- Bot bullets hitting local player
    for bi, bot in ipairs(bots) do
        for i = #bot.bullets, 1, -1 do
            local b = bot.bullets[i]
            if b.x >= bx and b.x <= bx + bw and b.y >= by and b.y <= by + bh then
                local kb_angle = math.atan2(b.dy, b.dx)
                Physics.apply_knockback(local_player, kb_angle, config.BULLET_KNOCKBACK_FORCE)
                Physics.take_damage(local_player, config.BULLET_DAMAGE)
                Physics.remove_bullet(bot, i)
                break
            end
        end
    end
end

local function check_local_player_hits()
    if local_player.attack_timer == 0 then return end
    
    local tx, ty, contact_angle = get_sword_tip(local_player)
    local cx = local_player.x + (config.SPRITE_SIZE / 2)
    local cy = local_player.y + (local_player.height / 2)
    
    -- Local player hitting network players
    for id, p in pairs(network_players) do
        if id ~= my_id then
            local bx = p.x
            local by = p.y
            local bw = config.SPRITE_SIZE
            local bh = p.height or config.PLAYER_STAND_HEIGHT
            
            if check_line_collision(cx, cy, tx, ty, bx, by, bw, bh) then
                local attack_id = local_player.attack_id or 0
                if last_hit_targets[id] ~= attack_id then
                    last_hit_targets[id] = attack_id
                end
            end
        end
    end

    -- Local player hitting bots
    for bi, bot in ipairs(bots) do
        local bx = bot.x
        local by = bot.y
        local bw = config.SPRITE_SIZE
        local bh = bot.height
        
        if check_line_collision(cx, cy, tx, ty, bx, by, bw, bh) then
            local attack_id = local_player.attack_id or 0
            local hit_key = "bot_" .. bi
            if last_hit_targets[hit_key] ~= attack_id then
                last_hit_targets[hit_key] = attack_id
                local at = local_player.attack_type or ""
                local damage = config.SWING_DAMAGE
                if at:sub(1, 4) == "stab" then
                    damage = config.STAB_DAMAGE
                end
                Physics.apply_knockback(bot, contact_angle)
                Physics.take_damage(bot, damage)
            end
        end
    end
end

local function check_sword_deflects_bullets()
    if local_player.attack_timer == 0 then return end

    local tx, ty = get_sword_tip(local_player)
    local cx = local_player.x + (config.SPRITE_SIZE / 2)
    local cy = local_player.y + (local_player.height / 2)

    for bi, bot in ipairs(bots) do
        for i = #bot.bullets, 1, -1 do
            local b = bot.bullets[i]
            local half = config.BULLET_SIZE / 2
            if check_line_collision(cx, cy, tx, ty, b.x - half, b.y - half, config.BULLET_SIZE, config.BULLET_SIZE) then
                Physics.remove_bullet(bot, i)
            end
        end
    end
end

local function check_bullet_hits()
    -- Local player bullets hitting network players
    for i = #local_player.bullets, 1, -1 do
        local b = local_player.bullets[i]
        for id, p in pairs(network_players) do
            if id ~= my_id then
                local bx = p.x
                local by = p.y
                local bw = config.SPRITE_SIZE
                local bh = p.height or config.PLAYER_STAND_HEIGHT
                
                if b.x >= bx and b.x <= bx + bw and b.y >= by and b.y <= by + bh then
                    local kb_angle = math.atan2(b.dy, b.dx)
                    Network.send_damage(id, config.BULLET_DAMAGE, kb_angle, config.BULLET_KNOCKBACK_FORCE)
                    Physics.remove_bullet(local_player, i)
                    break
                end
            end
        end
    end

    -- Local player bullets hitting bots
    for i = #local_player.bullets, 1, -1 do
        local b = local_player.bullets[i]
        for bi, bot in ipairs(bots) do
            local bx = bot.x
            local by = bot.y
            local bw = config.SPRITE_SIZE
            local bh = bot.height

            if b.x >= bx and b.x <= bx + bw and b.y >= by and b.y <= by + bh then
                local kb_angle = math.atan2(b.dy, b.dx)
                Physics.apply_knockback(bot, kb_angle, config.BULLET_KNOCKBACK_FORCE)
                Physics.take_damage(bot, config.BULLET_DAMAGE)
                Physics.remove_bullet(local_player, i)
                break
            end
        end
    end
end

local function check_hook_hits(dt)
    if not local_player.hook then return end
    
    local h = local_player.hook
    local cx = local_player.x + (config.SPRITE_SIZE / 2)
    local cy = local_player.y + (local_player.height / 2)

    if h.target_id then
        local is_bot = h.target_id:sub(1, 4) == "bot_"
        local p
        if is_bot then
            local bi = tonumber(h.target_id:sub(5))
            p = bots[bi]
        else
            p = network_players[h.target_id]
        end
        if p then
            local ex = p.x + (config.SPRITE_SIZE / 2)
            local ey = p.y + (p.height or config.PLAYER_STAND_HEIGHT) / 2
            local dist = math.sqrt((cx - ex) ^ 2 + (cy - ey) ^ 2)
            if h.initial_dist == 0 or dist <= h.initial_dist * 0.3 then
                local_player.hook = nil
            elseif is_bot then
                Physics.apply_pull(p, cx, cy, h.dx, h.dy)
            else
                Network.send_pull(h.target_id, cx, cy, h.dx, h.dy)
            end
        else
            local_player.hook = nil
        end
        return
    end

    -- Hook hitting network players
    for id, p in pairs(network_players) do
        if id ~= my_id then
            local bx = p.x
            local by = p.y
            local bw = config.SPRITE_SIZE
            local bh = p.height or config.PLAYER_STAND_HEIGHT
            
            if h.x >= bx and h.x <= bx + bw and h.y >= by and h.y <= by + bh then
                local_player.hook.target_id = id
                local_player.hook.x = bx + bw / 2
                local_player.hook.y = by + bh / 2
                local ex = bx + bw / 2
                local ey = by + bh / 2
                local_player.hook.initial_dist = math.sqrt((cx - ex) ^ 2 + (cy - ey) ^ 2)
                break
            end
        end
    end

    -- Hook hitting bots
    if not local_player.hook.target_id then
        for bi, bot in ipairs(bots) do
            local bx = bot.x
            local by = bot.y
            local bw = config.SPRITE_SIZE
            local bh = bot.height

            if h.x >= bx and h.x <= bx + bw and h.y >= by and h.y <= by + bh then
                local_player.hook.target_id = "bot_" .. bi
                local_player.hook.x = bx + bw / 2
                local_player.hook.y = by + bh / 2
                local ex = bx + bw / 2
                local ey = by + bh / 2
                local_player.hook.initial_dist = math.sqrt((cx - ex) ^ 2 + (cy - ey) ^ 2)
                break
            end
        end
    end
end

local function update_hook_tracking()
    if local_player.hook and local_player.hook.target_id then
        local tid = local_player.hook.target_id
        local p = network_players[tid]
        if p then
            local_player.hook.x = p.x + (config.SPRITE_SIZE / 2)
            local_player.hook.y = p.y + (p.height or config.PLAYER_STAND_HEIGHT) / 2
        elseif tid:sub(1, 4) == "bot_" then
            local bi = tonumber(tid:sub(5))
            local bot = bots[bi]
            if bot then
                local_player.hook.x = bot.x + (config.SPRITE_SIZE / 2)
                local_player.hook.y = bot.y + (bot.height / 2)
            end
        end
    end
end

-- Client loop processing
local function run_client(dt)
    local input_state = {
        dx = 0, dy = 0,
        jump = false, dash = false, crouch = false,
        attackStab = false, attackSlash = false, shootBullet = false, hook = false,
        mouse_x = 0, mouse_y = 0
    }
    
    if not Chat.is_typing then
        input_state = Input.get_state()
    end

    Physics.update(local_player, dt, input_state)

    -- Update bots
    local enemies = {}
    if my_id then
        table.insert(enemies, local_player)
    end
    for id, p in pairs(network_players) do
        if id ~= my_id then
            table.insert(enemies, p)
        end
    end

    for i, bot in ipairs(bots) do
        local bot_input = Bot.get_input(bot, enemies)
        Physics.update(bot, dt, bot_input)
    end

    local players, id, lost, pending_damage, pending_pull = Network.update(Player.to_view(local_player))
    network_players, my_id = players, id

    if pending_damage then
        Physics.take_damage(local_player, pending_damage.amount)
        if pending_damage.knockback ~= 0 then
            Physics.apply_knockback(local_player, pending_damage.knockback, pending_damage.force)
        end
        Network.pending_damage = nil
    end

    if pending_pull then
        Physics.apply_pull(local_player, pending_pull.x, pending_pull.y, pending_pull.dx, pending_pull.dy)
        Network.pending_pull = nil
    end

    check_collisions()
    check_local_player_hits()
    check_sword_deflects_bullets()
    check_bullet_hits()
    update_hook_tracking()
    check_hook_hits(dt)

    if lost then
        game_state = "connecting"
        connection_retry_timer = 0.2
        network_players, my_id = {}, nil
        last_hit_by = {}
        last_hit_targets = {}
        Chat.add("Connection lost! Reconnecting...")
    end
end

-- Love2D Update loop callback
function love.update(dt)
    if game_state == "connecting" then
        connection_retry_timer = connection_retry_timer - dt
        network_players, my_id = Network.update(Player.to_view(local_player))
        
        if my_id then
            game_state = "client_only"
        elseif connection_retry_timer <= 0 then
            game_state = "host_and_client"
            Network.quit()
            Server.init()
            Network.init()
        end
    else
        if game_state == "host_and_client" then 
            Server.update(dt) 
        end
        run_client(dt)
        Chat.update(dt)
    end
end

-- Love2D Draw callback
function love.draw()
    if game_state == "connecting" then
        love.graphics.print("Searching for game...", 20, 20)
    else
        Renderer.draw(local_player, network_players, my_id, bots)
        Chat.draw()
    end
end

function love.textinput(text)
    if game_state == "client_only" or game_state == "host_and_client" then
        Chat.textinput(text)
    end
end

function love.keypressed(key)
    if game_state == "client_only" or game_state == "host_and_client" then
        if key == "p" and not Chat.is_typing then
            bots_enabled = not bots_enabled
            if bots_enabled then
                for i = 1, config.BOT_COUNT do
                    local bx = config.SPAWN_X + 80 + (i - 1) * 40
                    local by = config.SPAWN_Y
                    bots[i] = Player.new(bx, by)
                end
            else
                bots = {}
            end
            return
        end
        local msg = Chat.keypressed(key)
        if msg then
            Network.send_chat(msg)
        end
    end
end

function love.wheelmoved(x, y)
    if game_state == "client_only" or game_state == "host_and_client" then
        Chat.wheelmoved(y)
    end
end

function love.quit()
    if game_state == "host_and_client" then 
        Server.quit() 
    end
    if game_state == "client_only" or game_state == "host_and_client" then 
        Network.quit() 
    end
end
