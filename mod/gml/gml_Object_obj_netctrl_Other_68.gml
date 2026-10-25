// Async Networking event. async_load is a ds_map in this game's GMS2 runtime.

var _type = ds_map_find_value(async_load, "type");
var _sock = ds_map_find_value(async_load, "id");

if (_sock != global.coop.socket)
    exit;

switch (_type)
{
    case network_type_non_blocking_connect:
    {
        var _succ = ds_map_find_value(async_load, "succeeded");
        if (_succ)
        {
            coop_log("tcp connected; sending HELLO");
            coop_on_connected();
        }
        else
        {
            global.coop.last_error = "connect failed";
            global.coop.state = "idle";
            coop_log("tcp connect FAILED");
        }
        break;
    }
    case network_type_data:
    {
        var _rx = ds_map_find_value(async_load, "buffer");
        var _sz = ds_map_find_value(async_load, "size");
        coop_log("rx bytes=" + string(_sz));
        coop_rx_append(_rx, _sz);
        while (true)
        {
            var _msg = coop_rx_try_pop();
            if (_msg == undefined)
                break;
            array_push(global.coop.inbox, _msg);
            coop_log_json("rx msg", _msg);
            var _t = variable_struct_get(_msg, "type");
            if (_t == "ROOM")
            {
                global.coop.role = _msg.role;
                global.coop.code = _msg.code;
                // Guest receives ROOM only when a host was already waiting → paired immediately.
                // Host receives ROOM on create and must still wait for PEER_JOINED.
                if (_msg.role == "guest")
                {
                    global.coop.peer_present = true;
                    global.coop.state = "paired";
                    coop_log("state -> paired (role=guest, host was waiting)");
                }
                else
                {
                    global.coop.state = "paired_wait";
                    coop_log("state -> paired_wait (role=host, code=" + global.coop.code + ")");
                }
            }
            else if (_t == "PEER_JOINED")
            {
                global.coop.peer_present = true;
                global.coop.state = "paired";
                coop_log("state -> paired (PEER_JOINED)");
            }
            else if (_t == "PEER_LEFT")
            {
                global.coop.peer_present = false;
                global.coop.state = "paired_wait";
                coop_log("state -> paired_wait (PEER_LEFT)");
            }
            else if (_t == "ERROR")
            {
                global.coop.last_error = _msg.msg;
                coop_log("relay ERROR: " + string(_msg.msg));
            }
            else if (_t == "CHAR_PICK")
            {
                global.coop.peer_char_ide = _msg.ide;
                coop_log("peer picked char: " + _msg.ide);
            }
            else if (_t == "READY")
            {
                global.coop.peer_ready = _msg.state;
                coop_log("peer ready=" + string(_msg.state));
            }
            else if (_t == "RUN_START")
            {
                coop_log("RUN_START received, deferring to next Step");
                if (global.coop.role == "guest")
                {
                    global.coop.pending_run = {
                        char_ide: _msg.guest_ide,
                        difficulty: _msg.difficulty,
                        seed: _msg.seed
                    };
                }
                else
                {
                    coop_log("RUN_START ignored (host already started locally)");
                }
            }
            else if (_t == "SCORE_SET")
            {
                // v0.18 — host-authoritative absolute-value score sync.
                coop_guest_apply_score_set(_msg);
            }
            else if (_t == "SPEND")
            {
                // v0.22 — peer spent cubes/score/pips (shop or donation).
                coop_apply_spend(_msg);
            }
            else if (_t == "STATE_SYNC")
            {
                // v0.23 — peer flipped scoring / not-scoring. Used for the
                // round-end WAITING overlay rendered by obj_netctrl.Draw_64.
                if (variable_struct_exists(_msg, "scoring"))
                {
                    var _was_scoring = global.coop.peer_scoring;
                    global.coop.peer_scoring = _msg.scoring;
                    // v0.26: timestamp when peer ENTERS scoring (for timeout).
                    // Reset when they leave so the next round's check starts clean.
                    if (_msg.scoring && !_was_scoring)
                        global.coop.peer_scoring_since = current_time;
                    else if (!_msg.scoring)
                        global.coop.peer_scoring_since = 0;
                }
            }
            else if (_t == "BOARD_PICK")
            {
                // v0.23 — peer clicked a map branch. Store; will be applied
                // once both sides have picked (see obj_netctrl.Step_0).
                if (variable_struct_exists(_msg, "pos")
                    && variable_struct_exists(_msg, "branch"))
                {
                    global.coop.peer_board_pick = { pos: _msg.pos, branch: _msg.branch };
                    global.coop.board_applied = false;
                }
            }
            else if (_t == "MAP_VOTE")
            {
                // v0.33 — peer voted roll or skip on the obj_map screen.
                // Try to resolve now (in case local already voted).
                if (variable_struct_exists(_msg, "vote"))
                {
                    global.coop.peer_map_vote = _msg.vote;
                    coop_log("map vote rx: peer=" + _msg.vote);
                    coop_map_vote_try_resolve();
                }
            }
            else if (_t == "STATE" || _t == "DELTA")
            {
                // v0.18 legacy — silently drop frames from pre-v0.18 peers.
            }
            else if (_t == "ROLL_COMMIT")
            {
                // v0.17 — peer sent list of their selected dice + signal ready
                // for the "roll" barrier. Actual spawn (coop_inject_peer_dice)
                // is deferred to coop_barrier_passed("roll") so it runs on the
                // main thread, not inside the async event.
                coop_receive_roll_commit(_msg);
            }
            else if (_t == "ROLL_DIE" || _t == "CLEAR_ROLL")
            {
                // v0.17 legacy — no-op. Old mod versions on peer side may still
                // emit these during the handshake transition. Silently drop.
            }
            else if (_t == "GAME_OVER")
            {
                // Peer's run ended (win or loss). Defer instance creation
                // to Step to avoid async-event spawn hazards. v0.24 H1:
                // capture winmode so a host WIN doesn't render as guest LOSS.
                global.coop.pending_gameover = true;
                global.coop.pending_gameover_winmode = variable_struct_exists(_msg, "winmode") && _msg.winmode;
            }
            else if (_t == "LOBBIES")
            {
                // v0.27 — relay's response to LIST_REQUEST during browse mode.
                var _codes = variable_struct_exists(_msg, "codes") ? _msg.codes : [];
                global.coop.lobby_list = _codes;
            }
            else if (_t == "ROLLS")
            {
                // v0.13 — peer's current obj_deckctrl.rolls. Step will average
                // with ours and apply + rebroadcast (converges in 1 round trip).
                var _pr = variable_struct_exists(_msg, "rolls") ? _msg.rolls : undefined;
                if (_pr != undefined)
                    global.coop.pending_peer_rolls = _pr;
            }
            else if (_t == "BARRIER_READY")
            {
                // v0.8 — peer has clicked and is waiting for us. Set the gate flag so
                // our button's Step will see both signals and fire the action.
                var _id = variable_struct_exists(_msg, "id") ? _msg.id : "";
                if (_id == "roll") global.coop.peer_roll_ready_gate = true;
                else if (_id == "shop") global.coop.peer_shop_ready_gate = true;
                else coop_log("unknown barrier id: " + string(_id));
            }
            else
            {
                coop_log("unknown msg type: " + string(_t));
            }
        }
        break;
    }
    case network_type_disconnect:
    {
        coop_log("socket closed by peer/relay");
        coop_disconnect();
        break;
    }
    default:
    {
        coop_log("async net: unhandled type=" + string(_type));
    }
}
