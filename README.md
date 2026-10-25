# DiceAMillionTogether

Unofficial two-player co-op mod for [Dice A Million](https://store.steampowered.com/app/3430340).

**C#/.NET 10 is the application language.** The relay, connection/session handling and new owner-aware cross-hand scoring rules are in `src/`. GML is retained **only for the GameMaker game integration**, because we are patching a compiled GameMaker game rather than working from its source project. The existing game-side GML is imported from the MIT-licensed [Pildu/multidice](https://github.com/Pildu/multidice) project; removing those hooks without an alternative would break co-op.

## Current implementation

- Existing mod: two-player CREATE ROOM / JOIN ROOM, individual character choice, synchronized rolling, peer dice, shared scoring and shop/map gates.
- **New .NET 10 TCP relay**: replacement for the upstream Python server, compatible with its GameMaker wire protocol (uint32 little-endian frame length followed by UTF-8 JSON). Supports hosting/joining, lobby browser, disconnect notifications and forwarding.
- **New .NET co-op effect core**: each die and cross-hand effect has an owner; Generous Die grants partner ×3 and own dice ×0.5. Tested for symmetry and stacking.
- GameMaker `data.win` patches are built locally by UndertaleModTool (a C#-based GameMaker patching tool).

**Important:** The effect core is not yet hooked into the game's item/shop/score systems. The co-op GameMaker code itself also needs a real Windows/Steam playtest against the currently installed game version. Native Steam friend invites/network transport are not yet present; the mod uses the running Steam game but a TCP relay for networking.

## Build and run (Windows)

Both players need a legitimate copy of Dice A Million on Steam (same version), Git Bash and the [UndertaleModTool CLI](https://github.com/UnderminersTeam/UndertaleModTool) as `tools/utmt_cli/UndertaleModCli.exe`. Install [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10) on the relay host. Set up a trusted private LAN/VPN for the relay.

1. **Run the .NET relay** on one machine:

   ```powershell
   # Local-only is the default. For trusted LAN/VPN, set the private interface IP:
   $env:DMT_BIND = "YOUR_PRIVATE_RELAY_IP"
   $env:DMT_PORT = "7777"
   dotnet run --project src/DiceAMillionTogether.Relay -c Release
   ```

   Allow inbound TCP 7777 from only the other player's private/VPN address. **Do not publicly expose this unencrypted, unauthenticated TCP service.**

2. **Patch each player's owned game** in Git Bash:

   ```bash
   GAME_DIR="/c/Program Files (x86)/Steam/steamapps/common/Dice A Million" \
     RELAY_HOST="YOUR_PRIVATE_RELAY_IP" \
     ./mod/build.sh coop
   ```

   Set `GAME_DIR` to the actual Steam library path. The script creates a side-by-side game folder at `~/DiceAMillionCoop` and does not alter the Steam installation.

3. Open Steam, then run `~/DiceAMillionCoop/run_coop.bat`. One player chooses **CO-OP → CREATE ROOM**, the other **JOIN ROOM** with the code. Both select characters and READY.

4. Runtime configuration is in `~/DiceAMillionCoop/dice_amillion_together.ini`; the host and port can be changed without re-patching:

   ```ini
   [relay]
   host=127.0.0.1
   port=7777
   ```

   For two PCs set the same reachable **private/VPN host** on both.

## Run automated checks

```bash
dotnet build tests/DiceAMillionTogether.SmokeTests -c Release
dotnet run --project tests/DiceAMillionTogether.SmokeTests -c Release --no-build
```

The tests start a live .NET relay on a random loopback port, open actual TCP sockets, assert v1 protocol behavior (including create/list/join, full rooms, frame forwarding, disconnect), and check C# cross-hand scoring. See [playtest checklist](docs/PLAYTEST.md) for tests that require the commercial game.

## Project structure

- `src/DiceAMillionTogether.Core`: pure .NET owner-aware co-op rules and cross-hand score/effect model.
- `src/DiceAMillionTogether.Relay`: actual multiplayer relay, now C#; no Python dependency.
- `tests/DiceAMillionTogether.SmokeTests`: standalone .NET test runner (no third-party NuGet packages).
- `mod/patch.csx`: C# build-time patch script using UndertaleModTool.
- `mod/gml`: **legacy GameMaker adapter hooks** necessary to integrate the mod with the game's bytecode; work to further shrink this is still pending.

## Safety and limitations

- The existing GameMaker patches are version-sensitive; patch compilation and two-client actual gameplay have not been verified against the current Steam game in this environment.
- This is still a relay-based co-op prototype, **not Steam Networking or Steam friend invites**.
- No compiled game executables or patched `data.win` are committed or distributed. The `dist` action refuses to package game assets.
- Use `./mod/build.sh coop`, not `./mod/build.sh install`; the latter modifies the original game's `data.win`.
- Test and report crashes/desyncs before merging. See [attribution](THIRD_PARTY_NOTICES.md).
