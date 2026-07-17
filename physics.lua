local config = require "config"

local Physics = {
    x = config.SPAWN_X,
    y = config.SPAWN_Y,
    height = 24,
    y_velocity = 0,
    is_on_ground = false,
    dash_cooldown = 0,
    dash_timer = 0,
    dash_dx = 0,
    dash_dy = 0,
    facing = 1,
    attack_timer = 0,
    cooldowns = {
        stab_left = 0, stab_right = 0, stab_up = 0, stab_down = 0,
        swing_up_left = 0, swing_up_right = 0, swing_down_left = 0, swing_down_right = 0
    },
    jump_cooldown = 0,
    attack_angle = 0,
    attack_type = nil,
    knockback_x = 0,
    attack_id = 0,
    health = config.MAX_HEALTH,
    hit_gravity_timer = 0
}

local function apply_gravity(dt, input)
    local gravity_multiplier = 1.0
    
    if math.abs(Physics.knockback_x) > 50 then
        gravity_multiplier = gravity_multiplier * config.GRAVITY_HIT_REDUCTION
    end
    
    if Physics.hit_gravity_timer > 0 then
        gravity_multiplier = gravity_multiplier * config.HIT_GRAVITY_MULTIPLIER
    end
    
    if input.crouch and not Physics.is_on_ground then
        gravity_multiplier = gravity_multiplier * config.CROUCH_FALL_MULTIPLIER
    end
    
    local gravity_accel = config.GRAVITY * gravity_multiplier * dt
    
    if Physics.y_velocity < 0 and not input.jump then
        gravity_accel = gravity_accel + config.GRAVITY * config.GRAVITY_JUMP_RELEASE_MULTIPLIER * dt
    end
    
    Physics.y_velocity = Physics.y_velocity + gravity_accel
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
    if Physics.x < 0 then
        Physics.x = 0
    elseif Physics.x > max_x then
        Physics.x = max_x
    end
end

local function update_crouch_height(dt, crouch_pressed)
    local prev_height = Physics.height
    Physics.height = crouch_pressed and config.PLAYER_CROUCH_HEIGHT or config.PLAYER_STAND_HEIGHT
    
    if Physics.is_on_ground then
        Physics.y = (Physics.y + prev_height) - Physics.height
    end
end

local function get_player_center()
    return Physics.x + config.SPRITE_SIZE / 2, Physics.y + Physics.height / 2
end

local function angle_from_mouse(input)
    local cx, cy = get_player_center()
    return math.atan2(input.mouse_y - cy, input.mouse_x - cx)
end

local function update_attacks(dt, input)
    for name, cd in pairs(Physics.cooldowns) do
        Physics.cooldowns[name] = math.max(0, cd - dt)
    end

    if Physics.attack_timer == 0 then
        local at, angle

        if input.attackStab then
            angle = angle_from_mouse(input)
            if angle > -math.pi / 4 and angle <= math.pi / 4 then
                at = "stab_right"
            elseif angle > math.pi / 4 and angle <= 3 * math.pi / 4 then
                at = "stab_down"
            elseif angle > -3 * math.pi / 4 and angle <= -math.pi / 4 then
                at = "stab_up"
            else
                at = "stab_left"
            end

        elseif input.attackSlash then
            local cx, cy = get_player_center()
            local mouse_above = input.mouse_y < cy
            local mouse_left = input.mouse_x < cx

            if mouse_above then
                at = mouse_left and "swing_down_left" or "swing_down_right"
            else
                at = mouse_left and "swing_up_left" or "swing_up_right"
            end

            local angles = {
                swing_down_left = 5 * math.pi / 4,
                swing_down_right = -math.pi / 4,
                swing_up_left = 3 * math.pi / 4,
                swing_up_right = math.pi / 4
            }
            angle = angles[at]
        end

        if at and Physics.cooldowns[at] == 0 then
            Physics.attack_angle = angle
            Physics.attack_type = at
            Physics.attack_id = Physics.attack_id + 1
            Physics.cooldowns[at] = at:sub(1, 4) == "stab" and config.STAB_COOLDOWN or config.SWING_COOLDOWN

            if at:sub(1, 4) == "stab" then
                Physics.attack_timer = -config.STAB_DURATION
            else
                Physics.attack_timer = config.SWING_DURATION
            end
        end
    end
end

local function update_attack_timers(dt)
    local active_timer = Physics.attack_timer
    
    if Physics.attack_timer > 0 then
        Physics.attack_timer = math.max(0, Physics.attack_timer - dt)
    elseif Physics.attack_timer < 0 then
        Physics.attack_timer = math.min(0, Physics.attack_timer + dt)
    end
    
    return active_timer
end

local function update_movement_and_dash(dt, input)
    Physics.dash_cooldown = math.max(0, Physics.dash_cooldown - dt)
    Physics.jump_cooldown = math.max(0, Physics.jump_cooldown - dt)
    local has_input = input.dx ~= 0 or input.dy ~= 0

    if Physics.dash_timer > 0 then
        Physics.dash_timer = math.max(0, Physics.dash_timer - dt)
        Physics.y_velocity = 0
        Physics.x = Physics.x + Physics.dash_dx * config.SPEED * config.DASH_SPEED_MULTIPLIER * dt
        Physics.y = Physics.y + Physics.dash_dy * config.SPEED * config.DASH_SPEED_MULTIPLIER * dt
    else
        Physics.knockback_x = Physics.knockback_x - Physics.knockback_x * config.KNOCKBACK_DECAY * dt
        Physics.x = Physics.x + (input.dx * config.SPEED + Physics.knockback_x) * dt
        
        if input.dash and Physics.dash_cooldown == 0 and has_input then
            local len = math.sqrt(input.dx * input.dx + input.dy * input.dy)
            Physics.dash_dx, Physics.dash_dy = input.dx / len, input.dy / len
            Physics.dash_timer = config.DASH_DURATION
            Physics.dash_cooldown = config.DASH_COOLDOWN
        end
        
        if input.jump and Physics.is_on_ground and Physics.jump_cooldown == 0 then
            Physics.y_velocity = config.JUMP
            Physics.is_on_ground = false
            Physics.jump_cooldown = config.JUMP_COOLDOWN
        end
        
        apply_gravity(dt, input)
    end
end

function Physics.apply_knockback(angle)
    Physics.knockback_x = math.cos(angle) * config.KNOCKBACK_FORCE
    Physics.y_velocity = math.sin(angle) * config.KNOCKBACK_FORCE
    Physics.is_on_ground = false
end

function Physics.take_damage(amount)
    Physics.health = math.max(0, Physics.health - amount)
    Physics.hit_gravity_timer = config.HIT_GRAVITY_DURATION
    if Physics.health <= 0 then
        Physics.x = config.SPAWN_X
        Physics.y = config.SPAWN_Y
        Physics.y_velocity = 0
        Physics.knockback_x = 0
        Physics.is_on_ground = false
        Physics.health = config.MAX_HEALTH
    end
end

function Physics.clear_cooldown(at)
    Physics.cooldowns[at] = 0
end

function Physics.update(dt, input)
    update_attacks(dt, input)
    Physics.hit_gravity_timer = math.max(0, Physics.hit_gravity_timer - dt)
    
    if input.dx ~= 0 and Physics.attack_timer == 0 then
        Physics.facing = input.dx > 0 and 1 or -1
    end

    update_movement_and_dash(dt, input)

    local is_crouching = input.crouch
    update_crouch_height(dt, is_crouching)
    enforce_boundaries(Physics.height)
    
    local active_timer = update_attack_timers(dt)
    
    local facing_val = active_timer ~= 0 and Physics.attack_angle or Physics.facing
    
    return {
        x = Physics.x,
        y = Physics.y,
        height = Physics.height,
        facing = facing_val,
        attack_timer = active_timer,
        attack_id = Physics.attack_id,
        attack_type = Physics.attack_type,
        health = Physics.health
    }
end

return Physics
