local config = require "config"
local Player = require "player"
local Network = require "network"
local Renderer = require "renderer"
local Server = require "server"
local Chat = require "chat"
local Menu = require "menu"
local Helpers = require "helpers"
local Controllers = require "controllers"
local Combat = require "combat"

local Client = {}
local game_state = "connecting"
local connection_retry_timer = 0.2

local local_player = Player.new()
local_player.mainColor = {0, 0.75, 0}
local_player.name = "You"

local bots = {}
local bots_enabled = false
local last_broadcast_invincible = nil

local network_players = {}
local my_id = nil
local is_host = false

ActiveProjectiles = {}
local score_font_large
local score_font_small

local round_state = "waiting"
local freeze_timer = 0
local score_left = 0
local score_right = 0
local last_winner

local opponent

local function update_opponent()
    if #bots > 0 then
        opponent = bots[1]
    else
        opponent = nil
        for id, p in pairs(network_players) do
            if id ~= my_id then
                opponent = p
                break
            end
        end
    end
end

local function get_right_spawn_x()
    return love.graphics.getWidth() / config.ZOOM - config.SPRITE_SIZE - 40
end

local function reset_player_state(p, x, y)
    p.x = x
    p.y = y
    p.y_velocity = 0
    p.knockback_x = 0
    p.air_velocity_x = 0
    p.is_on_ground = false
    p.health = config.MAX_HEALTH
    p.hook = nil
    p.pull_toward = nil
    p.dash_timer = 0
    p.attack_timer = 0
    p.attack_type = nil
    p.combat_cooldown = 0
    p.slow_timer = 0
    p.hit_gravity_timer = 0
    p.bullets = {}
    p.bullet_cooldown = 0
    p.state = nil
end

local function trigger_round_reset()
    if round_state == "waiting" then
        score_left = 0
        score_right = 0
        last_winner = nil
    end
    local spawn_y = config.GROUND_Y - config.PLAYER_STAND_HEIGHT
    reset_player_state(local_player, config.SPAWN_X_LEFT, spawn_y)
    if opponent then
        reset_player_state(opponent, get_right_spawn_x(), spawn_y)
    end
    freeze_timer = config.FREEZE_DURATION
    round_state = "frozen"
    ActiveProjectiles = {}
    Combat.reset_tracking()
    if is_host then
        Network.send_reset(score_left, score_right, last_winner)
    end
end

local function on_lost_connection()
    game_state = "connecting"
    connection_retry_timer = 0.2
    network_players, my_id = {}, nil
    bots = {}
    bots_enabled = false
    local_player.invincible = false
    round_state = "waiting"
    score_left = 0
    score_right = 0
    last_winner = nil
    Combat.reset_tracking()
    Chat.add("Connection lost! Reconnecting...")
end

local function build_render_list()
    local list = {}
    table.insert(list, { key = "local", entity = local_player, name = local_player.name, show_health = not local_player.invincible, is_local = true })
    for id, p in pairs(network_players) do
        if id ~= my_id then
            table.insert(list, { key = id, entity = p, name = p.name, show_health = not p.invincible })
        end
    end
    for i, bot in ipairs(bots) do
        table.insert(list, { key = "bot_" .. i, entity = bot, name = bot.name, show_health = not bot.invincible })
    end
    return list
end

local function run_client(dt)
    local cmd

    if Chat.is_typing or Menu.is_open then
        cmd = Controllers.empty_cmd()
    else
        cmd = Controllers.Local.get_cmd()
    end

    local players, id, lost, pending_damage, pending_pull, pending_invincible, pending_reset = Network.update(Player.to_view(local_player))
    network_players, my_id = players, id
    update_opponent()
    if not opponent and round_state == "playing" then
        round_state = "waiting"
    end

    for id, p in pairs(network_players) do
        p.mainColor = {1, 0.6, 0}
        p.name = "Guest " .. id
    end

    is_host = (game_state == "host_and_client")

    Menu.set_bots_enabled(bots_enabled)

    if Menu.consume_toggle_bots() then
        Client.try_toggle_bots()
        update_opponent()
    end

    local bot_settings, bot_enemies
    if is_host then
        bot_settings = Menu.get_settings()
        bot_enemies = { local_player }
        for oid, p in pairs(network_players) do
            if oid ~= my_id then
                table.insert(bot_enemies, p)
            end
        end
        local lobby_inv = Menu.get_lobby_invincible()
        if lobby_inv ~= last_broadcast_invincible then
            last_broadcast_invincible = lobby_inv
            Network.send_inv(lobby_inv)
        end
        local_player.invincible = lobby_inv
        for i, bot in ipairs(bots) do
            bot.invincible = lobby_inv
        end
    end

    if pending_damage then
        local dmg = local_player:applyEffect("net_damage", {
            amount = pending_damage.amount,
            angle = pending_damage.knockback,
            force = pending_damage.force,
            attacker_vx = pending_damage.attacker_vx,
            attack_type = pending_damage.attack_type,
            slow = pending_damage.slow,
        })
        Renderer.add_damage(local_player.x, local_player.y, dmg, {1, 0.3, 0.3})
        Network.pending_damage = nil
    end

    if pending_pull then
        local_player:applyPull(pending_pull.x, pending_pull.y, pending_pull.dx, pending_pull.dy)
        Network.pending_pull = nil
    end

    if pending_invincible ~= nil then
        local_player.invincible = pending_invincible
        Network.pending_invincible = nil
    end

    if pending_reset then
        if not is_host then
            local s_left, s_right, w = pending_reset:match("([^,]+),([^,]+),(.)")
            if s_left and s_right then
                score_left = tonumber(s_left)
                score_right = tonumber(s_right)
                if w == "l" then
                    last_winner = "left"
                elseif w == "r" then
                    last_winner = "right"
                else
                    last_winner = nil
                end
            end
            local spawn_y = config.GROUND_Y - config.PLAYER_STAND_HEIGHT
            reset_player_state(local_player, get_right_spawn_x(), spawn_y)
            freeze_timer = config.FREEZE_DURATION
            round_state = "frozen"
            ActiveProjectiles = {}
            Combat.reset_tracking()
        end
        Network.pending_reset = nil
    end

    if round_state == "frozen" then
        freeze_timer = freeze_timer - dt
        if freeze_timer <= 0 then
            round_state = "playing"
        end
        if lost then on_lost_connection() end
        return
    end

    if is_host and round_state == "waiting" and opponent then
        trigger_round_reset()
    end

    local_player:update(dt, cmd)

    if is_host then
        for i, bot in ipairs(bots) do
            local bot_cmd = Controllers.Bot.get_cmd(bot, bot_enemies, bot_settings, dt)
            bot:update(dt, bot_cmd)
            bot:updateState()
        end
    end

    ActiveProjectiles = {}
    local function add_bullets(source, owner, is_bot_source)
        if not source then return end
        for _, proj in ipairs(source) do
            proj.owner = owner
            if is_bot_source then
                proj._is_bot_bullet = true
            end
            table.insert(ActiveProjectiles, proj)
        end
    end
    add_bullets(local_player.bullets, local_player)
    for _, bot in ipairs(bots) do
        add_bullets(bot.bullets, bot, true)
    end
    for id, p in pairs(network_players) do
        if id ~= my_id then
            add_bullets(p.bullets, p)
        end
    end

    Combat.run({
        local_player = local_player,
        network_players = network_players,
        my_id = my_id,
        bots = bots,
        is_host = is_host,
    }, dt)
    local_player:updateState()

    if is_host and round_state == "playing" then
        if local_player.health <= 0 then
            score_right = score_right + 1
            last_winner = "right"
            trigger_round_reset()
        end
        if opponent and opponent.health ~= nil and opponent.health <= 0 then
            score_left = score_left + 1
            last_winner = "left"
            trigger_round_reset()
        end
    end

    if lost then on_lost_connection() end
end

function Client.try_toggle_bots()
    if is_host then
        bots_enabled = not bots_enabled
        if bots_enabled then
            for i = 1, config.BOT_COUNT do
                local bx = config.SPAWN_X + 80 + (i - 1) * 40
                local by = config.SPAWN_Y
                local bot = Player.new(bx, by, {0.5, 0.5, 0.5})
                bot.speed_mult = config.BOT_SPEED_MULT
                bot.name = "Bot " .. i
                bots[i] = bot
            end
            update_opponent()
            trigger_round_reset()
        else
            bots = {}
            round_state = "waiting"
            update_opponent()
        end
        Combat.reset_tracking()
        Chat.add(bots_enabled and "Bots enabled" or "Bots disabled")
    else
        Chat.add("Only the host can toggle bots")
    end
end

function Client.init()
    love.graphics.setDefaultFilter("nearest", "nearest")
    score_font_large = love.graphics.newFont(128)
    score_font_small = love.graphics.newFont(24)
    Network.init()
end

function Client.update(dt)
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

local function draw_score()
    local w = love.graphics.getWidth()
    local font = round_state == "frozen" and score_font_large or score_font_small
    local prev = love.graphics.getFont()
    love.graphics.setFont(font)

    local t_left = tostring(score_left)
    local t_right = tostring(score_right)
    local dash = " - "
    local tw_l = font:getWidth(t_left)
    local tw_d = font:getWidth(dash)
    local tw_r = font:getWidth(t_right)
    local total_w = tw_l + tw_d + tw_r
    local y = 10
    local x = (w - total_w) / 2

    if last_winner == "left" then
        love.graphics.setColor(0, 1, 0)
    elseif last_winner == "right" then
        love.graphics.setColor(1, 0, 0)
    else
        love.graphics.setColor(1, 1, 1)
    end
    love.graphics.print(t_left, x, y)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print(dash, x + tw_l, y)

    if last_winner == "right" then
        love.graphics.setColor(0, 1, 0)
    elseif last_winner == "left" then
        love.graphics.setColor(1, 0, 0)
    else
        love.graphics.setColor(1, 1, 1)
    end
    love.graphics.print(t_right, x + tw_l + tw_d, y)

    love.graphics.setFont(prev)
end

function Client.draw()
    if game_state == "connecting" then
        love.graphics.print("Searching for game...", 20, 20)
    else
        local render_list = build_render_list()
        Renderer.draw(render_list)
        Renderer.draw_cooldowns(local_player)
        draw_score()
        Menu.draw()
        Chat.draw()
    end
end

function Client.is_active()
    return game_state == "client_only" or game_state == "host_and_client"
end

function Client.quit()
    if game_state == "host_and_client" then
        Server.quit()
    end
    if game_state == "client_only" or game_state == "host_and_client" then
        Network.quit()
    end
end

return Client
