# DiceAMillionTogether

**Steam lobby and Steam P2P co-op for Dice A Million — experimental.**

> This Steam bridge is a stacked PR on top of the working .NET co-op foundation. The bridge compiles against Facepunch.Steamworks and keeps the legacy GameMaker co-op UI and gameplay patches. **It has not yet been tested with two Steam accounts and the current commercial game binary.** The game publisher may not have enabled Steam lobby support for app 3430340. No Steam credentials are collected by this mod.

## Fast path — two Windows Steam players

Both players need an owned Steam copy of [Dice A Million](https://store.steampowered.com/app/3430340), the same game version, [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10), Git Bash, and [UndertaleModTool CLI](https://github.com/UnderminersTeam/UndertaleModTool) in `tools/utmt_cli/UndertaleModCli.exe`.

1. Clone this feature branch, ensure Steam is running.
2. In Git Bash, from the repo root, on **both PCs** run:
   ```bash
   GAME_DIR="/c/Program Files (x86)/Steam/steamapps/common/Dice A Million" \
      NETWORK_MODE=steam ./mod/build.sh coop
   ```
   Change `GAME_DIR` to your own Steam library as needed.
3. Launch `~/DiceAMillionCoop/run_coop.bat` on each computer. This starts the C# Steam companion process and the locally patched game. Leave the Steam Bridge console running.
4. Host chooses **CO-OP → CREATE ROOM**; the mod creates a Steam lobby and shows a six-character code. Guest chooses **JOIN ROOM**, enters that code (or browses), picks their own character, and both click READY.

**No TCP relay server, no VPN, and no port forwarding.** The game connects to `127.0.0.1:7777`; the bridge uses the native Steam Lobby and SteamNetworkingSockets P2P APIs for Internet transport. Valve's relay network may carry the traffic automatically. The bridge never binds a public network interface.

If Steam lobby creation returns an access-denied or similar error, that is a possible app-level Steamworks capability restriction; see [Steam playtest troubleshooting](docs/STEAM-PLAYTEST.md). The previous custom relay remains available via `NETWORK_MODE=relay` for comparison.

## Architecture

- `src/DiceAMillionTogether.SteamBridge`: **C#** localhost compatibility adapter + real Steam Lobby discovery and reliable P2P socket transport.
- `src/DiceAMillionTogether.Core`: C# cross-hand item effect engine (Generous Die ×0.5 self / ×3 partner).
- `src/DiceAMillionTogether.Relay`: prior private TCP relay fallback, not used in Steam mode.
- `mod/gml`: legacy imported GameMaker hooks for dice, scoring and room UI; still necessary because the commercial game has no mod SDK.
- `mod/patch.csx`: C# patch script using UndertaleModTool to modify the *locally owned* game's data.
- `tests/DiceAMillionTogether.SmokeTests`: .NET framing, relay integration and scoring tests.

## Important boundaries

- Steam networking is implemented but live dual-account connectivity and GameMaker patch compatibility remain unverified. A successful CI compile does **not** establish game playability.
- The C# Generous Die rule is tested but is not wired into Dice A Million's actual items or shop.
- Six-character room codes are public Steam lobby metadata, not credentials. Lobbies are public so friends can locate them across regions. No automatic Steam friend invitation/overlay join yet; **this is Steam-based matchmaking and transport**, not Steam invite UX.
- `./mod/build.sh coop` preserves the original Steam game by creating a separate local folder. Do not distribute patched `data.win` or the game's executable.
- The bridge uses third-party [Facepunch.Steamworks](https://github.com/Facepunch/Facepunch.Steamworks) (pinned NuGet version 2.3.3). See [attribution](THIRD_PARTY_NOTICES.md).

## Automated tests

```bash
dotnet build src/DiceAMillionTogether.SteamBridge -c Release
dotnet run --project tests/DiceAMillionTogether.SmokeTests -c Release
```

Steam itself cannot be exercised in CI without actual logged-in accounts and an approved app; see the [two-player manual test plan](docs/STEAM-PLAYTEST.md).
