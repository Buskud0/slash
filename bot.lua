local config = require "config"

local Bot = {}

local function dist(x1, y1, x2, y2)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

function Bot.get_input(bot, enemies)
    local input = {
        dx = 0, dy = 0,
        jump = false, dash = false, crouch = false,
        attackStab = false, attackSlash = false, shootBullet = false, hook = false,
        mouse_x = 0, mouse_y = 0
    }

    local cx = bot.x + config.SPRITE_SIZE / 2
    local cy = bot.y + bot.height / 2

    local nearest = nil
    local nearest_dist = math.huge
    for _, e in pairs(enemies) do
        local d = dist(cx, cy, e.x + config.SPRITE_SIZE / 2, e.y + e.height / 2)
        if d < nearest_dist then
            nearest_dist = d
            nearest = e
        end
    end

    if not nearest then return input end

    local ex = nearest.x + config.SPRITE_SIZE / 2
    local ey = nearest.y + nearest.height / 2

    input.mouse_x = ex
    input.mouse_y = ey

    local dx = ex - cx
    local dy = ey - cy

    if math.abs(dx) > config.SPRITE_SIZE then
        input.dx = (dx > 0 and 1 or -1) * config.BOT_SPEED_MULT
    end

    local roll = math.random()

    if nearest_dist < config.SWING_LENGTH + 10 then
        if roll < 0.5 then
            input.attackSlash = true
        else
            input.attackStab = true
        end
    elseif nearest_dist < config.STAB_LENGTH then
        input.attackStab = true
    end

    if nearest_dist < config.STAB_LENGTH and roll > 0.85 then
        input.shootBullet = true
        input.attackStab = false
        input.attackSlash = false
    elseif nearest_dist > config.HOOK_RANGE * 0.5 and nearest_dist < config.HOOK_RANGE * 2 and roll > 0.6 then
        input.hook = true
        input.attackStab = false
        input.attackSlash = false
        input.shootBullet = false
    elseif nearest_dist < config.HOOK_RANGE * 2 and roll > 0.7 then
        input.shootBullet = true
    end

    if bot.is_on_ground and math.random() < 0.02 then
        input.jump = true
    end

    return input
end

return Bot
