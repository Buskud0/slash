local config = require "config"
local Input = require "input"
local Physics = require "physics"
local Network = require "network"
local Renderer = require "renderer"
local Server = require "server"
local Chat = require "chat"

-- Game orchestration state
local game_state = "connecting"
local connection_retry_timer = 0.2

-- Local player data
local local_player = {
    x = 0,
    y = 0,
    height = config.PLAYER_STAND_HEIGHT,
    facing = 1,
    attack_timer = 0,
    attack_id = 0,
    health = config.MAX_HEALTH
}

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
-- Uses the attack type (swing vs stab) and angle to locate the contact point.
local function get_sword_tip(player)
    local center_x = player.x + (config.SPRITE_SIZE / 2)
    local center_y = player.y + (player.height / 2)
    local timer = player.attack_timer
    
    if timer > 0 then
        -- SWING: Trigonometric sweep
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local facing = math.cos(player.facing) >= 0 and 1 or -1
        local s_dir = math.sin(player.facing) > 0.01 and -1 or 1
        local sweep = player.facing + s_dir * facing * (math.pi / 4) - progress * s_dir * facing * (math.pi / 2)
        
        -- Compute direction of sword motion (tangent vector) to apply knockback direction
        local rot_dir = -s_dir * facing
        local contact_angle = sweep + (rot_dir * math.pi / 2)
        
        local tip_x = center_x + math.cos(sweep) * config.SWORD_LENGTH
        local tip_y = center_y + math.sin(sweep) * config.SWORD_LENGTH
        return tip_x, tip_y, contact_angle
    else
        -- STAB: Linear thrust
        local progress = (config.STAB_DURATION - math.abs(timer)) / config.STAB_DURATION
        local radius = math.sin(progress * math.pi) * config.SWORD_LENGTH
        
        local tip_x = center_x + math.cos(player.facing) * radius
        local tip_y = center_y + math.sin(player.facing) * radius
        return tip_x, tip_y, player.facing
    end
end

-- Utility function to check intersection between the sword's segment and player bounding box
local function check_line_collision(cx, cy, tx, ty, bx, by, bw, bh)
    -- Sample 4 points along the line segment from center (cx, cy) to tip (tx, ty)
    for i = 0, 3 do
        local t = i / 3
        local px = cx + (tx - cx) * t
        local py = cy + (ty - cy) * t
        
        -- Check if point lies inside the bounding box
        if px >= bx and px <= bx + bw and py >= by and py <= by + bh then
            return true
        end
    end
    return false
end

-- Checks if any guest player's weapon intersects with the local player
local function check_collisions()
    if not my_id then return end
    
    local bx = local_player.x
    local by = local_player.y
    local bw = config.SPRITE_SIZE
    local bh = local_player.height
    
    for id, p in pairs(network_players) do
        -- Check only other players who are actively attacking (attack_timer != 0)
        if id ~= my_id and p.attack_timer and math.abs(p.attack_timer) > 0 then
            -- Verify if we've already registered a hit for this specific attack sequence
            local attack_id = p.attack_id or 0
            if last_hit_by[id] ~= attack_id then
                local tx, ty, contact_angle = get_sword_tip(p)
                local cx = p.x + (config.SPRITE_SIZE / 2)
                local cy = p.y + (p.height / 2)
                
                if check_line_collision(cx, cy, tx, ty, bx, by, bw, bh) then
                    -- Record this attack_id as processed to prevent double-hitting
                    last_hit_by[id] = attack_id
                    
                    -- Apply knockback in the direction of the sword's impact vector
                    Physics.apply_knockback(contact_angle)
                    
                    -- Calculate and apply damage based on attack type (swing vs stab)
                    local damage = (p.attack_timer > 0) and config.SWING_DAMAGE or config.STAB_DAMAGE
                    Physics.take_damage(damage)
                    break
                end
            end
        end
    end
end

-- Checks if the local player's weapon intersects with any other guest players.
-- If a hit occurs, resets the cooldown of the opposite attack type.
local function check_local_player_hits()
    if not my_id or local_player.attack_timer == 0 then return end
    
    local tx, ty, contact_angle = get_sword_tip(local_player)
    local cx = local_player.x + (config.SPRITE_SIZE / 2)
    local cy = local_player.y + (local_player.height / 2)
    
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
                    
                    -- Trigger cooldown refunds for opposite attack type
                    if local_player.attack_timer > 0 then
                        -- Swing hit -> clear stab cooldown
                        Physics.clear_stab_cooldown()
                    elseif local_player.attack_timer < 0 then
                        -- Stab hit -> clear swing cooldown
                        Physics.clear_swing_cooldown()
                    end
                end
            end
        end
    end
end

-- Client loop processing: handles inputs, movement, server communication, and collision checks
local function run_client(dt)
    local input_state = {
        dx = 0, dy = 0,
        jump = false, dash = false, crouch = false,
        attack = false, stab = false
    }
    
    -- Block input polling when typing in chat
    if not Chat.is_typing then
        input_state = Input.get_state()
    end

    -- Run physics simulation and update local player state
    local_player = Physics.update(dt, input_state)
    
    -- Sync with server and update remote players' statuses
    local players, id, lost = Network.update(local_player)
    network_players, my_id = players, id

    check_collisions()
    check_local_player_hits()

    -- Auto-reconnect if connection was severed
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
        network_players, my_id = Network.update(local_player)
        
        if my_id then
            game_state = "client_only"
        elseif connection_retry_timer <= 0 then
            -- If no server is found, host the server and connect locally
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
        Renderer.draw(local_player, network_players, my_id)
        Chat.draw()
    end
end

-- Love2D Text input callback (relayed to Chat)
function love.textinput(text)
    if game_state == "client_only" or game_state == "host_and_client" then
        Chat.textinput(text)
    end
end

-- Love2D Keypressed callback (relayed to Chat, sends out chat messages on return)
function love.keypressed(key)
    if game_state == "client_only" or game_state == "host_and_client" then
        local msg = Chat.keypressed(key)
        if msg then
            Network.send_chat(msg)
        end
    end
end

-- Love2D Mouse Scroll callback (relayed to Chat)
function love.wheelmoved(x, y)
    if game_state == "client_only" or game_state == "host_and_client" then
        Chat.wheelmoved(y)
    end
end

-- Love2D Application Shutdown callback
function love.quit()
    if game_state == "host_and_client" then 
        Server.quit() 
    end
    if game_state == "client_only" or game_state == "host_and_client" then 
        Network.quit() 
    end
end