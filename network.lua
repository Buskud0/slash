local enet = require "enet"
local config = require "config"
local Chat = require "chat"
local Helpers = require "helpers"

local Network = { 
    host = nil, 
    server = nil, 
    my_id = nil, 
    players = {},
    pending_damage = nil,
    pending_pull = nil,
    pending_invincible = nil,
    pending_reset = nil
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

function Network.send_damage(target_id, amount, angle, force, slow, attacker_vx, attack_type)
    if Network.server then
        local s = slow or 0
        local avx = attacker_vx or 0
        local at = attack_type or ""
        local payload = string.format("damage:%s,%.2f,%.4f,%.2f,%.2f,%.2f,%s",
            target_id, amount, angle, force, s, avx, at)
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

function Network.send_inv(state)
    if Network.server then
        Network.server:send("inv:" .. (state and "1" or "0"), 0, "reliable")
    end
end

function Network.send_reset(score_a, score_b, winner)
    local w = "n"
    if winner == "left" then w = "l"
    elseif winner == "right" then w = "r"
    end
    if Network.server then
        Network.server:send("reset:" .. score_a .. "," .. score_b .. "," .. w, 0, "reliable")
    end
end

local function parse_state(payload)
    local active = {}
    for player_data in string.gmatch(payload, "([^|]+)") do
        local id_end = player_data:find(":")
        if id_end then
            local id = player_data:sub(1, id_end - 1)
            local raw = player_data:sub(id_end + 1)
            local view = Helpers.decode_entity(raw)
            if view then
                active[id] = view
            end
        end
    end
    Network.players = active
end

function Network.update(local_player)
    local lost_connection = false

    if Network.server and Network.my_id and local_player then
        local payload = "pos:" .. Helpers.encode_entity(local_player)
        Network.server:send(payload, 0, "unreliable")
    end

    if Network.host then
        local ok, event = pcall(Network.host.service, Network.host, 0)
        if ok and event then
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
                        local amount, angle, force, slow, avx, at = parts:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),(.*)")
                        if amount and angle and force then
                            Network.pending_damage = {
                                amount = tonumber(amount),
                                knockback = tonumber(angle),
                                force = tonumber(force),
                                slow = tonumber(slow) or 0,
                                attacker_vx = tonumber(avx) or 0,
                                attack_type = at or ""
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
                    elseif data:sub(1, 4) == "inv:" then
                        Network.pending_invincible = data:sub(5) == "1"
                    elseif data:sub(1, 6) == "reset:" then
                        Network.pending_reset = data:sub(7)
                    end
                elseif event.type == "disconnect" then
                    Network.my_id = nil
                    Network.players = {}
                    Network.server = nil
                    lost_connection = true
                end
                local ok2, next_event = pcall(Network.host.service, Network.host, 0)
                if not ok2 then break end
                event = next_event
            end
        end
    end

    return Network.players, Network.my_id, lost_connection, Network.pending_damage, Network.pending_pull, Network.pending_invincible, Network.pending_reset
end

function Network.quit()
    if Network.server then
        Network.server:disconnect()
        Network.host:service(100)
    end
end

return Network
