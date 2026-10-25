// COOP PATCH (v0.8.1): adds a "WAITING..." label when a coop barrier is pending,
// so the user sees visual feedback that their click registered and we're waiting
// for the peer.
if (setup)
{
    draw_sprite_ext(sprite_index, img, x - 5, y + 5, 1 + scale_mod, 1 + scale_mod, 0, c_black, 0.3);
    draw_sprite_ext(sprite_index, img, x, y, 1 + scale_mod, 1 + scale_mod, 0, c_white, 1);
    set_main_font();
    draw_set_halign(fa_center);
    draw_set_valign(fa_top);

    var _label = "[spr_text][fa_middle]ROLL";
    var _scale_bump = 0;
    if (variable_global_exists("coop")
        && global.coop != undefined
        && global.coop.is_coop_run
        && global.coop.my_roll_queued)
    {
        // v0.22: pulsing WAITING animation — dot-cycle + scale throb.
        var _tick = floor(current_time / 350) mod 3;
        var _dots = (_tick == 0) ? "." : ((_tick == 1) ? ".." : "...");
        _label = "[spr_text][fa_middle][c_yellow]WAITING" + _dots;
        _scale_bump = sin(current_time / 200) * 0.15;
    }
    draw_text_adv_s(x, (y - 12) + push_mod, _label, 0, 0, 3 + scale_mod + _scale_bump, 1, 999, 1);

    if (global.gamepad)
    {
        var _img = img;
        if (rolltimer > 0)
        {
            _img = 1;
        }
        draw_sprite(spr_iconb_x, _img, ((x - (sprite_width / 2)) + 8) - (scale_mod * 5), y - 30 - (scale_mod * 5));
    }
}
