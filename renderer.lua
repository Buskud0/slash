local config = require "config"

local Renderer = {}

-- Private Helper: Draws a single player box with designated RGB colors
local function draw_player_box(x, y, h, r, g, b)
    love.graphics.setColor(r, g, b)
    love.graphics.rectangle("fill", x, y, config.SPRITE_SIZE, h)
end

-- Private Helper: Renders text above/below the player relative to their height
local function draw_nickname(name, x, y, h)
    love.graphics.setColor(1, 1, 1)
    local font = love.graphics.getFont()
    local text_w = font:getWidth(name) * 0.25
    local text_x = x + (config.SPRITE_SIZE / 2) - (text_w / 2)
    -- Prints text scaled down to fit nicely in pixel art style
    love.graphics.print(name, text_x, y + h + 1, 0, 0.25, 0.25)
end

-- Private Helper: Draws a tiny green/red health bar above a player
local function draw_health_bar(x, y, health)
    local bar_width = config.SPRITE_SIZE
    local bar_height = 2
    local hp_percent = math.max(0, math.min(1, health / config.MAX_HEALTH))
    
    -- Draw background bar (dark red/gray)
    love.graphics.setColor(0.3, 0.1, 0.1, 0.8)
    love.graphics.rectangle("fill", x, y, bar_width, bar_height)
    
    -- Draw foreground bar (green)
    love.graphics.setColor(0.2, 0.9, 0.2, 0.9)
    love.graphics.rectangle("fill", x, y, bar_width * hp_percent, bar_height)
end

-- Private Helper: Draws the sword slash/stab visual effects using trigonometric sweeps
local function draw_sword_attack(x, y, h, angle, timer)
    local cx = x + (config.SPRITE_SIZE / 2)
    local cy = y + (h / 2)
    
    love.graphics.setColor(1, 0, 0, 0.6)
    love.graphics.setLineWidth(2)

    if timer > 0 then
        -- Swing rendering (curved sweep motion)
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local facing = math.cos(angle) >= 0 and 1 or -1
        local s_dir = math.sin(angle) > 0.01 and -1 or 1
        local sweep_angle = angle + s_dir * facing * (math.pi / 4) - progress * s_dir * facing * (math.pi / 2)
        local tx = cx + math.cos(sweep_angle) * config.SWORD_LENGTH
        local ty = cy + math.sin(sweep_angle) * config.SWORD_LENGTH
        love.graphics.line(cx, cy, tx, ty)
    else
        -- Stab rendering (linear thrust motion)
        local abs_timer = math.abs(timer)
        local progress = (config.STAB_DURATION - abs_timer) / config.STAB_DURATION
        -- Linear sine curve extends and retracts the blade smoothly
        local radius = math.sin(progress * math.pi) * config.SWORD_LENGTH
        local tx = cx + math.cos(angle) * radius
        local ty = cy + math.sin(angle) * radius
        love.graphics.line(cx, cy, tx, ty)
    end
    
    love.graphics.setLineWidth(1)
end

-- Private Helper: Iterates through all connected players, drawing them and their active sword attacks
local function draw_players(local_player, players, my_id)
    for id, p in pairs(players) do
        local is_me = (id == my_id)
        local px = is_me and local_player.x or p.x
        local py = is_me and local_player.y or p.y
        local h = is_me and local_player.height or (p.height or config.PLAYER_STAND_HEIGHT)
        local facing = is_me and local_player.facing or (p.facing or 1)
        local timer = is_me and local_player.attack_timer or (p.attack_timer or 0)
        local hp = is_me and local_player.health or (p.health or config.MAX_HEALTH)

        if is_me then
            -- Draw local player as green box
            draw_player_box(px, py, h, 0, 1, 0)
            draw_nickname("You", px, py, h)
        else
            -- Draw guest players as red box
            draw_player_box(px, py, h, 1, 0, 0)
            draw_nickname("Guest " .. id, px, py, h)
        end

        -- Draw visual health bar 5 pixels above player's head
        draw_health_bar(px, py - 5, hp)

        -- Check absolute value to catch both positive swings and negative stabs
        if math.abs(timer) > 0 then
            draw_sword_attack(px, py, h, facing, timer)
        end
    end
end

-- Private Helper: Draws the static floor line across the window width
local function draw_floor()
    love.graphics.setColor(1, 1, 1)
    local screen_width = love.graphics.getWidth() / config.ZOOM
    love.graphics.line(0, config.GROUND_Y, screen_width, config.GROUND_Y)
end

-- Main entry point for renderer: sets up zoom/scale transformation, draws scene background/elements
function Renderer.draw(local_player, players, my_id)
    love.graphics.push()
    love.graphics.scale(config.ZOOM, config.ZOOM)

    draw_floor()
    draw_players(local_player, players, my_id)
    
    love.graphics.pop()
end

return Renderer