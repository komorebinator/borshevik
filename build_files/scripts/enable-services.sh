#!/usr/bin/env bash
set -euo pipefail

systemctl enable setup-kargs.service
systemctl --global preset borshevik-app-manager-first-run.service
systemctl --global preset borshevik-enable-new-extensions.service
systemctl --global preset borshevik-kill-gnome-if-hung.timer

# Fedora's presets enable it with the waydroid package; Android is installed only
# by those who ask for it, and borshevik-waydroid install enables it then.
systemctl disable waydroid-container.service

if [[ "${IMAGE_NAME:-}" == "borshevik-nvidia" ]]; then
  systemctl enable setup-ublue-mok.service
fi
