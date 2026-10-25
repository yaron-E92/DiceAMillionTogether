// Visual twin of a peer's die. Not a real obj_dice — doesn't participate in
// scoring/rings. Falls from the top of the screen with a bit of bounce, settles
// on target_x, target_y (the peer's final_x/final_y for that die).
//
// Fields populated by the spawner (coop_receive_roll_die):
//   sprite_asset, frame, target_x, target_y, owner, num

alpha = 0;
life_timer = 0;
max_life = 60 * 30;     // 30s fallback destroy
settled = false;

sprite_asset = -1;
frame = 0;
target_x = x;
target_y = y;
owner = "host";
num = 0;

// Physics state (deterministic starting conditions based on num to avoid any
// random* calls — we don't want to disturb the shared RNG stream).
vspeed_y = 0;
vspeed_x = 0;
