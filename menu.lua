local Menu = {}
Menu.is_open = false

local screen = "main"

local bot_settings = {
    allow_stab = true,
    allow_swing = true,
    allow_net = true,
    allow_hook = true,
    invincible = false,
    movement = "chase",
}

local main_items = {
    { label = "Bot Settings", action = function() screen = "bots" end },
}

local bot_toggles = {
    { key = "allow_stab",  label = "Stab" },
    { key = "allow_swing", label = "Swing" },
    { key = "allow_net",   label = "Net" },
    { key = "allow_hook",  label = "Hook" },
    { key = "invincible",  label = "Invincible" },
}

local movement_modes = {
    { key = "chase",       label = "Chase Player" },
    { key = "stand_still", label = "Stand Still" },
    { key = "to_center",   label = "Walk to Center" },
}

local function get_scale(sw, sh)
    local base = math.min(sw, sh)
    return base / 600
end

local function get_hitbox(x, y, w, h)
    local mx, my = love.mouse.getPosition()
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function draw_check(x, y, s, checked)
    local sz = 20 * s
    love.graphics.setColor(0.3, 0.3, 0.3)
    love.graphics.rectangle("line", x, y, sz, sz)
    if checked then
        love.graphics.setColor(0.2, 0.9, 0.3)
        love.graphics.rectangle("fill", x + 3 * s, y + 3 * s, sz - 6 * s, sz - 6 * s)
    end
end

local function draw_radio(x, y, s, selected)
    local r = 10 * s
    love.graphics.setColor(0.3, 0.3, 0.3)
    love.graphics.circle("line", x + r, y + r, r)
    if selected then
        love.graphics.setColor(0.2, 0.6, 1.0)
        love.graphics.circle("fill", x + r, y + r, r * 0.6)
    end
end

function Menu.toggle()
    Menu.is_open = not Menu.is_open
    if Menu.is_open then
        screen = "main"
    end
end

function Menu.get_settings()
    return bot_settings
end

function Menu.mousepressed(mx, my)
    if not Menu.is_open then return end
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local s = get_scale(sw, sh)

    if screen == "main" then
        local pw = 320 * s
        local ph = (60 + #main_items * 56) * s
        local px = sw / 2 - pw / 2
        local py = sh / 2 - ph / 2
        for i, item in ipairs(main_items) do
            local iy = py + 60 * s + (i - 1) * 56 * s
            if get_hitbox(px, iy, pw, 44 * s) then
                item.action()
                return
            end
        end

    elseif screen == "bots" then
        local pw = 360 * s
        local toggle_h = 40 * s
        local toggle_gap = 50 * s
        local mode_h = 38 * s
        local mode_gap = 44 * s
        local total_h = (60 + #bot_toggles * 50 + 20 + 30 + #movement_modes * 44 + 30 + 50) * s
        local px = sw / 2 - pw / 2
        local py = sh / 2 - total_h / 2

        local toggle_y = py + 60 * s
        for i, item in ipairs(bot_toggles) do
            local iy = toggle_y + (i - 1) * toggle_gap
            if get_hitbox(px, iy, pw, toggle_h) then
                bot_settings[item.key] = not bot_settings[item.key]
                return
            end
        end

        local mode_label_y = toggle_y + #bot_toggles * toggle_gap + 20 * s
        local mode_y = mode_label_y + 30 * s
        for i, mode in ipairs(movement_modes) do
            local iy = mode_y + (i - 1) * mode_gap
            if get_hitbox(px, iy, pw, mode_h) then
                bot_settings.movement = mode.key
                return
            end
        end

        local back_y = mode_y + #movement_modes * mode_gap + 30 * s
        if get_hitbox(px, back_y, pw, 44 * s) then
            screen = "main"
            return
        end
    end
end

function Menu.keypressed(key)
    if not Menu.is_open then return end

    if key == "escape" then
        if screen == "bots" then
            screen = "main"
        else
            Menu.is_open = false
        end
        return
    end

    if screen == "main" then
        if key == "1" then
            screen = "bots"
        end

    elseif screen == "bots" then
        if key == "1" then bot_settings.allow_stab = not bot_settings.allow_stab
        elseif key == "2" then bot_settings.allow_swing = not bot_settings.allow_swing
        elseif key == "3" then bot_settings.allow_net = not bot_settings.allow_net
        elseif key == "4" then bot_settings.allow_hook = not bot_settings.allow_hook
        elseif key == "5" then bot_settings.invincible = not bot_settings.invincible
        elseif key == "6" then bot_settings.movement = "chase"
        elseif key == "7" then bot_settings.movement = "stand_still"
        elseif key == "8" then bot_settings.movement = "to_center"
        end
    end
end

function Menu.draw()
    if not Menu.is_open then return end

    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local s = get_scale(sw, sh)

    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    if screen == "main" then
        Menu.draw_main(sw, sh, s)
    elseif screen == "bots" then
        Menu.draw_bots(sw, sh, s)
    end
end

function Menu.draw_main(sw, sh, s)
    local pw = 320 * s
    local ph = (60 + #main_items * 56) * s
    local px = sw / 2 - pw / 2
    local py = sh / 2 - ph / 2

    love.graphics.setColor(0.15, 0.15, 0.15, 0.95)
    love.graphics.rectangle("fill", px, py, pw, ph, 8 * s, 8 * s)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("MENU", px + pw / 2 - love.graphics.getFont():getWidth("MENU") * 0.9 * s, py + 15 * s, 0, 1.8 * s, 1.8 * s)

    for i, item in ipairs(main_items) do
        local iy = py + 60 * s + (i - 1) * 56 * s
        local hovered = get_hitbox(px, iy, pw, 44 * s)
        love.graphics.setColor(hovered and 0.35 or 0.25, hovered and 0.35 or 0.25, hovered and 0.35 or 0.25, 0.9)
        love.graphics.rectangle("fill", px + 10 * s, iy, pw - 20 * s, 44 * s, 6 * s, 6 * s)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(item.label, px + 30 * s, iy + 10 * s, 0, 1.2 * s, 1.2 * s)
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.print(">", px + pw - 50 * s, iy + 10 * s, 0, 1.2 * s, 1.2 * s)
    end
end

function Menu.draw_bots(sw, sh, s)
    local pw = 360 * s
    local toggle_h = 40 * s
    local toggle_gap = 50 * s
    local mode_h = 38 * s
    local mode_gap = 44 * s
    local total_h = (60 + #bot_toggles * 50 + 20 + 30 + #movement_modes * 44 + 30 + 50) * s
    local px = sw / 2 - pw / 2
    local py = sh / 2 - total_h / 2

    love.graphics.setColor(0.15, 0.15, 0.15, 0.95)
    love.graphics.rectangle("fill", px, py, pw, total_h, 8 * s, 8 * s)

    love.graphics.setColor(1, 1, 1)
    local title = "Bot Settings"
    love.graphics.print(title, px + pw / 2 - love.graphics.getFont():getWidth(title) * 0.8 * s, py + 15 * s, 0, 1.6 * s, 1.6 * s)

    local toggle_y = py + 60 * s
    for i, item in ipairs(bot_toggles) do
        local iy = toggle_y + (i - 1) * toggle_gap
        local hovered = get_hitbox(px, iy, pw, toggle_h)
        love.graphics.setColor(hovered and 0.3 or 0.2, hovered and 0.3 or 0.2, hovered and 0.3 or 0.2, 0.8)
        love.graphics.rectangle("fill", px + 10 * s, iy, pw - 20 * s, toggle_h, 4 * s, 4 * s)

        draw_check(px + 16 * s, iy + (toggle_h - 20 * s) / 2, s, bot_settings[item.key])

        love.graphics.setColor(1, 1, 1)
        love.graphics.print(item.label, px + 48 * s, iy + (toggle_h - 14 * s) / 2, 0, 1.1 * s, 1.1 * s)
    end

    local mode_label_y = toggle_y + #bot_toggles * toggle_gap + 20 * s
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.print("Movement:", px + 10 * s, mode_label_y, 0, 1.0 * s, 1.0 * s)

    local mode_y = mode_label_y + 30 * s
    for i, mode in ipairs(movement_modes) do
        local iy = mode_y + (i - 1) * mode_gap
        local hovered = get_hitbox(px, iy, pw, mode_h)
        love.graphics.setColor(hovered and 0.3 or 0.2, hovered and 0.3 or 0.2, hovered and 0.3 or 0.2, 0.8)
        love.graphics.rectangle("fill", px + 10 * s, iy, pw - 20 * s, mode_h, 4 * s, 4 * s)

        draw_radio(px + 16 * s, iy + (mode_h - 20 * s) / 2, s, bot_settings.movement == mode.key)

        love.graphics.setColor(1, 1, 1)
        love.graphics.print(mode.label, px + 48 * s, iy + (mode_h - 14 * s) / 2, 0, 1.0 * s, 1.0 * s)
    end

    local back_y = mode_y + #movement_modes * mode_gap + 30 * s
    local hovered = get_hitbox(px, back_y, pw, 44 * s)
    love.graphics.setColor(hovered and 0.4 or 0.3, hovered and 0.2 or 0.15, hovered and 0.2 or 0.15, 0.9)
    love.graphics.rectangle("fill", px + 10 * s, back_y, pw - 20 * s, 44 * s, 6 * s, 6 * s)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("< Back", px + 30 * s, back_y + 10 * s, 0, 1.2 * s, 1.2 * s)
end

return Menu
