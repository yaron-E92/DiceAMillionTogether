#!/usr/bin/env bash
# Build a patched data.win and optionally set up a side-by-side coop launch folder.
# Usage:
#   ./build.sh              # just build -> ./build/data.win.patched
#   ./build.sh coop         # install a side-by-side game copy + Windows Steam bridge
#   ./build.sh install      # (DANGEROUS) overwrite the original game's data.win
#   ./build.sh dist         # deliberately refused: patched game files are proprietary
#
# Environment overrides (all optional — defaults target a typical Windows+Steam layout
# accessed from Git Bash / MSYS2; paths use forward slashes):
#   GAME_DIR  — Steam install of Dice A Million (default: /c/Program Files (x86)/Steam/steamapps/common/Dice A Million)
#   COOP_DIR  — where `coop` mode installs the side-by-side copy (default: $HOME/DiceAMillionCoop)
#   UTMT_CLI  — path to UndertaleModCli.exe (default: ../tools/utmt_cli/UndertaleModCli.exe)
#   NETWORK_MODE — steam (default) or relay (legacy private TCP mode)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
GAME_DIR="${GAME_DIR:-/c/Program Files (x86)/Steam/steamapps/common/Dice A Million}"
COOP_DIR="${COOP_DIR:-$HOME/DiceAMillionCoop}"
UTMT_CLI="${UTMT_CLI:-$ROOT/../tools/utmt_cli/UndertaleModCli.exe}"
NETWORK_MODE="${NETWORK_MODE:-steam}"
if [[ "$NETWORK_MODE" != "steam" && "$NETWORK_MODE" != "relay" ]]; then echo "NETWORK_MODE must be steam or relay" >&2; exit 2; fi
RELAY_HOST="${RELAY_HOST:-127.0.0.1}"
RELAY_PORT="${RELAY_PORT:-7777}"
if [[ ! "$RELAY_PORT" =~ ^[0-9]+$ ]] || (( RELAY_PORT < 1 || RELAY_PORT > 65535 )); then
  echo "Invalid RELAY_PORT" >&2; exit 2
fi
if [[ ! -f "$UTMT_CLI" ]] && ! command -v "$UTMT_CLI" >/dev/null 2>&1; then echo "Missing UndertaleModCli.exe: $UTMT_CLI" >&2; exit 2; fi
# Prefer the pristine backup if one exists, so rebuilds always start from clean data.
if [[ -f "$GAME_DIR/data.win.orig" ]]; then
    SRC_WIN="$GAME_DIR/data.win.orig"
else
    SRC_WIN="$GAME_DIR/data.win"
fi
if [[ ! -f "$SRC_WIN" ]]; then echo "Missing Dice A Million data.win: $SRC_WIN" >&2; exit 2; fi
OUT_WIN="$ROOT/build/data.win.patched"
SCRIPT="$ROOT/patch.csx"

mkdir -p "$ROOT/build"

echo "[build] patching $SRC_WIN -> $OUT_WIN"
"$UTMT_CLI" load "$SRC_WIN" --scripts "$SCRIPT" -o "$OUT_WIN" -v >/tmp/multidice_utmt.log 2>&1 || {
    echo "[build] UTMT failed, last 40 log lines:"; tail -40 /tmp/multidice_utmt.log; exit 1;
}
echo "[build] patched data.win written"

# Recursively mirror a source tree into a destination using hardlinks for files,
# falling back to copy if hardlinking fails (e.g. across filesystems). Directories
# are created, not linked. Existing files in the destination are replaced.
mirror_hardlink() {
    local src="$1" dst="$2"
    mkdir -p "$dst"
    local entry name
    for entry in "$src"/* "$src"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        name="$(basename "$entry")"
        if [[ -d "$entry" ]]; then
            mirror_hardlink "$entry" "$dst/$name"
        else
            rm -f "$dst/$name"
            ln "$entry" "$dst/$name" 2>/dev/null || cp "$entry" "$dst/$name"
        fi
    done
}

case "${1:-}" in
    coop)
        echo "[build] setting up coop folder at $COOP_DIR"
        mkdir -p "$COOP_DIR"
        # Mirror the entire game folder via hardlinks (no data duplication for audiogroup1.dat etc.)
        mirror_hardlink "$GAME_DIR" "$COOP_DIR"
        # If a backup exists we just mirrored, the coop folder has data.win.orig too — harmless.
        # Replace data.win with the patched build.
        rm -f "$COOP_DIR/data.win"
        cp "$OUT_WIN" "$COOP_DIR/data.win"
        # Write steam_appid.txt so Steam doesn't redirect the launch back to the library install
        # via SteamAPI_RestartAppIfNecessary. 3430340 is the Dice A Million Steam app ID.
        echo -n "3430340" > "$COOP_DIR/steam_appid.txt"
        if [[ "$NETWORK_MODE" == "steam" ]]; then
          # GameMaker uses localhost TCP, Steam handles Internet P2P.
          RELAY_HOST="127.0.0.1"
          RELAY_PORT=7777
          command -v dotnet >/dev/null 2>&1 || { echo "Install .NET 10 SDK before building the Steam bridge." >&2; exit 2; }
          echo "[build] publishing self-contained Windows Steam bridge"
          dotnet publish "$ROOT/../src/DiceAMillionTogether.SteamBridge/DiceAMillionTogether.SteamBridge.csproj" \
              -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true \
              -o "$COOP_DIR/steam-bridge"
          # Use the legally installed game's local Steam native runtime if needed.
          if [[ ! -f "$COOP_DIR/steam-bridge/steam_api64.dll" && -f "$GAME_DIR/steam_api64.dll" ]]; then
              cp "$GAME_DIR/steam_api64.dll" "$COOP_DIR/steam-bridge/steam_api64.dll"
          fi
          printf '3430340' > "$COOP_DIR/steam-bridge/steam_appid.txt"
        fi
        printf '[relay]\nhost=%s\nport=%s\n' "$RELAY_HOST" "$RELAY_PORT" > "$COOP_DIR/dice_amillion_together.ini"
        # Write a launcher .bat right next to the exe.
        # We set SteamAppId/SteamGameId so Steamworks' RestartAppIfNecessary doesn't
        # redirect the launch back to the Steam library install. Env var is more
        # reliable than steam_appid.txt, which can be cleaned up by AV or Steam itself.
        if [[ "$NETWORK_MODE" == "steam" ]]; then
          cat > "$COOP_DIR/run_coop.bat" <<'EOF'
@echo off
cd /d "%~dp0"
set SteamAppId=3430340
set SteamGameId=3430340
if not exist "%~dp0steam-bridge\DiceAMillionTogether.SteamBridge.exe" (
  echo Steam bridge executable not found. Rebuild with NETWORK_MODE=steam.
  pause
  exit /b 1
)
start "DiceAMillionTogether Steam Bridge" /D "%~dp0steam-bridge" "%~dp0steam-bridge\DiceAMillionTogether.SteamBridge.exe"
rem Give Steam API and localhost listener a chance to start.
timeout /t 4 /nobreak >nul
start "Dice A Million (Co-op)" "dice a million.exe"
EOF
        else
          cat > "$COOP_DIR/run_coop.bat" <<'EOF'
@echo off
cd /d "%~dp0"
set SteamAppId=3430340
set SteamGameId=3430340
start "Dice A Million (Co-op)" "dice a million.exe"
EOF
        fi
        # Convenience copy in the project root so the user doesn't have to hunt for the folder.
        cp "$COOP_DIR/run_coop.bat" "$ROOT/../run_coop.bat"
        echo "[build] coop installed to $COOP_DIR"
        echo "[build] launcher: $COOP_DIR/run_coop.bat (and a copy at $ROOT/../run_coop.bat)"
        ;;
    install)
        BACKUP="$GAME_DIR/data.win.orig"
        if [[ ! -f "$BACKUP" ]]; then
            echo "[build] backing up original -> $BACKUP"
            cp "$GAME_DIR/data.win" "$BACKUP"
        fi
        echo "[build] overwriting original game data.win"
        cp "$OUT_WIN" "$GAME_DIR/data.win"
        ;;
    dist)
        echo "Refusing to distribute a patched data.win containing proprietary assets. Build locally." >&2
        exit 2
        ;;
    "")
        ;;
    *)
        echo "unknown subcommand: $1"; exit 2;;
esac

echo "[build] done"
