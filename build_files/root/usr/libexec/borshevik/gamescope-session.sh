#!/usr/bin/env bash
set -oue pipefail

STEAM_CMD=(steam -gamepadui)

exec gamescope -e -- "${STEAM_CMD[@]}"

