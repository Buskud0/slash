local config = require "config"

local Helpers = {}

function Helpers.get_player_center(player)
    return player.x + config.SPRITE_SIZE / 2, player.y + player.height / 2
end

function Helpers.get_sword_tip(player)
    local center_x = player.x + (config.SPRITE_SIZE / 2)
    local center_y = player.y + (player.height / 2)
    local timer = player.attack_timer
    local at = player.attack_type
    local face = player.view_facing or player.facing

    if at == "stab_left" or at == "stab_right" or at == "stab_up" or at == "stab_down" then
        local duration = config.STAB_DURATION
        local progress = (duration - math.abs(timer)) / duration
        local radius = math.sin(progress * math.pi) * config.STAB_LENGTH
        local angle = player.attack_angle or face
        local tip_x = center_x + math.cos(angle) * radius
        local tip_y = center_y + math.sin(angle) * radius
        return tip_x, tip_y, angle

    elseif at == "swing_up_left" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = math.pi - progress * (math.pi / 2)
        local tip_x = center_x + math.cos(sweep) * config.SWING_LENGTH
        local tip_y = center_y + math.sin(sweep) * config.SWING_LENGTH
        return tip_x, tip_y, 3 * math.pi / 4

    elseif at == "swing_up_right" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = progress * (math.pi / 2)
        local tip_x = center_x + math.cos(sweep) * config.SWING_LENGTH
        local tip_y = center_y + math.sin(sweep) * config.SWING_LENGTH
        return tip_x, tip_y, math.pi / 4

    elseif at == "swing_down_left" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = math.pi + progress * (math.pi / 2)
        local tip_x = center_x + math.cos(sweep) * config.SWING_LENGTH
        local tip_y = center_y + math.sin(sweep) * config.SWING_LENGTH
        return tip_x, tip_y, -3 * math.pi / 4

    elseif at == "swing_down_right" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = -progress * (math.pi / 2)
        local tip_x = center_x + math.cos(sweep) * config.SWING_LENGTH
        local tip_y = center_y + math.sin(sweep) * config.SWING_LENGTH
        return tip_x, tip_y, -math.pi / 4

    else
        return center_x, center_y, player.facing
    end
end

function Helpers.get_attack_damage(attack_type)
    if attack_type and attack_type:sub(1, 4) == "stab" then
        return config.STAB_DAMAGE
    end
    return config.SWING_DAMAGE
end

function Helpers.is_bot_id(id)
    return id and id:sub(1, 4) == "bot_"
end

function Helpers.get_entity_hitbox(entity)
    return entity.x, entity.y, config.SPRITE_SIZE, entity.height or config.PLAYER_STAND_HEIGHT
end

function Helpers.point_in_hitbox(px, py, entity)
    local ex, ey, ew, eh = Helpers.get_entity_hitbox(entity)
    return px >= ex and px <= ex + ew and py >= ey and py <= ey + eh
end

function Helpers.encode_entity(entity)
    local attack_facing = entity.attack_facing or entity.view_facing or entity.facing
    local state_id = 0
    if entity.state == "frozen" then state_id = 1
    elseif entity.state == "hooked" then state_id = 2
    elseif entity.state == "cooldown" then state_id = 3
    end
    local s = string.format("%d,%d,%d,%d,%d,%s,%d,%d,%d,%.1f,%d,%d,%.3f",
        math.floor(entity.x), math.floor(entity.y),
        math.floor(entity.height),
        math.floor(entity.facing * 100),
        math.floor(entity.attack_timer * 100),
        entity.attack_type or "none",
        entity.attack_id or 0,
        entity.health or config.MAX_HEALTH,
        math.floor((entity.air_velocity_x or 0) * 100),
        (entity.dash_timer or 0) * 100,
        entity.invincible and 1 or 0,
        state_id,
        attack_facing)
    local bullets = entity.bullets or {}
    if #bullets > 0 then
        s = s .. ",b:"
        for i, bul in ipairs(bullets) do
            if i > 1 then s = s .. ";" end
            s = s .. (bul.type or "freeze") .. "," .. math.floor(bul.x) .. "," .. math.floor(bul.y)
                .. "," .. string.format("%.2f", bul.dx or 0) .. "," .. string.format("%.2f", bul.dy or 0)
                .. "," .. string.format("%.2f", bul.timer or 0)
                .. "," .. string.format("%.2f", bul.speed or 0)
        end
    else
        s = s .. ",b:"
    end
    local hook = entity.hook
    if hook then
        local has_target = hook.target_id and 1 or 0
        s = s .. ",k:" .. math.floor(hook.x) .. "," .. math.floor(hook.y)
            .. "," .. string.format("%.2f", hook.dx) .. "," .. string.format("%.2f", hook.dy)
            .. "," .. has_target
    else
        s = s .. ",k:"
    end
    return s
end

local STATE_NAMES = { [0]="none", [1]="frozen", [2]="hooked", [3]="cooldown" }

function Helpers.decode_entity(raw)
    local main = raw:match("^(.-),b:")
    if not main then return nil end
    local px, py, ph, pf, pa, pat, paid, phealth, pavx, pDash, pInv, pState, pAF = main:match(
        "([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
    if not px then return nil end
    local state_str = STATE_NAMES[tonumber(pState) or 0]
    local entity = {
        x = tonumber(px), y = tonumber(py),
        height = tonumber(ph),
        facing = tonumber(pf) / 100,
        attack_facing = tonumber(pAF) or 0,
        attack_timer = tonumber(pa) / 100,
        attack_type = pat ~= "none" and pat or nil,
        attack_id = tonumber(paid) or 0,
        health = tonumber(phealth) or config.MAX_HEALTH,
        air_velocity_x = (tonumber(pavx) or 0) / 100,
        dash_timer = (tonumber(pDash) or 0) / 100,
        invincible = (tonumber(pInv) or 0) == 1,
        state = state_str ~= "none" and state_str or nil,
        bullets = {}, hook = nil
    }
    local bullets_str = raw:match(",b:(.-),k:")
    if not bullets_str then bullets_str = raw:match(",b:([^|]*)") end
    if bullets_str and #bullets_str > 0 then
        for bullet_data in bullets_str:gmatch("([^;]+)") do
            local btype, bx, by, bdx, bdy, btimer, bspeed = bullet_data:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
            if not bspeed then
                btype, bx, by, bdx, bdy, btimer = bullet_data:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
            end
            if bx then
                table.insert(entity.bullets, {
                    type = btype,
                    x = tonumber(bx), y = tonumber(by),
                    dx = tonumber(bdx) or 0, dy = tonumber(bdy) or 0,
                    timer = tonumber(btimer) or 0,
                    speed = tonumber(bspeed) or 0
                })
            end
        end
    end
    local hook_str = raw:match(",k:([^|]*)")
    if hook_str and #hook_str > 0 then
        local hx, hy, hdx, hdy, htarget = hook_str:match("([^,]+),([^,]+),([^,]+),([^,]+),?(.*)")
        if hx and hy then
            local hook = { x = tonumber(hx), y = tonumber(hy),
                dx = tonumber(hdx) or 0, dy = tonumber(hdy) or 0 }
            if htarget and #htarget > 0 and tonumber(htarget) == 1 then
                hook.target_id = true
            end
            entity.hook = hook
        end
    end
    return entity
end

function Helpers.each_target(network_players, my_id, bots, callback)
    for id, p in pairs(network_players) do
        if id ~= my_id then
            if callback(id, p, false) then return end
        end
    end
    for i, bot in ipairs(bots) do
        if callback("bot_" .. i, bot, true) then return end
    end
end

function Helpers.get_hitbox(x, y, w, h)
    local mx, my = love.mouse.getPosition()
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

return Helpers