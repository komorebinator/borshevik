#!/usr/bin/env bash

STEAM_CMD=(steam -gamepadui)

exec gamescope -e --expose-wayland --adaptive-sync -- "${STEAM_CMD[@]}"

