-- Physics functionality moved into player.lua (Player class methods).
-- This module kept as a forward-compatibility shim.

local Physics = {}

function Physics.update(player, dt, cmd)
    player:update(dt, cmd)
end

function Physics.take_damage(player, amount, attacker_vx, attack_type)
    player:takeDamage(amount, attacker_vx, attack_type)
end

function Physics.apply_knockback(player, angle, force, attacker_vx, attack_type)
    player:applyKnockback(angle, force, attacker_vx, attack_type)
end

function Physics.apply_net_slow(player, duration)
    player:applySlow(duration)
end

function Physics.apply_pull(player, target_x, target_y, hook_dx, hook_dy)
    player:applyPull(target_x, target_y, hook_dx, hook_dy)
end

function Physics.clear_pull(player)
    player:clearPull()
end

function Physics.clear_cooldown(player, at)
    player:clearCooldown(at)
end

return Physics
