// COOP PATCH (v0.8.2): minor change to pay_f — after subtract_score runs,
// call coop_rebase() so the local deduction doesn't propagate to the peer via
// DELTA. Both clients run pay_f independently for the same round-end quota, so
// each does its own local subtract; without rebase each also DELTA-echoes the
// change to the other, doubling the deduction from the shared pool.

draw_set_typist_parameters(0.5, snd_voice_phone);
typist.ease(UnknownEnum.Value_10, typist.get_position(), typist.get_position(), 5, 5, 30, 0.5);
ymod = 1;
xx = x;
yy = y;
shake_x = 0;
shake_y = 0;
phone_timer = 0;
phone_rot = -20;
setup = false;
scale_mult = 1.2;
menuxscale = 3.75 * scale_mult;
menuyscale = 1.6666666666666667 * scale_mult;
image_xscale = 1.4 * scale_mult;
image_yscale = 1.5 * scale_mult;
button_shake_x = 0;
button_shake_y = 0;
pips_time = 0;
pips_period = 10;
image_speed = 0;
if (!global.skipanim)
{
    global.ui_busy = true;
    audio_play_sound(snd_ach, 10, false, 1, 0, 1.5);
    audio_play_sound(snd_phone, 10, false);
}
done = false;
done_timer = 0;
dinged = false;
effect = false;
donemod = 1;
paying = false;
paying_timer = 0;
img = 0;
payed = false;
safety_timer = 0;
bossmode = false;
cubesmode = false;
if (obj_runctrl.flor_local_level == 6 && !(obj_runctrl.flor == 3 || (obj_runctrl.challenge != "none" && get_challenge(obj_runctrl.challenge).target == obj_runctrl.flor)))
{
    bossmode = true;
}
if (obj_runctrl.challenge != "none")
{
    if (check_tag(get_challenge(obj_runctrl.challenge), "noshop"))
    {
        bossmode = false;
    }
}
forceding = false;
if (global.skipanim)
{
    forceding = true;
}
display = get_number_display(obj_deckctrl.obj);
left_display = get_number_display(global.score - obj_deckctrl.obj);
pips_array = [];
for (var i = 0; i < 20; i++)
{
    array_push(pips_array,
    {
        timer: 50,
        spd: irandom_range(0.8, 1.2),
        offset: 30 + (i * 0.1),
        xoffset: irandom_range(-20, 20),
        yoffset: irandom_range(-20, 20)
    });
}
paytext = get_translation(choose("misc_paytext_1", "misc_paytext_2", "misc_paytext_3", "misc_paytext_4"));
if (obj_runctrl.flor > 3 || obj_runctrl.char.ide == "black" || obj_runctrl.char.ide == "hollow")
{
    paytext = get_translation("misc_paytext_5");
}
if (obj_runctrl.challenge == "blackjack")
{
    paytext = get_translation("misc_paytext_blackjack");
}

roundend = function()
{
    if (obj_shop.state == obj_shop.state_sleep)
    {
        if (obj_runctrl.challenge != "none")
        {
            if (obj_runctrl.flor_local_level == 6 && obj_runctrl.flor >= get_challenge(obj_runctrl.challenge).target)
            {
                obj_shop.state = obj_shop.state_shop;
            }
            else
            {
                obj_shop.state = obj_shop.state_booster;
            }
        }
        else if (obj_runctrl.flor == 3 && obj_runctrl.flor_local_level == 6 && (get_ring("sticker").status == "locked" || obj_runctrl.challenge != "none"))
        {
            obj_shop.state = obj_shop.state_shop;
        }
        else if (obj_runctrl.vortex_level < 13)
        {
            obj_shop.state = obj_shop.state_booster;
        }
        else
        {
            obj_shop.state = obj_shop.state_vortexend;
            reset_score();
        }
    }
    clean_dice();
    obj_deckctrl.reward_rerolls = gilded_value("lucky", 1);
    obj_deckctrl.win_setup = true;
    obj_deckctrl.state = obj_deckctrl.state_win;
    obj_deckctrl.thrown_dice = [];
    obj_deckctrl.elite = [];
    obj_deckctrl.discards = [];
    obj_deckctrl.turn = 0;
    obj_deckctrl.extradraw = 0;
    if (instance_exists(obj_boss))
    {
        obj_runctrl.char.infostats[3].value++;
    }
    obj_runctrl.char.infostats[2].value++;
    with (obj_dice)
    {
        if (selected)
        {
            de_sel_dice_function();
        }
    }
    for (var i = 0; i < instance_number(obj_ring); i++)
    {
        var _this = instance_find(obj_ring, i);
        _this.deactivated = false;
        _this.ring.deactivated = false;
    }
    global.ui_busy = false;
    instance_destroy();
};

pay_f = function()
{
    if (obj_runctrl.challenge != "blackjack")
    {
        subtract_score(obj_deckctrl.obj);
        // COOP PATCH: absorb this local-only change so peer's client doesn't
        // also apply a DELTA for the same round-end deduction.
        coop_rebase();
    }
    else
    {
        forceding = true;
    }
    if (string(display) == "NaNeinf" || string(display) == "NaN" || string(get_number_display(global.score)) == "NaNeinf" || string(get_number_display(global.score)) == "NaN")
    {
        forceding = true;
    }
    paying = true;
    image_index = 2;
};

if (global.skipanim)
{
    pay_f();
    if (global.dicelist[37].status == "locked")
    {
        unlock(global.dicelist[37], "dice");
    }
    if (global.dicelist[77].status == "locked")
    {
        if (obj_deckctrl.nodicethisround)
        {
            unlock(global.dicelist[77], "dice");
        }
    }
    if (!bossmode)
    {
        roundend();
    }
    else
    {
        cubesmode = true;
        instance_create_layer(683, 384, "hud", obj_cubesconverter);
    }
}

enum UnknownEnum
{
    Value_10 = 10
}
