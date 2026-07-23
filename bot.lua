local config = require "config"

local Bot = {}

local function dist(x1, y1, x2, y2)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

function Bot.get_input(bot, enemies, settings, dt)
    local input = {
        dx = 0, dy = 0,
        jump = false, dash = false, crouch = false,
        attackStab = false, attackSlash = false, shootBullet = false, hook = false,
        mouse_x = 0, mouse_y = 0
    }

    local s = settings or {}

    if s.stand_still or s.movement == "stand_still" then
        return input
    end

    local cx = bot.x + config.SPRITE_SIZE / 2
    local cy = bot.y + bot.height / 2

    local target_x, target_y

    if s.walk_to_center or s.movement == "to_center" then
        local screen_w = love.graphics.getWidth() / config.ZOOM
        target_x = screen_w / 2
        target_y = config.GROUND_Y - bot.height / 2
    else
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

        target_x = nearest.x + config.SPRITE_SIZE / 2
        target_y = nearest.y + nearest.height / 2
    end

    input.mouse_x = target_x
    input.mouse_y = target_y

    local dx = target_x - cx
    local dy = target_y - cy

    local dist_to_target = math.sqrt(dx * dx + dy * dy)

    if math.abs(dx) > config.SPRITE_SIZE then
        input.dx = (dx > 0 and 1 or -1) * config.BOT_SPEED_MULT
    end

    if not (s.walk_to_center or s.movement == "to_center") then
        local roll = math.random()

        if dist_to_target < config.SWING_LENGTH + 10 then
            if s.allow_swing and s.allow_stab then
                if roll < 0.5 then
                    input.attackSlash = true
                else
                    input.attackStab = true
                end
            elseif s.allow_swing then
                input.attackSlash = true
            elseif s.allow_stab then
                input.attackStab = true
            end
        elseif dist_to_target < config.STAB_LENGTH then
            if s.allow_stab then
                input.attackStab = true
            end
        end

        if s.allow_freeze_bolt and dist_to_target < config.STAB_LENGTH and roll > 0.85 then
            input.shootBullet = true
            input.attackStab = false
            input.attackSlash = false
        elseif s.allow_hook and dist_to_target > config.HOOK_RANGE * 0.5 and dist_to_target < config.HOOK_RANGE * 2 and roll > 0.6 then
            input.hook = true
            input.attackStab = false
            input.attackSlash = false
            input.shootBullet = false
        elseif s.allow_freeze_bolt and dist_to_target < config.HOOK_RANGE * 2 and roll > 0.7 then
            input.shootBullet = true
        end
    end

    if s.allow_jump and s.movement == "chase" then
        if not bot.jump_hold_timer then bot.jump_hold_timer = 0 end
        if bot.jump_hold_timer > 0 then
            if not bot.is_on_ground then
                input.jump = true
            end
            bot.jump_hold_timer = bot.jump_hold_timer - dt
        elseif bot.is_on_ground and math.random() < 0.01 then
            bot.jump_hold_timer = config.BOT_JUMP_HOLD_DURATION
            input.jump = true
        end
    end

    if s.allow_dash and s.movement == "chase" then
        if not bot.next_dash then bot.next_dash = 0 end
        bot.next_dash = bot.next_dash - dt
        if bot.next_dash <= 0 and bot.is_on_ground and math.random() < 0.01 then
            input.dash = true
            input.dx = (dx > 0 and 1 or -1) * config.BOT_SPEED_MULT
            bot.next_dash = 1 + math.random()
        end
    end

    return input
end

return Bot
