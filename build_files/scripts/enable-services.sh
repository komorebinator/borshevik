#!/usr/bin/env bash
set -euo pipefail

systemctl enable setup-kargs.service
systemctl --global preset borshevik-app-manager-first-run.service
systemctl --global preset borshevik-kill-gnome-if-hung.timer

if [[ "${IMAGE_NAME:-}" == "borshevik-nvidia" ]]; then
  systemctl enable setup-ublue-mok.service
fi
