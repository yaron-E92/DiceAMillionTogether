// COOP PATCH (v0.8): full rewrite of the "done shopping" button Step to gate the
// advance-to-next-round click on peer readiness. Solo behaviour unchanged.

fire_next_round = function()
{
    ui_sound();
    if (check_map() == "staticshop")
    {
        create_static(22);
    }
    img = 2;
    obj_shop.shopdone = true;
    instance_destroy();
    instance_destroy(obj_shop_ring);
    instance_destroy(obj_donations);
    if (obj_runctrl.flor_local_level == 6 && obj_runctrl.flor != 3)
    {
        obj_shop.paleoff = 100;
    }
    if (obj_runctrl.difficulty >= 6 && check_map() != "staticshop")
    {
        if (check_nan_score())
        {
            global.score = 100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
        }
        else
        {
            subtract_score(ceil(global.score / 2));
        }
    }
    if (obj_runctrl.flor_local_level == 6 && obj_runctrl.flor != 3 && check_for_ring("shiny"))
    {
        var _ring = get_ring_inst("shiny");
        var _finalval = gilded_value("shiny", obj_deckctrl.cubes) * 0.5;
        if (!variable_instance_exists(_ring.ring, "mult"))
        {
            _ring.ring.mult = 1;
        }
        _ring.ring.mult += _finalval;
    }
    obj_deckctrl.cubes = 0;
    // v0.24 C3 fix: both clients run fire_next_round symmetrically and each
    // sets cubes=0. Without rebase, coop_broadcast_spend_if_changed detects
    // the decrease from both sides, both emit SPEND{-cubes}, both apply
    // peer's → cubes ends up -50 on both. Snap trackers to the post-reset
    // values so no SPEND fires for this symmetric action.
    coop_rebase();
};

if (!setup)
{
    setup = true;
}
ymod = smooth_move(ymod, 0, false);

// v0.8: if we've already queued in coop and peer is now ready, fire deferred click.
if (coop_barrier_passed("shop"))
{
    if (variable_instance_exists(self, "_coop_click_pending") && _coop_click_pending)
    {
        _coop_click_pending = false;
        fire_next_round();
        // Exit — the instance just destroyed itself.
        exit;
    }
}

if ((place_meeting(x, y, obj_mouse) || (global.gamepad && global.x_key && x < 1366)) && !obj_shop.opening && !global.ui_busy)
{
    img = 1;
    if (global.mouse_left || (global.gamepad && global.x_key && x < 1366))
    {
        if (coop_my_barrier_pending("shop"))
        {
            // already waiting on peer
        }
        else if (variable_global_exists("coop") && global.coop != undefined && global.coop.is_coop_run)
        {
            _coop_click_pending = true;
            coop_request_barrier("shop");
            if (coop_barrier_passed("shop"))
            {
                _coop_click_pending = false;
                fire_next_round();
                exit;
            }
        }
        else
        {
            fire_next_round();
            exit;
        }
    }
}
else
{
    img = 0;
}
if (error_alpha > 0)
{
    error_alpha -= 0.01;
}
var _sine_mod = sine(0, 2, 3);
if (obj_runctrl.flor == 3 && obj_runctrl.flor_local_level == 6)
{
    x = init_x + (obj_shop.hollowunlock_mod * 1366);
    y = init_y + ymod + _sine_mod;
}
else
{
    var _gtmod = 0;
    x = init_x + ymod + _gtmod;
    y = init_y + obj_shop.pack_ymod + _sine_mod;
}
