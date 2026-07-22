local Menu = {}
Menu.is_open = false

local screen = "main"

local SAVE_FILE = "bot_settings.txt"

local defaults = {
    allow_stab = true,
    allow_swing = true,
    allow_net = true,
    allow_hook = true,
    allow_jump = true,
    allow_dash = false,
    invincible = false,
    movement = "chase",
}

local bot_settings = {}
for k, v in pairs(defaults) do bot_settings[k] = v end

local bots_enabled = false
local toggle_bots_pending = false

local main_items = {
    { label = "Bot Settings", action = function() screen = "bots" end },
}

local attack_toggles = {
    { key = "allow_stab",  label = "Stab" },
    { key = "allow_swing", label = "Swing" },
    { key = "allow_net",   label = "Net" },
    { key = "allow_hook",  label = "Hook" },
}

local movement_modes = {
    { key = "chase",       label = "Chase Player" },
    { key = "stand_still", label = "Stand Still" },
    { key = "to_center",   label = "Walk to Center" },
}

local bool_keys = {"allow_stab", "allow_swing", "allow_net", "allow_hook", "allow_jump", "allow_dash", "invincible"}

local function save_settings()
    local lines = {}
    for _, k in ipairs(bool_keys) do
        table.insert(lines, k .. "=" .. tostring(bot_settings[k]))
    end
    table.insert(lines, "movement=" .. bot_settings.movement)
    love.filesystem.write(SAVE_FILE, table.concat(lines, "\n"))
end

local function load_settings()
    local info = love.filesystem.getInfo(SAVE_FILE)
    if not info then return end
    local content, _ = love.filesystem.read(SAVE_FILE)
    if not content then return end
    for line in content:gmatch("[^\n]+") do
        local k, v = line:match("^([^=]+)=(.+)$")
        if k and v then
            if v == "true" then
                bot_settings[k] = true
            elseif v == "false" then
                bot_settings[k] = false
            else
                bot_settings[k] = v
            end
        end
    end
end

load_settings()

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

local function draw_toggle(x, y, w, h, s, label, checked, grayed)
    local hovered = not grayed and get_hitbox(x, y, w, h)
    if grayed then
        love.graphics.setColor(0.12, 0.12, 0.12, 0.6)
    else
        love.graphics.setColor(hovered and 0.3 or 0.2, hovered and 0.3 or 0.2, hovered and 0.3 or 0.2, 0.8)
    end
    love.graphics.rectangle("fill", x, y, w, h, 4 * s, 4 * s)
    draw_check(x + 6 * s, y + (h - 20 * s) / 2, s, checked)
    if grayed then
        love.graphics.setColor(0.4, 0.4, 0.4)
    else
        love.graphics.setColor(1, 1, 1)
    end
    love.graphics.print(label, x + 32 * s, y + (h - 14 * s) / 2, 0, 1.1 * s, 1.1 * s)
end

local function draw_radio_item(x, y, w, h, s, label, selected)
    local hovered = get_hitbox(x, y, w, h)
    love.graphics.setColor(hovered and 0.3 or 0.2, hovered and 0.3 or 0.2, hovered and 0.3 or 0.2, 0.8)
    love.graphics.rectangle("fill", x, y, w, h, 4 * s, 4 * s)
    draw_radio(x + 6 * s, y + (h - 20 * s) / 2, s, selected)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(label, x + 32 * s, y + (h - 14 * s) / 2, 0, 1.0 * s, 1.0 * s)
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

function Menu.set_bots_enabled(enabled)
    bots_enabled = enabled
end

function Menu.consume_toggle_bots()
    if toggle_bots_pending then
        toggle_bots_pending = false
        return true
    end
    return false
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
        local pw = 620
        local title_h = 60
        local label_h = 30
        local toggle_h = 40
        local toggle_gap = 50
        local mode_h = 38
        local mode_gap = 44
        local section_gap = 20
        local back_h = 44
        local padding = 15
        local col_gap = 20

        local left_w = 290
        local right_w = 290

        local left_col_h = label_h + #movement_modes * mode_gap
            + section_gap + toggle_h
            + section_gap + label_h + #attack_toggles * toggle_gap
        local right_col_h = label_h + toggle_h + section_gap + toggle_h + section_gap + toggle_h
        local content_h = math.max(left_col_h, right_col_h)

        local raw_h = title_h + content_h + section_gap + back_h + padding
        local pw_s = pw * s
        local total_h = raw_h * s
        local px = sw / 2 - pw_s / 2
        local py = sh / 2 - total_h / 2

        local left_x = px
        local right_x = px + (left_w + col_gap) * s

        local y = py + title_h * s

        local ry = y

        ry = ry + label_h * s
        for i, mode in ipairs(movement_modes) do
            local iy = ry + (i - 1) * mode_gap * s
            if get_hitbox(right_x, iy, right_w * s, mode_h * s) then
                bot_settings.movement = mode.key
                save_settings()
                return
            end
        end

        local inv_y = ry + #movement_modes * mode_gap * s + section_gap * s
        if get_hitbox(right_x, inv_y, right_w * s, toggle_h * s) then
            bot_settings.invincible = not bot_settings.invincible
            save_settings()
            return
        end

        local jump_y = inv_y + toggle_h * s + section_gap * s
        if bot_settings.movement == "chase" and get_hitbox(right_x, jump_y, right_w * s, toggle_h * s) then
            bot_settings.allow_jump = not bot_settings.allow_jump
            save_settings()
            return
        end

        local dash_y = jump_y + toggle_h * s + section_gap * s
        if bot_settings.movement == "chase" and get_hitbox(right_x, dash_y, right_w * s, toggle_h * s) then
            bot_settings.allow_dash = not bot_settings.allow_dash
            save_settings()
            return
        end

        local ly = y

        ly = ly + label_h * s
        if get_hitbox(left_x, ly, left_w * s, toggle_h * s) then
            toggle_bots_pending = true
            return
        end

        local attack_label_y = ly + toggle_h * s + section_gap * s
        local attack_y = attack_label_y + label_h * s
        for i, item in ipairs(attack_toggles) do
            local iy = attack_y + (i - 1) * toggle_gap * s
            if bot_settings.movement == "chase" and get_hitbox(left_x, iy, left_w * s, toggle_h * s) then
                bot_settings[item.key] = not bot_settings[item.key]
                save_settings()
                return
            end
        end

        local back_y = py + title_h * s + content_h * s + section_gap * s
        if get_hitbox(px, back_y, pw_s, back_h * s) then
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
        local changed = true
        if key == "1" then toggle_bots_pending = true
        elseif key == "2" then bot_settings.movement = "chase"
        elseif key == "3" then bot_settings.movement = "stand_still"
        elseif key == "4" then bot_settings.movement = "to_center"
        elseif key == "5" then bot_settings.invincible = not bot_settings.invincible
        elseif key == "6" and bot_settings.movement == "chase" then bot_settings.allow_jump = not bot_settings.allow_jump
        elseif key == "7" and bot_settings.movement == "chase" then bot_settings.allow_stab = not bot_settings.allow_stab
        elseif key == "8" and bot_settings.movement == "chase" then bot_settings.allow_swing = not bot_settings.allow_swing
        elseif key == "9" and bot_settings.movement == "chase" then bot_settings.allow_net = not bot_settings.allow_net
        elseif key == "0" and bot_settings.movement == "chase" then bot_settings.allow_hook = not bot_settings.allow_hook
        else changed = false
        end
        if changed then save_settings() end
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
    local pw = 620
    local title_h = 60
    local label_h = 30
    local toggle_h = 40
    local toggle_gap = 50
    local mode_h = 38
    local mode_gap = 44
    local section_gap = 20
    local back_h = 44
    local padding = 15
    local col_gap = 20

    local left_w = 290
    local right_w = 290

    local left_col_h = label_h + #movement_modes * mode_gap
        + section_gap + toggle_h
        + section_gap + label_h + #attack_toggles * toggle_gap
    local right_col_h = label_h + toggle_h + section_gap + toggle_h + section_gap + toggle_h
    local content_h = math.max(left_col_h, right_col_h)

    local raw_h = title_h + content_h + section_gap + back_h + padding
    local pw_s = pw * s
    local total_h = raw_h * s
    local px = sw / 2 - pw_s / 2
    local py = sh / 2 - total_h / 2

    love.graphics.setColor(0.15, 0.15, 0.15, 0.95)
    love.graphics.rectangle("fill", px, py, pw_s, total_h, 8 * s, 8 * s)

    love.graphics.setColor(1, 1, 1)
    local title = "Bot Settings"
    love.graphics.print(title, px + pw_s / 2 - love.graphics.getFont():getWidth(title) * 0.8 * s, py + 15 * s, 0, 1.6 * s, 1.6 * s)

    local left_x = px
    local right_x = px + (left_w + col_gap) * s

    local y = py + title_h * s

    local ly = y

    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.print("General:", left_x + 10 * s, ly, 0, 1.0 * s, 1.0 * s)

    ly = ly + label_h * s
    draw_toggle(left_x + 10 * s, ly, left_w * s, toggle_h * s, s, "Enable Bots", bots_enabled, false)

    local ry = y

    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.print("Movement:", right_x + 10 * s, ry, 0, 1.0 * s, 1.0 * s)

    ry = ry + label_h * s
    for i, mode in ipairs(movement_modes) do
        local iy = ry + (i - 1) * mode_gap * s
        draw_radio_item(right_x + 10 * s, iy, right_w * s, mode_h * s, s, mode.label, bot_settings.movement == mode.key)
    end

    local inv_y = ry + #movement_modes * mode_gap * s + section_gap * s
    draw_toggle(right_x + 10 * s, inv_y, right_w * s, toggle_h * s, s, "Invincible", bot_settings.invincible, false)

    local grayed = bot_settings.movement ~= "chase"

    local jump_y = inv_y + toggle_h * s + section_gap * s
    draw_toggle(right_x + 10 * s, jump_y, right_w * s, toggle_h * s, s, "Jumping", bot_settings.allow_jump, grayed)

    local dash_y = jump_y + toggle_h * s + section_gap * s
    draw_toggle(right_x + 10 * s, dash_y, right_w * s, toggle_h * s, s, "Dashing", bot_settings.allow_dash, grayed)

    local attack_label_y = ly + toggle_h * s + section_gap * s
    local label_r, label_g, label_b = 0.6, 0.6, 0.6
    if grayed then label_r, label_g, label_b = 0.35, 0.35, 0.35 end
    love.graphics.setColor(label_r, label_g, label_b)
    love.graphics.print("Attacks:", left_x + 10 * s, attack_label_y, 0, 1.0 * s, 1.0 * s)

    local attack_y = attack_label_y + label_h * s
    for i, item in ipairs(attack_toggles) do
        local iy = attack_y + (i - 1) * toggle_gap * s
        draw_toggle(left_x + 10 * s, iy, left_w * s, toggle_h * s, s, item.label, bot_settings[item.key], grayed)
    end

    local back_y = py + title_h * s + content_h * s + section_gap * s
    local hovered = get_hitbox(px, back_y, pw_s, back_h * s)
    love.graphics.setColor(hovered and 0.4 or 0.3, hovered and 0.2 or 0.15, hovered and 0.2 or 0.15, 0.9)
    love.graphics.rectangle("fill", px + 10 * s, back_y, pw_s - 20 * s, back_h * s, 6 * s, 6 * s)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("< Back", px + 30 * s, back_y + 10 * s, 0, 1.2 * s, 1.2 * s)
end

return Menu
