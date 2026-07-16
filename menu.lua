local Menu = { choice = nil }

function Menu.update()
    if love.keyboard.isDown("h") then
        Menu.choice = "host"
    elseif love.keyboard.isDown("j") then
        Menu.choice = "join"
    end
    return Menu.choice
end

function Menu.draw()
    love.graphics.print("Press 'H' to Host (Server)", 100, 100)
    love.graphics.print("Press 'J' to Join (Client)", 100, 130)
end

return Menu