#!/usr/bin/env bash
set -euo pipefail

TIMEOUT=10
GRACE=2

timeout "${TIMEOUT}s" gdbus call --session \
  --dest org.gnome.Shell \
  --object-path /org/gnome/Shell \
  --method org.freedesktop.DBus.Properties.Get \
  org.gnome.Shell ShellVersion >/dev/null 2>&1 \
|| {
  pids="$(pgrep -u "$USER" -x gnome-shell || true)"
  if [[ -n "${pids}" ]]; then
    echo "Timeout>${TIMEOUT}s -> kill gnome-shell: ${pids}" >&2
    kill -TERM ${pids} 2>/dev/null || true
    sleep "${GRACE}"
    pids2="$(pgrep -u "$USER" -x gnome-shell || true)"
    [[ -n "${pids2}" ]] && kill -KILL ${pids2} 2>/dev/null || true
  fi
}