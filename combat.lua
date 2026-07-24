local config = require "config"
local Helpers = require "helpers"
local Network = require "network"
local Visuals = require "visuals"

local Combat = {}
local last_hit_by = {}
local last_hit_targets = {}

local function check_line_collision(cx, cy, tx, ty, bx, by, bw, bh)
    local function point_in_rect(px, py)
        return px >= bx and px <= bx + bw and py >= by and py <= by + bh
    end

    if point_in_rect(tx, ty) then return true end

    local steps = 10
    for i = 1, steps - 1 do
        local t = i / steps
        local px = cx + (tx - cx) * t
        local py = cy + (ty - cy) * t
        if point_in_rect(px, py) then return true end
    end

    local function seg_cross_edge(ex1, ey1, ex2, ey2)
        local d1x, d1y = tx - cx, ty - cy
        local d2x, d2y = ex2 - ex1, ey2 - ey1
        local cross = d1x * d2y - d1y * d2x
        if math.abs(cross) < 1e-10 then return false end
        local ox, oy = ex1 - cx, ey1 - cy
        local t = (ox * d2y - oy * d2x) / cross
        local u = (ox * d1y - oy * d1x) / cross
        return t >= 0 and t <= 1 and u >= 0 and u <= 1
    end

    if seg_cross_edge(bx, by, bx + bw, by) then return true end
    if seg_cross_edge(bx, by + bh, bx + bw, by + bh) then return true end
    if seg_cross_edge(bx, by, bx, by + bh) then return true end
    if seg_cross_edge(bx + bw, by, bx + bw, by + bh) then return true end

    return false
end

function Combat.remove_projectile(proj)
    for i = #ActiveProjectiles, 1, -1 do
        if ActiveProjectiles[i] == proj then
            table.remove(ActiveProjectiles, i)
            break
        end
    end
    if proj.owner and proj.owner.bullets then
        for i = #proj.owner.bullets, 1, -1 do
            if proj.owner.bullets[i] == proj then
                table.remove(proj.owner.bullets, i)
                break
            end
        end
    end
end

local function check_sword_collisions(state)
    local player = state.local_player
    local bx, by, bw, bh = Helpers.get_entity_hitbox(player)

    for id, p in pairs(state.network_players) do
        if id ~= state.my_id and p.attack_timer and math.abs(p.attack_timer) > 0 then
            local attack_id = p.attack_id or 0
            if last_hit_by[id] ~= attack_id then
                local tx, ty, contact_angle = Helpers.get_sword_tip(p)
                local cx, cy = Helpers.get_player_center(p)

                if check_line_collision(cx, cy, tx, ty, bx, by, bw, bh) then
                    last_hit_by[id] = attack_id
                end
            end
        end
    end

    for id, p in pairs(state.network_players) do
        if id ~= state.my_id and state.is_host and p.attack_timer and math.abs(p.attack_timer) > 0 then
            local attack_id = p.attack_id or 0
            local hit_key = id .. "_bots"
            if last_hit_by[hit_key] ~= attack_id then
                for bi, bot in ipairs(state.bots) do
                    local bx2, by2, bw2, bh2 = Helpers.get_entity_hitbox(bot)
                    local tx, ty, contact_angle = Helpers.get_sword_tip(p)
                    local cx, cy = Helpers.get_player_center(p)
                    if check_line_collision(cx, cy, tx, ty, bx2, by2, bw2, bh2) then
                        last_hit_by[hit_key] = attack_id
                        local at = p.attack_type or ""
                        local damage = Helpers.get_attack_damage(at)
                        bot:applyKnockback(contact_angle, nil, p.air_velocity_x, at)
                        bot:takeDamage(damage)
                        Visuals.spawnDamageMarker(bot.x, bot.y, damage)
                    end
                end
            end
        end
    end

    for bi, bot in ipairs(state.bots) do
        if bot.attack_timer and math.abs(bot.attack_timer) > 0 then
            local attack_id = bot.attack_id or 0
            local hit_key = "bot_" .. bi
            if last_hit_by[hit_key] ~= attack_id then
                local tx, ty, contact_angle = Helpers.get_sword_tip(bot)
                local cx, cy = Helpers.get_player_center(bot)

                if check_line_collision(cx, cy, tx, ty, bx, by, bw, bh) then
                    last_hit_by[hit_key] = attack_id
                    local at = bot.attack_type or ""
                    local damage = Helpers.get_attack_damage(at)
                    player:applyEffect("sword", {angle=contact_angle, attacker_vx=bot.air_velocity_x, attack_type=at})
                    Visuals.spawnDamageMarker(player.x, player.y, damage, {1, 0.3, 0.3})
                end
            end
        end
    end

    if player.attack_timer ~= 0 then
        local tx, ty, contact_angle = Helpers.get_sword_tip(player)
        local cx, cy = Helpers.get_player_center(player)

        Helpers.each_target(state.network_players, state.my_id, state.bots, function(key, target, is_bot)
            local tbx, tby, tbw, tbh = Helpers.get_entity_hitbox(target)
            if check_line_collision(cx, cy, tx, ty, tbx, tby, tbw, tbh) then
                local attack_id = player.attack_id or 0
                if last_hit_targets[key] ~= attack_id then
                    last_hit_targets[key] = attack_id
                    player.attack_landed = true
                    local at = player.attack_type or ""
                    local damage = Helpers.get_attack_damage(at)

                    if is_bot then
                        if state.is_host then
                            target:applyEffect("sword", {angle=contact_angle, attacker_vx=player.air_velocity_x, attack_type=at})
                        else
                            Network.send_damage(key, damage, contact_angle, config.BASE_KNOCKBACK, 0, player.air_velocity_x, at)
                        end
                    else
                        Network.send_damage(key, damage, contact_angle, config.BASE_KNOCKBACK, 0, player.air_velocity_x, at)
                    end
                    Visuals.spawnDamageMarker(target.x, target.y, damage)
                end
            end
        end)
    end
end

local function check_projectile_collisions(state)
    local half_hook = config.HOOK_SIZE / 2
    local half_net = config.FREEZE_BOLT_SIZE / 2

    local hooks = {}
    if state.local_player.hook then
        hooks[#hooks + 1] = { h = state.local_player.hook, entity = state.local_player, remove = function() state.local_player.hook = nil end }
    end
    for bi, bot in ipairs(state.bots) do
        if bot.hook then
            local idx = bi
            hooks[#hooks + 1] = { h = bot.hook, entity = bot, remove = function() state.bots[idx].hook = nil end }
        end
    end
    for id, p in pairs(state.network_players) do
        if id ~= state.my_id and p.hook then
            local pid = id
            hooks[#hooks + 1] = { h = p.hook, entity = p, remove = function() if state.network_players[pid] then state.network_players[pid].hook = nil end end }
        end
    end

    local function hook_bullet_close(hb, bb)
        return math.abs(hb.x - bb.x) < half_hook + half_net and math.abs(hb.y - bb.y) < half_hook + half_net
    end

    local removed_hooks = {}
    local removed_projectiles = {}

    for hi = 1, #hooks do
        if not removed_hooks[hi] then
            for pi, proj in ipairs(ActiveProjectiles) do
                if not removed_projectiles[proj] and proj.type == "freeze" and hook_bullet_close(hooks[hi].h, proj) then
                    local hx, hy = hooks[hi].h.x, hooks[hi].h.y
                    Visuals.spawnClashMarker((hx + proj.x) / 2, (hy + proj.y) / 2)
                    removed_hooks[hi] = true
                    removed_projectiles[proj] = true
                end
            end
        end
    end

    for hi = 1, #hooks do
        if not removed_hooks[hi] then
            for hj = hi + 1, #hooks do
                if not removed_hooks[hj] then
                    local a, b = hooks[hi].h, hooks[hj].h
                    if math.abs(a.x - b.x) < half_hook * 2 and math.abs(a.y - b.y) < half_hook * 2 then
                        Visuals.spawnClashMarker((a.x + b.x) / 2, (a.y + b.y) / 2)
                        removed_hooks[hi] = true
                        removed_hooks[hj] = true
                    end
                end
            end
        end
    end

    for pi = 1, #ActiveProjectiles do
        if not removed_projectiles[ActiveProjectiles[pi]] then
            for pj = pi + 1, #ActiveProjectiles do
                if not removed_projectiles[ActiveProjectiles[pj]] then
                    local a, b = ActiveProjectiles[pi], ActiveProjectiles[pj]
                    if a.type == "freeze" and b.type == "freeze" and math.abs(a.x - b.x) < config.FREEZE_BOLT_SIZE and math.abs(a.y - b.y) < config.FREEZE_BOLT_SIZE then
                        Visuals.spawnClashMarker((a.x + b.x) / 2, (a.y + b.y) / 2)
                        removed_projectiles[a] = true
                        removed_projectiles[b] = true
                    end
                end
            end
        end
    end

    local swords = {}
    if state.local_player.attack_timer ~= 0 then
        local tx, ty = Helpers.get_sword_tip(state.local_player)
        local cx, cy = Helpers.get_player_center(state.local_player)
        swords[#swords + 1] = { cx = cx, cy = cy, tx = tx, ty = ty, entity = state.local_player }
    end
    for bi, bot in ipairs(state.bots) do
        if bot.attack_timer ~= 0 then
            local tx, ty = Helpers.get_sword_tip(bot)
            local cx, cy = Helpers.get_player_center(bot)
            swords[#swords + 1] = { cx = cx, cy = cy, tx = tx, ty = ty, entity = bot }
        end
    end
    for id, p in pairs(state.network_players) do
        if id ~= state.my_id and p.attack_timer and math.abs(p.attack_timer) > 0 then
            local tx, ty = Helpers.get_sword_tip(p)
            local cx, cy = Helpers.get_player_center(p)
            swords[#swords + 1] = { cx = cx, cy = cy, tx = tx, ty = ty, entity = p }
        end
    end

    for _, sw in ipairs(swords) do
        for hi = 1, #hooks do
            if not removed_hooks[hi] and hooks[hi].entity ~= sw.entity then
                local hk = hooks[hi].h
                local hk_half = config.HOOK_SIZE / 2
                if check_line_collision(sw.cx, sw.cy, sw.tx, sw.ty, hk.x - hk_half, hk.y - hk_half, config.HOOK_SIZE, config.HOOK_SIZE) then
                    Visuals.spawnClashMarker((sw.tx + hk.x) / 2, (sw.ty + hk.y) / 2)
                    removed_hooks[hi] = true
                end
            end
        end
        for _, proj in ipairs(ActiveProjectiles) do
            if not removed_projectiles[proj] and proj.type == "freeze" and proj.owner ~= sw.entity then
                if check_line_collision(sw.cx, sw.cy, sw.tx, sw.ty, proj.x - half_net, proj.y - half_net, config.FREEZE_BOLT_SIZE, config.FREEZE_BOLT_SIZE) then
                    Visuals.spawnClashMarker((sw.tx + proj.x) / 2, (sw.ty + proj.y) / 2)
                    removed_projectiles[proj] = true
                end
            end
        end
    end

    local removed_swords = {}
    for i = 1, #swords do
        for j = i + 1, #swords do
            if not removed_swords[swords[i]] and not removed_swords[swords[j]] then
                local a, b = swords[i], swords[j]
                local dx1, dy1 = a.tx - a.cx, a.ty - a.cy
                local dx2, dy2 = b.tx - b.cx, b.ty - b.cy
                local denom = dx1 * dy2 - dy1 * dx2
                if math.abs(denom) > 0.0001 then
                    local t = ((b.cx - a.cx) * dy2 - (b.cy - a.cy) * dx2) / denom
                    local u = ((b.cx - a.cx) * dy1 - (b.cy - a.cy) * dx1) / denom
                    if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
                        local ix = a.cx + dx1 * t
                        local iy = a.cy + dy1 * t
                        Visuals.spawnClashMarker(ix, iy)
                        removed_swords[swords[i]] = true
                        removed_swords[swords[j]] = true
                    end
                end
            end
        end
    end
    for sw, _ in pairs(removed_swords) do
        if sw.entity then
            sw.entity.attack_timer = 0
            sw.entity.attack_type = nil
        end
    end

    for hi, _ in pairs(removed_hooks) do
        hooks[hi].remove()
    end
    for proj, _ in pairs(removed_projectiles) do
        Combat.remove_projectile(proj)
    end
end

local function check_bullet_hits(state)
    for pi = #ActiveProjectiles, 1, -1 do
        local proj = ActiveProjectiles[pi]
        if proj.type ~= "freeze" then goto skip end
        local is_local_bullet = proj.owner == state.local_player
        local is_controlled = is_local_bullet or proj._is_bot_bullet or (state.is_host and proj.owner and proj.owner.applyEffect)
        if not is_controlled then goto skip end

        local lbx, lby, lbw, lbh = Helpers.get_entity_hitbox(state.local_player)
        if proj.x >= lbx and proj.x <= lbx + lbw and proj.y >= lby and proj.y <= lby + lbh then
            if proj.owner ~= state.local_player then
                state.local_player:applyEffect("freeze", {projectile = proj})
                Combat.remove_projectile(proj)
                goto skip
            end
        end

        Helpers.each_target(state.network_players, state.my_id, state.bots, function(key, target, is_bot)
            if proj.owner == target then return end
            local bx, by, bw, bh = Helpers.get_entity_hitbox(target)
            if proj.x >= bx and proj.x <= bx + bw and proj.y >= by and proj.y <= by + bh then
                local kb_angle = math.atan2(proj.dy, proj.dx)
                if target.applyEffect then
                    target:applyEffect("freeze", {projectile = proj})
                end
                if is_local_bullet then
                    if not state.is_host then
                        Network.send_damage(key, 0, kb_angle, config.FREEZE_BOLT_KNOCKBACK_FORCE, config.FREEZE_BOLT_SLOW_DURATION)
                    elseif not target.applyEffect then
                        Network.send_damage(key, 0, kb_angle, config.FREEZE_BOLT_KNOCKBACK_FORCE, config.FREEZE_BOLT_SLOW_DURATION)
                    end
                elseif state.is_host and not target.applyEffect then
                    Network.send_damage(key, 0, kb_angle, config.FREEZE_BOLT_KNOCKBACK_FORCE, config.FREEZE_BOLT_SLOW_DURATION)
                end
                Combat.remove_projectile(proj)
                return true
            end
        end)
        ::skip::
    end
end

local function check_hook_hits(state, dt)
    local player = state.local_player
    if not player.hook then return end
    if player.hook.retracting then return end

    local h = player.hook
    local cx, cy = Helpers.get_player_center(player)

    if h.target_id then
        local is_bot = Helpers.is_bot_id(h.target_id)
        local p
        if is_bot then
            local bi = tonumber(h.target_id:sub(5))
            p = state.bots[bi]
        else
            p = state.network_players[h.target_id]
        end
        if p then
            local ex, ey = Helpers.get_player_center(p)
            local dist = math.sqrt((cx - ex) ^ 2 + (cy - ey) ^ 2)
            if h.initial_dist == 0 or dist <= h.initial_dist * 0.3 then
                player.hook = nil
            elseif is_bot and state.is_host then
                p:applyPull(cx, cy, h.dx, h.dy)
            else
                Network.send_pull(h.target_id, cx, cy, h.dx, h.dy)
            end
        else
            player.hook = nil
        end
        return
    end

    Helpers.each_target(state.network_players, state.my_id, state.bots, function(key, target, is_bot)
        if player.hook.target_id then return true end
        local bx, by, bw, bh = Helpers.get_entity_hitbox(target)
        if h.x >= bx and h.x <= bx + bw and h.y >= by and h.y <= by + bh then
            player.hook.target_id = key
            local ex, ey = Helpers.get_player_center(target)
            player.hook.x = ex
            player.hook.y = ey
            player.hook.initial_dist = math.sqrt((cx - ex) ^ 2 + (cy - ey) ^ 2)
            return true
        end
    end)
end

local function check_bot_hook_hits(state)
    for bi, bot in ipairs(state.bots) do
        if not bot.hook then goto continue_bot end
        if bot.hook.retracting then goto continue_bot end

        local h = bot.hook
        local bcx, bcy = Helpers.get_player_center(bot)

        if h.target_id then
            local target
            if h.target_id == "local" then
                target = state.local_player
            else
                target = state.network_players[h.target_id]
            end
            if target then
                local tx, ty = Helpers.get_player_center(target)
                h.x = tx
                h.y = ty
                local d = math.sqrt((bcx - h.x) ^ 2 + (bcy - h.y) ^ 2)
                if h.initial_dist == 0 or d <= h.initial_dist * 0.3 then
                    bot.hook = nil
                else
                    if h.target_id == "local" then
                        state.local_player:applyPull(bcx, bcy, h.dx, h.dy)
                    else
                        Network.send_pull(h.target_id, bcx, bcy, h.dx, h.dy)
                    end
                end
            else
                bot.hook = nil
            end
            goto continue_bot
        end

        local lpx, lpy = Helpers.get_player_center(state.local_player)
        if math.abs(h.x - lpx) < config.SPRITE_SIZE and
           math.abs(h.y - lpy) < state.local_player.height then
            h.target_id = "local"
            h.x = lpx
            h.y = lpy
            h.initial_dist = math.sqrt((bcx - h.x) ^ 2 + (bcy - h.y) ^ 2)
            goto continue_bot
        end

        for id, p in pairs(state.network_players) do
            if id ~= state.my_id then
                if Helpers.point_in_hitbox(h.x, h.y, p) then
                    h.target_id = id
                    local ex, ey = Helpers.get_player_center(p)
                    h.x = ex
                    h.y = ey
                    h.initial_dist = math.sqrt((bcx - h.x) ^ 2 + (bcy - h.y) ^ 2)
                    break
                end
            end
        end

        ::continue_bot::
    end
end

local function update_hook_tracking(state)
    local player = state.local_player
    if player.hook and player.hook.target_id then
        local tid = player.hook.target_id
        local p = state.network_players[tid]
        if p then
            local hx, hy = Helpers.get_player_center(p)
            player.hook.x = hx
            player.hook.y = hy
        elseif Helpers.is_bot_id(tid) then
            local bi = tonumber(tid:sub(5))
            local bot = state.bots[bi]
            if bot then
                local hx, hy = Helpers.get_player_center(bot)
                player.hook.x = hx
                player.hook.y = hy
            end
        end
    end
end

function Combat.run(state, dt)
    check_sword_collisions(state)
    check_projectile_collisions(state)
    check_bullet_hits(state)
    update_hook_tracking(state)
    check_hook_hits(state, dt)
    if state.is_host then
        check_bot_hook_hits(state)
    end
end

function Combat.reset_tracking()
    last_hit_by = {}
    last_hit_targets = {}
end

return Combat
