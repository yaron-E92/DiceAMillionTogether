// Persistent networking controller. Lives across rooms, owns the relay socket.

if (variable_global_exists("coop") && global.coop != undefined && global.coop.owner != undefined && global.coop.owner != id)
{
    coop_log("duplicate netctrl created, destroying self");
    instance_destroy();
    exit;
}

global.coop = {
    owner: id,
    socket: -1,
    state: "idle",              // idle | connecting | connected | paired_wait | paired | in_run
    mode: "",                   // create | join
    code: "",                   // room code
    role: "",                   // host | guest (set after relay replies)
    peer_present: false,
    last_error: "",
    // v0.27: list of open lobby codes shown in "browse" mode.
    lobby_list: [],
    connect_async_id: -1,
    rx_buf: buffer_create(64, buffer_grow, 1),
    rx_filled: 0,
    inbox: [],
    // Lobby phase state.
    my_char_ide: "",
    peer_char_ide: "",
    my_ready: false,
    peer_ready: false,
    run_seed: 0,
    run_start_pending: false,
    // Deferred run-start payload (populated by the async RUN_START handler, consumed
    // in obj_netctrl.Step on the next frame so we're not mutating game state from
    // inside an Async Networking event).
    pending_run: undefined,
    // v0.8.2: deferred ROLL_DIE queue (v0.17: unused, kept for compat).
    pending_roll_dice: [],
    // v0.17: peer's selected dice from latest ROLL_COMMIT, consumed by
    // coop_inject_peer_dice() in the frame both sides pass the roll barrier.
    peer_committed_dice: [],
    peer_roll_committed: false,
    // v0.18: incremented on each roll barrier pass, fed into random_set_seed
    // so both clients draw identical irandom sequences during state_rolled.
    roll_counter: 0,
    // v0.19: track obj_deckctrl.state so we can detect the
    // state_rolled→state_menu transition and fade peer dice out then.
    last_deckctrl_state: undefined,
    // v0.11: game-over sync. When one client triggers obj_gameover, peer gets
    // notified and creates its own obj_gameover so the team loses together.
    gameover_broadcasted: false,
    pending_gameover: false,
    // v0.24 H1: winmode carried in GAME_OVER so win/loss render correctly.
    pending_gameover_winmode: false,
    // v0.3 shared state.
    is_coop_run: false,              // true while we're inside a coop run
    solo_target: undefined,          // snapshot of obj_runctrl.target at first opportunity
    solo_target_n: undefined,        // snapshot of obj_runctrl.target_n
    // Host-side "last broadcast" trackers — kept as BigNumber structs (via variable_clone).
    // We avoid round-tripping through decimal strings for local state because
    // BigFromDecimalString can crash on some edge-case strings (observed
    // "trying to index a variable which is not an array" in BigAddInt32).
    last_sent_score: undefined,
    last_sent_pips: undefined,
    // v0.21: money sync.
    last_sent_cubes: -1,
    // v0.22/v0.23: spend tracker for bilateral SPEND delta broadcast.
    last_spend_cubes: undefined,
    last_spend_score: undefined,
    last_spend_pips: undefined,
    // v0.23: track obj_deckctrl.state transitions for peer-dice cleanup and
    // round-end WAITING overlay. Mirrored via STATE_SYNC msg.
    my_scoring: false,
    peer_scoring: false,
    // v0.26: timestamp (current_time) when peer_scoring first went true.
    // Used by coop_round_end_allowed to time-out a stuck peer so a silent
    // disconnect doesn't soft-lock local game in state_rolled.
    peer_scoring_since: 0,
    // v0.23: board map pick synchronization.
    my_board_pick: undefined,
    peer_board_pick: undefined,
    board_applied: false,
    // Guest-side "last seen" trackers — same reason.
    last_seen_score: undefined,
    last_seen_pips: undefined,
    // v0.6 — final boss HP (host-authoritative). -1 means "no boss active".
    last_sent_boss_hp: -1,
    // v0.7 — per-roll ready barrier. Set true when local obj_diceroll fires, cleared on CleanUp.
    my_roll_ready: false,
    peer_roll_ready: false,
    // v0.13 — rolls consensus (avg of host/guest rolls after hand setup).
    last_sent_rolls: -1,
    pending_peer_rolls: undefined,
    // v0.8 — legacy field kept for back-compat; unused after rolls consensus.
    last_seen_rolls: -1,
    // v0.8 — per-barrier queue state. Each barrier id (roll, shop, reward) tracks
    // whether local player has clicked (my_queued) and whether peer has signalled
    // ready (peer_ready). When both are true, the button's Step fires the deferred
    // action and clears both flags.
    my_roll_queued: false,
    peer_roll_ready_gate: false,
    my_shop_queued: false,
    peer_shop_ready_gate: false,
    // v0.33: obj_map roll/skip vote synchronization. Each player votes
    // once per map screen. When both votes are in, both sides execute the
    // agreed (or random-resolved) action symmetrically. Map instance also
    // carries a consumed_vote flag so the same resolution doesn't re-fire
    // after obj_map is recreated (e.g. after backing out).
    my_map_vote: "",             // "", "roll", "skip"
    peer_map_vote: "",
    map_vote_resolved: false,    // latched true once both votes were seen
    map_vote_winner: "",         // "roll" | "skip" — the resolution
};

// Header separator + build marker at startup makes it easy to find each session in the log.
coop_log("================================================");
coop_log("netctrl created, mod v" + coop_mod_version() + ", proto=" + string(coop_proto_version()));
coop_log("working_directory=" + working_directory);

// Snapshot the solo baseline values of obj_runctrl.target / target_n NOW, while we're
// guaranteed to be in the pristine main-menu state (obj_runctrl has just finished Create
// with solo defaults). Any later snapshot attempt risks capturing a doubled-by-coop state
// if a previous coop run left obj_runctrl.target modified.
coop_ensure_solo_targets_snapshotted();
