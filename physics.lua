local config = require "config"

local Physics = {
    x = 40,
    y = 50,
    height = 24,
    y_velocity = 0,
    is_on_ground = false,
    dash_cooldown = 0,
    dash_timer = 0,
    dash_dx = 0,
    dash_dy = 0,
    facing = 1,
    attack_timer = 0,
    attack_cooldown = 0,
    attack_angle = 0,
    knockback_x = 0
}

local function apply_gravity(dt, fast_fall, jump_pressed)
    local mult = fast_fall and 3.5 or 1.0
    
    -- Temporarily reduce gravity to 25% while experiencing active hit knockback
    if math.abs(Physics.knockback_x) > 50 then
        mult = mult * 0.25
    end
    
    local grav = config.GRAVITY * mult * dt
    if Physics.y_velocity < 0 and not jump_pressed then
        grav = grav + config.GRAVITY * 3.0 * dt
    end
    Physics.y_velocity = Physics.y_velocity + grav
    Physics.y = Physics.y + Physics.y_velocity * dt
end

local function enforce_boundaries(height)
    local max_y = config.GROUND_Y - height
    if Physics.y >= max_y then
        Physics.y = max_y
        Physics.y_velocity = 0
        Physics.is_on_ground = true
    end
    local max_x = (love.graphics.getWidth() / config.ZOOM) - config.SPRITE_SIZE
    if Physics.x < 0 then Physics.x = 0
    elseif Physics.x > max_x then Physics.x = max_x end
end

local function interpolate_height(dt, crouch_pressed)
    local prev_h = Physics.height
    local target_h = crouch_pressed and config.PLAYER_CROUCH_HEIGHT or config.PLAYER_STAND_HEIGHT
    if Physics.height < target_h then
        Physics.height = math.min(target_h, Physics.height + 100 * dt)
    elseif Physics.height > target_h then
        Physics.height = math.max(target_h, Physics.height - 100 * dt)
    end
    if Physics.is_on_ground then
        Physics.y = (Physics.y + prev_h) - Physics.height
    end
end

function Physics.apply_knockback(angle)
    -- Calculate both horizontal and vertical velocities using the attack angle
    Physics.knockback_x = math.cos(angle) * 400
    Physics.y_velocity = math.sin(angle) * 400
    Physics.is_on_ground = false
end

function Physics.update(dt, dx, dy, jump_pressed, dash_pressed, fast_fall, crouch_pressed, attack_pressed, stab_pressed)
    Physics.dash_cooldown = math.max(0, Physics.dash_cooldown - dt)
    interpolate_height(dt, crouch_pressed)

    local has_input = dx ~= 0 or dy ~= 0

    if dx ~= 0 and Physics.attack_timer == 0 then
        Physics.facing = dx > 0 and 1 or -1
    end
    
    if attack_pressed and Physics.attack_timer == 0 and Physics.attack_cooldown == 0 then
        Physics.attack_timer, Physics.attack_cooldown = 0.12, 0.25
        local ax, ay = dx, dy
        if ax == 0 and ay == 0 then ax, ay = Physics.facing, 0 end
        Physics.attack_angle = math.atan2(ay, ax)
    elseif stab_pressed and Physics.attack_timer == 0 and Physics.attack_cooldown == 0 then
        Physics.attack_timer, Physics.attack_cooldown = -0.15, 0.30
        local ax, ay = dx, dy
        if ax == 0 and ay == 0 then ax, ay = Physics.facing, 0 end
        Physics.attack_angle = math.atan2(ay, ax)
    end

    if Physics.dash_timer > 0 then
        Physics.dash_timer = math.max(0, Physics.dash_timer - dt)
        Physics.y_velocity = 0
        Physics.x = Physics.x + Physics.dash_dx * config.SPEED * 2.5 * dt
        Physics.y = Physics.y + Physics.dash_dy * config.SPEED * 2.5 * dt
    else
        Physics.knockback_x = Physics.knockback_x - Physics.knockback_x * 8 * dt
        Physics.x = Physics.x + (dx * config.SPEED + Physics.knockback_x) * dt
        
        if dash_pressed and Physics.dash_cooldown == 0 and has_input then
            local len = math.sqrt(dx*dx + dy*dy)
            Physics.dash_dx, Physics.dash_dy = dx / len, dy / len
            Physics.dash_timer, Physics.dash_cooldown = 0.12, 0.8
        end
        if jump_pressed and Physics.is_on_ground then
            Physics.y_velocity, Physics.is_on_ground = config.JUMP, false
        end
        apply_gravity(dt, fast_fall, jump_pressed)
    end

    enforce_boundaries(Physics.height)
    
    local active_timer = Physics.attack_timer
    if Physics.attack_timer > 0 then
        Physics.attack_timer = math.max(0, Physics.attack_timer - dt)
    elseif Physics.attack_timer < 0 then
        Physics.attack_timer = math.min(0, Physics.attack_timer + dt)
    end
    
    Physics.attack_cooldown = math.max(0, Physics.attack_cooldown - dt)

    local facing_val = active_timer ~= 0 and Physics.attack_angle or Physics.facing
    return Physics.x, Physics.y, Physics.height, facing_val, active_timer
end

return Physics