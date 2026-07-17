local enet = require "enet"
local config = require "config"

local Server = { 
    host = nil, 
    clients = {}, 
    logs = {} 
}

-- Private Helper: Adds server-side logs and broadcasts them as system messages to all connected clients
local function add_log(msg)
    table.insert(Server.logs, msg)
    if #Server.logs > 5 then
        table.remove(Server.logs, 1)
    end
    if Server.host then
        Server.host:broadcast("msg:" .. msg, 0, "reliable")
    end
end

-- Initializes the network host to listen on all interfaces at the configured port
function Server.init()
    Server.host = enet.host_create("*:" .. config.PORT)
    add_log("hosting server on port " .. config.PORT)
end

-- Private Helper: Handles new client connection
local function on_connect(id, peer)
    peer:send("id:" .. id, 0, "reliable")
    peer:timeout(0, 1000, 3000)
    
    -- Send recent server messages to the newly connected player
    for _, log in ipairs(Server.logs) do
        peer:send("msg:" .. log, 0, "reliable")
    end
    
    -- Register the client with default starting positions and stats
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

-- Private Helper: Handles incoming data packets from clients
local function on_receive(id, data)
    local client = Server.clients[id]
    if not client then return end

    if data:sub(1, 4) == "pos:" then
        -- Format: "pos:x,y,height,facing,attack_timer,attack_type,attack_id,health"
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
        -- Format: "chat:message_content"
        local chat_msg = data:sub(6)
        add_log("Guest " .. id .. ": " .. chat_msg)
    end
end

-- Private Helper: Handles client disconnection
local function on_disconnect(id)
    Server.clients[id] = nil
    add_log("Player Guest " .. id .. " disconnected")
end

-- Private Helper: Pulls network events and dispatches them to their corresponding handlers
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

-- Private Helper: Broadcasts the updated coordinates and state of all clients to every client
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

-- Server tick logic: pulls incoming traffic, updates client positions, and broadcasts the world state
function Server.update(dt)
    if Server.host then
        handle_events()
        broadcast_state()
    end
end

-- Safely disconnects all clients and shuts down the server
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
