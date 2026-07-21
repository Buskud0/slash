local config = require "config"

local Renderer = {}
local damage_texts = {}

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

local function draw_bullets(bullets)
    if not bullets then return end
    love.graphics.setColor(0, 0.8, 0.9)
    for _, b in ipairs(bullets) do
        love.graphics.rectangle("fill", b.x - config.NET_SIZE / 2, b.y - config.NET_SIZE / 2, config.NET_SIZE, config.NET_SIZE)
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

local function draw_players(local_player, players, my_id)
    for id, p in pairs(players) do
        local is_me = (id == my_id)
        local px = is_me and local_player.x or p.x
        local py = is_me and local_player.y or p.y
        local h = is_me and local_player.height or (p.height or config.PLAYER_STAND_HEIGHT)
        local facing = is_me and (local_player.view_facing or local_player.facing) or (p.view_facing or p.facing or 1)
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

        local slow = is_me and local_player.slow_timer or (p.slow_timer or 0)
        if slow > 0 then
            love.graphics.setColor(0, 0.5, 1, 0.3)
            love.graphics.rectangle("fill", px - 1, py - 1, config.SPRITE_SIZE + 2, h + 2)
        end

        if not is_me then
            draw_bullets(p.bullets)
            draw_hook(p.hook, px, py, h)
        end
    end
end

local function draw_bot_players(bots)
    for i, bot in ipairs(bots) do
        draw_player_box(bot.x, bot.y, bot.height, 0.5, 0.5, 0.5)
        draw_nickname("Bot " .. i, bot.x, bot.y, bot.height)
        draw_health_bar(bot.x, bot.y - 5, bot.health)

        if math.abs(bot.attack_timer) > 0 then
            draw_sword_attack(bot.x, bot.y, bot.height, bot.view_facing or bot.facing, bot.attack_timer, bot.attack_type)
        end

        if bot.slow_timer and bot.slow_timer > 0 then
            love.graphics.setColor(0, 0.5, 1, 0.3)
            love.graphics.rectangle("fill", bot.x - 1, bot.y - 1, config.SPRITE_SIZE + 2, bot.height + 2)
        end

        draw_bullets(bot.bullets)
        draw_hook(bot.hook, bot.x, bot.y, bot.height)
    end
end

local function draw_floor()
    love.graphics.setColor(1, 1, 1)
    local screen_width = love.graphics.getWidth() / config.ZOOM
    love.graphics.line(0, config.GROUND_Y, screen_width, config.GROUND_Y)
end

function Renderer.add_damage(x, y, amount)
    table.insert(damage_texts, {
        x = x + config.SPRITE_SIZE / 2,
        y = y - 5,
        text = "-" .. amount,
        timer = 0.8,
        max_timer = 0.8,
        color = {1, 1, 1}
    })
end

function Renderer.add_clash(x, y)
    table.insert(damage_texts, {
        x = x,
        y = y,
        text = "*clash*",
        timer = 0.6,
        max_timer = 0.6,
        color = {1, 0.85, 0.2}
    })
end

function Renderer.update_damage_texts(dt)
    for i = #damage_texts, 1, -1 do
        local t = damage_texts[i]
        t.timer = t.timer - dt
        t.y = t.y - 30 * dt
        if t.timer <= 0 then
            table.remove(damage_texts, i)
        end
    end
end

function Renderer.draw(local_player, players, my_id, bots)
    love.graphics.push()
    love.graphics.scale(config.ZOOM, config.ZOOM)

    draw_floor()
    draw_players(local_player, players, my_id)
    draw_bot_players(bots)
    draw_bullets(local_player.bullets)
    draw_hook(local_player.hook, local_player.x, local_player.y, local_player.height)

    for _, t in ipairs(damage_texts) do
        local alpha = math.min(1, t.timer / (t.max_timer * 0.3))
        local c = t.color or {1, 1, 1}
        love.graphics.setColor(c[1], c[2], c[3], alpha)
        local font = love.graphics.getFont()
        local tw = font:getWidth(t.text) * 0.35
        love.graphics.print(t.text, t.x - tw / 2, t.y, 0, 0.35, 0.35)
    end
    
    love.graphics.pop()
end

return Renderer
