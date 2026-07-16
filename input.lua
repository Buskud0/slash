local Input = {}

function Input.get_movement()
    local dx, dy = 0, 0
    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then dx = -1
    elseif love.keyboard.isDown("right") or love.keyboard.isDown("d") then dx = 1 end
    if love.keyboard.isDown("up") or love.keyboard.isDown("w") then dy = -1
    elseif love.keyboard.isDown("down") or love.keyboard.isDown("s") then dy = 1 end
    return dx, dy
end

function Input.get_jump()
    return love.keyboard.isDown("up") or love.keyboard.isDown("w")
end

function Input.get_actions()
    local dash = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    local s_held = love.keyboard.isDown("s") or love.keyboard.isDown("down")
    local attack = love.keyboard.isDown("j") or love.keyboard.isDown("x")
    local stab = love.keyboard.isDown("l")
    return dash, s_held, s_held, attack, stab
end

return Input