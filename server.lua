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
    
    Server.clients[id] = { 
        raw_pos = "",
        peer = peer 
    }
    
    add_log("Player Guest " .. id .. " joined")
end

local function on_receive(id, data)
    local client = Server.clients[id]
    if not client then return end

    if data:sub(1, 4) == "pos:" then
        client.raw_pos = data:sub(5)
    elseif data:sub(1, 5) == "chat:" then
        local chat_msg = data:sub(6)
        add_log("Guest " .. id .. ": " .. chat_msg)
    elseif data:sub(1, 7) == "damage:" then
        local parts = data:sub(8)
        local target_id, amount, angle, force, slow = parts:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
        if target_id and amount and angle and force then
            local target = Server.clients[target_id]
            if target and target.peer then
                local s = slow or "0"
                target.peer:send("damage:" .. amount .. "," .. angle .. "," .. force .. "," .. s, 0, "reliable")
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
    local parts = {}
    for id, client in pairs(Server.clients) do
        if client.raw_pos and #client.raw_pos > 0 then
            table.insert(parts, id .. ":" .. client.raw_pos)
        end
    end
    if #parts > 0 then
        Server.host:broadcast("state:" .. table.concat(parts, "|"), 0, "unreliable")
    end
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
