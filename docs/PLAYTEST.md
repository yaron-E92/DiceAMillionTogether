# Windows / Steam manual playtest

CI checks the actual .NET relay over TCP and the C# effect engine. It cannot patch or play a licensed Steam game. The following must be completed by two Windows clients before considering the co-op mod validated.

1. Both players have matching official Steam Dice A Million versions, UndertaleModTool CLI, and Git Bash. Host has .NET 10 SDK.
2. Start `dotnet run --project src/DiceAMillionTogether.Relay` on a LAN/VPN-accessible IP using `DMT_BIND`. Confirm TCP 7777 connectivity from the other PC (configure firewall/private VPN).
3. Run `./mod/build.sh coop` on both PCs with correct `GAME_DIR` and `RELAY_HOST`, and verify `dice_amillion_together.ini`.
4. Open Steam. Launch the modded `run_coop.bat` on both computers.

- [ ] Both games launch with correct patch and show **CO-OP**.
- [ ] First client creates lobby; second joins by code (and optionally lobby browsing).
- [ ] Both players select different characters and mark READY.
- [ ] Both clients enter same world/map after run-start.
- [ ] Each player selects their own dice; peer dice are visible and cannot be selected locally.
- [ ] Roll and scoring barriers advance only after both commit; totals and effects converge.
- [ ] Shops and maps resolve without divergent state.
- [ ] Win/loss and restart behave correctly on both.
- [ ] Unmodified Steam game remains intact.

**Not yet available in-game:** cross-hand items, Generous Die, Steam friends/lobbies. These C# game-rule types are tested in isolation but are not patched into item acquisition or GameMaker scoring yet.

For errors collect both clients' `coop_mod.log`, game version and mod commit SHA (redact addresses/tokens). The relay intentionally does not persist untrusted LOG payloads.
