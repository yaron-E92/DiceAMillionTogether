// Fade in fast, then run a simple falling physics toward target_y with a bounce.
alpha = min(alpha + 0.12, 1);
life_timer++;
if (life_timer > max_life)
    instance_destroy();

if (!settled)
{
    // Gravity. Converge x toward target while falling.
    vspeed_y += 0.8;
    y += vspeed_y;
    x += (target_x - x) * 0.08 + vspeed_x;
    vspeed_x *= 0.95;

    if (y >= target_y)
    {
        y = target_y;
        if (abs(vspeed_y) > 2)
        {
            vspeed_y = -vspeed_y * 0.35;   // bounce
        }
        else
        {
            vspeed_y = 0;
            vspeed_x = 0;
            x = target_x;
            settled = true;
        }
    }
}
