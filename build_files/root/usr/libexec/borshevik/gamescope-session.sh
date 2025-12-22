#!/usr/bin/env bash

STEAM_CMD=(steam -gamepadui)

export VK_LOADER_LAYERS_DISABLE=VK_LAYER_FROG_gamescope_wsi

exec gamescope -e --expose-wayland --adaptive-sync -- "${STEAM_CMD[@]}"

