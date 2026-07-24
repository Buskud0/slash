local Combat = {}
local config = require "config"
local Helpers = require "helpers"
local Network = require "network"
local Physics = require "physics"
local Renderer = require "renderer"

local last_hit_by = {}
local last_hit_targets = {}

function Combat.reset_tracking()
    last_hit_by = {}
    last_hit_targets = {}
end

-- This is the "One Command" helper specifically for Combat
-- It handles the logic, the knockback, and the visual marker.
function Combat.deal_damage(target, amount, knockback_angle, force, attacker_vx, attack_type, color)
    -- 1. Apply health change and visual marker (Unified Physics + Renderer)
    Physics.apply_damage(target, amount, color)
    
    -- 2. Apply physics
    Physics.apply_knockback(target, knockback_angle, force, attacker_vx, attack_type)
end

function Combat.update(state, dt)
    local player = state.local_player
    local bx, by, bw, bh = Helpers.get_entity_hitbox(player)

    -- 1. Check if Bots hit Local Player
    -- (Network players hit you via the Network module, but Bots are handled locally)
    for bi, bot in ipairs(state.bots) do
        if bot.attack_timer and math.abs(bot.attack_timer) > 0 then
            local attack_id = bot.attack_id or 0
            local hit_key = "bot_" .. bi
            if last_hit_by[hit_key] ~= attack_id then
                local tx, ty, contact_angle = Helpers.get_sword_tip(bot)
                local cx, cy = Helpers.get_player_center(bot)
                
                if Helpers.check_line_collision(cx, cy, tx, ty, bx, by, bw, bh) then
                    last_hit_by[hit_key] = attack_id
                    local damage = Helpers.get_attack_damage(bot.attack_type or "")
                    
                    -- ONE COMMAND: Damage local player (Red color)
                    Combat.deal_damage(player, damage, contact_angle, nil, bot.air_velocity_x, bot.attack_type, {1, 0.3, 0.3})
                end
            end
        end
    end

    -- 2. Check if Local Player hits anyone (Bots or Network Players)
    if player.attack_timer ~= 0 then
        local tx, ty, contact_angle = Helpers.get_sword_tip(player)
        local cx, cy = Helpers.get_player_center(player)
        
        Helpers.each_target(state.network_players, state.my_id, state.bots, function(key, target, is_bot)
            local tbx, tby, tbw, tbh = Helpers.get_entity_hitbox(target)
            if Helpers.check_line_collision(cx, cy, tx, ty, tbx, tby, tbw, tbh) then
                local attack_id = player.attack_id or 0
                if last_hit_targets[key] ~= attack_id then
                    last_hit_targets[key] = attack_id
                    player.attack_landed = true
                    local at = player.attack_type or ""
                    local damage = Helpers.get_attack_damage(at)

                    if is_bot then
                        -- ONE COMMAND: Damage bot (White color)
                        Combat.deal_damage(target, damage, contact_angle, nil, player.air_velocity_x, at, {1, 1, 1})
                    else
                        -- Network players: tell them they got hit, but show marker locally immediately
                        Network.send_damage(key, damage, contact_angle, config.BASE_KNOCKBACK, 0, player.air_velocity_x, at)
                        Renderer.add_damage(target.x, target.y, damage, {1, 1, 1})
                    end
                end
            end
        end)
    end
    
    -- 3. Update Hook Tracking (unchanged)
    if player.hook and player.hook.target_id then
        local tid = player.hook.target_id
        local target = state.network_players[tid] or state.bots[tonumber(tid:sub(5))]
        if target then
            local hx, hy = Helpers.get_player_center(target)
            player.hook.x, player.hook.y = hx, hy
        end
    end
end

return Combat