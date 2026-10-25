# Steam multiplayer acceptance test

Two *different* Windows PCs/accounts, both owning the Steam game, are required. Running this in GitHub Actions proves compilation only; the actual Steamworks configuration is controlled by the publisher.

0. **Run Steam capability probe first**, from the repo root with Steam running: `dotnet run --project src/DiceAMillionTogether.SteamBridge -c Release -- --probe`. Check that lobby creation and SDR socket initialization both succeed. No GameMaker patch necessary for the probe.
1. On each machine, check out `feat/steam-p2p-bridge` and install .NET 10 SDK, Git Bash and UndertaleModTool CLI. Confirm Steam is logged in.
2. Run `GAME_DIR="..." NETWORK_MODE=steam ./mod/build.sh coop` on both clients, then run `~/DiceAMillionCoop/run_coop.bat`.
3. Ensure a **Steam Bridge** console prints a logged-in Steam ID, and game main menu shows **CO-OP**.
4. First client CREATE ROOM: look for six-character code and Steam lobby ID in bridge window. Second JOIN ROOM with that code. Alternatively browse open rooms.
5. If connecting: both select different characters, READY, enter game, commit dice, check totals and round-end barrier, then buy items, choose map path, game-over and reconnect.

## Troubleshooting

- **"STEAM BRIDGE FAILED" immediately**: Steam may be closed, account not licensed, missing native `steam_api64.dll`, or Steam API initialization may conflict with a second process using the game's app ID.
- **Cannot create Steam lobby / AccessDenied**: Steam app 3430340 may not enable Steamworks lobby creation for third-party processes. This cannot be enabled by a mod. An app-owner-approved Steam integration or alternative Steam-enabled test app would be required; do not misrepresent the old private TCP relay as Steam networking.
- **Lobby created but invisible to remote player**: Verify both accounts have the same game app ID, both bridges use matching code/Steam lobby metadata, and whether the app allows public lobby listings.
- **Lobby joined but P2P never connects**: Check Steam overlay/Steam client network connectivity and that host SteamNetworkingSockets accepted only the lobby member.
- **Game tries to connect to external IP**: In the modded game folder, ensure `dice_amillion_together.ini` has `host=127.0.0.1` and `port=7777`.
- **Original game fails to start**: Test the unmodified Steam game directly; then rebuild the mod for the current game version.

The bridge binds only to localhost. It is not a public relay. No game executable or data.win is committed or distributed.

## Gate before merge

- [ ] .NET Steam bridge builds and published win-x64 artifact exists
- [ ] Real Steam SDK initialization on owned game app ID
- [ ] CREATE ROOM yields Steam lobby, JOIN succeeds across two Steam accounts
- [ ] P2P socket connects and forwards ROLL_COMMIT bidirectionally
- [ ] Two-player game run completes without desync
- [ ] Original Steam installation unmodified
