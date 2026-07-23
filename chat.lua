local Chat = { logs = {}, is_typing = false, current_text = "", scroll_offset = 0 }
local MAX_MSG_LEN = 60

local function wrap_text(text, max_width)
    local lines = {}
    local remaining = text
    local font = love.graphics.getFont()
    while #remaining > 0 do
        if font:getWidth(remaining) <= max_width then
            table.insert(lines, remaining)
            break
        end
        local cut = #remaining
        while cut > 1 and font:getWidth(remaining:sub(1, cut)) > max_width do
            cut = cut - 1
        end
        table.insert(lines, remaining:sub(1, cut))
        remaining = remaining:sub(cut + 1)
    end
    if #lines == 0 then lines = { "" } end
    return lines
end

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
        elseif #Chat.current_text < MAX_MSG_LEN then
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
    local box_x = 10
    local box_w = 200
    local line_h = 18
    local text_max_w = box_w - 10
    local base_y = love.graphics.getHeight() - 40

    if Chat.is_typing then
        local visible = {}
        local max_visible = 6
        local start_idx = #Chat.logs - Chat.scroll_offset
        local end_idx = math.max(1, start_idx - max_visible + 1)
        for i = start_idx, end_idx, -1 do
            if Chat.logs[i] then
                table.insert(visible, 1, Chat.logs[i])
            end
        end

        local all_lines = {}
        for _, log in ipairs(visible) do
            local wl = wrap_text(log.text, text_max_w)
            for _, line in ipairs(wl) do
                table.insert(all_lines, { text = line, alpha = 1 })
            end
        end
        local input_lines = wrap_text("Say: " .. Chat.current_text .. "_", text_max_w)
        for _, il in ipairs(input_lines) do
            table.insert(all_lines, { text = il, alpha = 1 })
        end

        local total_lines = #all_lines
        local box_h = (total_lines * line_h) + 5
        local box_y = base_y - box_h

        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", box_x, box_y, box_w, box_h, 4)

        local draw_y = box_y + 3
        for i = 1, #all_lines do
            local entry = all_lines[i]
            love.graphics.setColor(1, 1, 1, entry.alpha)
            love.graphics.print(entry.text, box_x + 5, draw_y)
            draw_y = draw_y + line_h
        end
    else
        local start_idx = #Chat.logs
        local max_show = math.min(3, #Chat.logs)
        local end_idx = math.max(1, start_idx - max_show + 1)

        local all_lines = {}
        for i = end_idx, start_idx do
            local log = Chat.logs[i]
            if log then
                local wl = wrap_text(log.text, text_max_w)
                for _, line in ipairs(wl) do
                    table.insert(all_lines, { text = line, alpha = log.fade })
                end
            end
        end

        local draw_y = base_y - (#all_lines * line_h)
        for _, entry in ipairs(all_lines) do
            if entry.alpha > 0 then
                love.graphics.setColor(1, 1, 1, entry.alpha)
                love.graphics.print(entry.text, 15, draw_y)
            end
            draw_y = draw_y + line_h
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Chat