// COOP PATCH (v0.8): full rewrite of the roll-button Step to gate the click on
// the coop peer. In solo the original behaviour is preserved unchanged.
//
// Flow in coop:
//   1. User clicks (or Space/X) — we call coop_request_barrier("roll") which sends
//      BARRIER_READY to peer and sets my_roll_queued = true. We do NOT fire the
//      roll yet.
//   2. Each frame we poll coop_barrier_passed("roll"). If peer has also sent
//      BARRIER_READY, both flags clear and we actually fire the roll.
//   3. A single fire_roll() block contains the original state-transition code.

fire_roll = function()
{
    obj_deckctrl.sent_dice = obj_hud.selected_count;
    active = true;
    obj_deckctrl.rolls--;
    if (!door)
    {
        obj_deckctrl.state = obj_deckctrl.state_rolling;
    }
    else
    {
        global.ui_busy = true;
        audio_stop_sound(mus_empty);
    }
    audio_play_sound(snd_key, 10, false);
    audio_stop_sound(snd_tone);
    push_mod = 5;
};

if (!setup)
{
    setup = true;
    if (!door)
    {
        autosel = instance_create_layer(x, y, layer, obj_autosel);
        autosel.parent = self;
    }
}

// v0.8: if we've already queued in coop and peer is now ready, fire deferred roll.
if (coop_barrier_passed("roll"))
{
    if (variable_instance_exists(self, "_coop_click_pending") && _coop_click_pending)
    {
        _coop_click_pending = false;
        fire_roll();
    }
}

if (!active && (obj_deckctrl.hand_setup || obj_shop.state == obj_shop.state_door) && !instance_exists(obj_introreward) && (obj_deckctrl.rolls > 0 || obj_shop.state == obj_shop.state_door) && x > 0 && x < 1366 && y > 0 && y < 768 && obj_runctrl.bossrush_phase < 6)
{
    if ((place_meeting(x, y, obj_mouse) || global.spacebar || global.x_key_held) && !global.ui_busy && (obj_shop.state == obj_shop.state_sleep || obj_shop.state == obj_shop.state_roll || obj_shop.state == obj_shop.state_bossrush || (obj_shop.state == obj_shop.state_door && door)))
    {
        obj_deckctrl.hovering_roll = true;
        if (scale_mod < 0.05 && !check_if_mobile())
        {
            scale_mod += 0.06;
        }
        else
        {
            scale_mod = 0.1;
        }
        if (global.mouse_left || (global.spacebar || global.x_key_held))
        {
            var _check = true;
            for (var i = 0; i < instance_number(obj_dice); i++)
            {
                if (instance_find(obj_dice, i).sel_y_mod < 0.98 && instance_find(obj_dice, i).sel_y_mod > 0.02)
                {
                    _check = false;
                }
            }
            if (_check)
            {
                if (!global.gamepad || check_if_diceselected() || rolltimer >= 45)
                {
                    // v0.8: if we're already waiting for peer, ignore further clicks.
                    if (coop_my_barrier_pending("roll"))
                    {
                        // no-op — waiting on peer
                    }
                    else if (variable_global_exists("coop") && global.coop != undefined && global.coop.is_coop_run)
                    {
                        // Coop path: queue + signal peer, mark pending for deferred fire.
                        _coop_click_pending = true;
                        coop_request_barrier("roll");
                        // If peer was already waiting when we clicked, fire now.
                        if (coop_barrier_passed("roll"))
                        {
                            _coop_click_pending = false;
                            fire_roll();
                        }
                    }
                    else
                    {
                        // Solo path (unchanged from vanilla).
                        fire_roll();
                    }
                }
                else if (global.x_key_held)
                {
                    rolltimer++;
                    if (!audio_is_playing(snd_tone))
                    {
                        audio_play_sound(snd_tone, 0, true, 1, 0, 1 + ((rolltimer / 30) * 3));
                    }
                    audio_sound_pitch(snd_tone, 1 + ((rolltimer / 45) * 3));
                }
            }
        }
    }
    else
    {
        rolltimer = 0;
        audio_stop_sound(snd_tone);
        obj_deckctrl.hovering_roll = false;
        if (scale_mod > 0)
        {
            scale_mod -= 0.06;
        }
        else
        {
            scale_mod = 0;
        }
    }
}
else
{
    rolltimer = 0;
    audio_stop_sound(snd_tone);
}
if (active)
{
    img = 1;
    if (door)
    {
        door_spawn_timer--;
        for (var i = score_cycler; i < array_length(global.deck) && door_spawn_timer <= 0; i++)
        {
            instance_create_layer(683 + irandom_range(-200, 200), 80, "dice", obj_dice_extra,
            {
                die: variable_clone(global.deck[score_cycler]),
                deck_num: score_cycler
            });
            audio_stop_sound(snd_dice_throw1);
            audio_play_sound(snd_dice_throw1, 10, false, 1, 0.1, random_range(0.7, 1.3));
            score_cycler++;
            door_spawn_timer = clamp(10 - (floor(score_cycler / 10) * 2), 1, 10);
        }
        if (door_spawn_timer <= 0 && score_cycler >= (array_length(global.deck) - 1))
        {
            if (score_timer < 1000000)
            {
                score_timer++;
            }
            if (score_timer > (global.anim_time * 2))
            {
                if (!check_for_die("keyfull"))
                {
                    obj_deckctrl.dice_force_go = true;
                }
            }
            if (score_timer > (global.anim_time * 6) && !instance_exists(obj_gameover) && !instance_exists(obj_dicekeycut))
            {
                if (!check_for_die("keyfull"))
                {
                    var _inst = instance_create_layer(683, 384, "hud_over", obj_gameover);
                    _inst.winmode = true;
                    audio_play_sound(snd_dice_rare, 10, false);
                    audio_sound_gain(mus_dicemain, 1, 2000);
                }
                else
                {
                    for (var i = 0; i < instance_number(obj_dice_extra); i++)
                    {
                        if (instance_find(obj_dice_extra, i).die.ide == "keyfull")
                        {
                            instance_create_layer(instance_find(obj_dice_extra, i).x, instance_find(obj_dice_extra, i).y, "hud_dice", obj_dicekeycut);
                            instance_destroy(instance_find(obj_dice_extra, i));
                            break;
                        }
                    }
                }
            }
        }
    }
}
else
{
    img = 0;
}
if (obj_deckctrl.state == obj_deckctrl.state_menu)
{
    active = false;
    push_mod = 0;
}
if (!door)
{
    x = init_x + obj_deckctrl.win_mod;
    y = init_y + (obj_shop.introrewardmod * 200);
}
else
{
    y = init_y + obj_shop.door_mod;
}
if (door && obj_shop.state != obj_shop.state_door)
{
    instance_destroy();
}
