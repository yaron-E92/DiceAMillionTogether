# DiceAMillionTogether

Experimental two-player co-op for [Dice A Million](https://store.steampowered.com/app/3430340). This is an adapted version of the MIT-licensed [Pildu/multidice](https://github.com/Pildu/multidice) co-op implementation, with configurable networking and safeguards.

**This is a source-build, not a ready-made download.** It uses the official Steam game files you already own. The game runs through Steam, but multiplayer currently uses a separate TCP relay rather than Steam networking. Cross-hand items (including the requested ×3 partner / ×0.5 self effect) are not implemented yet.

## Getting into a co-op game (Windows)

1. Both players need an owned, same-version Steam installation of Dice A Million, Git Bash, and [UndertaleModTool CLI](https://github.com/UnderminersTeam/UndertaleModTool). Place `UndertaleModCli.exe` in `tools/utmt_cli/`.
2. The host starts `python3 relay/server.py` on a private LAN or VPN (Python 3 standard library only). Allow **TCP 7777** between the two machines.
3. Each player runs from Git Bash in this repo:
   ```bash
   GAME_DIR="/c/Program Files (x86)/Steam/steamapps/common/Dice A Million" RELAY_HOST="YOUR_PRIVATE_RELAY_IP" ./mod/build.sh coop
   ```
   Change `GAME_DIR` to the actual Steam library. The script creates a separate `~/DiceAMillionCoop` folder and preserves the original game installation.
4. Both launch `~/DiceAMillionCoop/run_coop.bat` with Steam running.
5. In the main menu choose **CO-OP**; first player **CREATE ROOM**, second **JOIN ROOM** with the six-character code. Pick separate characters and click READY.

The relay is configured at runtime in `~/DiceAMillionCoop/dice_amillion_together.ini`:
```ini
[relay]
host=127.0.0.1
port=7777
```
Both players must use the same **reachable** relay address. Changing that INI should not require rebuilding.

## Tests

Run the relay locally, then run `python3 relay/test_relay.py`. CI runs this plus Python syntax and Bash syntax checks. Game integration requires a Windows/Steam playtest and has **not** been validated in this environment. See [playtest checklist](docs/PLAYTEST.md).

## Limitations and safety

- This is the existing experimental TCP-relay co-op implementation: individual character choices, peer dice, shared scoring, synced shop/roll/map gates; bugs and desyncs are possible.
- Relay transport is unauthenticated and unencrypted: **use private LAN/VPN, not a public open TCP port**.
- `./mod/build.sh coop` creates a side-by-side patched game copy; `install` overwrites Steam's `data.win` and is **not recommended**.
- `dist` is deliberately disabled. No proprietary game executables or patched `data.win` are distributed by this repo.
- Game updates may invalidate imported full-replacement GML scripts. Rebuild only from the version you own and test on a copy.
- Native Steam lobbies, cross-hand items, reconnection and recovery remain future improvements.

See [attribution](THIRD_PARTY_NOTICES.md).