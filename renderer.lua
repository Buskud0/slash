local config = require "config"

local Renderer = {}
local V = require "visuals"

local damage_texts = {}

local function normalize_view(ent, meta)
    local is_local = meta.is_local
    return {
        x = ent.x,
        y = ent.y,
        h = ent.height,
        color = { meta.r, meta.g, meta.b },
        name = meta.name,
        hp = ent.health,
        show_health = meta.show_health,
        timer = ent.attack_timer or 0,
        move_facing = is_local and ent.facing or (ent.facing or 1),
        attack_facing = is_local and (ent.view_facing or ent.facing) or (ent.view_facing or ent.facing or 1),
        attack_type = ent.attack_type,
        slow_timer = ent.slow_timer or 0,
        combat_cooldown = ent.combat_cooldown or 0,
        being_hooked = ent.being_hooked or ent.pull_toward ~= nil,
        bullets = is_local and nil or ent.bullets,
        hook = ent.hook,
        dash_timer = ent.dash_timer or 0,
        dash_cooldown = is_local and ent.dash_cooldown or nil,
    }
end

local function draw_player_box(x, y, h, r, g, b)
    love.graphics.setColor(r, g, b)
    love.graphics.rectangle("fill", x, y, config.SPRITE_SIZE, h)
end

local function draw_nickname(name, x, y, h)
    love.graphics.setColor(1, 1, 1)
    local font = love.graphics.getFont()
    local scale = 0.35
    local text_w = font:getWidth(name) * scale
    local text_x = x + (config.SPRITE_SIZE / 2) - (text_w / 2)
    love.graphics.print(name, text_x, y + h + 1, 0, scale, scale)
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
        love.graphics.rectangle("fill", b.x - config.FREEZE_BOLT_SIZE / 2, b.y - config.FREEZE_BOLT_SIZE / 2, config.FREEZE_BOLT_SIZE, config.FREEZE_BOLT_SIZE)
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

local function draw_entity(v)
    local x, y, h = v.x, v.y, v.h
    local r, g, b = v.color[1], v.color[2], v.color[3]

    V.draw_shadow(x, y, h)

    local frozen = v.slow_timer > 0
    local hooked = v.being_hooked
    local locked = v.combat_cooldown > 0 and not hooked
    if frozen then
        love.graphics.setColor(0, 0.5, 1, 0.9)
    elseif hooked then
        love.graphics.setColor(1, 0.85, 0, 0.9)
    elseif locked then
        love.graphics.setColor(1, 0.15, 0.15, 0.9)
    else
        love.graphics.setColor(0, 0, 0, 0.5)
    end
    love.graphics.rectangle("line", x, y, config.SPRITE_SIZE, h)

    draw_player_box(x, y, h, r, g, b)
    V.draw_eyes(x, y, h, v.move_facing)
    draw_nickname(v.name, x, y, h)
    if v.show_health then
        draw_health_bar(x, y - 5, v.hp)
    end

    if math.abs(v.timer) > 0 then
        V.draw_sword_arc(x, y, h, v.attack_type, v.timer, v.attack_facing)
    end

    if v.bullets then
        draw_bullets(v.bullets)
    end
    if v.dash_cooldown and v.dash_cooldown <= 0 and v.dash_timer <= 0 then
        V.draw_dash_ready_sparkle(x, y, h)
    end
end

local all_trails = {}
local function update_entity_trail(key, entity, r, g, b)
    local dt = love.timer.getDelta()
    local trail = all_trails[key]
    if not trail then
        trail = {}
        all_trails[key] = trail
    end
    if entity.dash_timer and entity.dash_timer > 0 then
        table.insert(trail, 1, {x = entity.x, y = entity.y, h = entity.height, age = 0, r = r, g = g, b = b})
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

local function draw_entities(local_player, players, my_id, bots)
    local entities = {
        { key = "local", entity = local_player, r = 0, g = 1, b = 0, name = "You", show_health = true, is_local = true }
    }
    for id, p in pairs(players) do
        if id ~= my_id then
            table.insert(entities, { key = id, entity = p, r = 1, g = 0.6, b = 0, name = "Guest " .. id, show_health = true })
        end
    end
    for i, bot in ipairs(bots) do
        table.insert(entities, { key = "bot_" .. i, entity = bot, r = 0.5, g = 0.5, b = 0.5, name = "Bot " .. i, show_health = not bot.invincible })
    end

    local views = {}
    local attached_hooks = {}
    local unattached_hooks = {}

    for _, e in ipairs(entities) do
        local v = normalize_view(e.entity, e)
        local trail = update_entity_trail(e.key, e.entity, e.r, e.g, e.b)
        if #trail > 0 then V.draw_dash_trails(nil, trail) end
        table.insert(views, v)
        if v.hook then
            if v.hook.target_id then
                table.insert(attached_hooks, v)
            else
                table.insert(unattached_hooks, v)
            end
        end
    end

    for _, v in ipairs(unattached_hooks) do
        draw_hook(v.hook, v.x, v.y, v.h)
    end
    for _, v in ipairs(views) do
        draw_entity(v)
    end

    return attached_hooks
end

function Renderer.add_damage(x, y, amount, color)
    if amount <= 0 then return end
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

function Renderer.draw_cooldowns(local_player)
    local sw, sh = love.graphics.getDimensions()
    local scale = math.min(sw, sh) / 240
    local radius = 8 * scale
    local gap = 10 * scale
    local padding = 10 * scale

    local hook_cd = { name = "Hook", timer = local_player.hook_cooldown, max = config.HOOK_COOLDOWN, color = {0.8, 0.8, 0.2} }
    local freeze_cd = { name = "Freeze", timer = local_player.bullet_cooldown, max = config.FREEZE_BOLT_COOLDOWN, color = {0.3, 0.7, 0.9} }

    local cy = sh - padding - radius

    love.graphics.origin()

    local font_size = 0.5 * scale

    local function draw_cd(cd, cx)
        local pct = 1 - math.max(0, math.min(1, cd.timer / cd.max))
        love.graphics.setColor(0.15, 0.15, 0.2, 0.8)
        love.graphics.circle("fill", cx, cy, radius)
        love.graphics.setColor(cd.color[1], cd.color[2], cd.color[3], 0.9)
        love.graphics.arc("fill", cx, cy, radius, -math.pi / 2, -math.pi / 2 + pct * math.pi * 2)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.print(cd.name, cx, cy + radius + 1 * scale, 0, font_size, font_size, love.graphics.getFont():getWidth(cd.name) / 2, 0)
    end

    local pair_w = radius * 4 + gap
    local pair_x = (sw - pair_w) / 2 + radius
    draw_cd(freeze_cd, pair_x)
    draw_cd(hook_cd, pair_x + radius * 2 + gap)
end

function Renderer.draw(local_player, players, my_id, bots)
    love.graphics.push()
    love.graphics.scale(config.ZOOM, config.ZOOM)

    V.draw_background()
    V.draw_ground()

    local attached_hooks = draw_entities(local_player, players, my_id, bots)
    draw_bullets(local_player.bullets)
    for _, v in ipairs(attached_hooks) do
        draw_hook(v.hook, v.x, v.y, v.h)
    end

    for _, t in ipairs(damage_texts) do
        local alpha = math.min(1, t.timer / (t.max_timer * 0.3))
        local c = t.color or {1, 1, 1}
        love.graphics.setColor(c[1], c[2], c[3], alpha)
        local font = love.graphics.getFont()
        local tw = font:getWidth(t.text) * 0.35
        love.graphics.print(t.text, t.x - tw / 2, t.y, 0, 0.35, 0.35)
    end

    love.graphics.pop()

    Renderer.draw_cooldowns(local_player)
end

return Renderer
