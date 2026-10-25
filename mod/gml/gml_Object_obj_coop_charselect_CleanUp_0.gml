// v0.24 H3 fix: REMOVED `global.ui_busy = false;`
//
// The Step handler's comment warned against this but CleanUp was still
// clearing it. CleanUp runs at end-of-frame on instance_destroy; depending
// on Step ordering the next frame, obj_main_menu_collider could see
// global.ui_busy=false before obj_coop_lobby.Step re-asserts it — leaving
// a one-frame gap where the same click that closed charselect propagates
// through to the "New game"/"Continue" button underneath, launching a
// solo run.
//
// The coop lobby re-asserts ui_busy=true every Step. When returning to
// the main menu proper (no lobby, no charselect), the main_menu's own
// Step naturally clears ui_busy. Nothing here.
