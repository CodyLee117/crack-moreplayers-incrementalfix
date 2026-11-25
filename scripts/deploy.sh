#!/usr/bin/env bash
# Deploy the built plugin into the game's BepInEx plugins folder (own subfolder, next to
# khovanet's More_Players).
# Usage: ./scripts/deploy.sh [GameDir]   (default: the pinned install on D:)
set -euo pipefail
GAME_DIR="${1:-/mnt/d/SteamLibrary/steamapps/common/CRACK}"
SRC="$(dirname "$0")/../MorePlayersIncrementalFix/bin/Release/MorePlayersIncrementalFix.dll"
REPO="$(dirname "$0")/.."
DST="$GAME_DIR/BepInEx/plugins/crackmods-moreplayers-incrementalfix"
if [ ! -f "$SRC" ]; then
  echo "built DLL not found at $SRC - run: dotnet build MorePlayersIncrementalFix/MorePlayersIncrementalFix.csproj -c Release" >&2
  exit 1
fi
mkdir -p "$DST"
cp "$SRC" "$DST/MorePlayersIncrementalFix.dll"
cp "$REPO/manifest.json" "$REPO/README.md" "$DST/"
echo "deployed: $DST"
