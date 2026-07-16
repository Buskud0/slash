local enet = require "enet"
local config = require "config"
local Chat = require "chat"

local Network = { host = nil, server = nil, my_id = nil, players = {} }

function Network.init()
    Network.host = enet.host_create()
    Network.server = Network.host:connect(config.SERVER_IP .. ":" .. config.PORT)
    Network.server:timeout(0, 1000, 3000)
end

function Network.send_chat(text)
    if Network.server then
        Network.server:send("chat:" .. text, 0, "reliable")
    end
end

local function parse_state(payload)
    local active = {}
    for p_data in string.gmatch(payload, "([^|]+)") do
        local id, px, py, ph, pf, pa = p_data:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
        if id and px and py and ph and pf and pa then
            active[id] = { 
                x = tonumber(px), 
                y = tonumber(py), 
                height = tonumber(ph), 
                -- Decode the integer value back to facing direction or float angle
                facing = tonumber(pf) / 100, 
                attack_timer = tonumber(pa) / 100 
            }
        end
    end
    Network.players = active
end

function Network.update(local_x, local_y, local_height, local_facing, local_attack_timer)
    if Network.server and Network.my_id then
        local h = math.floor(local_height)
        -- Encode facing value as an integer (safe for both 1/-1 and exact float angles)
        local f = math.floor(local_facing * 100)
        local att = math.floor(local_attack_timer * 100)
        local payload = "pos:" .. math.floor(local_x) .. "," .. math.floor(local_y) .. "," .. h .. "," .. f .. "," .. att
        Network.server:send(payload, 0, "unreliable")
    end

    local event = Network.host:service(0)
    while event do
        if event.type == "receive" then
            local data = event.data
            if data:sub(1, 3) == "id:" then
                Network.my_id = data:sub(4)
            elseif data:sub(1, 6) == "state:" then
                parse_state(data:sub(7))
            elseif data:sub(1, 4) == "msg:" then
                Chat.add(data:sub(5))
            end
        elseif event.type == "disconnect" then
            Network.my_id = nil
            Network.players = {}
            Network.server = nil
            lost_connection = true
        end
        event = Network.host:service(0)
    end

    return Network.players, Network.my_id, lost_connection
end

function Network.quit()
    if Network.server then
        Network.server:disconnect()
        Network.host:service(100)
    end
end

return Network