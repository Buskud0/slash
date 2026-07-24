local config = require "config"
local Helpers = require "helpers"

local Player = {}
Player.__index = Player

function Player.new(spawn_x, spawn_y, main_color)
    local self = setmetatable({}, Player)
    self.x = spawn_x or config.SPAWN_X
    self.y = spawn_y or config.SPAWN_Y
    self.height = config.PLAYER_STAND_HEIGHT
    self.y_velocity = 0
    self.is_on_ground = false
    self.facing = 1
    self.view_facing = 1
    self.knockback_x = 0
    self.air_velocity_x = 0
    self.dash_cooldown = 0
    self.dash_timer = 0
    self.dash_dx = 0
    self.dash_dy = 0
    self.attack_timer = 0
    self.attack_id = 0
    self.attack_type = nil
    self.attack_angle = 0
    self.attack_landed = false
    self.cooldowns = { stab = 0, swing = 0 }
    self.jump_cooldown = 0
    self.hit_gravity_timer = 0
    self.slow_timer = 0
    self.combat_cooldown = 0
    self.health = config.MAX_HEALTH
    self.invincible = false
    self.bullets = {}
    self.bullet_cooldown = 0
    self.hook = nil
    self.hook_cooldown = 0
    self.pull_toward = nil
    self.speed_mult = 1.0
    self.effects = {}
    self.mainColor = main_color or {0, 0.75, 0}
    self.name = ""
    return self
end

function Player:syncEffects()
    self.effects.frozen = self.slow_timer > 0
    self.effects.hooked = self.pull_toward ~= nil
    self.effects.locked = self.combat_cooldown > 0 and not self.effects.hooked
end

function Player:getCurrentOutlineColor()
    if self.effects.frozen then return config.OUTLINE_FROZEN end
    if self.effects.hooked then return config.OUTLINE_HOOKED end
    if self.effects.locked then return config.OUTLINE_LOCKED end
    return config.OUTLINE_DEFAULT
end

local function angle_from_aim(self, cmd)
    local cx, cy = Helpers.get_player_center(self)
    return math.atan2(cmd.aimY - cy, cmd.aimX - cx)
end

local function apply_gravity(self, dt, cmd)
    local gravity_multiplier = 1.0
    if self.hit_gravity_timer > 0 then
        gravity_multiplier = gravity_multiplier * config.HIT_GRAVITY_MULTIPLIER
    end
    if cmd.crouch and not self.is_on_ground then
        gravity_multiplier = gravity_multiplier * config.CROUCH_FALL_MULTIPLIER
    end
    local gravity_accel = config.GRAVITY * gravity_multiplier * dt
    if self.y_velocity < 0 and (not cmd.jump or self.hit_gravity_timer > 0) then
        gravity_accel = gravity_accel + config.GRAVITY * config.GRAVITY_JUMP_RELEASE_MULTIPLIER * dt
    end
    self.y_velocity = self.y_velocity + gravity_accel
    self.y = self.y + self.y_velocity * dt
end

local function enforce_boundaries(self)
    local max_y = config.GROUND_Y - self.height
    if self.y >= max_y then
        self.y = max_y
        self.y_velocity = 0
        self.is_on_ground = true
    end
    local max_x = (love.graphics.getWidth() / config.ZOOM) - config.SPRITE_SIZE
    if self.x < 0 then
        self.x = 0
    elseif self.x > max_x then
        self.x = max_x
    end
end

local function update_crouch(self, cmd)
    local prev = self.height
    self.height = cmd.crouch and config.PLAYER_CROUCH_HEIGHT or config.PLAYER_STAND_HEIGHT
    if self.is_on_ground then
        self.y = (self.y + prev) - self.height
    end
end

local function update_attack_timers(self, dt)
    local active = self.attack_timer
    if self.attack_timer > 0 then
        self.attack_timer = math.max(0, self.attack_timer - dt)
        if active > 0 and self.attack_timer == 0 then
            local key = self.attack_type and self.attack_type:sub(1, 4) == "stab" and "stab" or "swing"
            self.cooldowns[key] = self.attack_landed and config.SWORD_COOLDOWN_HIT or config.SWORD_COOLDOWN_MISS
        end
    elseif self.attack_timer < 0 then
        self.attack_timer = math.min(0, self.attack_timer + dt)
        if active < 0 and self.attack_timer == 0 then
            local key = self.attack_type and self.attack_type:sub(1, 4) == "stab" and "stab" or "swing"
            self.cooldowns[key] = self.attack_landed and config.SWORD_COOLDOWN_HIT or config.SWORD_COOLDOWN_MISS
        end
    end
    return active
end

local function start_attack(self, dt, cmd)
    for name, cd in pairs(self.cooldowns) do
        self.cooldowns[name] = math.max(0, cd - dt)
    end
    self.combat_cooldown = math.max(0, self.combat_cooldown - dt)
    if self.attack_timer ~= 0 then return false end
    if self.combat_cooldown > 0 then return false end

    local at, angle
    if cmd.attack then
        angle = angle_from_aim(self, cmd)
        if angle > -math.pi / 4 and angle <= math.pi / 4 then
            at = "stab_right"
        elseif angle > math.pi / 4 and angle <= 3 * math.pi / 4 then
            at = "stab_down"
        elseif angle > -3 * math.pi / 4 and angle <= -math.pi / 4 then
            at = "stab_up"
        else
            at = "stab_left"
        end
    elseif cmd.attack2 then
        local cx, cy = Helpers.get_player_center(self)
        local above = cmd.aimY < cy
        local left = cmd.aimX < cx
        if above then
            at = left and "swing_down_left" or "swing_down_right"
        else
            at = left and "swing_up_left" or "swing_up_right"
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
        local key = at:sub(1, 4) == "stab" and "stab" or "swing"
        if self.cooldowns[key] == 0 then
            self.attack_angle = angle
            self.attack_type = at
            self.attack_id = self.attack_id + 1
            self.attack_landed = false
            self.attack_timer = at:sub(1, 4) == "stab" and -config.STAB_DURATION or config.SWING_DURATION
            return true
        end
    end
    return false
end

local function move_and_dash(self, dt, cmd)
    self.dash_cooldown = math.max(0, self.dash_cooldown - dt)
    self.jump_cooldown = math.max(0, self.jump_cooldown - dt)

    if self.pull_toward then
        self.pull_toward.timer = self.pull_toward.timer - dt
        self.combat_cooldown = 1
        if self.pull_toward.timer <= 0 then
            self.knockback_x = -self.pull_toward.dx * config.HOOK_PULL_FORCE
            self.y_velocity = -self.pull_toward.dy * config.HOOK_PULL_FORCE
            self.is_on_ground = false
            self.pull_toward = nil
        end
    end

    if self.pull_toward then
        local cx = self.x + config.SPRITE_SIZE / 2
        local cy = self.y + self.height / 2
        local dx = self.pull_toward.x - cx
        local dy = self.pull_toward.y - cy
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 1 then
            self.x = self.x + (dx / len) * config.HOOK_PULL_FORCE * dt
            self.y = self.y + (dy / len) * config.HOOK_PULL_FORCE * dt
        end
        self.combat_cooldown = 1
        self.y_velocity = 0
        self.knockback_x = 0
        self.is_on_ground = false
        return
    end

    local input_dx = (cmd.right and 1 or 0) - (cmd.left and 1 or 0)
    local input_dy = (cmd.down and 1 or 0) - (cmd.up and 1 or 0)
    local has_input = input_dx ~= 0 or input_dy ~= 0

    if self.dash_timer > 0 then
        self.dash_timer = math.max(0, self.dash_timer - dt)
        self.y_velocity = 0
        self.x = self.x + self.dash_dx * config.SPEED * config.DASH_SPEED_MULTIPLIER * dt
        self.y = self.y + self.dash_dy * config.SPEED * config.DASH_SPEED_MULTIPLIER * dt
        return
    end

    self.knockback_x = self.knockback_x - self.knockback_x * config.KNOCKBACK_DECAY * dt

    if input_dx ~= 0 then
        local speed = config.SPEED * self.speed_mult
        if self.slow_timer > 0 then
            speed = speed * config.FREEZE_BOLT_SLOW_MULTIPLIER
        end
        self.air_velocity_x = input_dx * speed
    elseif not self.is_on_ground then
        self.air_velocity_x = self.air_velocity_x - self.air_velocity_x * config.AIR_FRICTION * dt
    else
        self.air_velocity_x = self.air_velocity_x - self.air_velocity_x * config.GROUND_FRICTION * dt
        if math.abs(self.air_velocity_x) < 1 then self.air_velocity_x = 0 end
    end

    self.x = self.x + (self.air_velocity_x + self.knockback_x) * dt

    if cmd.dash and self.dash_cooldown == 0 and has_input then
        local len = math.sqrt(input_dx * input_dx + input_dy * input_dy)
        self.dash_dx, self.dash_dy = input_dx / len, input_dy / len
        self.dash_timer = config.DASH_DURATION
        self.dash_cooldown = config.DASH_COOLDOWN
        self.cooldowns.stab = 0
        self.cooldowns.swing = 0
    end

    if cmd.jump and self.is_on_ground and self.jump_cooldown == 0 then
        self.y_velocity = config.JUMP
        self.is_on_ground = false
        self.jump_cooldown = config.JUMP_COOLDOWN
    end

    apply_gravity(self, dt, cmd)
end

function Player:update(dt, cmd)
    self.hit_gravity_timer = math.max(0, self.hit_gravity_timer - dt)
    self.bullet_cooldown = math.max(0, self.bullet_cooldown - dt)
    self.hook_cooldown = math.max(0, self.hook_cooldown - dt)
    self.slow_timer = math.max(0, self.slow_timer - dt)

    if self.slow_timer > 0 then
        local active = update_attack_timers(self, dt)
        self.view_facing = active ~= 0 and self.attack_angle or self.facing
        self.knockback_x = self.knockback_x - self.knockback_x * config.KNOCKBACK_DECAY * dt
        self.x = self.x + self.knockback_x * dt

        if self.hook then
            local h = self.hook
            if not h.target_id then
                local step = config.HOOK_SPEED * dt
                h.x = h.x + h.dx * step
                h.y = h.y + h.dy * step
                h.traveled = h.traveled + step
            end
            if h.traveled >= config.HOOK_RANGE then
                self.hook = nil
                self.pull_toward = nil
            end
        end

        for i = #self.bullets, 1, -1 do
            local b = self.bullets[i]
            b.x = b.x + b.dx * config.FREEZE_BOLT_SPEED * dt
            b.y = b.y + b.dy * config.FREEZE_BOLT_SPEED * dt
            b.timer = b.timer - dt
            if b.timer <= 0 then table.remove(self.bullets, i) end
        end

        apply_gravity(self, dt, cmd)
        enforce_boundaries(self)
        return self
    end

    if self.pull_toward then
        move_and_dash(self, dt, cmd)
        enforce_boundaries(self)
        return self
    end

    local attack_started = start_attack(self, dt, cmd)

    local hook_activated = false
    if cmd.hook and self.hook_cooldown == 0 and not self.hook and self.combat_cooldown <= 0 then
        local cx, cy = Helpers.get_player_center(self)
        local dx = cmd.aimX - cx
        local dy = cmd.aimY - cy
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
            self.hook = { type = "hook", x = cx, y = cy, dx = dx / len, dy = dy / len, traveled = 0, target_id = nil, owner = self }
            self.hook_cooldown = config.HOOK_COOLDOWN
            hook_activated = true
        end
    end

    if self.hook then
        local h = self.hook
        if not h.target_id then
            local step = config.HOOK_SPEED * dt
            h.x = h.x + h.dx * step
            h.y = h.y + h.dy * step
            h.traveled = h.traveled + step
        end
        if h.traveled >= config.HOOK_RANGE then
            self.hook = nil
            self.pull_toward = nil
        end
    end

    local bullet_fired = false
    if cmd.fire and self.bullet_cooldown == 0 and not cmd.attack and not cmd.attack2 and self.combat_cooldown <= 0 then
        local cx, cy = Helpers.get_player_center(self)
        local dx = cmd.aimX - cx
        local dy = cmd.aimY - cy
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
            local proj = { type = "freeze", x = cx, y = cy, dx = dx / len, dy = dy / len, timer = config.FREEZE_BOLT_LIFETIME, owner = self }
            table.insert(self.bullets, proj)
            self.bullet_cooldown = config.FREEZE_BOLT_COOLDOWN
            bullet_fired = true
        end
    end

    if hook_activated and attack_started then
        self.attack_timer = 0
        self.attack_type = nil
    end
    if bullet_fired and self.hook then
        self.hook = nil
        self.pull_toward = nil
    end
    if attack_started and self.hook then
        self.hook = nil
        self.pull_toward = nil
    end

    for i = #self.bullets, 1, -1 do
        local b = self.bullets[i]
        b.x = b.x + b.dx * config.FREEZE_BOLT_SPEED * dt
        b.y = b.y + b.dy * config.FREEZE_BOLT_SPEED * dt
        b.timer = b.timer - dt
        if b.timer <= 0 then table.remove(self.bullets, i) end
    end

    local input_dx = (cmd.right and 1 or 0) - (cmd.left and 1 or 0)
    if input_dx ~= 0 and self.attack_timer == 0 then
        self.facing = input_dx > 0 and 1 or -1
    end

    move_and_dash(self, dt, cmd)
    update_crouch(self, cmd)
    enforce_boundaries(self)

    local active = update_attack_timers(self, dt)
    self.view_facing = active ~= 0 and self.attack_angle or self.facing

    return self
end

function Player:takeDamage(amount, attacker_vx, attack_type)
    self.health = math.max(0, self.health - amount)
    self.hit_gravity_timer = config.HIT_GRAVITY_DURATION
    self.attack_timer = 0
    self.attack_type = nil
    self.combat_cooldown = config.COMBAT_COOLDOWN
    if self.health <= 0 then
        self.x = config.SPAWN_X
        self.y = config.SPAWN_Y
        self.y_velocity = 0
        self.knockback_x = 0
        self.is_on_ground = false
        self.health = config.MAX_HEALTH
    end
end

function Player:applyKnockback(angle, force, attacker_vx, attack_type)
    force = force or config.BASE_KNOCKBACK
    self.knockback_x = math.cos(angle) * force + (attacker_vx or 0) * config.MOVEMENT_KNOCKBACK_MULTIPLIER
    self.y_velocity = math.sin(angle) * force * config.VERTICAL_KNOCKBACK_SCALE - math.abs(attacker_vx or 0) * config.VERTICAL_KNOCKBACK_SCALE
    if attack_type and (attack_type == "swing_up_left" or attack_type == "swing_up_right") then
        self.y_velocity = self.y_velocity - config.SWING_UPWARD_FORCE
    end
    self.is_on_ground = false
    self.pull_toward = nil
end

function Player:applyPull(target_x, target_y, hook_dx, hook_dy)
    if not self.pull_toward then
        self.pull_toward = { x = target_x, y = target_y, timer = 0.05, dx = hook_dx, dy = hook_dy }
    else
        self.pull_toward.x = target_x
        self.pull_toward.y = target_y
        self.pull_toward.timer = 0.05
    end
end

function Player:applySlow(duration)
    local dur = duration or config.FREEZE_BOLT_SLOW_DURATION
    self.slow_timer = math.max(self.slow_timer, dur)
end

function Player:clearCooldown(at)
    local key = at:sub(1, 4) == "stab" and "stab" or "swing"
    self.cooldowns[key] = 0
end

function Player:getHit(proj)
    if proj.type == "freeze" then
        local angle = math.atan2(proj.dy, proj.dx)
        self:applyKnockback(angle, config.FREEZE_BOLT_KNOCKBACK_FORCE)
        self:applySlow(config.FREEZE_BOLT_SLOW_DURATION)
        self.combat_cooldown = config.COMBAT_COOLDOWN
    end
end

function Player:clearPull()
    self.pull_toward = nil
end

function Player:to_view()
    return {
        x = self.x,
        y = self.y,
        height = self.height,
        facing = self.facing,
        attack_facing = self.view_facing or self.facing,
        attack_timer = self.attack_timer,
        attack_id = self.attack_id,
        attack_type = self.attack_type,
        health = self.health,
        slow_timer = self.slow_timer or 0,
        combat_cooldown = self.combat_cooldown or 0,
        being_hooked = self.pull_toward ~= nil,
        air_velocity_x = self.air_velocity_x or 0,
        dash_timer = self.dash_timer or 0,
        bullets = self.bullets,
        hook = self.hook
    }
end

return Player
