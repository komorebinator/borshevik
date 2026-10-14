#!/usr/bin/env bash
# Before tester's login: makes it a new account's first login, the App Manager's
# first run still to come. See @Services#first-login-scenario in spec/.
set -euo pipefail

home="$(getent passwd tester | cut -d: -f6)"
stamp="$home/.local/state/borshevik/app-manager-first-run.done"
rm -f "$stamp"
echo "removed $stamp"
