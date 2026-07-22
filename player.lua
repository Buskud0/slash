local config = require "config"

local Player = {}
Player.__index = Player

function Player.new(spawn_x, spawn_y)
    local self = setmetatable({}, Player)
    self.x = spawn_x or config.SPAWN_X
    self.y = spawn_y or config.SPAWN_Y
    self.height = config.PLAYER_STAND_HEIGHT
    self.y_velocity = 0
    self.is_on_ground = false
    self.dash_cooldown = 0
    self.dash_timer = 0
    self.dash_dx = 0
    self.dash_dy = 0
    self.facing = 1
    self.view_facing = 1
    self.attack_timer = 0
    self.cooldowns = {
        stab = 0,
        swing = 0
    }
    self.attack_landed = false
    self.jump_cooldown = 0
    self.attack_angle = 0
    self.attack_type = nil
    self.knockback_x = 0
    self.air_velocity_x = 0
    self.attack_id = 0
    self.health = config.MAX_HEALTH
    self.hit_gravity_timer = 0
    self.slow_timer = 0
    self.bullets = {}
    self.bullet_cooldown = 0
    self.hook = nil
    self.hook_cooldown = 0
    self.combat_cooldown = 0
    self.pull_toward = nil
    return self
end

function Player.to_view(self)
    return {
        x = self.x,
        y = self.y,
        height = self.height,
        facing = self.view_facing or self.facing,
        attack_timer = self.attack_timer,
        attack_id = self.attack_id,
        attack_type = self.attack_type,
        health = self.health,
        slow_timer = self.slow_timer or 0,
        air_velocity_x = self.air_velocity_x or 0,
        dash_timer = self.dash_timer or 0,
        bullets = self.bullets,
        hook = self.hook
    }
end

return Player
