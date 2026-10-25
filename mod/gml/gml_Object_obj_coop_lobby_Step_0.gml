alpha = min(alpha + 0.08, 1);

// Keep the main-menu colliders suppressed the whole time this panel is open.
// obj_coop_charselect sets ui_busy=false when it picks and destroys itself, and
// if we don't re-assert it here, the next click on our READY button also falls
// through to the main_menu_collider at y≈464 (pos 0/1: "Новая игра"/"Продолжить"),
// which then launches a solo run on top of the coop flow.
global.ui_busy = true;

// Net state → high-level mode_view transitions.
if (global.coop.state == "paired_wait" && mode_view != "paired_wait" && mode_view != "paired")
    mode_view = "paired_wait";
if (global.coop.state == "paired" && mode_view != "paired")
    mode_view = "paired";
if (global.coop.state == "in_run")
{
    coop_log("lobby: state in_run → closing panel");
    global.ui_busy = false;
    instance_destroy();
    exit;
}
if (global.coop.state == "idle" && (mode_view == "paired_wait" || mode_view == "paired" || mode_view == "create_wait"))
    mode_view = "choose";

// If the character-select modal is open, don't process clicks behind it.
if (instance_exists(obj_coop_charselect))
    exit;

var _cx = x;
var _cy = y;

// Close (X).
var _close_x1 = _cx + 220;
var _close_y1 = _cy - 150;
if (point_in_rectangle(obj_mouse.x, obj_mouse.y, _close_x1, _close_y1, _close_x1 + 30, _close_y1 + 30))
{
    button_hover = 100;
    if (global.mouse_left)
    {
        global.ui_busy = false;
        instance_destroy();
        exit;
    }
}

if (mode_view == "choose")
{
    button_hover = -1;
    var _b_w = 180; var _b_h = 50; var _b_y = _cy + 20;
    var _create_x = _cx - 100; var _join_x = _cx + 100;
    if (point_in_rectangle(obj_mouse.x, obj_mouse.y, _create_x - (_b_w / 2), _b_y - (_b_h / 2), _create_x + (_b_w / 2), _b_y + (_b_h / 2)))
    {
        button_hover = 0;
        if (global.mouse_left)
        {
            coop_log("UI: CREATE clicked");
            audio_play_sound(snd_dice_select, 10, false);
            coop_connect("create", "");
            mode_view = "create_wait";
        }
    }
    else if (point_in_rectangle(obj_mouse.x, obj_mouse.y, _join_x - (_b_w / 2), _b_y - (_b_h / 2), _join_x + (_b_w / 2), _b_y + (_b_h / 2)))
    {
        button_hover = 1;
        if (global.mouse_left)
        {
            coop_log("UI: JOIN clicked → browse");
            audio_play_sound(snd_dice_select, 10, false);
            mode_view = "browse";
            lobby_refresh_timer = 0; // immediate request
            coop_connect("list", "");
        }
    }
}
else if (mode_view == "browse")
{
    // v0.27: browse mode — refresh lobby list every 1.5 seconds and show
    // open rooms as clickable rows. Click a row → send JOIN to relay on
    // this same socket; relay promotes us to guest and the usual ROOM →
    // paired flow takes over.
    if (keyboard_check_pressed(vk_escape))
    {
        coop_log("UI: browse cancelled");
        coop_disconnect();
        mode_view = "choose";
    }
    if (global.coop.state == "browsing")
    {
        lobby_refresh_timer -= 1;
        if (lobby_refresh_timer <= 0)
        {
            lobby_refresh_timer = 90; // 1.5s @ 60fps
            coop_request_lobbies();
        }
        // Click handling over rendered list.
        var _list = global.coop.lobby_list;
        var _row_y = _cy - 80;
        var _row_h = 28;
        var _row_w = 340;
        var _row_x = _cx - (_row_w / 2);
        lobby_row_hover = -1;
        for (var i = 0; i < array_length(_list); i++)
        {
            if (i >= 7) break; // visible rows cap
            var _ry = _row_y + i * _row_h;
            if (point_in_rectangle(obj_mouse.x, obj_mouse.y, _row_x, _ry, _row_x + _row_w, _ry + _row_h - 4))
            {
                lobby_row_hover = i;
                if (global.mouse_left)
                {
                    audio_play_sound(snd_dice_select, 10, false);
                    coop_join_from_browse(_list[i]);
                    mode_view = "create_wait";
                }
            }
        }
    }
}
else if (mode_view == "paired")
{
    button_hover = -1;
    // Big "pick character" button (or "change" if already picked).
    var _pick_w = 260;
    var _pick_h = 50;
    var _pick_y = _cy - 20;
    if (!global.coop.my_ready
        && point_in_rectangle(obj_mouse.x, obj_mouse.y, _cx - (_pick_w / 2), _pick_y - (_pick_h / 2), _cx + (_pick_w / 2), _pick_y + (_pick_h / 2)))
    {
        button_hover = 20;
        if (global.mouse_left)
        {
            coop_log("UI: open charselect");
            audio_play_sound(snd_dice_select, 10, false);
            instance_create_layer(0, 0, "collection", obj_coop_charselect);
        }
    }

    // READY button.
    var _ready_w = 220;
    var _ready_h = 48;
    var _ready_y = _cy + 80;
    if (point_in_rectangle(obj_mouse.x, obj_mouse.y, _cx - (_ready_w / 2), _ready_y - (_ready_h / 2), _cx + (_ready_w / 2), _ready_y + (_ready_h / 2)))
    {
        button_hover = 12;
        if (global.mouse_left && global.coop.my_char_ide != "")
        {
            audio_play_sound(snd_dice_select, 10, false);
            coop_send_ready(!global.coop.my_ready);
        }
    }

    // Host: both ready → RUN_START after a tick.
    if (global.coop.role == "host" && global.coop.my_ready && global.coop.peer_ready)
    {
        if (start_emit_timer == 0)
            start_emit_timer = 30;
        start_emit_timer -= 1;
        if (start_emit_timer <= 0)
        {
            var _seed = irandom_range(1, 1000000000);
            var _host_ide = global.coop.my_char_ide;
            var _guest_ide = global.coop.peer_char_ide;
            coop_log("host: both ready; emitting RUN_START seed=" + string(_seed) + " host=" + _host_ide + " guest=" + _guest_ide);
            coop_send_run_start(_seed, _host_ide, _guest_ide, 0);
            var _host_char = coop_find_char_by_ide(_host_ide);
            coop_start_run(_host_char, 0, _seed);
        }
    }
    else
    {
        start_emit_timer = 0;
    }
}
