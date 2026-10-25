// v0.23: GUI-layer overlay (Draw Event 64 = Draw GUI) that shows a pulsing
// yellow "WAITING FOR PEER..." banner when the local client has finished
// scoring but the peer is still in state_rolled. Also shown while we're
// blocked on a shared board-map pick. Rendered in GUI coords so it always
// sits on top of the game view regardless of room.
if (!variable_global_exists("coop") || global.coop == undefined) exit;
if (!global.coop.is_coop_run) exit;

var _show = false;
var _txt  = "";

// 1. Round-end: I'm done scoring, peer still in state_rolled.
if (!global.coop.my_scoring && global.coop.peer_scoring)
{
    _show = true;
    _txt  = "WAITING FOR PEER TO FINISH SCORING";
}

// 2. Board pick: I've clicked, peer hasn't (or vice-versa).
if (global.coop.my_board_pick != undefined && global.coop.peer_board_pick == undefined)
{
    _show = true;
    _txt  = "WAITING FOR PEER TO PICK A BRANCH";
}
else if (global.coop.my_board_pick == undefined && global.coop.peer_board_pick != undefined)
{
    _show = true;
    _txt  = "PEER PICKED — CLICK A BRANCH";
}

// 3. v0.33: map roll/skip vote. My choice is cast, peer hasn't voted yet.
if (global.coop.my_map_vote != "" && global.coop.peer_map_vote == "")
{
    _show = true;
    var _my_label = (global.coop.my_map_vote == "roll") ? "ROLL" : "SKIP";
    _txt  = "YOU VOTED " + _my_label + " — WAITING FOR PEER";
}
else if (global.coop.my_map_vote == "" && global.coop.peer_map_vote != "")
{
    _show = true;
    var _peer_label = (global.coop.peer_map_vote == "roll") ? "ROLL" : "SKIP";
    _txt  = "PEER VOTED " + _peer_label + " — YOUR CHOICE";
}

if (_show)
{
    set_main_font();
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    var _tick = floor(current_time / 350) mod 3;
    var _dots = (_tick == 0) ? "." : ((_tick == 1) ? ".." : "...");
    var _scale_bump = sin(current_time / 200) * 0.15;
    // v0.25: compact top-strip overlay so ring-hover descriptions at the
    // center of the screen (y ~340-500) aren't covered. Previous version's
    // y=340-428 strip overlapped ring description boxes in the shop.
    draw_set_color(c_black);
    draw_set_alpha(0.75);
    draw_rectangle(0, 0, 1366, 50, false);
    draw_set_alpha(1.0);
    draw_text_adv_s(683, 26, "[spr_text][fa_middle][c_yellow]" + _txt + _dots,
                    0, 0, 1.6 + _scale_bump, 1, 2000, 1);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    // v0.31: restore draw_color to white. Without this, the c_black we set
    // for the background persists into the next frame's Draw_0 events.
    // draw_text_scribble_ext uses `blend(draw_get_color(), ...)` as the
    // starting color — so reward-card descriptions (scribble-rendered)
    // end up drawn black-on-black and appear missing. Title text uses
    // draw_text_adv_s with an explicit color arg so it wasn't affected,
    // which matches the exact symptom the user reported.
    draw_set_color(c_white);
}
