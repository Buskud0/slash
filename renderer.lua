local config = require "config"

local Renderer = {}

local function draw_rect(x, y, h, r, g, b)
    love.graphics.setColor(r, g, b)
    love.graphics.rectangle("fill", x, y, config.SPRITE_SIZE, h)
end

local function draw_nickname(name, x, y, h)
    love.graphics.setColor(1, 1, 1)
    local font = love.graphics.getFont()
    local text_w = font:getWidth(name) * 0.25
    local text_x = x + (config.SPRITE_SIZE / 2) - (text_w / 2)
    love.graphics.print(name, text_x, y + h + 1, 0, 0.25, 0.25)
end

local function draw_attack_hitbox(x, y, h, angle, timer)
    local cx = x + (config.SPRITE_SIZE / 2)
    local cy = y + (h / 2)
    
    love.graphics.setColor(1, 0, 0, 0.6)
    love.graphics.setLineWidth(2)

    if timer > 0 then
        -- Render Swing
        local progress = (0.12 - timer) / 0.12
        local facing = math.cos(angle) >= 0 and 1 or -1
        local s_dir = math.sin(angle) > 0.01 and -1 or 1
        local sweep_angle = angle + s_dir * facing * (math.pi / 4) - progress * s_dir * facing * (math.pi / 2)
        local tx = cx + math.cos(sweep_angle) * 38
        local ty = cy + math.sin(sweep_angle) * 38
        love.graphics.line(cx, cy, tx, ty)
    else
        -- Render Stab
        local abs_timer = math.abs(timer)
        local progress = (0.15 - abs_timer) / 0.15
        -- Linear sine curve extends and retracts the blade smoothly
        local radius = math.sin(progress * math.pi) * 38
        local tx = cx + math.cos(angle) * radius
        local ty = cy + math.sin(angle) * radius
        love.graphics.line(cx, cy, tx, ty)
    end
    
    love.graphics.setLineWidth(1)
end

local function draw_players(local_x, local_y, local_height, local_facing, local_attack_timer, players, my_id)
    for id, p in pairs(players) do
        local is_me = (id == my_id)
        local px = is_me and local_x or p.x
        local py = is_me and local_y or p.y
        local h = is_me and local_height or (p.height or config.PLAYER_STAND_HEIGHT)
        local facing = is_me and local_facing or (p.facing or 1)
        local timer = is_me and local_attack_timer or (p.attack_timer or 0)

        if is_me then
            draw_rect(px, py, h, 0, 1, 0)
            draw_nickname("You", px, py, h)
        else
            draw_rect(px, py, h, 1, 0, 0)
            draw_nickname("Guest " .. id, px, py, h)
        end

        -- Check absolute value to catch both positive swings and negative stabs
        if math.abs(timer) > 0 then
            draw_attack_hitbox(px, py, h, facing, timer)
        end
    end
end

function Renderer.draw(local_x, local_y, local_height, local_facing, local_attack_timer, players, my_id)
    love.graphics.push()
    love.graphics.scale(config.ZOOM, config.ZOOM)

    -- Floor
    love.graphics.setColor(1, 1, 1)
    love.graphics.line(0, config.GROUND_Y, 800, config.GROUND_Y)

    draw_players(local_x, local_y, local_height, local_facing, local_attack_timer, players, my_id)
    
    love.graphics.pop()
end

return Renderer