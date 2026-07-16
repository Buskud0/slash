local enet = require "enet"
local config = require "config"

local Server = { host = nil, clients = {}, logs = {} }

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

local function handle_events()
    local event = Server.host:service(0)
    while event do
        local id = tostring(event.peer:index())
        if event.type == "connect" then
            event.peer:send("id:" .. id, 0, "reliable")
            event.peer:timeout(0, 1000, 3000)
            for _, log in ipairs(Server.logs) do
                event.peer:send("msg:" .. log, 0, "reliable")
            end
            local start_h = tostring(config.PLAYER_STAND_HEIGHT)
            Server.clients[id] = { x = 40, y = 50, height = start_h, facing = "1", attacking = "0", peer = event.peer }
            add_log("Player Guest " .. id .. " joined")
        elseif event.type == "receive" then
            local prefix = event.data:sub(1, 4)
            if prefix == "pos:" then
                local x, y, h, f, a = event.data:sub(5):match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
                if x and y and h and f and a and Server.clients[id] then
                    Server.clients[id].x = x
                    Server.clients[id].y = y
                    Server.clients[id].height = h
                    Server.clients[id].facing = f
                    Server.clients[id].attacking = a
                end
            elseif event.data:sub(1, 5) == "chat:" then
                add_log("Guest " .. id .. ": " .. event.data:sub(6))
            end
        elseif event.type == "disconnect" then
            Server.clients[id] = nil
            add_log("Player Guest " .. id .. " disconnected")
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
        state = state .. id .. "," .. pos.x .. "," .. pos.y .. "," .. h .. "," .. f .. "," .. a .. "|"
    end
    Server.host:broadcast(state, 0, "unreliable")
end

function Server.update(dt)
    handle_events()
    broadcast_state()
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