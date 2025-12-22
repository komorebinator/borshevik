#!/usr/bin/env bash

STEAM_CMD=(steam -gamepadui)

exec gamescope -e -- "${STEAM_CMD[@]}"

