#!/usr/bin/env bash
set -euo pipefail

systemctl enable app-choice-subscription.service
systemctl enable setup-kargs.service
