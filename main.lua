local Input = require "input"
local Physics = require "physics"
local Network = require "network"
local Renderer = require "renderer"
local Server = require "server"
local Chat = require "chat"

local state = "connecting"
local timer = 0.2
local local_x, local_y = 0, 0
local local_height = 24
local local_facing = 1
local local_attack_timer = 0
local network_players = {}
local my_id = nil

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    Network.init()
end

local function get_sword_tip(p)
    local cx = p.x + 8
    local cy = p.y + (p.height / 2)
    local timer = p.attack_timer
    if timer > 0 then
        local progress = (0.12 - timer) / 0.12
        local facing = math.cos(p.facing) >= 0 and 1 or -1
        local s_dir = math.sin(p.facing) > 0.01 and -1 or 1
        local sweep = p.facing + s_dir * facing * (math.pi / 4) - progress * s_dir * facing * (math.pi / 2)
        
        -- Calculate the exact tangent angle (direction of the sword's movement)
        local rot_dir = -s_dir * facing
        local contact_angle = sweep + (rot_dir * math.pi / 2)
        
        return cx + math.cos(sweep) * 38, cy + math.sin(sweep) * 38, contact_angle
    else
        local progress = (0.15 - math.abs(timer)) / 0.15
        local r = math.sin(progress * math.pi) * 38
        return cx + math.cos(p.facing) * r, cy + math.sin(p.facing) * r, p.facing
    end
end

local function check_line_collision(cx, cy, tx, ty, bx, by, bw, bh)
    for i = 0, 3 do
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
    if not my_id then return end
    local bx, by, bw, bh = local_x, local_y, 16, local_height
    for id, p in pairs(network_players) do
        if id ~= my_id and p.attack_timer and math.abs(p.attack_timer) > 0 then
            local tx, ty, contact_angle = get_sword_tip(p)
            local cx = p.x + 8
            local cy = p.y + (p.height / 2)
            if check_line_collision(cx, cy, tx, ty, bx, by, bw, bh) then
                -- Apply knockback along the sword's actual movement vector on contact
                Physics.apply_knockback(contact_angle)
                break
            end
        end
    end
end

local function run_client(dt)
    local dx, dy, jump, dash, fast_fall, crouch, attack, stab = 0, 0, false, false, false, false, false, false
    
    if not Chat.is_typing then
        dx, dy = Input.get_movement()
        jump = Input.get_jump()
        dash, fast_fall, crouch, attack, stab = Input.get_actions()
    end

    local x, y, h, f, att = Physics.update(dt, dx, dy, jump, dash, fast_fall, crouch, attack, stab)
    local_x, local_y, local_height, local_facing, local_attack_timer = x, y, h, f, att
    
    local players, id, lost = Network.update(local_x, local_y, local_height, local_facing, local_attack_timer)
    network_players, my_id = players, id

    check_collisions()

    if lost then
        state = "connecting"
        timer = 0.2
        network_players, my_id = {}, nil
        Chat.add("Connection lost! Reconnecting...")
    end
end

function love.update(dt)
    if state == "connecting" then
        timer = timer - dt
        network_players, my_id = Network.update(local_x, local_y, local_height, local_facing, local_attack_timer)
        if my_id then
            state = "client_only"
        elseif timer <= 0 then
            state = "host_and_client"
            Network.quit()
            Server.init()
            Network.init()
        end
    else
        if state == "host_and_client" then Server.update(dt) end
        run_client(dt)
        Chat.update(dt)
    end
end

function love.draw()
    if state == "connecting" then
        love.graphics.print("Searching for game...", 20, 20)
    else
        Renderer.draw(local_x, local_y, local_height, local_facing, local_attack_timer, network_players, my_id)
        Chat.draw()
    end
end

function love.textinput(text)
    if state == "client_only" or state == "host_and_client" then
        Chat.textinput(text)
    end
end

function love.keypressed(key)
    if state == "client_only" or state == "host_and_client" then
        local msg = Chat.keypressed(key)
        if msg then
            Network.send_chat(msg)
        end
    end
end

function love.wheelmoved(x, y)
    if state == "client_only" or state == "host_and_client" then
        Chat.wheelmoved(y)
    end
end

function love.quit()
    if state == "host_and_client" then Server.quit() end
    if state == "client_only" or state == "host_and_client" then Network.quit() end
end