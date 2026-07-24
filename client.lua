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

local network_players = {}
local my_id = nil
local is_host = false

ActiveProjectiles = {}

local function build_render_list()
    local list = {}
    table.insert(list, { key = "local", entity = local_player, name = local_player.name, show_health = true, is_local = true })
    for id, p in pairs(network_players) do
        if id ~= my_id then
            table.insert(list, { key = id, entity = p, name = p.name, show_health = true })
        end
    end
    for i, bot in ipairs(bots) do
        table.insert(list, { key = "bot_" .. i, entity = bot, name = bot.name, show_health = not bot.invincible })
    end
    return list
end

local function encode_bots(bot_list)
    local settings = Menu.get_settings()
    local parts = {}
    for _, b in ipairs(bot_list) do
        b.invincible = settings.invincible
        table.insert(parts, Helpers.encode_entity(b))
    end
    return table.concat(parts, "|")
end

local function decode_bots(data)
    local result = {}
    if not data or #data == 0 then return result end
    for bd in data:gmatch("([^|]+)") do
        local entity = Helpers.decode_entity(bd)
        if entity then
            table.insert(result, entity)
        end
    end
    return result
end

local function run_client(dt)
    local cmd

    if Chat.is_typing or Menu.is_open then
        cmd = Controllers.empty_cmd()
    else
        cmd = Controllers.Local.get_cmd()
    end

    local_player:update(dt, cmd)

    local players, id, lost, pending_damage, pending_pull, pending_bots, pending_toggle = Network.update(Player.to_view(local_player))
    network_players, my_id = players, id

    for id, p in pairs(network_players) do
        p.mainColor = {1, 0.6, 0}
        p.name = "Guest " .. id
    end

    is_host = (game_state == "host_and_client")

    Menu.set_bots_enabled(bots_enabled)

    if Menu.consume_toggle_bots() then
        Client.try_toggle_bots()
    end

    if pending_toggle then
        Network.pending_toggle = false
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
            else
                bots = {}
            end
            Chat.add(bots_enabled and "Bots enabled" or "Bots disabled")
        else
            Chat.add("Bots toggled by host")
        end
    end

    if is_host then
        local settings = Menu.get_settings()
        local enemies = {}
        table.insert(enemies, local_player)
        for oid, p in pairs(network_players) do
            if oid ~= my_id then
                table.insert(enemies, p)
            end
        end
        for i, bot in ipairs(bots) do
            bot.invincible = settings.invincible
            local bot_cmd = Controllers.Bot.get_cmd(bot, enemies, settings, dt)
            bot:update(dt, bot_cmd)
            bot:updateState()
        end
        Network.send_bots(encode_bots(bots))
    else
        if pending_bots ~= nil then
            local decoded = decode_bots(pending_bots)
            bots = {}
            for _, raw in ipairs(decoded) do
                raw.mainColor = {0.5, 0.5, 0.5}
                raw.name = "Bot"
                table.insert(bots, raw)
            end
            Network.pending_bots = nil
        end
    end

    if pending_damage then
        if pending_damage.target_id and Helpers.is_bot_id(pending_damage.target_id) then
            if is_host then
                local bi = tonumber(pending_damage.target_id:sub(5))
                local bot = bots[bi]
                if bot then
                    local dmg = bot:applyEffect("net_damage", {
                        amount = pending_damage.amount,
                        angle = pending_damage.knockback,
                        force = pending_damage.force,
                        attacker_vx = pending_damage.attacker_vx,
                        attack_type = pending_damage.attack_type,
                        slow = pending_damage.slow,
                    })
                    if dmg > 0 then
                        Renderer.add_damage(bot.x, bot.y, dmg)
                    end
                end
            end
        else
            local dmg = local_player:applyEffect("net_damage", {
                amount = pending_damage.amount,
                angle = pending_damage.knockback,
                force = pending_damage.force,
                attacker_vx = pending_damage.attacker_vx,
                attack_type = pending_damage.attack_type,
                slow = pending_damage.slow,
            })
            Renderer.add_damage(local_player.x, local_player.y, dmg, {1, 0.3, 0.3})
        end
        Network.pending_damage = nil
    end

    if pending_pull then
        if pending_pull.target_id and Helpers.is_bot_id(pending_pull.target_id) then
            local bi = tonumber(pending_pull.target_id:sub(5))
            local bot = bots[bi]
            if bot and is_host then
                bot:applyPull(pending_pull.x, pending_pull.y, pending_pull.dx, pending_pull.dy)
            end
        else
            local_player:applyPull(pending_pull.x, pending_pull.y, pending_pull.dx, pending_pull.dy)
        end
        Network.pending_pull = nil
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

    if lost then
        game_state = "connecting"
        connection_retry_timer = 0.2
        network_players, my_id = {}, nil
        bots = {}
        bots_enabled = false
        Combat.reset_tracking()
        Chat.add("Connection lost! Reconnecting...")
    end
end

function Client.try_toggle_bots()
    if is_host then
        Network.send_toggle_bots()
    else
        Chat.add("Only the host can toggle bots")
    end
end

function Client.init()
    love.graphics.setDefaultFilter("nearest", "nearest")
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

function Client.draw()
    if game_state == "connecting" then
        love.graphics.print("Searching for game...", 20, 20)
    else
        local render_list = build_render_list()
        Renderer.draw(render_list)
        Renderer.draw_cooldowns(local_player)
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
