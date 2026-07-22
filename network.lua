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
    pending_bots = nil,
    pending_toggle = false
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

function Network.send_bots(data)
    if Network.server then
        Network.server:send("bots:" .. data, 0, "unreliable")
    end
end

function Network.send_toggle_bots()
    if Network.server then
        Network.server:send("toggle_bots:", 0, "reliable")
    end
end

local function parse_state(payload)
    local active = {}
    for player_data in string.gmatch(payload, "([^|]+)") do
        local id_end = player_data:find(":")
        if id_end then
            local id = player_data:sub(1, id_end - 1)
            local raw = player_data:sub(id_end + 1)

            local px, py, ph, pf, pa, pat, paid, phealth, pslow, pavx = raw:match(
                "([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
            if px and py and ph and pf and pa and pat and paid and phealth then
                local view = {
                    x = tonumber(px),
                    y = tonumber(py),
                    height = tonumber(ph),
                    facing = tonumber(pf) / 100,
                    attack_timer = tonumber(pa) / 100,
                    attack_type = pat ~= "none" and pat or nil,
                    attack_id = tonumber(paid) or 0,
                    health = tonumber(phealth) or config.MAX_HEALTH,
                    slow_timer = tonumber(pslow) or 0,
                    air_velocity_x = (tonumber(pavx) or 0) / 100,
                    bullets = {},
                    hook = nil
                }

                local bullets_str = raw:match(",b:(.-),k:")
                if not bullets_str then
                    bullets_str = raw:match(",b:([^|]*)")
                end
                if bullets_str and #bullets_str > 0 then
                    local idx = 1
                    for bx, by in bullets_str:gmatch("([^,]+),([^,]+)") do
                        view.bullets[idx] = { x = tonumber(bx), y = tonumber(by) }
                        idx = idx + 1
                    end
                end

                local hook_str = raw:match(",k:([^|]*)")
                if hook_str and #hook_str > 0 then
                    local hx, hy, hdx, hdy = hook_str:match("([^,]+),([^,]+),([^,]+),([^,]+)")
                    if hx and hy then
                        view.hook = {
                            x = tonumber(hx),
                            y = tonumber(hy),
                            dx = tonumber(hdx) or 0,
                            dy = tonumber(hdy) or 0
                        }
                    end
                end

                active[id] = view
            end
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
        local slow = math.floor((local_player.slow_timer or 0) * 100)

        local payload = string.format("pos:%d,%d,%d,%d,%d,%s,%d,%d,%d,%d",
            math.floor(local_player.x),
            math.floor(local_player.y),
            height,
            facing,
            attack_timer,
            attack_type,
            local_player.attack_id or 0,
            local_player.health or config.MAX_HEALTH,
            slow,
            math.floor((local_player.air_velocity_x or 0) * 100)
        )

        local bullets = local_player.bullets or {}
        if #bullets > 0 then
            payload = payload .. ",b:"
            for i, b in ipairs(bullets) do
                if i > 1 then payload = payload .. "," end
                payload = payload .. math.floor(b.x) .. "," .. math.floor(b.y)
            end
        else
            payload = payload .. ",b:"
        end

        local hook = local_player.hook
        if hook then
            payload = payload .. ",k:" .. math.floor(hook.x) .. "," .. math.floor(hook.y) .. "," .. string.format("%.2f", hook.dx) .. "," .. string.format("%.2f", hook.dy)
        else
            payload = payload .. ",k:"
        end

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
                    local target_id, amount, angle, force, slow, avx, at
                    
                    if Helpers.is_bot_id(parts) then
                        local bid, rest = parts:match("([^,]+),(.+)")
                        if bid and rest then
                            target_id = bid
                            amount, angle, force, slow, avx, at = rest:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),(.*)")
                        end
                    else
                        target_id = nil
                        amount, angle, force, slow, avx, at = parts:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),(.*)")
                    end
                    
                    if amount and angle and force then
                        local result = {
                            amount = tonumber(amount),
                            knockback = tonumber(angle),
                            force = tonumber(force),
                            slow = tonumber(slow) or 0,
                            attacker_vx = tonumber(avx) or 0,
                            attack_type = at or ""
                        }
                        if target_id then
                            result.target_id = target_id
                        end
                        Network.pending_damage = result
                    end
                elseif data:sub(1, 5) == "pull:" then
                    local parts = data:sub(6)
                    local target_id, tx, ty, dx, dy
                    
                    if Helpers.is_bot_id(parts) then
                        local bid
                        bid, tx, ty, dx, dy = parts:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
                        if bid then
                            target_id = bid
                        end
                    else
                        tx, ty, dx, dy = parts:match("([^,]+),([^,]+),([^,]+),([^,]+)")
                    end
                    
                    if tx and ty and dx and dy then
                        local result = {
                            x = tonumber(tx),
                            y = tonumber(ty),
                            dx = tonumber(dx),
                            dy = tonumber(dy)
                        }
                        if target_id then
                            result.target_id = target_id
                        end
                        Network.pending_pull = result
                    end
                elseif data:sub(1, 5) == "bots:" then
                    Network.pending_bots = data:sub(6)
                elseif data:sub(1, 12) == "toggle_bots:" then
                    Network.pending_toggle = true
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

    return Network.players, Network.my_id, lost_connection, Network.pending_damage, Network.pending_pull, Network.pending_bots, Network.pending_toggle
end

function Network.quit()
    if Network.server then
        Network.server:disconnect()
        Network.host:service(100)
    end
end

return Network
