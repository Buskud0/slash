return {
    PORT = 12345,
    SERVER_IP = "localhost",
    SPRITE_SIZE = 16,
    PLAYER_STAND_HEIGHT = 24,
    PLAYER_CROUCH_HEIGHT = 16,
    GROUND_Y = 170,
    ZOOM = 3,
    SPEED = 120,
    GRAVITY = 500,
    JUMP = -200,

    -- Combat Constants
    SWING_DURATION = 0.12,
    STAB_DURATION = 0.15,
    SWING_COOLDOWN = 1.0,
    STAB_COOLDOWN = 1.0,
    STAB_LENGTH = 50,
    SWING_LENGTH = 35,
    SWING_DAMAGE = 10,
    STAB_DAMAGE = 15,
    MAX_HEALTH = 100,
    SPAWN_X = 40,
    SPAWN_Y = 50,

    -- Dash Constants
    DASH_DURATION = 0.15,
    DASH_COOLDOWN = 1,
    DASH_SPEED_MULTIPLIER = 3,

    -- Physics Constants
    KNOCKBACK_FORCE = 400,
    KNOCKBACK_DECAY = 8,
    AIR_FRICTION = 6,
    GRAVITY_HIT_REDUCTION = 0.25,
    GRAVITY_JUMP_RELEASE_MULTIPLIER = 3.0,
    JUMP_COOLDOWN = 0.2,
    CROUCH_FALL_MULTIPLIER = 3.0,

    -- Hit Gravity Constants
    HIT_GRAVITY_DURATION = 0.5,
    HIT_GRAVITY_MULTIPLIER = 0.1,

    -- Net Constants
    NET_SPEED = 300,
    NET_COOLDOWN = 3,
    NET_LIFETIME = 1.5,
    NET_SIZE = 5,
    NET_KNOCKBACK_FORCE = 200,
    NET_SLOW_DURATION = 0.5,
    NET_SLOW_MULTIPLIER = 0.2,

    -- Hook Constants
    HOOK_SPEED = 300,
    HOOK_RANGE = 120,
    HOOK_COOLDOWN = 3,
    HOOK_SIZE = 3,
    HOOK_PULL_FORCE = 400,

    -- Bot Constants
    BOT_COUNT = 1,
    BOT_SPEED_MULT = 0.5
}
