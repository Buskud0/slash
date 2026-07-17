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
    swing_cooldown = 0,
    stab_cooldown = 0,
    jump_cooldown = 0,
    attack_angle = 0,
    knockback_x = 0,
    attack_id = 0,
    health = config.MAX_HEALTH
}

-- Private Helper: Apply gravity with modifications for hit-knockback and variable jump height
local function apply_gravity(dt, input)
    local gravity_multiplier = 1.0
    
    -- Temporarily reduce gravity during high knockback for floatier hit reaction
    if math.abs(Physics.knockback_x) > 50 then
        gravity_multiplier = gravity_multiplier * config.GRAVITY_HIT_REDUCTION
    end
    
    local gravity_accel = config.GRAVITY * gravity_multiplier * dt
    
    -- Apply extra downward force if the user released the jump button early
    if Physics.y_velocity < 0 and not input.jump then
        gravity_accel = gravity_accel + config.GRAVITY * config.GRAVITY_JUMP_RELEASE_MULTIPLIER * dt
    end
    
    Physics.y_velocity = Physics.y_velocity + gravity_accel
    Physics.y = Physics.y + Physics.y_velocity * dt
end

-- Private Helper: Keep the player inside the visible screen bounds and handle landing
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

-- Private Helper: Smoothly transition player height when crouching/standing
local function update_crouch_height(dt, crouch_pressed)
    local prev_height = Physics.height
    Physics.height = crouch_pressed and config.PLAYER_CROUCH_HEIGHT or config.PLAYER_STAND_HEIGHT
    
    if Physics.is_on_ground then
        Physics.y = (Physics.y + prev_height) - Physics.height
    end
end

-- Private Helper: Handle attack input and trigger swings or stabs
local function update_attacks(dt, input)
    -- Reduce cooldowns
    Physics.swing_cooldown = math.max(0, Physics.swing_cooldown - dt)
    Physics.stab_cooldown = math.max(0, Physics.stab_cooldown - dt)

    if Physics.attack_timer == 0 then
        local ax, ay = input.dx, input.dy
        if ax == 0 and ay == 0 then
            ax, ay = Physics.facing, 0
        end

        if input.attack and Physics.swing_cooldown == 0 then
            Physics.attack_timer = config.SWING_DURATION
            Physics.swing_cooldown = config.SWING_COOLDOWN
            Physics.attack_angle = math.atan2(ay, ax)
            Physics.attack_id = Physics.attack_id + 1
        elseif input.stab and Physics.stab_cooldown == 0 then
            -- Stabs use a negative timer to distinguish them from swings
            Physics.attack_timer = -config.STAB_DURATION
            Physics.stab_cooldown = config.STAB_COOLDOWN
            Physics.attack_angle = math.atan2(ay, ax)
            Physics.attack_id = Physics.attack_id + 1
        end
    end
end

-- Private Helper: Update active attack duration timers
local function update_attack_timers(dt)
    local active_timer = Physics.attack_timer
    
    if Physics.attack_timer > 0 then
        Physics.attack_timer = math.max(0, Physics.attack_timer - dt)
    elseif Physics.attack_timer < 0 then
        Physics.attack_timer = math.min(0, Physics.attack_timer + dt)
    end
    
    return active_timer
end

-- Private Helper: Handle movement, jumps, knockback, and dashes
local function update_movement_and_dash(dt, input)
    Physics.dash_cooldown = math.max(0, Physics.dash_cooldown - dt)
    Physics.jump_cooldown = math.max(0, Physics.jump_cooldown - dt)
    local has_input = input.dx ~= 0 or input.dy ~= 0

    if Physics.dash_timer > 0 then
        -- Currently dashing: ignore gravity, move at constant dash speed
        Physics.dash_timer = math.max(0, Physics.dash_timer - dt)
        Physics.y_velocity = 0
        Physics.x = Physics.x + Physics.dash_dx * config.SPEED * config.DASH_SPEED_MULTIPLIER * dt
        Physics.y = Physics.y + Physics.dash_dy * config.SPEED * config.DASH_SPEED_MULTIPLIER * dt
    else
        -- Normal movement and knockback decay
        Physics.knockback_x = Physics.knockback_x - Physics.knockback_x * config.KNOCKBACK_DECAY * dt
        Physics.x = Physics.x + (input.dx * config.SPEED + Physics.knockback_x) * dt
        
        -- Trigger dash if requested and ready
        if input.dash and Physics.dash_cooldown == 0 and has_input then
            local len = math.sqrt(input.dx * input.dx + input.dy * input.dy)
            Physics.dash_dx, Physics.dash_dy = input.dx / len, input.dy / len
            Physics.dash_timer = config.DASH_DURATION
            Physics.dash_cooldown = config.DASH_COOLDOWN
        end
        
        -- Handle jumping
        if input.jump and Physics.is_on_ground and Physics.jump_cooldown == 0 then
            Physics.y_velocity = config.JUMP
            Physics.is_on_ground = false
            Physics.jump_cooldown = config.JUMP_COOLDOWN
        end
        
        apply_gravity(dt, input)
    end
end

-- Applies external knockback force when hit
function Physics.apply_knockback(angle)
    Physics.knockback_x = math.cos(angle) * config.KNOCKBACK_FORCE
    Physics.y_velocity = math.sin(angle) * config.KNOCKBACK_FORCE
    Physics.is_on_ground = false
end

-- Reduces player health and handles respawning if defeated
function Physics.take_damage(amount)
    Physics.health = math.max(0, Physics.health - amount)
    if Physics.health <= 0 then
        -- Respawn player
        Physics.x = config.SPAWN_X
        Physics.y = config.SPAWN_Y
        Physics.y_velocity = 0
        Physics.knockback_x = 0
        Physics.is_on_ground = false
        Physics.health = config.MAX_HEALTH
    end
end

-- Clears the swing cooldown (triggered when landing a stab hit)
function Physics.clear_swing_cooldown()
    Physics.swing_cooldown = 0
end

-- Clears the stab cooldown (triggered when landing a swing hit)
function Physics.clear_stab_cooldown()
    Physics.stab_cooldown = 0
end

-- Main entry point for physics module: coordinates all movement, crouch, and combat updates.
-- Accepts a structured 'input' state table and returns the player's updated state table.
function Physics.update(dt, input)
    update_attacks(dt, input)
    
    -- Face movement direction if not actively attacking
    if input.dx ~= 0 and Physics.attack_timer == 0 then
        Physics.facing = input.dx > 0 and 1 or -1
    end

    update_movement_and_dash(dt, input)

    -- Crouch only when ctrl is held
    local is_crouching = input.crouch
    update_crouch_height(dt, is_crouching)
    enforce_boundaries(Physics.height)
    
    local active_timer = update_attack_timers(dt)
    
    -- When attacking, facing direction is the attack angle; otherwise normal facing dir
    local facing_val = active_timer ~= 0 and Physics.attack_angle or Physics.facing
    
    return {
        x = Physics.x,
        y = Physics.y,
        height = Physics.height,
        facing = facing_val,
        attack_timer = active_timer,
        attack_id = Physics.attack_id,
        health = Physics.health
    }
end

return Physics