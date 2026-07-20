local config = require "config"

local Input = {}

local KEYMAP = {
    left = {"left", "a"},
    right = {"right", "d"},
    up = {"up", "w"},
    down = {"down", "s"},
    jump = {"up", "w"},
    crouch = {"down", "s"},
    dash = {"lshift", "rshift"}
}

local function is_any_down(keys)
    if not keys then return false end
    for _, key in ipairs(keys) do
        if love.keyboard.isDown(key) then
            return true
        end
    end
    return false
end

function Input.get_state()
    local dx = 0
    if is_any_down(KEYMAP.left) then dx = dx - 1 end
    if is_any_down(KEYMAP.right) then dx = dx + 1 end

    local dy = 0
    if is_any_down(KEYMAP.up) then dy = dy - 1 end
    if is_any_down(KEYMAP.down) then dy = dy + 1 end

    local mx, my = love.mouse.getPosition()
    local world_mouse_x = mx / config.ZOOM
    local world_mouse_y = my / config.ZOOM

    return {
        dx = dx,
        dy = dy,
        jump = is_any_down(KEYMAP.jump),
        dash = is_any_down(KEYMAP.dash),
        crouch = is_any_down(KEYMAP.crouch),

        attackStab = love.mouse.isDown(1),
        attackSlash = love.mouse.isDown(2),
        shootBullet = love.mouse.isDown(3),
        hook = love.keyboard.isDown("e"),
        mouse_x = world_mouse_x,
        mouse_y = world_mouse_y
    }
end

return Input
