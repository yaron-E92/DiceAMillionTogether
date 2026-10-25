// Multidice co-op patch script.
//
// 1. Imports all *.gml files from ./mod/gml/ as named code entries
//    (AutoCreateAssets handles creating new objects + scripts + events).
// 2. Appends a single instance_create_layer line to obj_main_menu_Create_0
//    so the CO-OP button appears on the main menu.
//
// Run via:
//   UndertaleModCli.exe load <data.win> --scripts patch.csx -o <out.win> -v

using System;
using System.IO;
using System.Linq;
using UndertaleModLib.Compiler;

EnsureDataLoaded();

// Folder holding the mod GML sources. Hardcoded for automation.
string importFolder = Path.GetFullPath(Path.Combine(
    Path.GetDirectoryName(typeof(UndertaleModLib.UndertaleData).Assembly.Location) ?? ".",
    "..", "..", "mod", "gml"));

// Fallback: try cwd-based path if the above doesn't resolve.
if (!Directory.Exists(importFolder))
{
    importFolder = Path.GetFullPath(Path.Combine(Environment.CurrentDirectory, "mod", "gml"));
}
if (!Directory.Exists(importFolder))
{
    importFolder = Path.GetFullPath(@"s:\serv\multidice\mod\gml");
}
if (!Directory.Exists(importFolder))
{
    throw new Exception("mod gml folder not found: " + importFolder);
}

Console.WriteLine($"[patch] importing from {importFolder}");

string[] files = Directory.GetFiles(importFolder, "*.gml");
if (files.Length == 0)
    throw new Exception("no .gml files in " + importFolder);

var group = new CodeImportGroup(Data) { AutoCreateAssets = true };
foreach (string file in files)
{
    string code = File.ReadAllText(file);
    string name = Path.GetFileNameWithoutExtension(file);
    group.QueueReplace(name, code);
    Console.WriteLine($"[patch] queue {name}");
}
group.Import();
Console.WriteLine("[patch] new code entries imported");

// CodeImportGroup auto-creates new UndertaleGameObject entries with default flags
// (Visible defaults to false in GMS2's bytecode, so Draw events get skipped).
// Force the flags we need on each of our objects.
// NOTE: gml_Object_obj_runctrl_Step_0.gml is an OVERWRITE of an existing game script,
// not a new object. CodeImportGroup will replace the entry — if the game updates this
// script, we'd silently lose the upstream changes. If that happens, re-copy the script
// and re-apply the COOP PATCH block at the top.
string[] ourObjects = new[] { "obj_netctrl", "obj_coopbutton", "obj_coop_lobby", "obj_coop_charselect", "obj_peer_dice" };
foreach (string objName in ourObjects)
{
    var obj = Data.GameObjects.ByName(objName);
    if (obj == null)
    {
        Console.WriteLine($"[patch] WARN: object {objName} not found after import");
        continue;
    }
    obj.Visible = true;
    obj.Persistent = objName == "obj_netctrl"; // only netctrl needs to survive room transitions
    obj.Awake = true;
    Console.WriteLine($"[patch] configured {objName}: Visible=true Persistent={obj.Persistent}");
}

// Append the coop button spawn line to obj_main_menu_Create_0.
// Idempotency is handled by build.sh: it always rebuilds from data.win.orig, never from an
// already-patched file. Running this script twice against a patched file would double-append.
const string mainMenuCreate = "gml_Object_obj_main_menu_Create_0";
if (Data.Code.ByName(mainMenuCreate) == null)
    throw new Exception($"code entry not found: {mainMenuCreate}");

var appendGroup = new CodeImportGroup(Data);
appendGroup.QueueAppend(
    mainMenuCreate,
    "\ninstance_create_layer(683, 700, \"controllers\", obj_coopbutton);\n");

// v0.4 hook was on obj_diceroll_dice but that object is only used for CARD effects,
// not the main gameplay roll. Leaving it in for parity with card flows, but the
// v0.8 hooks below on obj_dice (the REAL gameplay dice) are the ones that matter.
appendGroup.QueueAppend(
    "gml_Object_obj_diceroll_dice_Create_0",
    "\ncoop_send_roll_die(die, image_index, num, position_x, position_y);\n");

// v0.17: per-instance coop state on every obj_dice.
// coop_peer=true marks dice injected from peer's ROLL_COMMIT (see
// coop_inject_peer_dice in scr_coop_net). They are REAL obj_dice — game's
// own Step/Draw run unchanged. Only Draw_0 Prepend adds a blue halo to
// visually distinguish them; physics/scoring are 100% native.
appendGroup.QueueAppend(
    "gml_Object_obj_dice_Create_0",
    @"
coop_peer = false;
coop_peer_owner = """";
");

// v0.21 #2b: make peer dice non-interactive. Force selected=true every Step
// so the player's click (which calls de_sel_dice_function setting false)
// is immediately reverted on the next frame. Also clear hovered so scaling
// animations don't highlight a peer die under the cursor as if it were
// clickable. Runs BEFORE the game's Step body via Prepend.
appendGroup.QueuePrepend(
    "gml_Object_obj_dice_Step_0",
    @"
if (coop_peer && setup && !discarded)
{
    selected = true;
    hovered = false;
}
");

// v0.21: classic 8-directional sprite outline for peer dice. Drawn BEFORE
// the main Draw_0 body so the normal-color sprite paints on top of the
// offset copies; only a ~4-pixel blue rim remains visible around the die.
// Much cleaner than scaled halos, which either overlap the main sprite's
// edges (blue bleed into face) or look like a thin shadow.
appendGroup.QueuePrepend(
    "gml_Object_obj_dice_Draw_0",
    @"
if (coop_peer && setup && !discarded)
{
    var _coop_outline_color = make_color_rgb(70, 170, 255);
    var _o = 4; // pixels of outline thickness
    draw_sprite_ext(sprite_index, image_index, x - _o, y,      1, 1, shaker, _coop_outline_color, 1.0);
    draw_sprite_ext(sprite_index, image_index, x + _o, y,      1, 1, shaker, _coop_outline_color, 1.0);
    draw_sprite_ext(sprite_index, image_index, x,      y - _o, 1, 1, shaker, _coop_outline_color, 1.0);
    draw_sprite_ext(sprite_index, image_index, x,      y + _o, 1, 1, shaker, _coop_outline_color, 1.0);
    draw_sprite_ext(sprite_index, image_index, x - _o, y - _o, 1, 1, shaker, _coop_outline_color, 1.0);
    draw_sprite_ext(sprite_index, image_index, x + _o, y - _o, 1, 1, shaker, _coop_outline_color, 1.0);
    draw_sprite_ext(sprite_index, image_index, x - _o, y + _o, 1, 1, shaker, _coop_outline_color, 1.0);
    draw_sprite_ext(sprite_index, image_index, x + _o, y + _o, 1, 1, shaker, _coop_outline_color, 1.0);
}
");

// v0.11/v0.18: back_to_menu resets total_score=0. Without a guard, host
// broadcasts SCORE_SET {score:0} to guest, wiping guest's score the moment
// this client returns to menu. Insert is_coop_run=false + coop_rebase() so
// the reset is absorbed locally and no more score broadcasts are sent.
try
{
    appendGroup.QueueFindReplace(
        "gml_GlobalScript_scr_save_functions",
        "obj_runctrl.total_score = BigZero();",
        "obj_runctrl.total_score = BigZero(); if (variable_global_exists(\"coop\") && global.coop != undefined) { global.coop.is_coop_run = false; coop_rebase(); }");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] scr_save_functions FindReplace failed: " + _fe.Message);
}

// v0.24 C2 fix: pay_f in obj_roundend runs symmetrically on both clients
// (subtract_score(obj_deckctrl.obj) is the round quota payment). Without
// a coop_rebase() right after, both clients detect the decrease, each
// broadcasts SPEND{-quota}, and each applies peer's SPEND → quota paid
// TWICE out of the shared pool. Insert rebase right after the subtract.
try
{
    appendGroup.QueueFindReplace(
        "gml_Object_obj_roundend_Create_0",
        "subtract_score(obj_deckctrl.obj);",
        "subtract_score(obj_deckctrl.obj); coop_rebase();");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] roundend rebase failed: " + _fe.Message);
}

// v0.24 C4 fix: peer dice trigger dice_roll_stat (bumps my unlock stats
// with peer die types) and obj_deckctrl.generated_dice-- (breaks hand size
// logic). Guard both with coop_peer so they only fire for MY dice.
try
{
    appendGroup.QueueFindReplace(
        "gml_Object_obj_dice_Step_0",
        "                    dice_roll_stat(die);",
        "                    if (!coop_peer) dice_roll_stat(die);");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] dice_roll_stat guard failed: " + _fe.Message);
}
try
{
    appendGroup.QueueFindReplace(
        "gml_Object_obj_dice_Step_0",
        "                    obj_deckctrl.generated_dice--;",
        "                    if (!coop_peer) obj_deckctrl.generated_dice--;");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] generated_dice guard failed: " + _fe.Message);
}

// v0.24 H2 fix: peer dice have exhaust=true (injected by coop_inject_peer_dice
// so they vanish with native deffect_exhaust animation). But the exhaust
// scoring block at Step_0:654 also triggers MY fision ring (draws extra
// dice into my deck) and MY fusion ring (adds random cards to my hand).
// These effects are local, use local RNG, and are never echoed — so my
// deck/cards diverge from peer's every time they roll into my rings.
// Replace the `exhaust && !eternal` guard with one that also requires
// !coop_peer so peer dice skip these side-effects.
try
{
    appendGroup.QueueFindReplace(
        "gml_Object_obj_dice_Step_0",
        "if (exhaust && !check_for_enchant(die, \"eternal\"))",
        "if (exhaust && !check_for_enchant(die, \"eternal\") && !coop_peer)");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] exhaust ring guard failed: " + _fe.Message);
}

// v0.25/v0.28: guard round_end() with coop_mark_scoring_done() first so the
// peer sees our scoring=false, then coop_round_end_allowed() checks peer.
// Calling mark_done BEFORE the check is essential: without it, my_scoring
// stays true (state hasn't left state_rolled) and peer's matching barrier
// also stays blocked → mutual deadlock (the v0.25-0.27 "first roll freezes
// game" bug). Solo: both helpers are no-ops so round_end fires normally.
try
{
    appendGroup.QueueFindReplace(
        "gml_Object_obj_deckctrl_Create_0",
        "                round_end();",
        "                coop_mark_scoring_done(); if (coop_round_end_allowed()) round_end();");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] round_end barrier failed: " + _fe.Message);
}

// v0.24 H5 fix: save_run iterates every obj_dice and serialises it into
// _hand_dice. Without guarding coop_peer, peer dice get saved to my local
// save file — next load they re-materialise as real hand dice in my deck.
// Guard the `_check = true` default: if it's a peer die, skip.
try
{
    appendGroup.QueueFindReplace(
        "gml_GlobalScript_scr_save_functions",
        "var _check = true;\n            if (_this.info_mode)",
        "var _check = !(variable_instance_exists(_this, \"coop_peer\") && _this.coop_peer);\n            if (_this.info_mode)");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] save_run peer-dice filter failed: " + _fe.Message);
}

// v0.24 M2 fix: thrown_dice push in obj_deckctrl.Create also iterates all
// obj_dice. Peer dice have .num = -1000-i (synthetic negative) — these
// accumulate in obj_deckctrl.thrown_dice and get saved. Harmless but
// polluting. Guard the push.
try
{
    appendGroup.QueueFindReplace(
        "gml_Object_obj_deckctrl_Create_0",
        "array_push(thrown_dice, selected_dice[i].die.num);",
        "if (!(variable_instance_exists(selected_dice[i], \"coop_peer\") && selected_dice[i].coop_peer)) array_push(thrown_dice, selected_dice[i].die.num);");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] thrown_dice peer filter failed: " + _fe.Message);
}

// v0.18 Bug D + v0.19 full guard: destroy_dice() on a peer die would bump
// destroyed_dice_count, push to obj_dicelist.destroyed_dice, and worst of
// all call add_dice() for pig/ourodie effects — which injects a new die
// straight into MY global.deck (user's "peer dice go into my bag" complaint).
// Early-return from destroy_dice for coop_peer so none of that runs.
// Use a unique marker line at the function's top as FindReplace anchor.
try
{
    appendGroup.QueueFindReplace(
        "gml_Object_obj_dice_Create_0",
        "if (!audio_is_playing(snd_glassbreak))",
        "if (coop_peer) { instance_destroy(); exit; } if (!audio_is_playing(snd_glassbreak))");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] destroy_dice early-return FindReplace failed: " + _fe.Message);
}

// v0.19 crash fix: obj_dice.Step_0:315 iterates `instance_find(obj_dice, i)`
// and reads `.deck_num`. The v0.18 peer-injection crash happened because the
// iterator hit a pending-destroy peer instance (or an obj_dice subclass)
// with no `deck_num` set. Guard the read.
// Also skip coop_peer dice entirely — their deck_num is synthetic (500+i)
// and the decrement logic is meant to close gaps in the local deck order,
// which doesn't apply to peer dice.
try
{
    appendGroup.QueueFindReplace(
        "gml_Object_obj_dice_Step_0",
        "if (_this.deck_num > deck_num)",
        "if (variable_instance_exists(_this, \"deck_num\") && !(variable_instance_exists(_this, \"coop_peer\") && _this.coop_peer) && _this.deck_num > deck_num)");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] deck_num iteration guard FindReplace failed: " + _fe.Message);
}

// v0.20 #1: prevent peer dice from ending up in the player's deck via
// `array_push(obj_deckctrl.discards, die)`. The game's state_rolled block
// pushes every scored die's `die` struct into discards which then
// `replenish_deck()` merges back into global.deck — so peer dice were
// permanently added to my bag after each round. Four occurrences in
// obj_dice.Step_0 (state_menu + three scoring branches) all share the
// exact same line and get patched by a single FindReplace.
try
{
    appendGroup.QueueFindReplace(
        "gml_Object_obj_dice_Step_0",
        "array_push(obj_deckctrl.discards, die);",
        "if (!coop_peer) array_push(obj_deckctrl.discards, die);");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] discards push guard FindReplace failed: " + _fe.Message);
}

// v0.22: 5th discards source — scr_card_functions:128 "discard all" card
// effect iterates with(obj_dice) and pushes each die to discards. Previously
// unguarded, so a card that wipes the table would scoop peer dice into the
// local deck via replenish_deck.
try
{
    appendGroup.QueueFindReplace(
        "gml_GlobalScript_scr_card_functions",
        "array_push(obj_deckctrl.discards, die);",
        "if (!coop_peer) array_push(obj_deckctrl.discards, die);");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] scr_card_functions discards guard failed: " + _fe.Message);
}

// v0.23: intercept the board-map branch click in obj_boardmap.Draw_0.
// coop_board_pick_or_queue returns false in coop mode (queues pick + sends
// BOARD_PICK to peer) so the local click doesn't immediately commit the
// move; obj_netctrl.Step applies the authoritative resolved pick once both
// sides have clicked. `break` exits the inner `for (var o ...)` loop.
try
{
    appendGroup.QueueFindReplace(
        "gml_Object_obj_boardmap_Draw_0",
        "obj_runctrl.board_pos += movedice[o].die.faces[movedice[o].image_index].value;",
        "if (!coop_board_pick_or_queue(movedice[o].die.faces[movedice[o].image_index].value, b)) break; obj_runctrl.board_pos += movedice[o].die.faces[movedice[o].image_index].value;");
}
catch (System.Exception _fe)
{
    Console.WriteLine("[patch] boardmap pick guard failed: " + _fe.Message);
}

// v0.24 H1 fix: defer GAME_OVER broadcast to Step so winmode has been set.
// In Create, winmode is still default false (caller sets it after
// instance_create_layer returns). Previously GAME_OVER always carried
// winmode=false, so a host WIN looked like a LOSS on guest.
appendGroup.QueueAppend(
    "gml_Object_obj_gameover_Create_0",
    @"
coop_gameover_broadcasted_local = false;
");
appendGroup.QueuePrepend(
    "gml_Object_obj_gameover_Step_0",
    @"
if (variable_global_exists(""coop"") && global.coop != undefined && global.coop.is_coop_run
    && !global.coop.gameover_broadcasted && !coop_gameover_broadcasted_local)
{
    coop_gameover_broadcasted_local = true;
    global.coop.gameover_broadcasted = true;
    coop_send({ type: ""GAME_OVER"", winmode: (variable_instance_exists(self, ""winmode"") && winmode) });
}
");

// v0.21 #3 / v0.22: WAITING overlay on the shop 'next round' button with
// pulsing animation matching obj_rollbutton.Draw_0.
appendGroup.QueueAppend(
    "gml_Object_obj_shop_nextround_Draw_0",
    @"
if (setup && variable_global_exists(""coop"")
    && global.coop != undefined
    && global.coop.is_coop_run
    && global.coop.my_shop_queued)
{
    var _tick = floor(current_time / 350) mod 3;
    var _dots = (_tick == 0) ? ""."" : ((_tick == 1) ? "".."" : ""..."");
    var _scale_bump = sin(current_time / 200) * 0.15;
    set_main_font();
    draw_set_halign(fa_center);
    draw_set_valign(fa_top);
    draw_text_adv_s(x, y - 70, ""[spr_text][fa_middle][c_yellow]WAITING"" + _dots, 0, 0, 1.8 + _scale_bump, 1, 999, 1);
}
");

// v0.33: render a vote indicator next to the ROLL / SKIP buttons on obj_map.
// Shows YOU / PEER / BOTH tags depending on who voted which choice.
// Makes the vote state discoverable without forcing the player to look at
// the top-strip overlay. Draw_73 is Draw GUI.
appendGroup.QueueAppend(
    "gml_Object_obj_map_Draw_73",
    @"
if (variable_global_exists(""coop"") && global.coop != undefined && global.coop.is_coop_run)
{
    var _roll_btn_x = b_x + button_offset;
    var _skip_btn_x = b_x + (button_offset * 2);
    var _tag_y = b_y - 80;
    set_main_font();
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    var _mine = global.coop.my_map_vote;
    var _peer = global.coop.peer_map_vote;
    if (_mine == ""roll"" && _peer == ""roll"")
        draw_text_adv_s(_roll_btn_x, _tag_y, ""[fa_middle][c_lime][scale, 1.2]v BOTH"", 0, 0, 1, 1, 999, 1);
    else if (_mine == ""roll"")
        draw_text_adv_s(_roll_btn_x, _tag_y, ""[fa_middle][c_lime][scale, 1.2]v YOU"", 0, 0, 1, 1, 999, 1);
    else if (_peer == ""roll"")
        draw_text_adv_s(_roll_btn_x, _tag_y, ""[fa_middle][c_aqua][scale, 1.2]v PEER"", 0, 0, 1, 1, 999, 1);
    if (canskip)
    {
        if (_mine == ""skip"" && _peer == ""skip"")
            draw_text_adv_s(_skip_btn_x, _tag_y, ""[fa_middle][c_lime][scale, 1.2]v BOTH"", 0, 0, 1, 1, 999, 1);
        else if (_mine == ""skip"")
            draw_text_adv_s(_skip_btn_x, _tag_y, ""[fa_middle][c_lime][scale, 1.2]v YOU"", 0, 0, 1, 1, 999, 1);
        else if (_peer == ""skip"")
            draw_text_adv_s(_skip_btn_x, _tag_y, ""[fa_middle][c_aqua][scale, 1.2]v PEER"", 0, 0, 1, 1, 999, 1);
    }
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}
");

appendGroup.Import();
Console.WriteLine("[patch] obj_main_menu_Create_0 appended with coop button spawn");

Console.WriteLine("[patch] done");
