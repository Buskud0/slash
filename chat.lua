local Chat = { logs = {}, is_typing = false, current_text = "", scroll_offset = 0 }

function Chat.add(text)
    -- Max history set to 20 to support scrolling
    table.insert(Chat.logs, { text = text, timer = 5.0, fade = 1.0 })
    if #Chat.logs > 20 then
        table.remove(Chat.logs, 1)
    end
end

function Chat.update(dt)
    -- Timers always update in the background to ensure perfect cross-player sync
    for _, log in ipairs(Chat.logs) do
        if log.timer > 0 then
            log.timer = math.max(0, log.timer - dt)
        else
            log.fade = math.max(0, log.fade - dt)
        end
    end

    -- Safeguard: instantly reset scroll position when chat is closed
    if not Chat.is_typing then
        Chat.scroll_offset = 0
    end
end

function Chat.textinput(text)
    if Chat.is_typing then
        if Chat.ignore_first_y then
            Chat.ignore_first_y = false
        else
            Chat.current_text = Chat.current_text .. text
        end
    end
end

function Chat.keypressed(key)
    if not Chat.is_typing then
        if key == "y" then
            Chat.is_typing = true
            Chat.current_text = ""
            Chat.scroll_offset = 0
            Chat.ignore_first_y = true
        end
    else
        if key == "escape" then
            Chat.is_typing = false
        elseif key == "backspace" then
            Chat.current_text = Chat.current_text:sub(1, -2)
        elseif key == "return" then
            Chat.is_typing = false
            local msg = Chat.current_text
            Chat.current_text = ""
            return msg ~= "" and msg or nil
        end
    end
end

function Chat.wheelmoved(y_dir)
    if Chat.is_typing then
        local max_visible = 6 -- Limit window draw size inside background card
        local max_scroll = math.max(0, #Chat.logs - max_visible)
        Chat.scroll_offset = math.max(0, math.min(max_scroll, Chat.scroll_offset + y_dir))
    end
end

function Chat.draw()
    local base_y = love.graphics.getHeight() - 40
    local max_show = Chat.is_typing and 6 or math.min(3, #Chat.logs)
    local start_idx = #Chat.logs - Chat.scroll_offset
    local end_idx = math.max(1, start_idx - max_show + 1)

    if Chat.is_typing then
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", 10, base_y - (max_show * 18) + 10, 350, (max_show * 18) + 5, 4)
    end

    local draw_y = base_y
    for i = start_idx, end_idx, -1 do
        local log = Chat.logs[i]
        if log then
            -- Override to solid opacity when typing, otherwise use synchronous fade
            local alpha = Chat.is_typing and 1 or log.fade
            if alpha > 0 then
                love.graphics.setColor(1, 1, 1, alpha)
                love.graphics.print(log.text, 15, draw_y)
                draw_y = draw_y - 18
            end
        end
    end

    if Chat.is_typing then
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.print("Say: " .. Chat.current_text .. "_", 15, love.graphics.getHeight() - 25)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Chat