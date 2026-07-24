local config = require "config"

local Renderer = {}
local V = require "visuals"

local OUTLINE_MAP = {
    frozen = config.OUTLINE_FROZEN,
    hooked = config.OUTLINE_HOOKED,
    cooldown = config.OUTLINE_LOCKED,
}

local function get_outline_color(ent)
    if ent.getCurrentOutlineColor then
        return ent:getCurrentOutlineColor()
    end
    return OUTLINE_MAP[ent.state] or config.OUTLINE_DEFAULT
end

local function normalize_view(ent, meta)
    local oc = get_outline_color(ent)
    return {
        x = ent.x,
        y = ent.y,
        h = ent.height,
        fill = ent.mainColor or meta.color or {1, 1, 1},
        outline = oc,
        name = meta.name,
        hp = ent.health,
        show_health = meta.show_health,
        timer = ent.attack_timer or 0,
        move_facing = ent.facing or 1,
        attack_facing = ent.attack_facing or ent.view_facing or ent.facing or 0,
        attack_type = ent.attack_type,
        state = ent.state,
        hook = ent.hook,
        is_local = meta.is_local or false,
        dash_timer = ent.dash_timer or 0,
        dash_cooldown = ent.dash_cooldown ~= nil and ent.dash_cooldown or 0,
    }
end

local function draw_player_box(x, y, h, fill)
    love.graphics.setColor(fill[1], fill[2], fill[3])
    love.graphics.rectangle("fill", x, y, config.SPRITE_SIZE, h)
end

local function draw_nickname(name, x, y, h)
    if not name then return end
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

    V.draw_shadow(x, y, h)

    love.graphics.setColor(v.outline[1], v.outline[2], v.outline[3], v.outline[4] or 0.5)
    love.graphics.rectangle("line", x, y, config.SPRITE_SIZE, h)

    draw_player_box(x, y, h, v.fill)
    V.draw_eyes(x, y, h, v.move_facing)
    draw_nickname(v.name, x, y, h)
    if v.show_health then
        draw_health_bar(x, y - 5, v.hp)
    end

    if math.abs(v.timer) > 0 then
        V.draw_sword_arc(x, y, h, v.attack_type, v.timer, v.attack_facing)
    end

    if v.is_local and v.dash_cooldown <= 0 and v.dash_timer <= 0 then
        V.draw_dash_ready_sparkle(x, y, h)
    end
end

local all_trails = {}

function Renderer.draw(render_list)
    love.graphics.push()
    love.graphics.scale(config.ZOOM, config.ZOOM)

    V.draw_background()
    V.draw_ground()

    local views = {}
    local attached_hooks = {}
    local unattached_hooks = {}

    for _, entry in ipairs(render_list) do
        local v = normalize_view(entry.entity, entry)
        local dt = love.timer.getDelta()
        local trail = all_trails[entry.key]
        if not trail then
            trail = {}
            all_trails[entry.key] = trail
        end

        if entry.entity.dash_timer and entry.entity.dash_timer > 0 then
            local fc = v.fill
            table.insert(trail, 1, {x = entry.entity.x, y = entry.entity.y, h = entry.entity.height, age = 0, r = fc[1], g = fc[2], b = fc[3]})
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
        if #trail > 0 then
            V.draw_dash_trails(nil, trail)
        end

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

    if ActiveProjectiles then
        for _, proj in ipairs(ActiveProjectiles) do
            if proj.type == "freeze" then
                V.draw_bullet_glow(proj.x, proj.y)
                love.graphics.setColor(0, 0.8, 0.9)
                love.graphics.rectangle("fill", proj.x - config.FREEZE_BOLT_SIZE / 2, proj.y - config.FREEZE_BOLT_SIZE / 2, config.FREEZE_BOLT_SIZE, config.FREEZE_BOLT_SIZE)
            end
        end
    end
    for _, v in ipairs(views) do
        draw_entity(v)
    end
    for _, v in ipairs(attached_hooks) do
        draw_hook(v.hook, v.x, v.y, v.h)
    end

    V.draw_damage_texts()

    love.graphics.pop()
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

function Renderer.add_damage(x, y, amount, color)
    V.spawnDamageMarker(x, y, amount, color)
end

function Renderer.update_damage_texts(dt)
    V.update_damage_texts(dt)
end

return Renderer
