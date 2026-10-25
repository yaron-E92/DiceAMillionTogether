// Full-screen-ish modal for picking a character in a coop run.
// Opened by obj_coop_lobby; on pick, writes global.coop.my_char_ide and sends CHAR_PICK,
// then destroys itself. obj_coop_lobby reads global.coop.my_char_ide afterward.

global.ui_busy = true;
alpha = 0;
hover_idx = -1;                 // index into global.charlist, or -1

coop_log("charselect: opened (n=" + string(array_length(global.charlist)) + ")");

// Layout: 5 columns x 2 rows, cell ~180x180, centered in room (room is 1366x768).
grid_cols = 5;
grid_rows = 2;
cell_w = 180;
cell_h = 180;
grid_x = (1366 / 2) - ((grid_cols * cell_w) / 2);
grid_y = 200;
