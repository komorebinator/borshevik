#!/usr/bin/env bash

set -ouex pipefail

meson gnome-shell-extension-appindicator /tmp/g-s-appindicators-build
ninja -C /tmp/g-s-appindicators-build install