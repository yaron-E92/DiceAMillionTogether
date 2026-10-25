// Panel background.
var _cx = x;
var _cy = y;
var _px1 = _cx - 260;
var _py1 = _cy - 170;
var _px2 = _cx + 260;
var _py2 = _cy + 170;
draw_set_alpha(0.92 * alpha);
draw_set_color(2434341);
draw_roundrect(_px1, _py1, _px2, _py2, false);
draw_set_alpha(alpha);
draw_set_color(merge_color(c_purple, c_white, 0.3));
draw_roundrect(_px1, _py1, _px2, _py2, true);

draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_set_color(c_white);
draw_text(_cx, _py1 + 30, "CO-OP");

// Close X.
var _close_x1 = _cx + 220;
var _close_y1 = _cy - 150;
draw_set_color(button_hover == 100 ? c_red : c_ltgray);
draw_text(_close_x1 + 15, _close_y1 + 15, "X");

// Status line.
var _status;
switch (global.coop.state)
{
    case "idle":         _status = (mode_view == "browse") ? "connecting to lobby list..." : "offline"; break;
    case "connecting":   _status = "connecting to relay..."; break;
    case "connected":    _status = "handshaking..."; break;
    case "browsing":     _status = "browsing open lobbies (click one, or Esc)"; break;
    case "paired_wait":  _status = (global.coop.role == "host") ? ("room " + global.coop.code + ", waiting for peer") : ("joined room " + global.coop.code); break;
    case "paired":       _status = "pick character, then READY"; break;
    case "in_run":       _status = "starting run..."; break;
    default:             _status = global.coop.state;
}
if (global.coop.last_error != "")
    _status = "error: " + global.coop.last_error;
draw_set_color(c_white);
draw_text(_cx, _py1 + 58, _status);

if (mode_view == "choose")
{
    var _b_w = 180; var _b_h = 50; var _b_y = _cy + 20;
    var _create_x = _cx - 100; var _join_x = _cx + 100;

    draw_set_color(button_hover == 0 ? merge_color(c_purple, c_white, 0.4) : c_gray);
    draw_roundrect(_create_x - (_b_w / 2), _b_y - (_b_h / 2), _create_x + (_b_w / 2), _b_y + (_b_h / 2), false);
    draw_set_color(c_white);
    draw_text(_create_x, _b_y, "CREATE ROOM");

    draw_set_color(button_hover == 1 ? merge_color(c_purple, c_white, 0.4) : c_gray);
    draw_roundrect(_join_x - (_b_w / 2), _b_y - (_b_h / 2), _join_x + (_b_w / 2), _b_y + (_b_h / 2), false);
    draw_set_color(c_white);
    draw_text(_join_x, _b_y, "JOIN ROOM");
}
else if (mode_view == "browse")
{
    // v0.27: open-lobbies list. Each row is a clickable code; hover highlights.
    // Empty list prompts the player to create one themselves (or wait for a host).
    draw_set_color(c_white);
    draw_text(_cx, _cy - 115, "OPEN LOBBIES");
    var _list = global.coop.lobby_list;
    var _row_y = _cy - 80;
    var _row_h = 28;
    var _row_w = 340;
    var _row_x = _cx - (_row_w / 2);
    if (array_length(_list) == 0)
    {
        draw_set_color(c_gray);
        draw_text(_cx, _cy - 40, "no open lobbies — refreshing every ~1.5s");
        draw_text(_cx, _cy - 10, "(or click CREATE on the previous screen)");
    }
    else
    {
        var _shown = min(array_length(_list), 7);
        for (var i = 0; i < _shown; i++)
        {
            var _ry = _row_y + i * _row_h;
            var _col = (lobby_row_hover == i) ? merge_color(c_purple, c_white, 0.4) : merge_color(c_gray, c_black, 0.3);
            draw_set_color(_col);
            draw_roundrect(_row_x, _ry, _row_x + _row_w, _ry + _row_h - 4, false);
            draw_set_color(c_white);
            draw_text(_cx, _ry + 10, _list[i]);
        }
        if (array_length(_list) > 7)
        {
            draw_set_color(c_ltgray);
            draw_text(_cx, _row_y + _shown * _row_h + 8, "+ " + string(array_length(_list) - 7) + " more...");
        }
    }
    draw_set_color(c_ltgray);
    draw_text(_cx, _cy + 125, "(Esc to cancel)");
}
else if (mode_view == "create_wait" || mode_view == "paired_wait")
{
    if (global.coop.role == "host" && global.coop.code != "")
    {
        draw_set_color(c_yellow);
        draw_text(_cx, _cy, "ROOM CODE");
        draw_set_color(c_white);
        draw_text(_cx, _cy + 30, global.coop.code);
        draw_text(_cx, _cy + 70, "give this code to your friend");
    }
}
else if (mode_view == "paired")
{
    // Picks display: "YOU: white | PEER: red" / "(not picked yet)"
    draw_set_color(c_lime);
    draw_text(_cx - 110, _py1 + 100, "YOU");
    draw_set_color(global.coop.my_char_ide == "" ? c_dkgray : c_white);
    draw_text(_cx - 110, _py1 + 125, global.coop.my_char_ide == "" ? "(not picked)" : global.coop.my_char_ide);

    draw_set_color(c_aqua);
    draw_text(_cx + 110, _py1 + 100, "PEER");
    draw_set_color(global.coop.peer_char_ide == "" ? c_dkgray : c_white);
    draw_text(_cx + 110, _py1 + 125, global.coop.peer_char_ide == "" ? "(not picked)" : global.coop.peer_char_ide);

    // PICK CHARACTER button.
    var _pick_w = 260;
    var _pick_h = 50;
    var _pick_y = _cy - 20;
    var _pick_label = global.coop.my_char_ide == "" ? "PICK CHARACTER" : "CHANGE CHARACTER";
    var _pick_col;
    if (global.coop.my_ready)
        _pick_col = c_dkgray;
    else if (button_hover == 20)
        _pick_col = merge_color(c_purple, c_white, 0.4);
    else
        _pick_col = c_gray;
    draw_set_color(_pick_col);
    draw_roundrect(_cx - (_pick_w / 2), _pick_y - (_pick_h / 2), _cx + (_pick_w / 2), _pick_y + (_pick_h / 2), false);
    draw_set_color(c_white);
    draw_text(_cx, _pick_y, _pick_label);

    // READY button.
    var _ready_w = 220;
    var _ready_h = 48;
    var _ready_y = _cy + 80;
    var _ready_col;
    if (global.coop.my_char_ide == "")
        _ready_col = c_dkgray;
    else if (global.coop.my_ready)
        _ready_col = c_lime;
    else if (button_hover == 12)
        _ready_col = merge_color(c_purple, c_white, 0.4);
    else
        _ready_col = c_gray;
    draw_set_color(_ready_col);
    draw_roundrect(_cx - (_ready_w / 2), _ready_y - (_ready_h / 2), _cx + (_ready_w / 2), _ready_y + (_ready_h / 2), false);
    draw_set_color(c_white);
    draw_text(_cx, _ready_y, global.coop.my_ready ? "READY (click to unready)" : "READY");

    draw_set_color(global.coop.peer_ready ? c_lime : c_gray);
    draw_text(_cx, _ready_y + 35, global.coop.peer_ready ? "peer is READY" : "peer not ready");
}

draw_set_halign(fa_left);
draw_set_valign(fa_top);
draw_set_alpha(1);
