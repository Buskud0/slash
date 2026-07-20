local config = require "config"

local Renderer = {}

local function draw_player_box(x, y, h, r, g, b)
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

local function draw_health_bar(x, y, health)
    local bar_width = config.SPRITE_SIZE
    local bar_height = 2
    local hp_percent = math.max(0, math.min(1, health / config.MAX_HEALTH))
    
    love.graphics.setColor(0.3, 0.1, 0.1, 0.8)
    love.graphics.rectangle("fill", x, y, bar_width, bar_height)
    
    love.graphics.setColor(0.2, 0.9, 0.2, 0.9)
    love.graphics.rectangle("fill", x, y, bar_width * hp_percent, bar_height)
end

local function draw_sword_attack(x, y, h, angle, timer, attack_type)
    local cx = x + (config.SPRITE_SIZE / 2)
    local cy = y + (h / 2)
    
    love.graphics.setColor(1, 0, 0, 0.6)
    love.graphics.setLineWidth(2)

    if attack_type == "stab_left" or attack_type == "stab_right" or attack_type == "stab_up" or attack_type == "stab_down" then
        local duration = config.STAB_DURATION
        local progress = (duration - math.abs(timer)) / duration
        local radius = math.sin(progress * math.pi) * config.STAB_LENGTH
        local tx = cx + math.cos(angle) * radius
        local ty = cy + math.sin(angle) * radius
        love.graphics.line(cx, cy, tx, ty)

    elseif attack_type == "swing_up_left" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = math.pi - progress * (math.pi / 2)
        local tx = cx + math.cos(sweep) * config.SWING_LENGTH
        local ty = cy + math.sin(sweep) * config.SWING_LENGTH
        love.graphics.line(cx, cy, tx, ty)

    elseif attack_type == "swing_up_right" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = progress * (math.pi / 2)
        local tx = cx + math.cos(sweep) * config.SWING_LENGTH
        local ty = cy + math.sin(sweep) * config.SWING_LENGTH
        love.graphics.line(cx, cy, tx, ty)

    elseif attack_type == "swing_down_left" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = math.pi + progress * (math.pi / 2)
        local tx = cx + math.cos(sweep) * config.SWING_LENGTH
        local ty = cy + math.sin(sweep) * config.SWING_LENGTH
        love.graphics.line(cx, cy, tx, ty)

    elseif attack_type == "swing_down_right" then
        local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
        local sweep = -progress * (math.pi / 2)
        local tx = cx + math.cos(sweep) * config.SWING_LENGTH
        local ty = cy + math.sin(sweep) * config.SWING_LENGTH
        love.graphics.line(cx, cy, tx, ty)
    end
    
    love.graphics.setLineWidth(1)
end

local function draw_players(local_player, players, my_id)
    for id, p in pairs(players) do
        local is_me = (id == my_id)
        local px = is_me and local_player.x or p.x
        local py = is_me and local_player.y or p.y
        local h = is_me and local_player.height or (p.height or config.PLAYER_STAND_HEIGHT)
        local facing = is_me and local_player.facing or (p.facing or 1)
        local timer = is_me and local_player.attack_timer or (p.attack_timer or 0)
        local hp = is_me and local_player.health or (p.health or config.MAX_HEALTH)
        local at = is_me and local_player.attack_type or (p.attack_type or nil)

        if is_me then
            draw_player_box(px, py, h, 0, 1, 0)
            draw_nickname("You", px, py, h)
        else
            draw_player_box(px, py, h, 1, 0, 0)
            draw_nickname("Guest " .. id, px, py, h)
        end

        draw_health_bar(px, py - 5, hp)

        if math.abs(timer) > 0 then
            draw_sword_attack(px, py, h, facing, timer, at)
        end
    end
end

local function draw_floor()
    love.graphics.setColor(1, 1, 1)
    local screen_width = love.graphics.getWidth() / config.ZOOM
    love.graphics.line(0, config.GROUND_Y, screen_width, config.GROUND_Y)
end

local function draw_bullets(bullets)
    if not bullets then return end
    love.graphics.setColor(1, 1, 0)
    for _, b in ipairs(bullets) do
        love.graphics.rectangle("fill", b.x - config.BULLET_SIZE / 2, b.y - config.BULLET_SIZE / 2, config.BULLET_SIZE, config.BULLET_SIZE)
    end
end

local function draw_hook(hook, x, y, h)
    if not hook then return end
    local cx = x + (config.SPRITE_SIZE / 2)
    local cy = y + (h / 2)
    love.graphics.setColor(0.8, 0.8, 0.2)
    love.graphics.setLineWidth(1)
    love.graphics.line(cx, cy, hook.x, hook.y)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", hook.x - config.HOOK_SIZE / 2, hook.y - config.HOOK_SIZE / 2, config.HOOK_SIZE, config.HOOK_SIZE)
end

function Renderer.draw(local_player, players, my_id)
    love.graphics.push()
    love.graphics.scale(config.ZOOM, config.ZOOM)

    draw_floor()
    draw_players(local_player, players, my_id)
    draw_bullets(local_player.bullets)
    draw_hook(local_player.hook, local_player.x, local_player.y, local_player.height)
    
    love.graphics.pop()
end

return Renderer
