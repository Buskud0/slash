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
    SWORD_COOLDOWN_HIT = 0.5,
    SWORD_COOLDOWN_MISS = 1.5,
    COMBAT_COOLDOWN = 0.5,
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
    KNOCKBACK_FORCE = 250,
    KNOCKBACK_DECAY = 8,
    KNOCKBACK_VELOCITY_MULTIPLIER = 4,
    KNOCKBACK_VERTICAL_MULTIPLIER = 1.5,
    SWING_LIFT_FORCE = 180,
    AIR_FRICTION = 6,
    GRAVITY_JUMP_RELEASE_MULTIPLIER = 3.0,
    JUMP_COOLDOWN = 0.2,
    CROUCH_FALL_MULTIPLIER = 3.0,

    -- Hit Gravity Constants
    HIT_GRAVITY_DURATION = 0.5,
    HIT_GRAVITY_MULTIPLIER = 0.1,

    -- Bot Constants
    BOT_SPEED_MULT = 0.5,
    BOT_COUNT = 1,
    BOT_JUMP_HOLD_DURATION = 0.18,

    -- Freeze Bolt Constants
    FREEZE_BOLT_SPEED = 300,
    FREEZE_BOLT_COOLDOWN = 3,
    FREEZE_BOLT_LIFETIME = 1.5,
    FREEZE_BOLT_SIZE = 4,
    FREEZE_BOLT_KNOCKBACK_FORCE = 200,
    FREEZE_BOLT_SLOW_DURATION = 0.5,
    FREEZE_BOLT_SLOW_MULTIPLIER = 0.2,

    -- Hook Constants
    HOOK_SPEED = 300,
    HOOK_RANGE = 120,
    HOOK_COOLDOWN = 3,
    HOOK_SIZE = 3,
    HOOK_PULL_FORCE = 300,

    -- Visual Settings (toggle or tweak easily)
    VISUALS = {
        BACKGROUND_COLOR = {0.08, 0.09, 0.14},
        GROUND_COLOR = {0.25, 0.22, 0.18},
        GROUND_DEPTH = 6,
        GROUND_HIGHLIGHT = {0.35, 0.30, 0.25},
        SHADOW_COLOR = {0, 0, 0, 0.25},
        SHADOW_Y_OFFSET = -1,
        SHADOW_SCALE_X = 0.9,
        EYE_SIZE = 2,
        EYE_OFFSET_X = 3,
        EYE_OFFSET_Y = 5,
        SWORD_ARC_SEGMENTS = 12,
        SWORD_ARC_COLOR = {1, 0.4, 0.3, 0.4},
        SWORD_TIP_COLOR = {1, 0.6, 0.5, 0.9},
        SWORD_STAB_COLOR = {1, 0.5, 0.4, 0.8},
        BULLET_GLOW_COLOR = {0, 0.8, 0.9, 0.15},
        BULLET_GLOW_RADIUS = 4,
        HOOK_CHAIN_SPACING = 6,
        HOOK_CHAIN_SIZE = 2,
        HOOK_CHAIN_COLOR = {0.6, 0.6, 0.15, 0.7},
        DASH_TRAIL_COUNT = 8,
        DASH_TRAIL_LIFETIME = 0.4,
        DASH_TRAIL_SPACING = 0.03,
        DASH_TRAIL_BASE_ALPHA = 0.3,
        DASH_TRAIL_COLOR = {0.5, 0.6, 0.8},
    },
}
