// Lobby UI. Lets the user create a new room or join an existing one by code.
// After pairing, shows character pick summary + READY barrier. Character pick itself
// happens in obj_coop_charselect (separate full-screen modal).

global.ui_busy = true;
alpha = 0;

mode_view = "choose";           // choose | create_wait | browse | paired_wait | paired
join_code_input = "";
button_hover = -1;
start_emit_timer = 0;
// v0.27 browse mode state.
lobby_refresh_timer = 0;
lobby_row_hover = -1;

if (!instance_exists(obj_netctrl))
    instance_create_layer(0, 0, "controllers", obj_netctrl);

keyboard_string = "";
