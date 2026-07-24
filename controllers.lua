local config = require "config"
local Controllers = {}

local function is_any_down(keys)
    if not keys then return false end
    for _, key in ipairs(keys) do
        if love.keyboard.isDown(key) then
            return true
        end
    end
    return false
end

function Controllers.empty_cmd()
    return {
        left = false, right = false, up = false, down = false,
        jump = false, dash = false, crouch = false,
        attack = false, attack2 = false, hook = false, fire = false,
        aimX = 0, aimY = 0,
    }
end

Controllers.Local = {}

function Controllers.Local.get_cmd()
    local cmd = Controllers.empty_cmd()

    if is_any_down({"left", "a"}) then cmd.left = true end
    if is_any_down({"right", "d"}) then cmd.right = true end
    if is_any_down({"up", "w"}) then cmd.up = true end
    if is_any_down({"down", "s"}) then cmd.down = true end

    cmd.jump = is_any_down({"up", "w"})
    cmd.crouch = is_any_down({"down", "s"})
    cmd.dash = is_any_down({"lshift", "rshift"})
    cmd.attack = love.mouse.isDown(1)
    cmd.attack2 = love.mouse.isDown(2)
    cmd.fire = love.keyboard.isDown("q")
    cmd.hook = love.keyboard.isDown("e")

    local mx, my = love.mouse.getPosition()
    cmd.aimX = mx / config.ZOOM
    cmd.aimY = my / config.ZOOM

    return cmd
end

Controllers.Bot = {}

local function dist(x1, y1, x2, y2)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

function Controllers.Bot.get_cmd(bot, enemies, settings, dt)
    local cmd = Controllers.empty_cmd()
    local s = settings or {}

    if s.stand_still or s.movement == "stand_still" then
        return cmd
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
        if not nearest then return cmd end
        target_x = nearest.x + config.SPRITE_SIZE / 2
        target_y = nearest.y + nearest.height / 2
    end

    cmd.aimX = target_x
    cmd.aimY = target_y

    local dx = target_x - cx
    local dy = target_y - cy
    local dist_to_target = math.sqrt(dx * dx + dy * dy)

    if math.abs(dx) > config.SPRITE_SIZE then
        if dx > 0 then cmd.right = true else cmd.left = true end
    end

    if not (s.walk_to_center or s.movement == "to_center") then
        local roll = math.random()

        if dist_to_target < config.SWING_LENGTH + 10 then
            if s.allow_swing and s.allow_stab then
                if roll < 0.5 then
                    cmd.attack2 = true
                else
                    cmd.attack = true
                end
            elseif s.allow_swing then
                cmd.attack2 = true
            elseif s.allow_stab then
                cmd.attack = true
            end
        elseif dist_to_target < config.STAB_LENGTH then
            if s.allow_stab then
                cmd.attack = true
            end
        end

        if s.allow_freeze_bolt and dist_to_target < config.STAB_LENGTH and roll > 0.85 then
            cmd.fire = true
            cmd.attack = false
            cmd.attack2 = false
        elseif s.allow_hook and dist_to_target > config.HOOK_RANGE * 0.5 and dist_to_target < config.HOOK_RANGE * 2 and roll > 0.6 then
            cmd.hook = true
            cmd.attack = false
            cmd.attack2 = false
            cmd.fire = false
        elseif s.allow_freeze_bolt and dist_to_target < config.HOOK_RANGE * 2 and roll > 0.7 then
            cmd.fire = true
        end
    end

    if s.allow_jump and s.movement == "chase" then
        if not bot.jump_hold_timer then bot.jump_hold_timer = 0 end
        if bot.jump_hold_timer > 0 then
            if not bot.is_on_ground then
                cmd.jump = true
            end
            bot.jump_hold_timer = bot.jump_hold_timer - dt
        elseif bot.is_on_ground and math.random() < 0.01 then
            bot.jump_hold_timer = config.BOT_JUMP_HOLD_DURATION
            cmd.jump = true
        end
    end

    if s.allow_dash and s.movement == "chase" then
        if not bot.next_dash then bot.next_dash = 0 end
        bot.next_dash = bot.next_dash - dt
        if bot.next_dash <= 0 and bot.is_on_ground and math.random() < 0.01 then
            cmd.dash = true
            if dx > 0 then cmd.right = true else cmd.left = true end
            bot.next_dash = 1 + math.random()
        end
    end

    return cmd
end

Controllers.Network = {}

function Controllers.Network.new()
    return {
        cmd = Controllers.empty_cmd(),
        set_cmd = function(self, new_cmd)
            self.cmd = new_cmd
        end,
        get_cmd = function(self)
            return self.cmd
        end,
    }
end

return Controllers
