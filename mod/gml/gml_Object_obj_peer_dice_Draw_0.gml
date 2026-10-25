// Render the peer's die with a subtle owner tint per design:
//   host  = neutral (white)
//   guest = light blue
if (sprite_asset < 0 || !sprite_exists(sprite_asset))
    exit;
var _tint = (owner == "guest") ? make_color_rgb(180, 220, 255) : c_white;
draw_sprite_ext(sprite_asset, frame, x, y, 1.4, 1.4, 0, _tint, alpha);
