local enet = require "enet"
local config = require "config"

local Server = { 
    host = nil, 
    clients = {}, 
    logs = {} 
}

local function add_log(msg)
    table.insert(Server.logs, msg)
    if #Server.logs > 5 then
        table.remove(Server.logs, 1)
    end
    if Server.host then
        Server.host:broadcast("msg:" .. msg, 0, "reliable")
    end
end

function Server.init()
    Server.host = enet.host_create("*:" .. config.PORT)
    add_log("hosting server on port " .. config.PORT)
end

local function on_connect(id, peer)
    peer:send("id:" .. id, 0, "reliable")
    peer:timeout(0, 1000, 3000)
    
    for _, log in ipairs(Server.logs) do
        peer:send("msg:" .. log, 0, "reliable")
    end
    
    local start_h = tostring(config.PLAYER_STAND_HEIGHT)
    Server.clients[id] = { 
        x = config.SPAWN_X, 
        y = config.SPAWN_Y, 
        height = start_h, 
        facing = "1", 
        attacking = "0", 
        attack_type = "none",
        attack_id = "0",
        health = tostring(config.MAX_HEALTH),
        peer = peer 
    }
    
    add_log("Player Guest " .. id .. " joined")
end

local function on_receive(id, data)
    local client = Server.clients[id]
    if not client then return end

    if data:sub(1, 4) == "pos:" then
        local x, y, h, f, a, atype, aid, hp = data:sub(5):match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
        if x and y and h and f and a and atype and aid and hp then
            client.x = x
            client.y = y
            client.height = h
            client.facing = f
            client.attacking = a
            client.attack_type = atype
            client.attack_id = aid
            client.health = hp
        end
    elseif data:sub(1, 5) == "chat:" then
        local chat_msg = data:sub(6)
        add_log("Guest " .. id .. ": " .. chat_msg)
    elseif data:sub(1, 7) == "damage:" then
        local parts = data:sub(8)
        local target_id, amount, angle, force = parts:match("([^,]+),([^,]+),([^,]+),([^,]+)")
        if target_id and amount and angle and force then
            local target = Server.clients[target_id]
            if target and target.peer then
                target.peer:send("damage:" .. amount .. "," .. angle .. "," .. force, 0, "reliable")
            end
        end
    elseif data:sub(1, 5) == "pull:" then
        local parts = data:sub(6)
        local target_id, tx, ty, dx, dy = parts:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
        if target_id and tx and ty and dx and dy then
            local target = Server.clients[target_id]
            if target and target.peer then
                target.peer:send("pull:" .. tx .. "," .. ty .. "," .. dx .. "," .. dy, 0, "reliable")
            end
        end
    end
end

local function on_disconnect(id)
    Server.clients[id] = nil
    add_log("Player Guest " .. id .. " disconnected")
end

local function handle_events()
    local event = Server.host:service(0)
    while event do
        local id = tostring(event.peer:index())
        
        if event.type == "connect" then
            on_connect(id, event.peer)
        elseif event.type == "receive" then
            on_receive(id, event.data)
        elseif event.type == "disconnect" then
            on_disconnect(id)
        end
        
        event = Server.host:service(0)
    end
end

local function broadcast_state()
    local state = "state:"
    for id, pos in pairs(Server.clients) do
        local h = pos.height or tostring(config.PLAYER_STAND_HEIGHT)
        local f = pos.facing or "1"
        local a = pos.attacking or "0"
        local atype = pos.attack_type or "none"
        local aid = pos.attack_id or "0"
        local hp = pos.health or tostring(config.MAX_HEALTH)
        state = state .. id .. "," .. pos.x .. "," .. pos.y .. "," .. h .. "," .. f .. "," .. a .. "," .. atype .. "," .. aid .. "," .. hp .. "|"
    end
    Server.host:broadcast(state, 0, "unreliable")
end

function Server.update(dt)
    if Server.host then
        handle_events()
        broadcast_state()
    end
end

function Server.quit()
    if Server.host then
        for _, client in pairs(Server.clients) do
            if client.peer then
                client.peer:disconnect()
            end
        end
        Server.host:flush()
    end
end

return Server
