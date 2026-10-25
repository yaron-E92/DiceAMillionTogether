if (!instance_exists(obj_main_menu))
{
    instance_destroy();
    exit;
}

// Only visible in the base menu state (not during char select / play transition).
if (obj_main_menu.state != "menu")
    exit;

// Simple hover scale.
if (point_in_rectangle(obj_mouse.x, obj_mouse.y, x - 80, y - 24, x + 80, y + 24))
{
    scale = min(scale + 0.02, 0.15);
    if (!hovered)
    {
        hovered = true;
        audio_play_sound(snd_dice_hover, 10, false);
    }
    if (global.mouse_left && !global.ui_busy && !instance_exists(obj_coop_lobby))
    {
        audio_play_sound(snd_dice_select, 10, false);
        instance_create_layer(683, 384, "collection", obj_coop_lobby);
    }
}
else
{
    scale = max(scale - 0.02, 0);
    hovered = false;
}
