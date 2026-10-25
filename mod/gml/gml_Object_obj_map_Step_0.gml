// COOP PATCH (v0.33): synchronized ROLL / SKIP on the map screen.
// The vanilla click handlers for "roll the round dice" and "skip the round
// for a reward pack" mutate obj_runctrl.level / flor_local_level and spawn
// obj_diceroll / reward packs. Running that on only one client's click
// desyncs the level counters and the peer gets stuck while the clicker
// advances. Fix: both actions go through coop_cast_map_vote. When both
// players have voted, the action fires symmetrically on both sides (with
// coop_rebase() absorbing the shared subtract_score so cost is paid once).
// On vote mismatch, a deterministic shared RNG (seeded from runctrl.seed
// + level) picks the winner so both clients agree without extra traffic.

// --- coop vote resolution: fire flags driven by either (a) local click
// in solo / vote-casting-disabled mode, or (b) the resolved map_vote.
// Flags are set down inside the !nextwave && !global.ui_busy block so the
// action fires in the same state context as a normal click. Vote cleared
// only AFTER the action body actually runs — not here — so a vote that
// resolves during a transition doesn't get lost.
var _coop_fire_roll = false;
var _coop_fire_skip = false;
var _coop_vote_consumed = false;

if (!setup)
{
    setup = true;
    if (!timed)
    {
        backbutton = instance_create_layer(x, y, "hud_dice", obj_backbutton);
        backbutton.parent = self;
        backbutton.mapmode = true;
    }
    else if (obj_runctrl.flor < 4)
    {
        set_canskip();
    }
    if (timed)
    {
        save_run();
    }
}
y = smooth_move(y, target_y, true);
shadow_bg = smooth_move(shadow_bg, 1, true);
if (obj_runctrl.flor < 4)
{
    local_level_local = obj_runctrl.flor_local_level;
}
else
{
    if (obj_runctrl.flor_local_level == 3)
    {
        local_level_local = 1;
    }
    if (obj_runctrl.flor_local_level == 6)
    {
        local_level_local = 2;
    }
}
if (display_pos != local_level_local)
{
    if (display_pos > local_level_local)
    {
        display_pos -= (abs(display_pos - local_level_local) / 8);
    }
    if (display_pos < local_level_local)
    {
        display_pos += (abs(display_pos - local_level_local) / 8);
    }
}
if (selector_y_dir == 0)
{
    if (selector_y < 25)
    {
        selector_y += ((25 - selector_y) / 6);
    }
    if (selector_y > 24)
    {
        selector_y = 25;
        selector_y_dir = 1;
    }
}
if (selector_y_dir == 1)
{
    if (selector_y > 0)
    {
        selector_y -= (selector_y / 6);
    }
    if (selector_y < 1)
    {
        selector_y = 0;
        selector_y_dir = 0;
    }
}
if (timed)
{
    if (!instance_exists(obj_shop_cardpack_card))
    {
        var _skipcheck = false;
        if (!nextwave && !global.ui_busy)
        {
            if (place_meeting(b_x, b_y, obj_mouse) || next_trigger)
            {
                hovering_next = true;
                if (global.mouse_left || (global.gamepad && global.a_key) || next_trigger)
                {
                    next_trigger = false;
                    nextwave = true;
                    ui_sound();
                    hovering_next = false;
                    if (obj_deckctrl.state != obj_deckctrl.state_win)
                    {
                        obj_deckctrl.state = obj_deckctrl.state_win;
                        obj_deckctrl.win_setup = true;
                    }
                    for (var i = 0; i < instance_number(obj_map_point); i++)
                    {
                        var _this = instance_find(obj_map_point, i);
                        if (_this.num == (obj_runctrl.flor_local_level + 1))
                        {
                            _this.path_destroy_anim = true;
                        }
                    }
                    obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].down = get_maplist("none", obj_runctrl.flor);
                    obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].up = get_maplist("none", obj_runctrl.flor);
                }
            }
            else
            {
                hovering_next = false;
            }
            // COOP PATCH: consume resolved vote here — inside the same
            // state gate that normally guards a click. Prevents firing
            // during nextwave / ui_busy transitions.
            if (variable_global_exists("coop") && global.coop != undefined
                && global.coop.is_coop_run && global.coop.map_vote_resolved)
            {
                if (global.coop.map_vote_winner == "roll") _coop_fire_roll = true;
                else if (global.coop.map_vote_winner == "skip") _coop_fire_skip = true;
                _coop_vote_consumed = true;
            }

            if (place_meeting(b_x + button_offset, b_y, obj_mouse))
            {
                hovering_roll = true;
                if (global.mouse_left || (global.gamepad && global.a_key))
                {
                    // COOP PATCH: cast vote instead of firing immediately.
                    if (coop_should_intercept_map_click())
                    {
                        coop_cast_map_vote("roll");
                    }
                    else
                    {
                        _coop_fire_roll = true;
                    }
                }
            }
            else
            {
                hovering_roll = false;
                if (place_meeting(b_x + (button_offset * 2), b_y, obj_mouse) && canskip)
                {
                    if (global.mouse_left || (global.gamepad && global.a_key))
                    {
                        // COOP PATCH: cast vote instead of firing immediately.
                        if (coop_should_intercept_map_click())
                        {
                            coop_cast_map_vote("skip");
                        }
                        else
                        {
                            _coop_fire_skip = true;
                        }
                    }
                }
            }

            // --- ROLL action body (fires on solo click or coop vote win).
            if (_coop_fire_roll)
            {
                if (bossnext)
                {
                    audio_play_sound(snd_eerie, 10, false, 1, 0, 0.5);
                    global.ui_busy = true;
                    instance_create_layer(0, 0, "transition", obj_bossreroll,
                    {
                        boss: variable_clone(obj_runctrl.boss[obj_runctrl.flor])
                    });
                }
                else
                {
                    var _mergecheck = false;
                    with (obj_map_point)
                    {
                        if (merged[0] || merged[1])
                        {
                            _mergecheck = true;
                        }
                    }
                    if ((obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].down.ide != "none" || obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].up.ide != "none") && !_mergecheck)
                    {
                        if (obj_runctrl.challenge != "blackjack" || !blackjack_roll)
                        {
                            if (BigGreater(global.score, roll_price, true) || check_nan_score())
                            {
                                if (obj_runctrl.challenge != "blackjack")
                                {
                                    subtract_score(roll_price);
                                    // v0.33: symmetric deduction — both clients
                                    // run this, so rebase prevents bilateral
                                    // SPEND from charging the price a second
                                    // time via peer's broadcast.
                                    coop_rebase();
                                }
                                else
                                {
                                    blackjack_roll = true;
                                }
                                audio_play_sound(snd_cash, 10, false);
                                hovering_roll = false;
                                if (obj_runctrl.flor_local_level == 2)
                                {
                                    var _merge = 0;
                                    var _q = 0;
                                    if (obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].up.ide == "bossrush")
                                    {
                                        obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].main = obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].up;
                                        _q++;
                                    }
                                    if (obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].down.ide == "staticshop")
                                    {
                                        obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].main = obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].down;
                                        _merge = 1;
                                        _q++;
                                    }
                                    if (_q == 1)
                                    {
                                        with (obj_map_point)
                                        {
                                            if (num == (obj_runctrl.flor_local_level + 1))
                                            {
                                                merged[_merge] = true;
                                            }
                                        }
                                    }
                                    else if (_q == 2)
                                    {
                                        var _p_up = obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].up;
                                        var _p_down = obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].down;
                                        if (_p_up.ide != "none")
                                        {
                                            _p_up.cond.state = "won";
                                        }
                                        if (_p_down.ide != "none")
                                        {
                                            _p_down.cond.state = "won";
                                        }
                                        var _dic = instance_create_layer(0, 0, "hud", obj_diceroll);
                                        _dic.dice_done = true;
                                    }
                                }
                                else
                                {
                                    instance_create_layer(0, 0, "hud", obj_diceroll);
                                }
                            }
                            else
                            {
                                not_enough_money();
                                roll_price_text_color_timer = 20;
                            }
                        }
                    }
                }
            }

            // --- SKIP action body.
            if (_coop_fire_skip)
            {
                ui_sound();
                global.ui_busy = true;
                screen_shake(15);
                audio_play_sound(snd_eerie, 10, false, 1, 0, 1.5);
                audio_play_sound(snd_vampire, 10, false, 0.7, 0, 0.7);
                with (obj_map_point)
                {
                    merged[0] = false;
                    merged[1] = false;
                }
                subtract_score(get_target(obj_runctrl.level + 1));
                // v0.33: symmetric deduction — see ROLL branch above.
                coop_rebase();
                pack_timer = 50;
                for (var i = 0; i < instance_number(obj_map_point); i++)
                {
                    var _this = instance_find(obj_map_point, i);
                    if (_this.num == (obj_runctrl.flor_local_level + 1))
                    {
                        _this.path_destroy_anim = true;
                    }
                }
                obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].down = get_maplist("none", obj_runctrl.flor);
                obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level + 1].up = get_maplist("none", obj_runctrl.flor);
                obj_runctrl.flor_local_level++;
                obj_runctrl.level++;
                set_roll_price();
            }

            // v0.33: clear the resolved vote only after action body ran.
            if (_coop_vote_consumed)
            {
                coop_clear_map_vote();
            }

            if (obj_shop.state == obj_shop.state_roll)
            {
                if (back)
                {
                    back = false;
                    obj_shop.state = obj_shop.state_map;
                    instance_destroy(backbutton);
                }
            }
        }
        if (nextwave)
        {
            timer -= (1 * get_animtime_mult());
            if (timer < 70)
            {
                if (!leveled)
                {
                    leveled = true;
                    obj_runctrl.level++;
                    if (!nomove)
                    {
                        if (obj_runctrl.flor < 4)
                        {
                            obj_runctrl.flor_local_level++;
                        }
                        else if (obj_runctrl.flor_local_level == 0)
                        {
                            obj_runctrl.flor_local_level = 3;
                        }
                        else if (obj_runctrl.flor_local_level == 3)
                        {
                            obj_runctrl.flor_local_level = 6;
                        }
                    }
                }
            }
            if (timer < 20)
            {
                if ((obj_runctrl.flor_local_level == 6 || (obj_runctrl.flor_local_level > 0 && obj_runctrl.challenge == "natural6" && obj_runctrl.flor_local_level != 3)) && !bosscutscenedone)
                {
                    if (!instance_exists(obj_cutboss))
                    {
                        instance_create_layer(0, 0, "transition", obj_cutboss);
                    }
                }
                else if (!instance_exists(obj_transition))
                {
                    nomove = false;
                    var _spd = 1;
                    if (check_map() == "staticshop")
                    {
                        create_static(50);
                        _spd = 5;
                    }
                    var _inst = instance_create_layer(x, y, "transition", obj_transition);
                    _inst.spd = _spd;

                    _inst.func = function()
                    {
                        instance_destroy(obj_cutboss);
                        instance_destroy(obj_map);
                        instance_destroy(obj_map_point);
                        instance_destroy(obj_skiptoboss);
                        if (instance_exists(obj_dice_particle))
                        {
                            instance_destroy(obj_dice_particle);
                        }
                        if (instance_exists(obj_dice_generator))
                        {
                            instance_destroy(obj_dice_generator);
                        }
                        global.ui_busy = false;
                        obj_shop.mapped = false;
                        if (obj_runctrl.flor_local_level == 3)
                        {
                            if (obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level].main.ide == "bossrush")
                            {
                                obj_shop.state = obj_shop.state_bossrush;
                            }
                            else if (obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level].main.ide == "staticshop")
                            {
                                obj_shop.state = obj_shop.state_shop;
                            }
                            else
                            {
                                obj_shop.state = obj_shop.state_booster;
                            }
                        }
                        else
                        {
                            obj_deckctrl.state = obj_deckctrl.state_setup;
                            obj_shop.state = obj_shop.state_sleep;
                            if (obj_runctrl.map[obj_runctrl.flor - 1][obj_runctrl.flor_local_level].elite)
                            {
                                obj_deckctrl.roundelite = true;
                            }
                        }
                    };
                }
            }
        }
        if (global.gamepad && !global.ui_busy)
        {
            if (!obj_shop.mouse_pos_cards && !obj_shop.opening)
            {
                if (mouse_state == "menu")
                {
                    mouse_pos = clamp(mouse_pos, 0, (check_tutorial_done("mapbranch") || !global.tutorial_enabled) + canskip);
                    if (global.up_key)
                    {
                        mouse_state = "path";
                        mouse_pos = clamp(mouse_pos, 0, 6);
                    }
                    if (!nextwave)
                    {
                        obj_mouse.x = 200 + clamp(button_offset * mouse_pos, 0, button_offset * 1.81);
                        obj_mouse.y = 670 - (30 * clamp(mouse_pos, 0, 1));
                    }
                    else
                    {
                        obj_mouse.x = -100;
                        obj_mouse.y = -100;
                    }
                }
                if (mouse_state == "path")
                {
                    var _down_check = false;
                    var _up_check = false;
                    mouse_pos = clamp(mouse_pos, 0, 6);
                    obj_mouse.x = (x + (option_sep * mouse_pos)) - (option_sep * 3);
                    obj_mouse.y = 384;
                    if (global.down_key)
                    {
                        mouse_pos = clamp(mouse_pos, 0, check_tutorial_done("mapbranch") || !global.tutorial_enabled);
                        mouse_state = "menu";
                    }
                }
                if (global.right_key)
                {
                    mouse_pos++;
                }
                if (global.left_key)
                {
                    mouse_pos--;
                }
            }
        }
    }
    if (global.gamepad && !obj_shop.mouse_pos_cards)
    {
        if (global.rb_key || global.lb_key)
        {
            if (instance_exists(obj_card))
            {
                obj_shop.mouse_pos_cards = true;
                obj_shop.mouse_pos = 0;
                obj_shop.mouse_pos_cards_cooldown = 1;
                exit;
            }
        }
    }
}
else
{
    if (global.mouse_right || (global.gamepad && global.rt_key))
    {
        back = true;
    }
    if (back)
    {
        set_uibusy(false);
        obj_menu_map.cooldown = 5;
        instance_destroy(obj_map_point);
        instance_destroy(backbutton);
        instance_destroy();
    }
}
if (obj_runctrl.char.ide == "static")
{
    static_img += 0.25;
    if (static_img > 3)
    {
        static_img = 0;
    }
}
shadow_timer--;
if (shadow_timer <= 0)
{
    shadow_timer = 30;
    shadow_x = irandom_range(-5, 5);
    shadow_y = irandom_range(-5, 5);
}
if (map_button_anim < 1)
{
    map_button_anim += 0.05;
}
else
{
    map_button_anim = 0;
}
if (roll_price_text_color_timer > 0)
{
    roll_price_text_color_timer--;
}
if (obj_runctrl.in_vortex)
{
    vortex_img += 0.15;
    vortex_img = wrap(vortex_img, 0, 4);
}
if (pack_timer > 0)
{
    pack_timer -= (1 * get_animtime_mult());
    pack_mod = smooth_move(pack_mod, 1, true);
    if (pack_timer <= 0)
    {
        global.ui_busy = false;
        var _inst = instance_create_layer(b_x + (button_offset * 2), b_y + 200, "cards_cantuse", obj_shop_cardpack,
        {
            pack: skippack
        });
        _inst.autoopen = true;
        _inst.price = 0;
        set_canskip();
    }
}
if (canskip)
{
    skip_mod = smooth_move(skip_mod, 0, false);
}
else
{
    skip_mod = smooth_move(skip_mod, 1, true);
}
