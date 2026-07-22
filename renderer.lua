local config = require "config"

local Renderer = {}
local Menu = require "menu"
local V = require "visuals"

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

local function draw_bullets(bullets)
    if not bullets then return end
    for _, b in ipairs(bullets) do
        V.draw_bullet_glow(b.x, b.y)
        love.graphics.setColor(0, 0.8, 0.9)
        love.graphics.rectangle("fill", b.x - config.NET_SIZE / 2, b.y - config.NET_SIZE / 2, config.NET_SIZE, config.NET_SIZE)
    end
end

local function draw_hook(hook, x, y, h)
    if not hook then return end
    local cx = x + (config.SPRITE_SIZE / 2)
    local cy = y + (h / 2)
    V.draw_hook_chain(cx, cy, hook.x, hook.y)
    love.graphics.setColor(0.8, 0.8, 0.2)
    love.graphics.setLineWidth(1)
    love.graphics.line(cx, cy, hook.x, hook.y)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", hook.x - config.HOOK_SIZE / 2, hook.y - config.HOOK_SIZE / 2, config.HOOK_SIZE, config.HOOK_SIZE)
end

local function draw_entity(x, y, h, color_r, color_g, color_b, name, hp, show_health, timer, move_facing, attack_facing, attack_type, slow_timer, bullets, hook, dash_timer)
    V.draw_shadow(x, y, h)

    draw_player_box(x, y, h, color_r, color_g, color_b)
    V.draw_eyes(x, y, h, move_facing)
    draw_nickname(name, x, y, h)
    if show_health then
        draw_health_bar(x, y - 5, hp)
    end

    if math.abs(timer) > 0 then
        V.draw_sword_arc(x, y, h, attack_type, timer, attack_facing)
    end

    if slow_timer and slow_timer > 0 then
        love.graphics.setColor(0, 0.5, 1, 0.3)
        love.graphics.rectangle("fill", x - 1, y - 1, config.SPRITE_SIZE + 2, h + 2)
    end

    if bullets then
        draw_bullets(bullets)
    end
    if hook then
        draw_hook(hook, x, y, h)
    end
end

local all_trails = {}
local function update_entity_trail(key, entity)
    local dt = love.timer.getDelta()
    local trail = all_trails[key]
    if not trail then
        trail = {}
        all_trails[key] = trail
    end
    if entity.dash_timer and entity.dash_timer > 0 then
        table.insert(trail, 1, {x = entity.x, y = entity.y, h = entity.height, age = 0})
        while #trail > config.VISUALS.DASH_TRAIL_COUNT do
            table.remove(trail)
        end
    end
    for i = #trail, 1, -1 do
        trail[i].age = trail[i].age + dt
        if trail[i].age > config.VISUALS.DASH_TRAIL_LIFETIME then
            table.remove(trail, i)
        end
    end
    return trail
end

local function draw_players(local_player, players, my_id)
    local my_trail = update_entity_trail("local", local_player)
    if #my_trail > 0 then V.draw_dash_trails(nil, my_trail) end
    for id, p in pairs(players) do
        local is_me = (id == my_id)
        local px = is_me and local_player.x or p.x
        local py = is_me and local_player.y or p.y
        local h = is_me and local_player.height or (p.height or config.PLAYER_STAND_HEIGHT)
        local move_facing = is_me and local_player.facing or (p.facing or 1)
        local attack_facing = is_me and (local_player.view_facing or local_player.facing) or (p.view_facing or p.facing or 1)
        local timer = is_me and local_player.attack_timer or (p.attack_timer or 0)
        local hp = is_me and local_player.health or (p.health or config.MAX_HEALTH)
        local at = is_me and local_player.attack_type or (p.attack_type or nil)
        local slow = is_me and local_player.slow_timer or (p.slow_timer or 0)
        local dt = is_me and local_player.dash_timer or (p.dash_timer or 0)

        if not is_me then
            local trail = update_entity_trail(id, p)
            if #trail > 0 then V.draw_dash_trails(nil, trail) end
        end

        if is_me then
            draw_entity(px, py, h, 0, 1, 0, "You", hp, true, timer, move_facing, attack_facing, at, slow, nil, nil, dt)
        else
            draw_entity(px, py, h, 1, 0, 0, "Guest " .. id, hp, true, timer, move_facing, attack_facing, at, slow, p.bullets, p.hook, dt)
        end
    end
end

local function draw_bot_players(bots)
    local invincible = Menu.get_settings().invincible
    for i, bot in ipairs(bots) do
        local trail = update_entity_trail("bot_" .. i, bot)
        if #trail > 0 then V.draw_dash_trails(nil, trail) end
        draw_entity(bot.x, bot.y, bot.height, 0.5, 0.5, 0.5, "Bot " .. i,
            bot.health, not invincible, bot.attack_timer,
            bot.facing, bot.view_facing or bot.facing, bot.attack_type, bot.slow_timer,
            bot.bullets, bot.hook, bot.dash_timer or 0)
    end
end

function Renderer.add_damage(x, y, amount, color)
    table.insert(damage_texts, {
        x = x + config.SPRITE_SIZE / 2,
        y = y - 5,
        text = "-" .. amount,
        timer = 0.8,
        max_timer = 0.8,
        color = color or {1, 1, 1}
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

    V.draw_background()
    V.draw_ground()

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
