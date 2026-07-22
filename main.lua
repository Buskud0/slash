local config = require "config"
local Input = require "input"
local Player = require "player"
local Physics = require "physics"
local Network = require "network"
local Renderer = require "renderer"
local Server = require "server"
local Chat = require "chat"
local Bot = require "bot"
local Menu = require "menu"
local Helpers = require "helpers"

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

local is_host = false

local function try_toggle_bots()
    if is_host then
        Network.send_toggle_bots()
    else
        Chat.add("Only the host can toggle bots")
    end
end

-- Love2D Initial Load callback
function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    Network.init()
end

local function check_line_collision(cx, cy, tx, ty, bx, by, bw, bh)
    local function point_in_rect(px, py)
        return px >= bx and px <= bx + bw and py >= by and py <= by + bh
    end

    if point_in_rect(tx, ty) then return true end

    local steps = 10
    for i = 1, steps - 1 do
        local t = i / steps
        local px = cx + (tx - cx) * t
        local py = cy + (ty - cy) * t
        if point_in_rect(px, py) then return true end
    end

    local function seg_cross_edge(ex1, ey1, ex2, ey2)
        local d1x, d1y = tx - cx, ty - cy
        local d2x, d2y = ex2 - ex1, ey2 - ey1
        local cross = d1x * d2y - d1y * d2x
        if math.abs(cross) < 1e-10 then return false end
        local ox, oy = ex1 - cx, ey1 - cy
        local t = (ox * d2y - oy * d2x) / cross
        local u = (ox * d1y - oy * d1x) / cross
        return t >= 0 and t <= 1 and u >= 0 and u <= 1
    end

    if seg_cross_edge(bx, by, bx + bw, by) then return true end
    if seg_cross_edge(bx, by + bh, bx + bw, by + bh) then return true end
    if seg_cross_edge(bx, by, bx, by + bh) then return true end
    if seg_cross_edge(bx + bw, by, bx + bw, by + bh) then return true end

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
                local tx, ty, contact_angle = Helpers.get_sword_tip(p)
                local cx, cy = Helpers.get_player_center(p)
                
                if check_line_collision(cx, cy, tx, ty, bx, by, bw, bh) then
                    last_hit_by[id] = attack_id
                    break
                end
            end
        end
    end

    -- Bot collisions: network players hitting bots
    for id, p in pairs(network_players) do
        if id ~= my_id and p.attack_timer and math.abs(p.attack_timer) > 0 then
            local attack_id = p.attack_id or 0
            local hit_key = id .. "_bots"
            if last_hit_by[hit_key] ~= attack_id then
                for bi, bot in ipairs(bots) do
                    local bx2 = bot.x
                    local by2 = bot.y
                    local bw2 = config.SPRITE_SIZE
                    local bh2 = bot.height
                    local tx, ty, contact_angle = Helpers.get_sword_tip(p)
                    local cx, cy = Helpers.get_player_center(p)
                    if check_line_collision(cx, cy, tx, ty, bx2, by2, bw2, bh2) then
                        last_hit_by[hit_key] = attack_id
                        local at = p.attack_type or ""
                        local damage = Helpers.get_attack_damage(at)
                        Physics.apply_knockback(bot, contact_angle, nil, p.air_velocity_x, at)
                        if not Menu.get_settings().invincible then
                            Physics.take_damage(bot, damage)
                        end
                        Renderer.add_damage(bot.x, bot.y, damage)
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
                local kb_angle
                if b.dx and b.dy then
                    kb_angle = math.atan2(b.dy, b.dx)
                else
                    kb_angle = math.atan2(b.y - (by + bh / 2), b.x - (bx + bw / 2))
                end
                Physics.apply_knockback(local_player, kb_angle, config.NET_KNOCKBACK_FORCE)
                Physics.apply_net_slow(local_player)
                Physics.remove_bullet(bot, i)
                break
            end
        end
    end

    -- Bot sword attacks hitting local player
    for bi, bot in ipairs(bots) do
        if bot.attack_timer and math.abs(bot.attack_timer) > 0 then
            local attack_id = bot.attack_id or 0
            local hit_key = "bot_" .. bi
            if last_hit_by[hit_key] ~= attack_id then
                local tx, ty, contact_angle = Helpers.get_sword_tip(bot)
                local cx, cy = Helpers.get_player_center(bot)

                if check_line_collision(cx, cy, tx, ty, bx, by, bw, bh) then
                    last_hit_by[hit_key] = attack_id
                    local at = bot.attack_type or ""
                    Physics.apply_knockback(local_player, contact_angle, nil, bot.air_velocity_x, at)

                    local damage = Helpers.get_attack_damage(at)
                    Physics.take_damage(local_player, damage)
                    Renderer.add_damage(local_player.x, local_player.y, damage, {1, 0.3, 0.3})
                end
            end
        end
    end
end

local function check_local_player_hits()
    if local_player.attack_timer == 0 then return end
    
    local tx, ty, contact_angle = Helpers.get_sword_tip(local_player)
    local cx, cy = Helpers.get_player_center(local_player)
    
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
                    local_player.attack_landed = true
                    local at = local_player.attack_type or ""
                    local damage = Helpers.get_attack_damage(at)
                    Network.send_damage(id, damage, contact_angle, config.KNOCKBACK_FORCE, 0, local_player.air_velocity_x, at)
                    Renderer.add_damage(p.x, p.y, damage)
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
                        local_player.attack_landed = true
                        local at = local_player.attack_type or ""
                        local damage = Helpers.get_attack_damage(at)
                        Physics.apply_knockback(bot, contact_angle, nil, local_player.air_velocity_x, at)
                        if not Menu.get_settings().invincible then
                            Physics.take_damage(bot, damage)
                        end
                        Renderer.add_damage(bot.x, bot.y, damage)
                    end
                end
    end
end

local function check_projectile_collisions()
    local half_hook = config.HOOK_SIZE / 2
    local half_net = config.NET_SIZE / 2

    local hooks = {}
    if local_player.hook then
        hooks[#hooks + 1] = { h = local_player.hook, owner = "local", remove = function() local_player.hook = nil end }
    end
    for bi, bot in ipairs(bots) do
        if bot.hook then
            local idx = bi
            hooks[#hooks + 1] = { h = bot.hook, owner = "bot", remove = function() bots[idx].hook = nil end }
        end
    end
    for id, p in pairs(network_players) do
        if id ~= my_id and p.hook then
            local pid = id
            hooks[#hooks + 1] = { h = p.hook, owner = "net", id = pid, remove = function() if network_players[pid] then network_players[pid].hook = nil end end }
        end
    end

    local bullets = {}
    for i, b in ipairs(local_player.bullets) do
        local idx = i
        bullets[#bullets + 1] = { b = b, owner = "local", remove = function() Physics.remove_bullet(local_player, idx) end }
    end
    for bi, bot in ipairs(bots) do
        for i, b in ipairs(bot.bullets) do
            local bii, ii = bi, i
            bullets[#bullets + 1] = { b = b, owner = "bot", remove = function() Physics.remove_bullet(bots[bii], ii) end }
        end
    end
    for id, p in pairs(network_players) do
        if id ~= my_id and p.bullets then
            for i, b in ipairs(p.bullets) do
                local pid, ii = id, i
                bullets[#bullets + 1] = { b = b, owner = "net", id = pid, remove = function() if network_players[pid] and network_players[pid].bullets then table.remove(network_players[pid].bullets, ii) end end }
            end
        end
    end

    local function hook_bullet_close(hb, bb)
        return math.abs(hb.x - bb.x) < half_hook + half_net and math.abs(hb.y - bb.y) < half_hook + half_net
    end

    local removed_hooks = {}
    local removed_bullets = {}

    for hi = 1, #hooks do
        if not removed_hooks[hi] then
            for bi = 1, #bullets do
                if not removed_bullets[bi] then
                    if hook_bullet_close(hooks[hi].h, bullets[bi].b) then
                        local hx, hy = hooks[hi].h.x, hooks[hi].h.y
                        local bx, by = bullets[bi].b.x, bullets[bi].b.y
                        Renderer.add_clash((hx + bx) / 2, (hy + by) / 2)
                        removed_hooks[hi] = true
                        removed_bullets[bi] = true
                    end
                end
            end
        end
    end

    for hi = 1, #hooks do
        if not removed_hooks[hi] then
            for hj = hi + 1, #hooks do
                if not removed_hooks[hj] then
                    local a, b = hooks[hi].h, hooks[hj].h
                    if math.abs(a.x - b.x) < half_hook * 2 and math.abs(a.y - b.y) < half_hook * 2 then
                        Renderer.add_clash((a.x + b.x) / 2, (a.y + b.y) / 2)
                        removed_hooks[hi] = true
                        removed_hooks[hj] = true
                    end
                end
            end
        end
    end

    for bi = 1, #bullets do
        if not removed_bullets[bi] then
            for bj = bi + 1, #bullets do
                if not removed_bullets[bj] then
                    local a, b = bullets[bi].b, bullets[bj].b
                    if math.abs(a.x - b.x) < config.NET_SIZE and math.abs(a.y - b.y) < config.NET_SIZE then
                        Renderer.add_clash((a.x + b.x) / 2, (a.y + b.y) / 2)
                        removed_bullets[bi] = true
                        removed_bullets[bj] = true
                    end
                end
            end
        end
    end

    local swords = {}
    if local_player.attack_timer ~= 0 then
        local tx, ty = Helpers.get_sword_tip(local_player)
        local cx, cy = Helpers.get_player_center(local_player)
        swords[#swords + 1] = { cx = cx, cy = cy, tx = tx, ty = ty, owner = "local" }
    end
    for bi, bot in ipairs(bots) do
        if bot.attack_timer ~= 0 then
            local tx, ty = Helpers.get_sword_tip(bot)
            local cx, cy = Helpers.get_player_center(bot)
            swords[#swords + 1] = { cx = cx, cy = cy, tx = tx, ty = ty, owner = "bot" }
        end
    end
    for id, p in pairs(network_players) do
        if id ~= my_id and p.attack_timer and math.abs(p.attack_timer) > 0 then
            local tx, ty = Helpers.get_sword_tip(p)
            local cx, cy = Helpers.get_player_center(p)
            swords[#swords + 1] = { cx = cx, cy = cy, tx = tx, ty = ty, owner = "net" }
        end
    end

    for _, sw in ipairs(swords) do
        for hi = 1, #hooks do
            if not removed_hooks[hi] and hooks[hi].owner ~= sw.owner then
                local hk = hooks[hi].h
                local hk_half = config.HOOK_SIZE / 2
                if check_line_collision(sw.cx, sw.cy, sw.tx, sw.ty, hk.x - hk_half, hk.y - hk_half, config.HOOK_SIZE, config.HOOK_SIZE) then
                    Renderer.add_clash((sw.tx + hk.x) / 2, (sw.ty + hk.y) / 2)
                    removed_hooks[hi] = true
                end
            end
        end
        for bi = 1, #bullets do
            if not removed_bullets[bi] and bullets[bi].owner ~= sw.owner then
                local bb = bullets[bi].b
                if check_line_collision(sw.cx, sw.cy, sw.tx, sw.ty, bb.x - half_net, bb.y - half_net, config.NET_SIZE, config.NET_SIZE) then
                    Renderer.add_clash((sw.tx + bb.x) / 2, (sw.ty + bb.y) / 2)
                    removed_bullets[bi] = true
                end
            end
        end
    end

    local removed_swords = {}
    for i = 1, #swords do
        for j = i + 1, #swords do
            if not removed_swords[i] and not removed_swords[j] then
                local a, b = swords[i], swords[j]
                local dx1, dy1 = a.tx - a.cx, a.ty - a.cy
                local dx2, dy2 = b.tx - b.cx, b.ty - b.cy
                local denom = dx1 * dy2 - dy1 * dx2
                if math.abs(denom) > 0.0001 then
                    local t = ((b.cx - a.cx) * dy2 - (b.cy - a.cy) * dx2) / denom
                    local u = ((b.cx - a.cx) * dy1 - (b.cy - a.cy) * dx1) / denom
                    if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
                        local ix = a.cx + dx1 * t
                        local iy = a.cy + dy1 * t
                        Renderer.add_clash(ix, iy)
                        removed_swords[i] = true
                        removed_swords[j] = true
                    end
                end
            end
        end
    end
    for si, _ in pairs(removed_swords) do
        local sw = swords[si]
        if sw.owner == "local" then
            local_player.attack_timer = 0
            local_player.attack_type = nil
        elseif sw.owner == "bot" then
            local bi = nil
            for ii, b in ipairs(bots) do
                if b.x + config.SPRITE_SIZE / 2 == sw.cx then bi = ii; break end
            end
            if bi then bots[bi].attack_timer = 0; bots[bi].attack_type = nil end
        elseif sw.owner == "net" and sw.id then
            if network_players[sw.id] then
                network_players[sw.id].attack_timer = 0
                network_players[sw.id].attack_type = nil
            end
        end
    end

    for hi, _ in pairs(removed_hooks) do
        hooks[hi].remove()
    end
    for bi, _ in pairs(removed_bullets) do
        bullets[bi].remove()
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
                    Network.send_damage(id, 0, kb_angle, config.NET_KNOCKBACK_FORCE, config.NET_SLOW_DURATION)
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
                    Network.send_damage("bot_" .. bi, 0, kb_angle, config.NET_KNOCKBACK_FORCE, config.NET_SLOW_DURATION)
                    if is_host then
                        Physics.apply_knockback(bot, kb_angle, config.NET_KNOCKBACK_FORCE)
                        Physics.apply_net_slow(bot)
                    end
                    Physics.remove_bullet(local_player, i)
                break
            end
        end
    end
end

local function check_hook_hits(dt)
    if not local_player.hook then return end
    
    local h = local_player.hook
    local cx, cy = Helpers.get_player_center(local_player)

    if h.target_id then
        local is_bot = Helpers.is_bot_id(h.target_id)
        local p
        if is_bot then
            local bi = tonumber(h.target_id:sub(5))
            p = bots[bi]
        else
            p = network_players[h.target_id]
        end
        if p then
            local ex, ey = Helpers.get_player_center(p)
            local dist = math.sqrt((cx - ex) ^ 2 + (cy - ey) ^ 2)
            if h.initial_dist == 0 or dist <= h.initial_dist * 0.3 then
                local_player.hook = nil
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
                local ex, ey = Helpers.get_player_center(p)
                local_player.hook.x = ex
                local_player.hook.y = ey
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
                local ex, ey = Helpers.get_player_center(bot)
                local_player.hook.x = ex
                local_player.hook.y = ey
                local_player.hook.initial_dist = math.sqrt((cx - ex) ^ 2 + (cy - ey) ^ 2)
                break
            end
        end
    end
end

local function check_bot_hook_hits()
    for bi, bot in ipairs(bots) do
        if not bot.hook then goto continue_bot end

        local h = bot.hook
        local bcx, bcy = Helpers.get_player_center(bot)

        if h.target_id then
            local target
            if h.target_id == "local" then
                target = local_player
            else
                target = network_players[h.target_id]
            end
            if target then
                local tx, ty = Helpers.get_player_center(target)
                h.x = tx
                h.y = ty
                local d = math.sqrt((bcx - h.x) ^ 2 + (bcy - h.y) ^ 2)
                if h.initial_dist == 0 or d <= h.initial_dist * 0.3 then
                    bot.hook = nil
                else
                    if h.target_id == "local" then
                        Physics.apply_pull(local_player, bcx, bcy, h.dx, h.dy)
                    else
                        Network.send_pull(h.target_id, bcx, bcy, h.dx, h.dy)
                    end
                end
            else
                bot.hook = nil
            end
            goto continue_bot
        end

        local lpx, lpy = Helpers.get_player_center(local_player)
        if math.abs(h.x - lpx) < config.SPRITE_SIZE and
           math.abs(h.y - lpy) < local_player.height then
            h.target_id = "local"
            h.x = lpx
            h.y = lpy
            h.initial_dist = math.sqrt((bcx - h.x) ^ 2 + (bcy - h.y) ^ 2)
            goto continue_bot
        end

        for id, p in pairs(network_players) do
            if id ~= my_id then
                local bx = p.x
                local by = p.y
                local bw = config.SPRITE_SIZE
                local bh = p.height or config.PLAYER_STAND_HEIGHT
                if h.x >= bx and h.x <= bx + bw and h.y >= by and h.y <= by + bh then
                    h.target_id = id
                    local ex, ey = Helpers.get_player_center(p)
                    h.x = ex
                    h.y = ey
                    h.initial_dist = math.sqrt((bcx - h.x) ^ 2 + (bcy - h.y) ^ 2)
                    break
                end
            end
        end

        ::continue_bot::
    end
end

local function update_hook_tracking()
    if local_player.hook and local_player.hook.target_id then
        local tid = local_player.hook.target_id
        local p = network_players[tid]
        if p then
            local hx, hy = Helpers.get_player_center(p)
            local_player.hook.x = hx
            local_player.hook.y = hy
        elseif Helpers.is_bot_id(tid) then
            local bi = tonumber(tid:sub(5))
            local bot = bots[bi]
            if bot then
                local hx, hy = Helpers.get_player_center(bot)
                local_player.hook.x = hx
                local_player.hook.y = hy
            end
        end
    end
end

local function encode_bots(bot_list)
    local parts = {}
    for _, b in ipairs(bot_list) do
        local s = string.format("%d,%d,%d,%d,%d,%s,%d,%d,%d,%.1f",
            math.floor(b.x), math.floor(b.y),
            math.floor(b.height),
            math.floor((b.view_facing or b.facing) * 100),
            math.floor(b.attack_timer * 100),
            b.attack_type or "none",
            b.attack_id or 0,
            b.health or config.MAX_HEALTH,
            math.floor((b.slow_timer or 0) * 100),
            (b.dash_timer or 0) * 100)
        if #b.bullets > 0 then
            s = s .. ",b:"
            for i, bul in ipairs(b.bullets) do
                if i > 1 then s = s .. "," end
                s = s .. math.floor(bul.x) .. "," .. math.floor(bul.y)
            end
        else
            s = s .. ",b:"
        end
        if b.hook then
            s = s .. ",k:" .. math.floor(b.hook.x) .. "," .. math.floor(b.hook.y)
                .. "," .. string.format("%.2f", b.hook.dx) .. "," .. string.format("%.2f", b.hook.dy)
        else
            s = s .. ",k:"
        end
        table.insert(parts, s)
    end
    return table.concat(parts, "|")
end

local function decode_bots(data)
    local result = {}
    if not data or #data == 0 then return result end
    for bd in data:gmatch("([^|]+)") do
        local x, y, h, f, a, at, aid, hp, pslow, pDash = bd:match(
            "([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
        if x then
            local bot = {
                x = tonumber(x), y = tonumber(y),
                height = tonumber(h),
                facing = tonumber(f) / 100,
                attack_timer = tonumber(a) / 100,
                attack_type = at ~= "none" and at or nil,
                attack_id = tonumber(aid) or 0,
                health = tonumber(hp) or config.MAX_HEALTH,
                slow_timer = tonumber(pslow) or 0,
                dash_timer = (tonumber(pDash) or 0) / 100,
                bullets = {}, hook = nil
            }
            local bs = bd:match(",b:(.-),k:")
            if not bs then bs = bd:match(",b:([^|]*)") end
            if bs and #bs > 0 then
                local idx = 1
                for bx, by in bs:gmatch("([^,]+),([^,]+)") do
                    bot.bullets[idx] = { x = tonumber(bx), y = tonumber(by) }
                    idx = idx + 1
                end
            end
            local hs = bd:match(",k:([^|]*)")
            if hs and #hs > 0 then
                local hx, hy, hdx, hdy = hs:match("([^,]+),([^,]+),([^,]+),([^,]+)")
                if hx and hy then
                    bot.hook = { x = tonumber(hx), y = tonumber(hy),
                        dx = tonumber(hdx) or 0, dy = tonumber(hdy) or 0 }
                end
            end
            table.insert(result, bot)
        end
    end
    return result
end

-- Client loop processing
local function run_client(dt)
    local input_state = {
        dx = 0, dy = 0,
        jump = false, dash = false, crouch = false,
        attackStab = false, attackSlash = false, shootBullet = false, hook = false,
        mouse_x = 0, mouse_y = 0
    }
    
    if not Chat.is_typing and not Menu.is_open then
        input_state = Input.get_state()
    end

    Physics.update(local_player, dt, input_state)

    local players, id, lost, pending_damage, pending_pull, pending_bots, pending_toggle = Network.update(Player.to_view(local_player))
    network_players, my_id = players, id

    is_host = (game_state == "host_and_client")

    Menu.set_bots_enabled(bots_enabled)

    if Menu.consume_toggle_bots() then
        try_toggle_bots()
    end

    if pending_toggle then
        Network.pending_toggle = false
        if is_host then
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
            Chat.add(bots_enabled and "Bots enabled" or "Bots disabled")
        else
            Chat.add("Bots toggled by host")
        end
    end

    if is_host then
        local enemies = {}
        table.insert(enemies, local_player)
        for oid, p in pairs(network_players) do
            if oid ~= my_id then
                table.insert(enemies, p)
            end
        end
        for i, bot in ipairs(bots) do
            local bot_input = Bot.get_input(bot, enemies, Menu.get_settings(), dt)
            Physics.update(bot, dt, bot_input)
        end
        Network.send_bots(encode_bots(bots))
    else
        if pending_bots ~= nil then
            bots = decode_bots(pending_bots)
            Network.pending_bots = nil
        end
    end

    if pending_damage then
        if pending_damage.target_id and Helpers.is_bot_id(pending_damage.target_id) then
            if is_host then
                local bi = tonumber(pending_damage.target_id:sub(5))
                local bot = bots[bi]
                if bot then
                    Physics.apply_knockback(bot, pending_damage.knockback, pending_damage.force, pending_damage.attacker_vx, pending_damage.attack_type)
                    Physics.apply_net_slow(bot, pending_damage.slow)
                end
            end
        else
            Physics.take_damage(local_player, pending_damage.amount)
            Renderer.add_damage(local_player.x, local_player.y, pending_damage.amount, {1, 0.3, 0.3})
            Physics.apply_knockback(local_player, pending_damage.knockback, pending_damage.force, pending_damage.attacker_vx, pending_damage.attack_type)
            if pending_damage.slow and pending_damage.slow > 0 then
                Physics.apply_net_slow(local_player, pending_damage.slow)
            end
        end
        Network.pending_damage = nil
    end

    if pending_pull then
        if pending_pull.target_id and Helpers.is_bot_id(pending_pull.target_id) then
            local bi = tonumber(pending_pull.target_id:sub(5))
            local bot = bots[bi]
            if bot and is_host then
                Physics.apply_pull(bot, pending_pull.x, pending_pull.y, pending_pull.dx, pending_pull.dy)
            end
        else
            Physics.apply_pull(local_player, pending_pull.x, pending_pull.y, pending_pull.dx, pending_pull.dy)
        end
        Network.pending_pull = nil
    end

    check_collisions()
    check_local_player_hits()
    check_projectile_collisions()
    check_bullet_hits()
    update_hook_tracking()
    check_hook_hits(dt)
    if is_host then
        check_bot_hook_hits()
    end

    if lost then
        game_state = "connecting"
        connection_retry_timer = 0.2
        network_players, my_id = {}, nil
        bots = {}
        bots_enabled = false
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
        Renderer.update_damage_texts(dt)
        Chat.update(dt)
    end
end

-- Love2D Draw callback
function love.draw()
    if game_state == "connecting" then
        love.graphics.print("Searching for game...", 20, 20)
    else
        Renderer.draw(local_player, network_players, my_id, bots)
        Menu.draw()
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
        if Menu.is_open then
            Menu.keypressed(key)
            return
        end
        if key == "escape" then
            Menu.toggle()
            return
        end
        if key == "p" and not Chat.is_typing and (game_state == "host_and_client" or game_state == "client_only") then
            try_toggle_bots()
            return
        end
        local msg = Chat.keypressed(key)
        if msg then
            Network.send_chat(msg)
        end
    end
end

function love.mousepressed(x, y, button)
    if Menu.is_open then
        Menu.mousepressed(x, y)
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
