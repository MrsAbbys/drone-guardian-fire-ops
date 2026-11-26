#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
GODOT_BIN=${GODOT_BIN:-godot}
SERVER_OUTPUT="$ROOT/exports/linux-server/drone-server.x86_64"
CLIENT_OUTPUT="$ROOT/exports/linux-client/drone-client.x86_64"

mkdir -p "$ROOT/exports/linux-server" "$ROOT/exports/linux-client"

"$GODOT_BIN" --headless --editor --path "$ROOT" --quit
"$GODOT_BIN" --headless --path "$ROOT" --export-release "Linux Server" "$SERVER_OUTPUT"
"$GODOT_BIN" --headless --path "$ROOT" --export-release "Linux Cliente" "$CLIENT_OUTPUT"
