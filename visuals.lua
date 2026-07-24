local config = require "config"
local Helpers = require "helpers"

local V = {}
local VCfg = config.VISUALS

V.damage_texts = {}

function V.draw_background()
    local c = VCfg.BACKGROUND_COLOR
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth() / config.ZOOM, love.graphics.getHeight() / config.ZOOM)
end

function V.draw_ground()
    local screen_width = love.graphics.getWidth() / config.ZOOM

    local gc = VCfg.GROUND_COLOR
    love.graphics.setColor(gc[1], gc[2], gc[3])
    love.graphics.rectangle("fill", 0, config.GROUND_Y, screen_width, VCfg.GROUND_DEPTH)

    local hc = VCfg.GROUND_HIGHLIGHT
    love.graphics.setColor(hc[1], hc[2], hc[3])
    love.graphics.rectangle("fill", 0, config.GROUND_Y, screen_width, 1)

    love.graphics.setColor(gc[1] * 0.6, gc[2] * 0.6, gc[3] * 0.6)
    love.graphics.rectangle("fill", 0, config.GROUND_Y + VCfg.GROUND_DEPTH, screen_width, 1)
end

function V.draw_shadow(x, y, h)
    local sc = VCfg.SHADOW_COLOR
    love.graphics.setColor(sc[1], sc[2], sc[3], sc[4])
    local shadow_y = config.GROUND_Y + VCfg.SHADOW_Y_OFFSET
    local shadow_w = config.SPRITE_SIZE * VCfg.SHADOW_SCALE_X
    love.graphics.ellipse("fill", x + config.SPRITE_SIZE / 2, shadow_y, shadow_w / 2, 2)
end

function V.draw_eyes(x, y, h, facing)
    local ec = VCfg.EYE_COLOR or {0.1, 0.1, 0.1}
    love.graphics.setColor(ec[1], ec[2], ec[3])
    local eye_y = y + VCfg.EYE_OFFSET_Y
    local eye_size = VCfg.EYE_SIZE
    if facing > 0 then
        local eye_x = x + config.SPRITE_SIZE / 2 + VCfg.EYE_OFFSET_X
        love.graphics.rectangle("fill", eye_x, eye_y, eye_size, eye_size)
    else
        local eye_x = x + config.SPRITE_SIZE / 2 - VCfg.EYE_OFFSET_X - eye_size
        love.graphics.rectangle("fill", eye_x, eye_y, eye_size, eye_size)
    end
end

function V.draw_sword_arc(x, y, h, attack_type, timer, facing)
    if not attack_type then return end

    local cx = x + (config.SPRITE_SIZE / 2)
    local cy = y + (h / 2)
    local segments = VCfg.SWORD_ARC_SEGMENTS

    if attack_type:sub(1, 4) == "stab" then
        local tx, ty = Helpers.get_sword_tip({x = x, y = y, height = h, attack_timer = timer, attack_type = attack_type, attack_angle = facing, view_facing = facing, facing = facing})
        local sc = VCfg.SWORD_STAB_COLOR
        love.graphics.setColor(sc[1], sc[2], sc[3], sc[4] * 0.3)
        love.graphics.setLineWidth(4)
        love.graphics.line(cx, cy, tx, ty)
        love.graphics.setColor(sc[1], sc[2], sc[3], sc[4])
        love.graphics.setLineWidth(2)
        love.graphics.line(cx, cy, tx, ty)
        love.graphics.setLineWidth(1)
        return
    end

    local sweep_data = {
        swing_up_left    = {start = math.pi,     ["end"] = math.pi / 2},
        swing_up_right   = {start = 0,           ["end"] = math.pi / 2},
        swing_down_left  = {start = math.pi,     ["end"] = math.pi * 1.5},
        swing_down_right = {start = 0,           ["end"] = -math.pi / 2},
    }

    local sd = sweep_data[attack_type]
    if not sd then return end

    local progress = (config.SWING_DURATION - timer) / config.SWING_DURATION
    local angle_range = sd["end"] - sd.start

    for i = 1, segments do
        local t = i / segments
        if t <= progress then
            local sweep = sd.start + angle_range * t
            local prev_t = (i - 1) / segments
            local prev_sweep = sd.start + angle_range * prev_t
            local tip_x = cx + math.cos(sweep) * config.SWING_LENGTH
            local tip_y = cy + math.sin(sweep) * config.SWING_LENGTH
            local prev_tip_x = cx + math.cos(prev_sweep) * config.SWING_LENGTH
            local prev_tip_y = cy + math.sin(prev_sweep) * config.SWING_LENGTH

            local alpha = 0.15 + 0.75 * (1 - (progress - t))
            local sc = VCfg.SWORD_ARC_COLOR
            love.graphics.setColor(sc[1], sc[2], sc[3], alpha)
            love.graphics.setLineWidth(2)
            love.graphics.line(prev_tip_x, prev_tip_y, tip_x, tip_y)
            love.graphics.setLineWidth(1)
        end
    end

    local final_sweep = sd.start + angle_range * progress
    local tx = cx + math.cos(final_sweep) * config.SWING_LENGTH
    local ty = cy + math.sin(final_sweep) * config.SWING_LENGTH
    local tc = VCfg.SWORD_TIP_COLOR
    love.graphics.setColor(tc[1], tc[2], tc[3], tc[4])
    love.graphics.setLineWidth(2)
    love.graphics.line(cx, cy, tx, ty)
    love.graphics.setLineWidth(1)
end

function V.draw_bullet_glow(bx, by)
    local gc = VCfg.BULLET_GLOW_COLOR
    local r = VCfg.BULLET_GLOW_RADIUS
    love.graphics.setColor(gc[1], gc[2], gc[3], gc[4])
    love.graphics.circle("fill", bx, by, r)
end

function V.draw_hook_chain(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return end

    local spacing = VCfg.HOOK_CHAIN_SPACING
    local count = math.floor(dist / spacing)
    local cc = VCfg.HOOK_CHAIN_COLOR

    for i = 1, count do
        local t = i / count
        local px = x1 + dx * t
        local py = y1 + dy * t
        local fade = 0.4 + 0.6 * (1 - t)
        love.graphics.setColor(cc[1], cc[2], cc[3], cc[4] * fade)
        love.graphics.rectangle("fill", px - 0.5, py - 0.5, VCfg.HOOK_CHAIN_SIZE, VCfg.HOOK_CHAIN_SIZE)
    end
end

function V.draw_dash_ready_sparkle(x, y, h)
    local time = love.timer.getTime()
    local cx = x + config.SPRITE_SIZE / 2
    local cy = y + h - 2
    for i = 1, 4 do
        local phase = time * 4 + i * 1.3
        local sx = cx + math.sin(phase) * 5
        local sy = cy + math.cos(phase * 1.5) * 3
        local brightness = (math.sin(phase * 3) + 1) / 2
        local alpha = 0.5 + brightness * 0.5
        local size = 0.5 + brightness * 0.8
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.rectangle("fill", sx - size / 2, sy - size / 2, size, size)
    end
end

function V.draw_dash_trails(player, trail_positions, alpha_mult)
    if not trail_positions or #trail_positions == 0 then return end
    local mult = alpha_mult or 1
    for _, pos in ipairs(trail_positions) do
        local age_ratio = pos.age / VCfg.DASH_TRAIL_LIFETIME
        local alpha = VCfg.DASH_TRAIL_BASE_ALPHA * (1 - age_ratio) * mult
        if alpha > 0 then
            love.graphics.setColor(pos.r or 1, pos.g or 1, pos.b or 1, alpha)
            love.graphics.rectangle("fill", pos.x, pos.y, config.SPRITE_SIZE, pos.h or config.PLAYER_STAND_HEIGHT)
        end
    end
end

function V.spawnDamageMarker(x, y, amount, color)
    if amount <= 0 then return end
    table.insert(V.damage_texts, {
        x = x + config.SPRITE_SIZE / 2,
        y = y - 5,
        text = "-" .. amount,
        timer = 0.8,
        max_timer = 0.8,
        color = color or {1, 1, 1}
    })
end

function V.spawnClashMarker(x, y)
    table.insert(V.damage_texts, {
        x = x,
        y = y,
        text = "*clash*",
        timer = 0.6,
        max_timer = 0.6,
        color = {1, 0.85, 0.2}
    })
end

function V.update_damage_texts(dt)
    for i = #V.damage_texts, 1, -1 do
        local t = V.damage_texts[i]
        t.timer = t.timer - dt
        t.y = t.y - 30 * dt
        if t.timer <= 0 then
            table.remove(V.damage_texts, i)
        end
    end
end

function V.draw_damage_texts()
    for _, t in ipairs(V.damage_texts) do
        local alpha = math.min(1, t.timer / (t.max_timer * 0.3))
        local c = t.color or {1, 1, 1}
        love.graphics.setColor(c[1], c[2], c[3], alpha)
        local font = love.graphics.getFont()
        local tw = font:getWidth(t.text) * 0.35
        love.graphics.print(t.text, t.x - tw / 2, t.y, 0, 0.35, 0.35)
    end
end

return V
