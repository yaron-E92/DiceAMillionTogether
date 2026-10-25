// Consume any pending run-start payload on the main thread (outside the async event).
if (global.coop.pending_run != undefined)
{
    var _p = global.coop.pending_run;
    global.coop.pending_run = undefined;
    coop_log("Step: consuming deferred RUN_START (char=" + _p.char_ide + ", seed=" + string(_p.seed) + ")");
    var _char = coop_find_char_by_ide(_p.char_ide);
    coop_start_run(_char, _p.difficulty, _p.seed);
}

// v0.17: pending_roll_dice queue is no longer used (ROLL_DIE replaced by
// ROLL_COMMIT which is processed synchronously in coop_receive_roll_commit
// and spawned inside coop_barrier_passed("roll")).

// v0.26 CRITICAL: order matters. SPEND first, then SCORE_SET.
// If SCORE_SET fires first when local value just decreased, it broadcasts
// the post-spend absolute value (e.g. pips:90 after -10 spend). Then SPEND
// follows with pips_d:-10. Peer applies BOTH → pips = 90-10 = 80, wrong.
// Running SPEND first updates last_sent_* to the new value, so SCORE_SET's
// change-detector sees no change → no double broadcast. Deterministic sync.
coop_broadcast_spend_if_changed();
coop_host_broadcast_score_if_changed();

// v0.13: rolls consensus. Broadcast own rolls on change, then if a peer value
// is pending, compute avg and apply. Order matters: apply_rolls_average may
// mutate rolls and bump last_sent_rolls itself, so do it AFTER broadcast.
coop_broadcast_rolls_if_changed();
coop_apply_rolls_average();

// v0.23/v0.28/v0.29: track deckctrl state transitions.
// v0.29 fix: auto-detect uses EDGE of state transition (not snapshot).
// Previously `if (_now_scoring && !my_scoring)` re-fired every frame after
// coop_mark_scoring_done set my_scoring=false while we're still stuck in
// state_rolled (barrier holding). Result: 2 STATE_SYNC per frame forever
// — 681 true/false pairs observed in the 16:19 session. Fix: only flip
// my_scoring=true when state JUST entered state_rolled/state_rolling from
// something else. Leaving state_rolled is handled by mark_done explicitly.
if (global.coop.is_coop_run && instance_exists(obj_deckctrl))
{
    var _state_now = obj_deckctrl.state;
    var _prev = global.coop.last_deckctrl_state;
    var _now_scoring = (_state_now == obj_deckctrl.state_rolled)
                   || (_state_now == obj_deckctrl.state_rolling);
    var _prev_scoring = (_prev == obj_deckctrl.state_rolled)
                    || (_prev == obj_deckctrl.state_rolling);
    // Transition: leaving state_rolled → fade peer dice via exhaust_on_hand.
    if ((_prev == obj_deckctrl.state_rolled) && !_now_scoring)
    {
        with (obj_dice)
        {
            if (variable_instance_exists(self, "coop_peer") && coop_peer)
                exhaust_on_hand = true;
        }
    }
    // Edge-trigger on ENTRY to scoring (not snapshot). Fires once per round.
    if (_now_scoring && !_prev_scoring)
    {
        global.coop.my_scoring = true;
        coop_send({ type: "STATE_SYNC", scoring: true });
    }
    global.coop.last_deckctrl_state = _state_now;
}

// v0.23: apply pending board pick once both sides have clicked. Host's
// values win if the two picks differ (user's option Y: both click, host
// resolves conflict).
if (global.coop.is_coop_run
    && global.coop.my_board_pick != undefined
    && global.coop.peer_board_pick != undefined
    && !global.coop.board_applied
    && instance_exists(obj_runctrl)
    && instance_exists(obj_boardmap))
{
    var _pick = global.coop.role == "host" ? global.coop.my_board_pick : global.coop.peer_board_pick;
    // (Guest's peer_board_pick IS the host's pick, since only host's pick wins.)
    coop_log("board pick applied: pos=" + string(_pick.pos) + " branch=" + string(_pick.branch));
    obj_runctrl.board_pos = _pick.pos;
    obj_runctrl.board_pos = clamp(obj_runctrl.board_pos, 0, array_length(obj_runctrl.board[obj_runctrl.flor].tiles) - 1);
    obj_runctrl.board_branch = _pick.branch;
    global.ui_busy = true;
    with (obj_boardmap) exiting = true;
    global.coop.board_applied = true;
    global.coop.my_board_pick = undefined;
    global.coop.peer_board_pick = undefined;
}

// v0.11 / v0.24: consume deferred GAME_OVER from peer. Propagate winmode
// so a host WIN shows as a guest WIN (previously always rendered as loss).
// v0.31: skip if we've already left gameplay — the Step runs from a
// persistent netctrl, so a GAME_OVER that arrives after the local client
// returned to menu would crash on instance_create_layer("hud_over")
// because the main-menu room has no such layer. Drop the pending flag.
if (global.coop.pending_gameover)
{
    if (!instance_exists(obj_runctrl) || !layer_exists(layer_get_id("hud_over")))
    {
        global.coop.pending_gameover = false;
    }
    else if (!instance_exists(obj_gameover))
    {
        global.coop.pending_gameover = false;
        global.coop.gameover_broadcasted = true;
        var _inst = instance_create_layer(683, 384, "hud_over", obj_gameover);
        if (_inst != noone)
            _inst.winmode = global.coop.pending_gameover_winmode;
    }
}

// v0.7 obj_diceroll freezing was removed in v0.8 — those hooks were on the wrong
// object. Real barriers now live in patched obj_rollbutton and obj_shop_nextround.
