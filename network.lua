local enet = require "enet"
local config = require "config"
local Chat = require "chat"

local Network = { 
    host = nil, 
    server = nil, 
    my_id = nil, 
    players = {},
    pending_damage = nil,
    pending_pull = nil
}

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

function Network.send_damage(target_id, amount, angle, force)
    if Network.server then
        local payload = string.format("damage:%s,%.2f,%.4f,%.2f",
            target_id, amount, angle, force)
        Network.server:send(payload, 0, "reliable")
    end
end

function Network.send_pull(target_id, target_x, target_y, hook_dx, hook_dy)
    if Network.server then
        local payload = string.format("pull:%s,%.2f,%.2f,%.4f,%.4f",
            target_id, target_x, target_y, hook_dx, hook_dy)
        Network.server:send(payload, 0, "reliable")
    end
end

local function parse_state(payload)
    local active = {}
    for player_data in string.gmatch(payload, "([^|]+)") do
        local id, px, py, ph, pf, pa, pat, paid, phealth = player_data:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
        if id and px and py and ph and pf and pa and pat and paid and phealth then
            active[id] = { 
                x = tonumber(px), 
                y = tonumber(py), 
                height = tonumber(ph), 
                facing = tonumber(pf) / 100, 
                attack_timer = tonumber(pa) / 100,
                attack_type = pat ~= "none" and pat or nil,
                attack_id = tonumber(paid) or 0,
                health = tonumber(phealth) or config.MAX_HEALTH
            }
        end
    end
    Network.players = active
end

function Network.update(local_player)
    local lost_connection = false

    if Network.server and Network.my_id and local_player then
        local height = math.floor(local_player.height)
        local facing = math.floor(local_player.facing * 100)
        local attack_timer = math.floor(local_player.attack_timer * 100)
        local attack_type = local_player.attack_type or "none"
        
        local payload = string.format("pos:%d,%d,%d,%d,%d,%s,%d,%d", 
            math.floor(local_player.x), 
            math.floor(local_player.y), 
            height, 
            facing, 
            attack_timer,
            attack_type,
            local_player.attack_id or 0,
            local_player.health or config.MAX_HEALTH
        )
        Network.server:send(payload, 0, "unreliable")
    end

    if Network.host then
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
                elseif data:sub(1, 7) == "damage:" then
                    local parts = data:sub(8)
                    local amount, angle, force = parts:match("([^,]+),([^,]+),([^,]+)")
                    if amount and angle and force then
                        Network.pending_damage = {
                            amount = tonumber(amount),
                            knockback = tonumber(angle),
                            force = tonumber(force)
                        }
                    end
                elseif data:sub(1, 5) == "pull:" then
                    local parts = data:sub(6)
                    local tx, ty, dx, dy = parts:match("([^,]+),([^,]+),([^,]+),([^,]+)")
                    if tx and ty and dx and dy then
                        Network.pending_pull = {
                            x = tonumber(tx),
                            y = tonumber(ty),
                            dx = tonumber(dx),
                            dy = tonumber(dy)
                        }
                    end
                end
            elseif event.type == "disconnect" then
                Network.my_id = nil
                Network.players = {}
                Network.server = nil
                lost_connection = true
            end
            event = Network.host:service(0)
        end
    end

    return Network.players, Network.my_id, lost_connection, Network.pending_damage, Network.pending_pull
end

function Network.quit()
    if Network.server then
        Network.server:disconnect()
        Network.host:service(100)
    end
end

return Network
