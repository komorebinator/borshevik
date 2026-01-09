#!/usr/bin/env bash
set -euo pipefail

systemctl enable setup-kargs.service
systemctl --global preset borshevik-app-manager-first-run.service