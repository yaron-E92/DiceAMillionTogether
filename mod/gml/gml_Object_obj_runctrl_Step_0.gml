if (!run_setup)
{
    run_setup = true;
    if (!loading)
    {
        // COOP PATCH (v0.5): if this is a coop run with a shared seed, use it
        // instead of randomize() so both clients' RNG stream stays in lockstep.
        // This makes map/boss/shop/ring generation identical on both sides.
        if (variable_global_exists("coop")
            && global.coop != undefined
            && global.coop.is_coop_run
            && obj_runctrl.seed != 0)
        {
            random_set_seed(obj_runctrl.seed);
            seed = obj_runctrl.seed;
        }
        else
        {
            randomize();
            seed = random_get_seed();
        }
        obj_bosslist.avaliable_boss = variable_clone(global.bosslist);
        if (obj_runctrl.challenge != "natural6")
        {
            var _boss_1 = 0;
            if (global.dicelist[19].status == "locked" || global.dicelist[10].status == "locked")
            {
                _boss_1 = get_boss(choose("odd", "even", "greedy", "blackout"));
                for (var i = 0; i < array_length(obj_bosslist.avaliable_boss); i++)
                {
                    if (obj_bosslist.avaliable_boss[i].ide == _boss_1.ide)
                    {
                        array_delete(obj_bosslist.avaliable_boss, i, 1);
                        break;
                    }
                }
            }
            else
            {
                _boss_1 = get_random_boss();
            }
            var _boss_2 = 0;
            if (global.dicelist[19].status == "locked" || global.dicelist[10].status == "locked")
            {
                _boss_2 = get_boss(choose("capricious", "heretic", "sloth", "patient", "pyromaniac"));
                for (var i = 0; i < array_length(obj_bosslist.avaliable_boss); i++)
                {
                    if (obj_bosslist.avaliable_boss[i].ide == _boss_2.ide)
                    {
                        array_delete(obj_bosslist.avaliable_boss, i, 1);
                        break;
                    }
                }
            }
            else
            {
                _boss_2 = get_random_boss();
            }
            var _boss_3 = get_random_boss();
            var _boss_4 = get_random_boss();
            var _boss_5 = get_random_boss();
            _boss_4.plus = true;
            _boss_5.plus = true;
            if (obj_runctrl.challenge == "ultrahard")
            {
                _boss_1.plus = true;
                _boss_2.plus = true;
                _boss_3.plus = true;
            }
            boss = [0, _boss_1, _boss_2, _boss_3, _boss_4, _boss_5];
        }
        else
        {
            for (var i = 0; i < array_length(target); i++)
            {
                boss_natural6[i] = get_random_boss(true);
            }
        }
        create_map();
        shop_ring = get_random_ring();
    }
    else
    {
        loading = false;
    }
}
