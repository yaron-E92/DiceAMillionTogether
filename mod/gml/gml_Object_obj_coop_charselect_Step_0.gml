alpha = min(alpha + 0.1, 1);

// Keep main-menu colliders and other background UI frozen while the modal is open.
global.ui_busy = true;

hover_idx = -1;
var _n = min(array_length(global.charlist), grid_cols * grid_rows);
for (var i = 0; i < _n; i++)
{
    var _col = i mod grid_cols;
    var _row = i div grid_cols;
    var _x = grid_x + (_col * cell_w);
    var _y = grid_y + (_row * cell_h);
    if (point_in_rectangle(obj_mouse.x, obj_mouse.y, _x + 10, _y + 10, _x + cell_w - 10, _y + cell_h - 10))
    {
        hover_idx = i;
        if (global.mouse_left)
        {
            var _ide = global.charlist[i].ide;
            coop_log("charselect: picked " + _ide);
            audio_play_sound(snd_dice_select, 10, false);
            coop_send_char_pick(_ide);
            // NOTE: we do NOT clear global.ui_busy here — obj_coop_lobby re-asserts it
            // every Step so the background main_menu_collider stays suppressed. Clearing
            // it leaves a one-frame gap where the same click propagates through to
            // "Новая игра"/"Продолжить" underneath and launches a solo run.
            instance_destroy();
            exit;
        }
    }
}

// Close on right-click or Escape.
if (keyboard_check_pressed(vk_escape) || global.mouse_right)
{
    coop_log("charselect: cancelled");
    // ui_busy stays true — lobby will keep it held.
    instance_destroy();
    exit;
}
