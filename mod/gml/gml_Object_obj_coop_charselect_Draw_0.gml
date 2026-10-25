// Dim backdrop covering the room, then a title, then the grid.
draw_set_alpha(0.85 * alpha);
draw_set_color(c_black);
draw_rectangle(0, 0, 1366, 768, false);

draw_set_alpha(alpha);
draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_set_color(c_white);
draw_text(1366 / 2, 100, "CHOOSE YOUR CHARACTER");
draw_set_color(c_ltgray);
draw_text(1366 / 2, 140, "click a tile — Esc or right-click to cancel");

var _n = min(array_length(global.charlist), grid_cols * grid_rows);
for (var i = 0; i < _n; i++)
{
    var _col = i mod grid_cols;
    var _row = i div grid_cols;
    var _x = grid_x + (_col * cell_w);
    var _y = grid_y + (_row * cell_h);
    var _cx = _x + (cell_w / 2);
    var _cy = _y + (cell_h / 2);
    var _ch = global.charlist[i];
    var _selected = (_ch.ide == global.coop.my_char_ide);
    var _peer = (_ch.ide == global.coop.peer_char_ide);
    var _hovered = (hover_idx == i);

    // Tile background.
    if (_selected)
        draw_set_color(merge_color(c_lime, c_dkgray, 0.6));
    else if (_hovered)
        draw_set_color(merge_color(c_purple, c_white, 0.35));
    else
        draw_set_color(4210752);
    draw_set_alpha(alpha);
    draw_roundrect(_x + 8, _y + 8, _x + cell_w - 8, _y + cell_h - 8, false);

    // Outline (brighter if peer picked this).
    if (_peer)
        draw_set_color(c_aqua);
    else
        draw_set_color(merge_color(c_purple, c_white, 0.2));
    draw_roundrect(_x + 8, _y + 8, _x + cell_w - 8, _y + cell_h - 8, true);

    // Sprite + name.
    if (variable_struct_exists(_ch, "sprite_sel"))
        draw_sprite(_ch.sprite_sel, 0, _cx, _cy - 10);
    draw_set_color(c_white);
    draw_text(_cx, _y + cell_h - 30, _ch.ide);

    // Small "peer" marker badge if the peer has this one.
    if (_peer)
    {
        draw_set_color(c_aqua);
        draw_text(_x + 25, _y + 25, "P2");
    }
    if (_selected)
    {
        draw_set_color(c_lime);
        draw_text(_x + cell_w - 25, _y + 25, "YOU");
    }
}

draw_set_alpha(1);
draw_set_halign(fa_left);
draw_set_valign(fa_top);
