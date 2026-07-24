local Client = require "client"
local Chat = require "chat"
local Menu = require "menu"
local Network = require "network"

function love.load()
    Client.init()
end

function love.update(dt)
    Client.update(dt)
end

function love.draw()
    Client.draw()
end

function love.textinput(text)
    if Client.is_active() then
        Chat.textinput(text)
    end
end

function love.keypressed(key)
    if Client.is_active() then
        if Menu.is_open then
            Menu.keypressed(key)
            return
        end
        if key == "escape" then
            Menu.toggle()
            return
        end
        if key == "p" and not Chat.is_typing then
            Client.try_toggle_bots()
            return
        end
        local msg = Chat.keypressed(key)
        if msg then
            Network.send_chat(msg)
        end
    end
end

function love.mousepressed(x, y, button)
    if Menu.is_open then
        Menu.mousepressed(x, y)
    end
end

function love.wheelmoved(x, y)
    if Client.is_active() then
        Chat.wheelmoved(y)
    end
end

function love.quit()
    Client.quit()
end
