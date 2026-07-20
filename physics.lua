local config = require "config"

local Physics = {}

local function apply_gravity(player, dt, input)
    local gravity_multiplier = 1.0
    
    if math.abs(player.knockback_x) > 50 then
        gravity_multiplier = gravity_multiplier * config.GRAVITY_HIT_REDUCTION
    end
    
    if player.hit_gravity_timer > 0 then
        gravity_multiplier = gravity_multiplier * config.HIT_GRAVITY_MULTIPLIER
    end
    
    if input.crouch and not player.is_on_ground then
        gravity_multiplier = gravity_multiplier * config.CROUCH_FALL_MULTIPLIER
    end
    
    local gravity_accel = config.GRAVITY * gravity_multiplier * dt
    
    if player.y_velocity < 0 and not input.jump then
        gravity_accel = gravity_accel + config.GRAVITY * config.GRAVITY_JUMP_RELEASE_MULTIPLIER * dt
    end
    
    player.y_velocity = player.y_velocity + gravity_accel
    player.y = player.y + player.y_velocity * dt
end

local function enforce_boundaries(player)
    local max_y = config.GROUND_Y - player.height
    if player.y >= max_y then
        player.y = max_y
        player.y_velocity = 0
        player.is_on_ground = true
    end
    
    local max_x = (love.graphics.getWidth() / config.ZOOM) - config.SPRITE_SIZE
    if player.x < 0 then
        player.x = 0
    elseif player.x > max_x then
        player.x = max_x
    end
end

local function update_crouch_height(player, crouch_pressed)
    local prev_height = player.height
    player.height = crouch_pressed and config.PLAYER_CROUCH_HEIGHT or config.PLAYER_STAND_HEIGHT
    
    if player.is_on_ground then
        player.y = (player.y + prev_height) - player.height
    end
end

local function get_player_center(player)
    return player.x + config.SPRITE_SIZE / 2, player.y + player.height / 2
end

local function angle_from_mouse(player, input)
    local cx, cy = get_player_center(player)
    return math.atan2(input.mouse_y - cy, input.mouse_x - cx)
end

local function update_attacks(player, dt, input)
    for name, cd in pairs(player.cooldowns) do
        player.cooldowns[name] = math.max(0, cd - dt)
    end

    if player.attack_timer == 0 then
        local at, angle

        if input.attackStab then
            angle = angle_from_mouse(player, input)
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
            local cx, cy = get_player_center(player)
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

        if at then
            local cd_key = at:sub(1, 4) == "stab" and "stab" or "swing"
            if player.cooldowns[cd_key] == 0 then
                player.attack_angle = angle
                player.attack_type = at
                player.attack_id = player.attack_id + 1
                player.cooldowns[cd_key] = cd_key == "stab" and config.STAB_COOLDOWN or config.SWING_COOLDOWN

                if at:sub(1, 4) == "stab" then
                    player.attack_timer = -config.STAB_DURATION
                else
                    player.attack_timer = config.SWING_DURATION
                end
            end
        end
    end
end

local function update_attack_timers(player, dt)
    local active_timer = player.attack_timer
    
    if player.attack_timer > 0 then
        player.attack_timer = math.max(0, player.attack_timer - dt)
    elseif player.attack_timer < 0 then
        player.attack_timer = math.min(0, player.attack_timer + dt)
    end
    
    return active_timer
end

local function update_movement_and_dash(player, dt, input)
    player.dash_cooldown = math.max(0, player.dash_cooldown - dt)
    player.jump_cooldown = math.max(0, player.jump_cooldown - dt)

    if player.pull_toward then
        player.pull_toward.timer = player.pull_toward.timer - dt
        if player.pull_toward.timer <= 0 then
            player.knockback_x = -player.pull_toward.dx * config.HOOK_PULL_FORCE
            player.y_velocity = -player.pull_toward.dy * config.HOOK_PULL_FORCE
            player.is_on_ground = false
            player.pull_toward = nil
        end
    end

    if player.pull_toward then
        local px = player.x + config.SPRITE_SIZE / 2
        local py = player.y + player.height / 2
        local dx = player.pull_toward.x - px
        local dy = player.pull_toward.y - py
        local len = math.sqrt(dx * dx + dy * dy)
        local speed = config.HOOK_PULL_FORCE
        if len > 1 then
            player.x = player.x + (dx / len) * speed * dt
            player.y = player.y + (dy / len) * speed * dt
        end
        player.y_velocity = 0
        player.knockback_x = 0
        player.is_on_ground = false
        return
    end

    local has_input = input.dx ~= 0 or input.dy ~= 0

    if player.dash_timer > 0 then
        player.dash_timer = math.max(0, player.dash_timer - dt)
        player.y_velocity = 0
        player.x = player.x + player.dash_dx * config.SPEED * config.DASH_SPEED_MULTIPLIER * dt
        player.y = player.y + player.dash_dy * config.SPEED * config.DASH_SPEED_MULTIPLIER * dt
    else
        player.knockback_x = player.knockback_x - player.knockback_x * config.KNOCKBACK_DECAY * dt
        player.x = player.x + (input.dx * config.SPEED + player.knockback_x) * dt
        
        if input.dash and player.dash_cooldown == 0 and has_input then
            local len = math.sqrt(input.dx * input.dx + input.dy * input.dy)
            player.dash_dx, player.dash_dy = input.dx / len, input.dy / len
            player.dash_timer = config.DASH_DURATION
            player.dash_cooldown = config.DASH_COOLDOWN
            player.cooldowns.stab = 0
            player.cooldowns.swing = 0
        end
        
        if input.jump and player.is_on_ground and player.jump_cooldown == 0 then
            player.y_velocity = config.JUMP
            player.is_on_ground = false
            player.jump_cooldown = config.JUMP_COOLDOWN
        end
        
        apply_gravity(player, dt, input)
    end
end

function Physics.apply_knockback(player, angle, force)
    force = force or config.KNOCKBACK_FORCE
    player.knockback_x = math.cos(angle) * force
    player.y_velocity = math.sin(angle) * force
    player.is_on_ground = false
end

function Physics.take_damage(player, amount)
    player.health = math.max(0, player.health - amount)
    player.hit_gravity_timer = config.HIT_GRAVITY_DURATION
    if player.health <= 0 then
        player.x = config.SPAWN_X
        player.y = config.SPAWN_Y
        player.y_velocity = 0
        player.knockback_x = 0
        player.is_on_ground = false
        player.health = config.MAX_HEALTH
    end
end

function Physics.clear_cooldown(player, at)
    local cd_key = at:sub(1, 4) == "stab" and "stab" or "swing"
    player.cooldowns[cd_key] = 0
end

function Physics.remove_bullet(player, index)
    table.remove(player.bullets, index)
end

function Physics.apply_pull(player, target_x, target_y, hook_dx, hook_dy)
    if not player.pull_toward then
        player.pull_toward = { x = target_x, y = target_y, timer = 0.05, dx = hook_dx, dy = hook_dy }
    else
        player.pull_toward.x = target_x
        player.pull_toward.y = target_y
        player.pull_toward.timer = 0.05
    end
end

function Physics.clear_pull(player)
    player.pull_toward = nil
end

function Physics.update(player, dt, input)
    player.hit_gravity_timer = math.max(0, player.hit_gravity_timer - dt)
    player.bullet_cooldown = math.max(0, player.bullet_cooldown - dt)
    player.hook_cooldown = math.max(0, player.hook_cooldown - dt)

    if player.pull_toward then
        update_movement_and_dash(player, dt, input)
        enforce_boundaries(player)
        return player
    end

    update_attacks(player, dt, input)

    if input.hook and player.hook_cooldown == 0 and not player.hook then
        local cx, cy = get_player_center(player)
        local dx = input.mouse_x - cx
        local dy = input.mouse_y - cy
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
            player.hook = {
                x = cx,
                y = cy,
                dx = dx / len,
                dy = dy / len,
                traveled = 0,
                target_id = nil
            }
            player.hook_cooldown = config.HOOK_COOLDOWN
        end
    end

    if player.hook then
        local h = player.hook
        if not h.target_id then
            local step = config.HOOK_SPEED * dt
            h.x = h.x + h.dx * step
            h.y = h.y + h.dy * step
            h.traveled = h.traveled + step
        end
        if h.traveled >= config.HOOK_RANGE then
            player.hook = nil
            player.pull_toward = nil
        end
    end

    if player.hook and (input.shootBullet or input.attackStab or input.attackSlash) then
        player.hook = nil
        player.pull_toward = nil
    end

    if input.shootBullet and player.bullet_cooldown == 0 and not input.attackStab and not input.attackSlash then
        local cx, cy = get_player_center(player)
        local dx = input.mouse_x - cx
        local dy = input.mouse_y - cy
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
            table.insert(player.bullets, {
                x = cx,
                y = cy,
                dx = dx / len,
                dy = dy / len,
                timer = config.BULLET_LIFETIME
            })
            player.bullet_cooldown = config.BULLET_COOLDOWN
        end
    end

    for i = #player.bullets, 1, -1 do
        local b = player.bullets[i]
        b.x = b.x + b.dx * config.BULLET_SPEED * dt
        b.y = b.y + b.dy * config.BULLET_SPEED * dt
        b.timer = b.timer - dt
        if b.timer <= 0 then
            table.remove(player.bullets, i)
        end
    end
    
    if input.dx ~= 0 and player.attack_timer == 0 then
        player.facing = input.dx > 0 and 1 or -1
    end

    update_movement_and_dash(player, dt, input)

    update_crouch_height(player, input.crouch)
    enforce_boundaries(player)
    
    local active_timer = update_attack_timers(player, dt)
    
    player.view_facing = active_timer ~= 0 and player.attack_angle or player.facing
    
    return player
end

return Physics
