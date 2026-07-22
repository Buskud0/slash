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

function Helpers.get_hitbox(x, y, w, h)
    local mx, my = love.mouse.getPosition()
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

return Helpers