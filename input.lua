local Input = {}

-- Key mappings to easily configure controls in one place
local KEYMAP = {
    left = {"left", "a"},
    right = {"right", "d"},
    up = {"up", "space"},
    aim_up = {"w"},
    aim_down = {"s"},
    dash = {"lshift", "rshift"},
    crouch = {"lctrl"},
    attack = {"j", "x"},
    stab = {"l"}
}

-- Helper function to check if any key in a list is pressed
local function is_any_down(keys)
    for _, key in ipairs(keys) do
        if love.keyboard.isDown(key) then
            return true
        end
    end
    return false
end

-- Returns a structured table representing the current logical state of the inputs.
-- This keeps input polling clean and decoupled from game physics.
function Input.get_state()
    local dx = 0
    if is_any_down(KEYMAP.left) then
        dx = -1
    elseif is_any_down(KEYMAP.right) then
        dx = 1
    end

    local dy = 0
    if is_any_down(KEYMAP.aim_up) then
        dy = -1
    elseif is_any_down(KEYMAP.aim_down) then
        dy = 1
    end

    return {
        dx = dx,
        dy = dy,
        jump = is_any_down(KEYMAP.up),
        dash = is_any_down(KEYMAP.dash),
        crouch = is_any_down(KEYMAP.crouch),
        attack = is_any_down(KEYMAP.attack),
        stab = is_any_down(KEYMAP.stab)
    }
end

return Input