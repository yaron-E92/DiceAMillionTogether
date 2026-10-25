// Multidice co-op networking helpers.
//
// Protocol: TCP to relay (host:port configured below), length-prefixed frames:
//   uint32 LE length + UTF-8 JSON payload.
//
// All state lives on global.coop — a struct created once by obj_netctrl.Create.
//
// RELAY ADDRESS: configured in dice_amillion_together.ini next to the game.
// Both players must connect to the same relay. The relay does not
// parse game state — it just forwards frames between paired peers.

// UTMT's GMS2 compiler doesn't reliably propagate #macro across imported files, so we
// expose these as regular functions — guaranteed globally visible at runtime.
function coop_relay_host()
{
    ini_open(working_directory + "dice_amillion_together.ini");
    var _host = ini_read_string("relay", "host", "127.0.0.1");
    ini_close();
    return _host;
}
function coop_relay_port()
{
    ini_open(working_directory + "dice_amillion_together.ini");
    var _port = ini_read_real("relay", "port", 7777);
    ini_close();
    return clamp(floor(_port), 1, 65535);
}
function coop_proto_version() { return 1; }
function coop_mod_version() { return "0.33.0"; }

// v0.28 CRITICAL FIX: explicit "scoring locally done" signal.
//
// Problem in v0.25-0.27: my_scoring was auto-derived from state==state_rolled
// in obj_netctrl.Step. But my round_end barrier *blocks the state transition
// out of state_rolled*. So both clients reached scoring-complete, both stayed
// state_rolled (blocked), both had my_scoring=true, both had peer_scoring=true
// → coop_round_end_allowed returned false forever → deadlock.
//
// Fix: my_scoring is now set TRUE only via auto-detect (state enters rolled),
// and set FALSE only via THIS explicit helper — called right before the
// round_end barrier check. Once both clients call it, both peer_scoring flip
// false, barrier opens, round_end fires on both sides.
function coop_mark_scoring_done()
{
    if (!variable_global_exists("coop") || global.coop == undefined) return;
    if (!global.coop.is_coop_run) return;
    if (!global.coop.my_scoring) return;  // already done
    global.coop.my_scoring = false;
    coop_send({ type: "STATE_SYNC", scoring: false });
}

// v0.27: request a refresh of the open-lobbies list from the relay. Used
// by obj_coop_lobby in "browse" mode. Relay responds with a LOBBIES msg
// listing the codes of rooms that have no guest yet.
function coop_request_lobbies()
{
    if (global.coop.socket < 0) return;
    if (global.coop.state != "browsing") return;
    coop_send({ type: "LIST_REQUEST" });
}

// v0.27: from the browse list, the user clicked a lobby — promote our
// existing browse socket into a guest of that room. Relay answers with
// the usual ROOM frame which transitions state to "paired".
function coop_join_from_browse(_code)
{
    if (global.coop.socket < 0) return;
    if (global.coop.state != "browsing") return;
    coop_log("UI: JOIN from browse, code=" + _code);
    global.coop.code = _code;
    coop_send({ type: "JOIN", code: _code });
}

// v0.17: shim for legacy FindReplace (no longer used — kept so that a
// previously-patched data.win with the replacement still links). Always
// returns place_meeting result without filtering — behaves identically to
// the original pre-replace code. Safe to remove once data.win is rebuilt
// from a clean source.
function coop_real_dice_overlap(_x, _y, _self)
{
    return place_meeting(_x, _y, obj_dice);
}

// ---- logging ----

// coop_log writes to three sinks: show_debug_message (stdout), local coop_mod.log,
// and (when the relay socket is up) a {"type":"LOG"} message sent to the server so the
// developer can read both clients' logs from the VM without exchanging files.
// Always safe to call, even before global.coop exists — sinks fail open.
function coop_log(_msg)
{
    var _h = current_hour;
    var _m = current_minute;
    var _s = current_second;
    var _ts = (_h < 10 ? "0" : "") + string(_h) + ":"
            + (_m < 10 ? "0" : "") + string(_m) + ":"
            + (_s < 10 ? "0" : "") + string(_s);
    var _line = "[" + _ts + "][coop] " + string(_msg);
    show_debug_message(_line);
    try
    {
        var _f = file_text_open_append(working_directory + "coop_mod.log");
        file_text_write_string(_f, _line);
        file_text_writeln(_f);
        file_text_close(_f);
    }
    catch (_e) {}

    // Remote sink: only once we're past the HELLO handshake. Sending while state is
    // "connected" (pre-HELLO) or earlier would race the HELLO frame and the relay
    // would reject the connection with "first frame must be HELLO".
    if (variable_global_exists("coop")
        && global.coop != undefined
        && global.coop.socket >= 0
        && (global.coop.state == "paired_wait"
         || global.coop.state == "paired"
         || global.coop.state == "in_run"))
    {
        try
        {
            var _frame = coop_pack_frame({ type: "LOG", line: _line });
            var _sz = buffer_get_size(_frame);
            network_send_raw(global.coop.socket, _frame, _sz);
            buffer_delete(_frame);
        }
        catch (_e) {}
    }
}

// Dump a struct/value as json for logging. Handles things json_stringify chokes on.
function coop_log_json(_label, _obj)
{
    var _s;
    try { _s = json_stringify(_obj); } catch (_e) { _s = "<unjson>"; }
    coop_log(_label + ": " + _s);
}

// ---- frame pack/unpack ----

// Build a wire frame from a GML struct: 4-byte LE length + JSON bytes.
// Returns a fresh buffer the caller must delete.
function coop_pack_frame(_obj)
{
    var _json = json_stringify(_obj);
    var _bytes = buffer_create(1, buffer_grow, 1);
    buffer_write(_bytes, buffer_text, _json);
    var _len = buffer_tell(_bytes);
    var _frame = buffer_create(4 + _len, buffer_fixed, 1);
    buffer_write(_frame, buffer_u32, _len);
    buffer_copy(_bytes, 0, _len, _frame, 4);
    buffer_delete(_bytes);
    return _frame;
}

// Append bytes from an async_load networking buffer into global.coop.rx_buf at the
// current fill offset, then advance the fill count. buffer_copy uses explicit offsets
// on a buffer_grow-typed destination, which grows as needed.
function coop_rx_append(_src_buffer, _src_size)
{
    buffer_copy(_src_buffer, 0, _src_size, global.coop.rx_buf, global.coop.rx_filled);
    global.coop.rx_filled += _src_size;
}

// Try to parse one complete frame from global.coop.rx_buf.
// Returns the decoded struct, or undefined if there isn't a full frame yet.
// On success, shifts remaining bytes to the start of rx_buf.
function coop_rx_try_pop()
{
    if (global.coop.rx_filled < 4)
        return undefined;
    buffer_seek(global.coop.rx_buf, buffer_seek_start, 0);
    var _ln = buffer_read(global.coop.rx_buf, buffer_u32);
    if (global.coop.rx_filled < (4 + _ln))
        return undefined;

    // Copy the JSON bytes into a fresh fixed buffer with a trailing NUL so buffer_text works.
    var _tmp = buffer_create(_ln + 1, buffer_fixed, 1);
    buffer_copy(global.coop.rx_buf, 4, _ln, _tmp, 0);
    buffer_poke(_tmp, _ln, buffer_u8, 0);
    buffer_seek(_tmp, buffer_seek_start, 0);
    var _str = buffer_read(_tmp, buffer_text);
    buffer_delete(_tmp);

    // Shift remaining bytes (if any) to the start of rx_buf via a tiny carry buffer.
    var _consumed = 4 + _ln;
    var _remaining = global.coop.rx_filled - _consumed;
    if (_remaining > 0)
    {
        var _carry = buffer_create(_remaining, buffer_fixed, 1);
        buffer_copy(global.coop.rx_buf, _consumed, _remaining, _carry, 0);
        buffer_copy(_carry, 0, _remaining, global.coop.rx_buf, 0);
        buffer_delete(_carry);
    }
    global.coop.rx_filled = _remaining;

    try
    {
        return json_parse(_str);
    }
    catch (_e)
    {
        coop_log("bad json: " + _str);
        return undefined;
    }
}

// Send a struct as one framed message. No-op if the socket isn't up.
// We write the frame to the socket BEFORE logging, so that HELLO (and every other
// payload) gets flushed ahead of any LOG frame coop_log might append. Otherwise the
// remote LOG piggyback can race the primary message and the relay will reject the
// connection with "first frame must be HELLO".
function coop_send(_obj)
{
    if (global.coop.socket < 0 || global.coop.state == "idle" || global.coop.state == "connecting")
    {
        coop_log_json("send DROPPED (state=" + global.coop.state + ")", _obj);
        return;
    }
    var _frame = coop_pack_frame(_obj);
    var _sz = buffer_get_size(_frame);
    var _rc = network_send_raw(global.coop.socket, _frame, _sz);
    buffer_delete(_frame);
    coop_log_json("tx", _obj);
    if (_rc < 0)
        coop_log("send failed rc=" + string(_rc));
}

// ---- connection lifecycle ----

function coop_connect(_mode, _code)
{
    if (global.coop.socket >= 0)
    {
        coop_log("connect called but socket already up, ignoring");
        return;
    }
    coop_log("connect start: mode=" + _mode + " code=" + string(_code) + " host=" + coop_relay_host() + ":" + string(coop_relay_port()));
    global.coop.mode = _mode;
    global.coop.code = _code;
    global.coop.state = "connecting";
    global.coop.last_error = "";
    global.coop.socket = network_create_socket(network_socket_tcp);
    var _rc = network_connect_raw_async(global.coop.socket, coop_relay_host(), coop_relay_port());
    coop_log("connect_async started, async_id=" + string(_rc) + " socket=" + string(global.coop.socket));
    global.coop.connect_async_id = _rc;
}

function coop_disconnect()
{
    coop_log("disconnect called (socket=" + string(global.coop.socket) + " state=" + global.coop.state + ")");
    if (global.coop.socket >= 0)
    {
        network_destroy(global.coop.socket);
        global.coop.socket = -1;
    }
    if (buffer_exists(global.coop.rx_buf))
        buffer_delete(global.coop.rx_buf);
    global.coop.rx_buf = buffer_create(64, buffer_grow, 1);
    global.coop.rx_filled = 0;
    global.coop.state = "idle";
    global.coop.role = "";
    global.coop.code = "";
    global.coop.peer_present = false;
    global.coop.my_char_ide = "";
    global.coop.peer_char_ide = "";
    global.coop.my_ready = false;
    global.coop.peer_ready = false;
    // v0.24 M3 fix: full state reset on disconnect so a new lobby doesn't
    // inherit is_coop_run=true or stale scoring/board pick state from a
    // previous session that dropped its socket.
    global.coop.is_coop_run = false;
    global.coop.my_scoring = false;
    global.coop.peer_scoring = false;
    global.coop.peer_scoring_since = 0;
    global.coop.my_roll_queued = false;
    global.coop.peer_roll_committed = false;
    global.coop.my_shop_queued = false;
    global.coop.peer_shop_ready_gate = false;
    global.coop.peer_committed_dice = [];
    global.coop.my_board_pick = undefined;
    global.coop.peer_board_pick = undefined;
    global.coop.board_applied = false;
    global.coop.pending_gameover = false;
    global.coop.pending_gameover_winmode = false;
    global.coop.gameover_broadcasted = false;
    global.coop.pending_peer_rolls = undefined;
    global.coop.roll_counter = 0;
}

function coop_on_connected()
{
    global.coop.state = "connected";
    coop_send({
        type: "HELLO",
        proto: coop_proto_version(),
        mod: coop_mod_version(),
        mode: global.coop.mode,
        code: global.coop.code
    });
    // v0.27: for mode=list the relay doesn't send a ROOM frame back; it
    // just keeps the socket open and waits for LIST_REQUEST/JOIN. Transition
    // straight to "browsing" so the refresh timer in obj_coop_lobby fires.
    if (global.coop.mode == "list")
    {
        global.coop.state = "browsing";
        global.coop.lobby_list = [];
    }
}

// ---- game-level messages (lobby) ----

function coop_send_char_pick(_ide)
{
    coop_log("UI: picked char " + _ide);
    global.coop.my_char_ide = _ide;
    coop_send({ type: "CHAR_PICK", ide: _ide });
}

function coop_send_ready(_state)
{
    coop_log("UI: ready toggled to " + string(_state));
    global.coop.my_ready = _state;
    coop_send({ type: "READY", state: _state });
}

function coop_send_run_start(_seed, _host_ide, _guest_ide, _difficulty)
{
    coop_send({
        type: "RUN_START",
        seed: _seed,
        host_ide: _host_ide,
        guest_ide: _guest_ide,
        difficulty: _difficulty
    });
}

// ---- v0.3 shared team state ----

// Serialize a "big-like" value (in this game's non-bignumber mode all the Big* APIs
// actually operate on plain numbers, so string() works and handles negatives
// correctly — which BigToDecimalString does NOT, it wraps negatives to 2^64-X).
// We keep the is_array branch for theoretical bignumber-array mode, but the game
// never enables it (obj_settings.Create sets global.bignumbers = false).
function coop_big_to_str(_big)
{
    if (is_array(_big))
        return BigToDecimalString(_big, false);
    return string(_big);
}

// Parse a decimal string. `real()` handles negatives and empty strings (→0).
// Using BigFromDecimalString here is what caused the v0.3–v0.7 score-sync crashes:
// it calls BigZero() which returns 0 (not an array) when bignumbers are off, then
// BigAddInt32 tries to index that 0 and fails.
function coop_big_from_str(_s)
{
    if (_s == "" || _s == undefined)
        return 0;
    return real(_s);
}

// Compare two "big-like" values (number or array).
function coop_num_equal(_a, _b)
{
    if (is_array(_a) && is_array(_b)) return array_equals(_a, _b);
    if (is_array(_a) || is_array(_b)) return false;
    return _a == _b;
}

// v0.8.2: snap last_seen trackers to the current values so the next diff-check
// sees no change and doesn't emit a DELTA. Call this right after a LOCAL-ONLY
// change to score/pips — i.e. an action the game's code runs on BOTH clients
// simultaneously (round-end quota pay_f, end-of-run reset, etc). Without rebase,
// both clients would subtract locally AND echo the subtraction to each other
// via DELTA, doubling the deduction out of the shared pool.
function coop_rebase()
{
    if (!variable_global_exists("coop") || global.coop == undefined) return;
    if (!global.coop.is_coop_run) return;
    // v0.24 C2 fix: snap ALL trackers, not just legacy last_seen_*. The
    // v0.17+ DELTA model used last_seen; v0.22+ uses last_spend_* +
    // last_sent_*. Without updating them, pay_f's symmetric subtract is
    // detected as user-initiated SPEND on both clients, each broadcasts
    // SPEND{pips_d:-quota}, peer re-subtracts → round quota deducted twice
    // from the shared pool. Same for any other "both clients run this
    // code locally" mutation (back_to_menu reset, round_end pay, etc).
    if (instance_exists(obj_runctrl))
    {
        global.coop.last_seen_score = obj_runctrl.total_score;
        global.coop.last_sent_score = obj_runctrl.total_score;
        global.coop.last_spend_score = obj_runctrl.total_score;
    }
    if (variable_global_exists("score"))
    {
        global.coop.last_seen_pips = global.score;
        global.coop.last_sent_pips = global.score;
        global.coop.last_spend_pips = global.score;
    }
    if (instance_exists(obj_deckctrl))
    {
        global.coop.last_sent_cubes = obj_deckctrl.cubes;
        global.coop.last_spend_cubes = obj_deckctrl.cubes;
    }
}

// Capture the current obj_runctrl.target / target_n as the "solo" baseline once.
// Safe to call any number of times — snapshot is taken only the first time.
function coop_ensure_solo_targets_snapshotted()
{
    if (global.coop.solo_target != undefined)
        return;
    if (!instance_exists(obj_runctrl))
        return;
    global.coop.solo_target = variable_clone(obj_runctrl.target);
    global.coop.solo_target_n = variable_clone(obj_runctrl.target_n);
    coop_log("snapshotted solo targets: target len=" + string(array_length(obj_runctrl.target))
        + ", target_n len=" + string(array_length(obj_runctrl.target_n)));
}

// Restore target arrays from the solo snapshot and, if we're in a coop run,
// multiply every goal by 2 (per design: two players → double the bar).
function coop_apply_coop_targets()
{
    coop_ensure_solo_targets_snapshotted();
    if (global.coop.solo_target == undefined)
    {
        coop_log("apply_coop_targets: no snapshot, skipping");
        return;
    }
    obj_runctrl.target = variable_clone(global.coop.solo_target);
    obj_runctrl.target_n = variable_clone(global.coop.solo_target_n);
    if (global.coop.is_coop_run)
    {
        // v0.33: x4 quota (was x2 in v0.3). v0.32's bilateral DELTA sync
        // makes both players' rings contribute to the shared pool, so
        // combined scoring on identical rings effectively doubles vs solo.
        // x4 target compensates for the extra contribution + keeps coop
        // meaningfully challenging.
        for (var _i = 0; _i < array_length(obj_runctrl.target); _i++)
            obj_runctrl.target[_i] *= 4;
        for (var _i = 0; _i < array_length(obj_runctrl.target_n); _i++)
        {
            for (var _j = 0; _j < array_length(obj_runctrl.target_n[_i]); _j++)
                obj_runctrl.target_n[_i][_j] *= 4;
        }
        coop_log("apply_coop_targets: x4 goals for coop run");
    }
}

// v0.18: host-authoritative absolute score broadcast.
// v0.32: now only carries boss_hp. Score/pips/cubes moved to pure
// bilateral DELTA (see coop_broadcast_spend_if_changed) — each side
// broadcasts its local pip changes, receiver applies bilaterally. That
// implements "shared pool" semantics: both players' rings contribute to
// the shared wallet, both players' chest clicks stack (balances v0.3's
// x2 targets). Deterministic symmetric events (pay_f, back_to_menu)
// suppress broadcast via coop_rebase() so the same event isn't counted
// twice from both sides. Host-authoritative absolute was incompatible
// with shared-pool since it would overwrite guest's local ring gains.
// boss_hp stays absolute because it's a single authoritative enemy
// state, not a shared resource — delta semantics don't apply.
function coop_host_broadcast_score_if_changed()
{
    if (global.coop.role != "host")
        return;
    if (global.coop.state != "in_run")
        return;
    if (!global.coop.is_coop_run)
        return;
    if (!instance_exists(obj_runctrl))
        return;

    var _boss_hp = -1;
    if (instance_exists(obj_finalboss))
        _boss_hp = obj_finalboss.hp;

    if (_boss_hp == global.coop.last_sent_boss_hp)
        return;

    global.coop.last_sent_boss_hp = _boss_hp;
    coop_send({
        type: "SCORE_SET",
        boss_hp: _boss_hp
    });
}

// Guest: apply authoritative boss_hp from host. Score/pips/cubes fields
// may be present in messages from older hosts but are ignored — v0.32
// moved them to bilateral DELTA (see coop_apply_spend). Only boss_hp
// is still absolute-authoritative.
function coop_guest_apply_score_set(_msg)
{
    if (global.coop.role == "host")
        return;
    if (!instance_exists(obj_runctrl))
        return;
    try
    {
        if (variable_struct_exists(_msg, "boss_hp")
            && _msg.boss_hp >= 1
            && instance_exists(obj_finalboss))
        {
            obj_finalboss.hp = _msg.boss_hp;
        }
    }
    catch (_e)
    {
        coop_log("apply_score_set failed: " + string(_e));
    }
}

// v0.17 legacy stubs — pre-v0.18 call sites continue to link without
// broadcasting. The Step loop calls coop_host_broadcast_score_if_changed now.
function coop_host_broadcast_state_if_changed() {}
function coop_guest_apply_state(_msg) {}

// v0.13: rolls consensus. Each hand has its own calculate_diceperturn() result,
// which can differ between characters — e.g. host picked a 3-roll hand and
// guest picked a 2-roll hand. Without a consensus, whoever is lower runs out
// of rolls first and ends the round for themselves. Design decision (user):
// both sides should end up with floor((a+b)/2) at the start of each round.
//
// Protocol: any client whose deckctrl.rolls changes (detected per frame in
// obj_netctrl.Step) broadcasts ROLLS {rolls:N}. Receiver stores peer_rolls;
// once we have peer_rolls AND peer_rolls != last_applied_peer_rolls, both
// sides compute avg = floor((my + peer) / 2) and apply if different.
//
// avg(avg, avg) = avg, so the two-way echo converges in at most one round
// trip and never oscillates. Barrier-driven rolls-- in fire_roll stays in sync
// afterwards because both sides decrement simultaneously.
function coop_broadcast_rolls_if_changed()
{
    if (global.coop.state != "in_run") return;
    if (!global.coop.is_coop_run) return;
    if (!instance_exists(obj_deckctrl)) return;
    // v0.17: don't broadcast pre-setup rolls. Until hand_setup=true, rolls
    // holds stale-or-zero values from the previous round and advertising them
    // makes the peer average incorrect numbers.
    if (!obj_deckctrl.hand_setup) return;
    var _r = obj_deckctrl.rolls;
    if (_r == global.coop.last_sent_rolls) return;
    global.coop.last_sent_rolls = _r;
    coop_send({ type: "ROLLS", rolls: _r });
}

function coop_apply_rolls_average()
{
    if (!instance_exists(obj_deckctrl)) return;
    if (global.coop.pending_peer_rolls == undefined) return;
    // v0.17: guard against race where peer's ROLLS arrives before our own
    // hand_setup has assigned rolls. Previously this averaged 0 (stale) with
    // peer's real value, collapsing both sides to a smaller number (seen in
    // v0.16 logs as `avg: mine=0 peer=3 -> 1`). Wait until we're ready.
    if (!obj_deckctrl.hand_setup) return;
    var _peer = global.coop.pending_peer_rolls;
    global.coop.pending_peer_rolls = undefined;
    var _mine = obj_deckctrl.rolls;
    var _avg = floor((_mine + _peer) / 2);
    if (_avg == _mine) return;
    coop_log("rolls avg: mine=" + string(_mine) + " peer=" + string(_peer) + " -> " + string(_avg));
    obj_deckctrl.rolls = _avg;
    global.coop.last_sent_rolls = _avg;
    coop_send({ type: "ROLLS", rolls: _avg });
}

// v0.18 legacy stub — DELTA broadcast removed, host authority replaced it.
function coop_guest_send_deltas_if_changed() {}

// v0.22: bilateral spend-tracking for the shop / pack phase. User reported
// that when guest buys but host is still scoring, guest's cubes go down
// locally but host's SCORE_SET broadcast overwrites them back to the higher
// value — guest's purchase is lost.
//
// Fix: whenever local obj_deckctrl.cubes DECREASES (or obj_runctrl.total_score
// decreases — some donations cost score), broadcast SPEND {cubes_d, score_d}.
// Peer applies the delta (subtracts from local). Host's next SCORE_SET will
// carry the updated authoritative values as usual.
//
// Why only decreases: increases happen through scoring (ring/dice effects)
// on both clients simultaneously (seed-synced). Broadcasting those would
// double-count. Decreases only happen through user action (buy click) which
// is single-client, so bilateral SPEND is safe.
function coop_broadcast_spend_if_changed()
{
    if (global.coop.state != "in_run") return;
    if (!global.coop.is_coop_run) return;
    if (!instance_exists(obj_deckctrl)) return;
    if (!instance_exists(obj_runctrl)) return;
    if (!variable_global_exists("score")) return;

    var _cubes = obj_deckctrl.cubes;
    var _score = obj_runctrl.total_score;
    var _pips  = global.score;

    if (global.coop.last_spend_cubes == undefined) global.coop.last_spend_cubes = _cubes;
    if (global.coop.last_spend_score == undefined) global.coop.last_spend_score = _score;
    if (global.coop.last_spend_pips  == undefined) global.coop.last_spend_pips  = _pips;

    var _dc = _cubes - global.coop.last_spend_cubes;
    var _ds = coop_num_equal(_score, global.coop.last_spend_score) ? 0 : (_score - global.coop.last_spend_score);
    var _dp = coop_num_equal(_pips,  global.coop.last_spend_pips)  ? 0 : (_pips  - global.coop.last_spend_pips);

    global.coop.last_spend_cubes = _cubes;
    global.coop.last_spend_score = _score;
    global.coop.last_spend_pips  = _pips;

    // v0.32: broadcast ANY non-zero delta, both directions. Peer applies
    // the signed delta bilaterally ("shared pool" semantics):
    //  - Spends (user buys): broadcast negative delta, peer deducts too.
    //  - Gains (ring on one side only, chest-reward click on one side):
    //    broadcast positive delta, peer adds too. Combined with v0.3's x2
    //    targets, this balances out correctly — each chest / ring gain
    //    contributes to the shared wallet exactly once per player click.
    // Deterministic symmetric events (pay_f round-quota, back_to_menu
    // reset) call coop_rebase() right after mutating to snap last_spend_*
    // to the post-event value, so the next frame's change detector sees
    // no delta and no broadcast fires — both sides already agree.
    var _changed = (_dc != 0)
                || (is_real(_ds) && _ds != 0)
                || (is_real(_dp) && _dp != 0);
    if (_changed)
    {
        coop_send({
            type: "SPEND",
            cubes_d: _dc,
            score_d: is_real(_ds) ? coop_big_to_str(_ds) : "0",
            pips_d:  is_real(_dp) ? coop_big_to_str(_dp) : "0"
        });
    }
}

// v0.23: invoked from obj_boardmap.Draw_0 click handler (via FindReplace) to
// decide whether to apply a board pick locally. Solo → true, apply normally.
// Coop → false, queue our pick; obj_netctrl.Step will apply the authoritative
// resolved pick once both sides have clicked.
//
// Conflict resolution: host's pick wins (option Y from design chat).
// See obj_netctrl_Step_0.gml where the apply block runs.
// v0.25: returns true if it's OK for THIS client to fire round_end() (the
// transition out of state_rolled into state_menu which opens shop/reward UI).
// Returns false if we're in coop and peer is still scoring — blocks the
// transition so peer doesn't race ahead into the shop while host still
// animates scoring. Re-checked every frame; once peer finishes (STATE_SYNC
// flips their scoring to false), this returns true and round_end fires.
function coop_round_end_allowed()
{
    if (!variable_global_exists("coop") || global.coop == undefined) return true;
    if (!global.coop.is_coop_run) return true;
    if (!global.coop.peer_scoring) return true;
    // Peer still mid-scoring → hold, BUT with a 30-second timeout so that
    // a silently dropped peer socket doesn't freeze this client in state_rolled
    // forever. If peer_scoring has been stuck on for 30s, release the gate.
    if (global.coop.peer_scoring_since == 0)
        global.coop.peer_scoring_since = current_time;
    if (current_time - global.coop.peer_scoring_since > 30000)
    {
        coop_log("round_end timeout: peer stuck in scoring for 30s, releasing");
        global.coop.peer_scoring = false;
        global.coop.peer_scoring_since = 0;
        return true;
    }
    return false;
}

// v0.33: obj_map roll/skip vote. Each player casts exactly one vote per
// map screen. When both votes are in, coop_map_vote_try_resolve computes
// the winner (matching votes pass through, mismatched vote uses a shared
// deterministic RNG seeded from runctrl.seed + level so both clients agree
// without extra message). The winning action then fires symmetrically on
// both sides: local subtract_score + level advance + reward pack. Since
// it's symmetric + immediately followed by coop_rebase(), the price is
// only paid once (not 2x despite bilateral SPEND broadcast otherwise).
function coop_should_intercept_map_click()
{
    if (!variable_global_exists("coop") || global.coop == undefined) return false;
    if (!global.coop.is_coop_run) return false;
    return global.coop.my_map_vote == "" && !global.coop.map_vote_resolved;
}

function coop_cast_map_vote(_vote)
{
    if (!variable_global_exists("coop") || global.coop == undefined) return;
    if (!global.coop.is_coop_run) return;
    if (global.coop.my_map_vote != "") return; // already voted
    global.coop.my_map_vote = _vote;
    coop_send({ type: "MAP_VOTE", vote: _vote });
    coop_log("map vote cast: " + _vote);
    coop_map_vote_try_resolve();
}

function coop_map_vote_try_resolve()
{
    if (!variable_global_exists("coop") || global.coop == undefined) return;
    if (global.coop.map_vote_resolved) return;
    if (global.coop.my_map_vote == "") return;
    if (global.coop.peer_map_vote == "") return;

    var _mine = global.coop.my_map_vote;
    var _peer = global.coop.peer_map_vote;
    var _winner;
    if (_mine == _peer)
    {
        _winner = _mine;
    }
    else
    {
        // Mismatch — shared RNG so both clients pick the same winner.
        // Seeded from runctrl.seed + level + flor_local_level to vary
        // each map screen while staying deterministic across clients.
        var _seed = 0;
        if (instance_exists(obj_runctrl))
            _seed = obj_runctrl.seed + (obj_runctrl.level * 7919) + (obj_runctrl.flor_local_level * 13);
        var _saved = random_get_seed();
        random_set_seed(_seed);
        _winner = (irandom(1) == 0) ? "roll" : "skip";
        random_set_seed(_saved);
    }
    global.coop.map_vote_winner = _winner;
    global.coop.map_vote_resolved = true;
    coop_log("map vote resolved: mine=" + _mine + " peer=" + _peer + " winner=" + _winner);
}

function coop_clear_map_vote()
{
    if (!variable_global_exists("coop") || global.coop == undefined) return;
    global.coop.my_map_vote = "";
    global.coop.peer_map_vote = "";
    global.coop.map_vote_resolved = false;
    global.coop.map_vote_winner = "";
}

function coop_board_pick_or_queue(_delta, _branch)
{
    // v0.24 C1 fix: `global.coop` only exists after the user opens the coop
    // lobby. A solo run that never touches the CO-OP button never instantiates
    // obj_netctrl, so `global.coop` is undefined. Without this guard the
    // board-map click throws "accessed before being set" and crashes solo.
    if (!variable_global_exists("coop") || global.coop == undefined) return true;
    if (!global.coop.is_coop_run) return true;
    if (!instance_exists(obj_runctrl)) return true;
    var _pos = obj_runctrl.board_pos + _delta;
    _pos = clamp(_pos, 0, array_length(obj_runctrl.board[obj_runctrl.flor].tiles) - 1);
    global.coop.my_board_pick = { pos: _pos, branch: _branch };
    global.coop.board_applied = false;
    coop_send({ type: "BOARD_PICK", pos: _pos, branch: _branch, role: global.coop.role });
    coop_log("board pick queued: pos=" + string(_pos) + " branch=" + string(_branch));
    return false;
}

function coop_apply_spend(_msg)
{
    if (!instance_exists(obj_deckctrl)) return;
    if (!instance_exists(obj_runctrl)) return;
    if (!variable_global_exists("score")) return;
    try
    {
        // v0.32: apply signed deltas in either direction. See
        // coop_broadcast_spend_if_changed for the shared-pool model.
        if (variable_struct_exists(_msg, "cubes_d"))
        {
            var _dc = _msg.cubes_d;
            if (is_real(_dc) && _dc != 0)
            {
                obj_deckctrl.cubes += _dc;
                global.coop.last_spend_cubes = obj_deckctrl.cubes;
            }
        }
        if (variable_struct_exists(_msg, "score_d"))
        {
            var _ds = coop_big_from_str(_msg.score_d);
            if (!coop_num_equal(_ds, 0))
            {
                obj_runctrl.total_score = obj_runctrl.total_score + _ds;
                global.coop.last_spend_score = obj_runctrl.total_score;
            }
        }
        if (variable_struct_exists(_msg, "pips_d"))
        {
            var _dp = coop_big_from_str(_msg.pips_d);
            if (!coop_num_equal(_dp, 0))
            {
                global.score = global.score + _dp;
                global.coop.last_spend_pips = global.score;
            }
        }
    }
    catch (_e)
    {
        coop_log("apply_spend failed: " + string(_e));
    }
}

// ---- v0.17 ROLL_COMMIT / peer-dice injection ----
// Replaces the old ghost visualization (ROLL_DIE + coop_receive_roll_die).
// At barrier-fire on "roll", each client collects its selected dice and
// sends a ROLL_COMMIT. The peer injects those dice as REAL obj_dice with
// selected=true into its own obj_deckctrl, so the game's own state_rolling
// picks them up natively — no custom physics, no ghost prepend, no halo
// hacks. Peer dice get a coop_peer=true flag for visual tinting only.
//
// Stub kept for compatibility with any queued-build path that still calls it.
function coop_send_roll_die() {}

// Collect a serialisable summary of every currently selected obj_dice. Called
// at the moment the player clicks Roll, so selection is final.
function coop_collect_selected_dice()
{
    var _out = [];
    for (var i = 0; i < instance_number(obj_dice); i++)
    {
        var _d = instance_find(obj_dice, i);
        if (!_d.selected) continue;
        // Skip boss dice: they live on the boss side and aren't owned by either
        // player's deck, so we don't transmit them.
        if (variable_instance_exists(_d, "boss") && _d.boss) continue;
        // v0.24 M6 fix: skip peer dice — they were force-selected=true by
        // our prepend, so they'd be re-broadcast back to the peer which
        // would inject them again as double-peer dice.
        if (variable_instance_exists(_d, "coop_peer") && _d.coop_peer) continue;
        var _ent = {
            ide: _d.die.ide,
            level: variable_struct_exists(_d.die, "level") ? _d.die.level : 0,
            enchant_ide: "none",
            enchant_type: "none",
            enchant_number_ide: 0
        };
        try
        {
            if (variable_struct_exists(_d.die, "enchant") && _d.die.enchant != undefined)
            {
                _ent.enchant_ide = _d.die.enchant.ide;
                _ent.enchant_type = _d.die.enchant.type;
                _ent.enchant_number_ide = _d.die.enchant.number_ide;
            }
        }
        catch (_e) {}
        array_push(_out, _ent);
    }
    return _out;
}

// Send our selected dice as ROLL_COMMIT + signal "roll" barrier ready.
// Called from coop_request_barrier("roll").
function coop_send_roll_commit()
{
    if (global.coop.state != "in_run" || !global.coop.is_coop_run)
        return;
    var _dice = coop_collect_selected_dice();
    coop_send({
        type: "ROLL_COMMIT",
        dice: _dice,
        owner: global.coop.role
    });
}

// Receiver — stash peer's committed selection. Actual spawn is deferred to
// coop_inject_peer_dice(), called from coop_barrier_passed("roll") on the
// frame both sides are ready, right before fire_roll().
function coop_receive_roll_commit(_msg)
{
    if (!global.coop.is_coop_run)
        return;
    var _dice = variable_struct_exists(_msg, "dice") ? _msg.dice : [];
    global.coop.peer_committed_dice = _dice;
    global.coop.peer_roll_committed = true;
    coop_log("received ROLL_COMMIT from peer: " + string(array_length(_dice)) + " dice");
}

// Spawn peer's committed dice as REAL obj_dice in my hand with selected=true.
// Called once per round right before fire_roll() so they enter state_rolling
// together with my own selected dice and the game scores them natively.
function coop_inject_peer_dice()
{
    if (!instance_exists(obj_deckctrl)) return;
    var _list = global.coop.peer_committed_dice;
    if (!is_array(_list)) return;
    // Destroy any leftover peer dice from previous rounds before spawning
    // new ones. Peer dice have reroll_on_hand=false so the game's state_menu
    // sweep doesn't clean them.
    // v0.19: collect ids first, then destroy outside `with`. Inside `with`
    // the destroy is queued to end-of-event, and iterator state during the
    // rest of this frame can still include those zombie instances — caused
    // the v0.18 peer crash at obj_dice.Step_0:315 reading .deck_num on a
    // pending-destroy instance.
    var _to_kill = [];
    with (obj_dice)
    {
        if (variable_instance_exists(self, "coop_peer") && coop_peer)
            array_push(_to_kill, id);
    }
    for (var _k = 0; _k < array_length(_to_kill); _k++)
        if (instance_exists(_to_kill[_k])) instance_destroy(_to_kill[_k]);
    var _peer_owner = global.coop.role == "host" ? "guest" : "host";
    var _layer = layer_exists("dice") ? "dice" : "Instances";
    var _count = 0;
    for (var i = 0; i < array_length(_list); i++)
    {
        var _ent = _list[i];
        var _tpl = coop_find_die_template_by_ide(_ent.ide);
        if (_tpl == undefined)
        {
            coop_log("inject_peer_dice: unknown ide " + string(_ent.ide) + ", skipping");
            continue;
        }
        var _die = variable_clone(_tpl);
        if (variable_struct_exists(_ent, "level")) _die.level = _ent.level;
        // v0.30: fields that add_dice() initialises but raw template doesn't.
        // dice_effect reads die.times_rolled unconditionally for matrioshka
        // and a few other die types, so a missing field crashes with
        // "Variable <unknown_object>.times_rolled not set" (observed in the
        // host log at 17:20:55 when peer rolled a matrioshka). Seed all the
        // fields add_dice() normally sets so peer dice survive dice_effect.
        _die.times_rolled = 0;
        if (!variable_struct_exists(_die, "extra_value")) _die.extra_value = BigZero();
        if (_die.ide == "crypto" && !variable_struct_exists(_die, "value"))
            _die.value = 0; // deterministic; host's actual value will come via face_value in future.
        if (_die.ide == "foam" && !variable_struct_exists(_die, "base_color"))
            _die.base_color = 16777215; // white; host visual irrelevant for scoring.
        // Rebind enchant by ide (dicelist default is enchantlist[0] = none).
        var _ei = variable_struct_exists(_ent, "enchant_ide") ? _ent.enchant_ide : "none";
        var _et = variable_struct_exists(_ent, "enchant_type") ? _ent.enchant_type : "none";
        if (_ei != "none")
        {
            var _src = (_et == "curse") ? global.curselist : global.enchantlist;
            for (var j = 0; j < array_length(_src); j++)
            {
                if (_src[j].ide == _ei) { _die.enchant = _src[j]; break; }
            }
        }
        // Negative .num keeps peer's die out of the local global.deck index space.
        _die.num = -1000 - i;
        // Protect shared RNG from obj_dice.Create's irandom_range(default_face).
        var _seed = random_get_seed();
        // v0.22: stagger spawn position per peer die (spread 40px × 40px grid)
        // so the game's `x=612;y=612;motion_set(...)` block at Step_0:407 (run
        // ONCE per die via roll_setup guard) doesn't pin all peer dice to the
        // exact same starting coordinate. Without this they spawn concentric
        // and frequently end the roll stacked on top of each other.
        var _stagger_x = ((i mod 5) - 2) * 40;
        var _stagger_y = (((i + 2) mod 5) - 2) * 40;
        var _inst = instance_create_layer(_stagger_x, _stagger_y, _layer, obj_dice, {
            die: _die,
            deck_num: 500 + i
        });
        random_set_seed(_seed);
        if (_inst == noone) continue;
        _inst.coop_peer = true;
        // BUG C fix: owner is carried by the ROLL_COMMIT top-level field
        // (not per-entry). Derive from my role: the peer is whoever I'm not.
        _inst.coop_peer_owner = _peer_owner;
        _inst.selected = true;
        _inst.intro = true;
        _inst.intro_anim = 0;
        _inst.setup = true;
        _inst.pos_setup = true;
        _inst.alpha = 1;
        _inst.spawn_warp = 0;
        _inst.spawn_warp_speed = 0;
        // v0.20 #3: mark peer die with the game's built-in `exhaust` flag.
        // During state_rolled scoring, obj_dice.Step_0:654 sees exhaust=true,
        // invokes deffect_exhaust(self) (explosion + particle + snd_exhaust
        // + "exhausted" text) and skips the array_push to discards (line 646
        // guard `(!exhaust || check_for_enchant(die, "eternal"))`). Net effect:
        // peer dice vanish with the native game animation and NEVER end up
        // in my global.deck via the discards→replenish_deck path.
        _inst.exhaust = true;
        _count++;
        // Game's Step will pick up this instance in state_rolling, run
        // rolling_setup, push into selected_dice, motion_set → all native.
    }
    coop_log("injected " + string(_count) + " peer dice (requested "
        + string(array_length(_list)) + ")");
    global.coop.peer_committed_dice = [];
}

// Look up a die template by its ide string.
// v0.12: also search global.dicelist_hidden — that array holds "secret"/unlockable
// templates like matrioshka2, paperpaper, etc. Earlier versions missed these and
// logged "unknown die ide" whenever a peer rolled one.
function coop_find_die_template_by_ide(_ide)
{
    if (variable_global_exists("dicelist"))
    {
        for (var i = 0; i < array_length(global.dicelist); i++)
        {
            if (global.dicelist[i].ide == _ide)
                return global.dicelist[i];
        }
    }
    if (variable_global_exists("dicelist_hidden"))
    {
        for (var i = 0; i < array_length(global.dicelist_hidden); i++)
        {
            if (global.dicelist_hidden[i].ide == _ide)
                return global.dicelist_hidden[i];
        }
    }
    return undefined;
}

// v0.17 legacy stub.
function coop_send_clear_roll() {}

// v0.8 — per-barrier signalling. id is one of: "roll", "shop".
// v0.17: "roll" barrier now carries the ROLL_COMMIT payload (selected dice).
// When both sides have committed, coop_barrier_passed("roll") returns true
// and the caller (obj_rollbutton) first calls coop_inject_peer_dice() then
// fire_roll(). Other barriers (shop) still use BARRIER_READY.
function coop_request_barrier(_id)
{
    if (global.coop.state != "in_run" || !global.coop.is_coop_run)
        return true; // no gate in solo — let caller proceed immediately
    switch (_id)
    {
        case "roll":
            global.coop.my_roll_queued = true;
            // ROLL_COMMIT implicitly signals "ready for roll" AND carries the
            // list of dice the peer should inject.
            coop_send_roll_commit();
            break;
        case "shop":
            global.coop.my_shop_queued = true;
            coop_send({ type: "BARRIER_READY", id: _id });
            break;
    }
    return false; // peer must also be ready for action to proceed
}

// Called every frame by a gated button: returns true if BOTH sides are ready.
// Clears flags when returning true so the action fires once.
// v0.17: for "roll", injects peer's dice into our hand immediately before
// returning true, so fire_roll() operates on the combined hand.
function coop_barrier_passed(_id)
{
    if (global.coop.state != "in_run" || !global.coop.is_coop_run)
        return true;
    switch (_id)
    {
        case "roll":
            if (global.coop.my_roll_queued && global.coop.peer_roll_committed)
            {
                coop_inject_peer_dice();
                // v0.18: shared RNG seed before state_rolling. Game's own
                // state_rolled block calls irandom_range for roll_ang + roll_power
                // on each selected die. Seeding from obj_runctrl.seed + per-roll
                // counter keeps both clients' RNG streams aligned so the tumble
                // result and any irandom-driven ring effects match.
                if (instance_exists(obj_runctrl))
                {
                    global.coop.roll_counter += 1;
                    random_set_seed(obj_runctrl.seed + global.coop.roll_counter * 7919);
                }
                global.coop.my_roll_queued = false;
                global.coop.peer_roll_committed = false;
                return true;
            }
            return false;
        case "shop":
            if (global.coop.my_shop_queued && global.coop.peer_shop_ready_gate)
            {
                global.coop.my_shop_queued = false;
                global.coop.peer_shop_ready_gate = false;
                return true;
            }
            return false;
    }
    return true;
}

function coop_my_barrier_pending(_id)
{
    if (!global.coop.is_coop_run) return false;
    switch (_id)
    {
        case "roll": return global.coop.my_roll_queued;
        case "shop": return global.coop.my_shop_queued;
    }
    return false;
}

// Legacy shims for v0.7 that are no longer used, kept to avoid compile errors if
// referenced elsewhere. The pre-v0.8 hooks on obj_diceroll were on the wrong object.
function coop_send_ready_roll() {}
function coop_send_roll_used() {}

// v0.17 legacy stubs — peer dice are now spawned by coop_inject_peer_dice()
// from a ROLL_COMMIT message, not one-by-one ROLL_DIE messages.
function coop_receive_roll_die(_msg) {}
function coop_receive_clear_roll() {}

// v0.18 legacy stub — DELTA handler removed (host authority replaced it).
function coop_host_apply_delta(_msg) {}

// Look up a character struct in global.charlist by its "ide" tag.
// Returns undefined if not found.
function coop_find_char_by_ide(_ide)
{
    for (var i = 0; i < array_length(global.charlist); i++)
    {
        if (global.charlist[i].ide == _ide)
            return global.charlist[i];
    }
    return undefined;
}

// Kick off the standard solo-run start flow with the given character + seed.
// Mirrors the sequence in obj_main_menu Step when state == "play".
// Called on both clients simultaneously when the host emits RUN_START.
function coop_start_run(_char, _difficulty, _seed)
{
    if (_char == undefined)
    {
        coop_log("start_run ABORT: char is undefined");
        return;
    }
    coop_log("start_run: char=" + _char.ide + " difficulty=" + string(_difficulty) + " seed=" + string(_seed));
    obj_runctrl.char = _char;
    obj_runctrl.difficulty = _difficulty;
    // v0.5: store the host-supplied seed on obj_runctrl. The patched run_setup block
    // in obj_runctrl.Step (see patch.csx) will call random_set_seed() with this value
    // instead of the default randomize(), so both clients generate identical maps,
    // bosses, and shop content from the same RNG stream.
    obj_runctrl.seed = _seed;
    global.coop.run_seed = _seed;
    obj_runctrl.loading = false;
    obj_runctrl.run_setup = false;
    global.coop.state = "in_run";

    // v0.3: mark this as a coop run and apply x2 targets.
    global.coop.is_coop_run = true;
    coop_apply_coop_targets();
    // v0.11: reset game-over guard for the new run (previous run's flag may
    // still be set if user started another coop session without fully resetting).
    global.coop.gameover_broadcasted = false;
    global.coop.pending_gameover = false;
    // v0.18: force-init total_score/global.score so both clients start from
    // identical baselines. Reset the host-authority trackers to undefined —
    // first broadcast fires and establishes new baseline. Also reset the
    // roll_counter so RNG seed derivation starts from 0 each run.
    if (instance_exists(obj_runctrl))
        obj_runctrl.total_score = BigZero();
    global.score = BigZero();
    global.coop.last_sent_score = undefined;
    global.coop.last_sent_pips = undefined;
    global.coop.last_sent_cubes = -1;
    global.coop.last_sent_boss_hp = -1;
    global.coop.last_spend_cubes = undefined;
    global.coop.last_spend_score = undefined;
    global.coop.last_spend_pips = undefined;
    global.coop.my_scoring = false;
    global.coop.peer_scoring = false;
    global.coop.peer_scoring_since = 0;
    global.coop.my_board_pick = undefined;
    global.coop.peer_board_pick = undefined;
    global.coop.board_applied = false;
    global.coop.last_seen_score = undefined;
    global.coop.last_seen_pips = undefined;
    global.coop.roll_counter = 0;
    // v0.33: map-vote init for new run.
    global.coop.my_map_vote = "";
    global.coop.peer_map_vote = "";
    global.coop.map_vote_resolved = false;
    global.coop.map_vote_winner = "";

    var _inst = instance_create_layer(0, 0, "transition", obj_transition);
    _inst.func = function()
    {
        coop_log("start_run: transition func running; creating obj_deckctrl");
        if (instance_exists(obj_dice))
            instance_destroy(obj_dice);
        instance_create_layer(0, 0, "controllers", obj_deckctrl);
        choose_music();
    };
}
