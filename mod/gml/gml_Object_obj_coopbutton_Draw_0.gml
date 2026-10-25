// Rounded pill button: dark background, purple outline, white label.
var _w = 140 + (scale * 100);
var _h = 40 + (scale * 20);
draw_set_alpha(0.85);
draw_set_color(4210752);
draw_roundrect(x - (_w / 2), y - (_h / 2), x + (_w / 2), y + (_h / 2), false);
draw_set_alpha(1);
draw_set_color(merge_color(c_purple, c_white, 0.35));
draw_roundrect(x - (_w / 2), y - (_h / 2), x + (_w / 2), y + (_h / 2), true);

draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_set_color(c_white);
draw_text(x, y, "CO-OP");
draw_set_halign(fa_left);
draw_set_valign(fa_top);
