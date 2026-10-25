#!/usr/bin/env bash
set -euo pipefail
DER="/etc/pki/akmods/certs/akmods-ublue.der"
PASSWORD="borshevik"
COUNTDOWN=10
KEYFILE=/run/borshevik-mok-key
HASH=/run/borshevik-mok.hash

SB_STATE="$(mokutil --sb-state 2>/dev/null || true)"
if ! grep -qi 'SecureBoot enabled' <<<"$SB_STATE"; then
  echo "Secure Boot is OFF; skipping MOK enroll."
  exit 0
fi

if ! mokutil --test-key "$DER" >/dev/null 2>&1; then
  echo "MOK key already enrolled; nothing to do."
  exit 0
fi

SYSTEM_LANG="$(. /etc/locale.conf 2>/dev/null; echo "${LANG:-}")"

# plymouth's client aborts on a message longer than 255 bytes, so the whole
# message, Cyrillic taking two bytes a letter, has to stay within that.
instructions() {
  if [[ "$1" == ru* ]]; then
    printf '%s\n' \
      "Подтвердите ключ драйвера NVIDIA. На синем экране:" \
      "Enroll MOK > Continue > Yes, пароль $PASSWORD, Reboot."
  else
    printf '%s\n' \
      "The NVIDIA driver's key must be confirmed once. On the blue screen choose" \
      "Enroll MOK > Continue > Yes, type $PASSWORD (lowercase), then Reboot."
  fi
}

message() {
  local left="$1" lang="$2"
  instructions "$lang"
  echo
  if [[ "$lang" == ru* ]]; then
    echo "Перезагрузка через $left с. R — перезагрузить, S — пропустить"
  else
    echo "Restarting in $left s.  R: restart now.  S: skip"
  fi
}

KEY=""
if plymouth --ping 2>/dev/null; then
  : >"$KEYFILE"
  # к and ы are what R and S give under a ru console keymap.
  plymouth watch-keystroke --keys="rRкКsSыЫ" >"$KEYFILE" 2>/dev/null &
  WATCHER=$!
  SHOWN=""
  for ((left = COUNTDOWN; left > 0; left--)); do
    TEXT="$(message "$left" "$SYSTEM_LANG")"
    [[ -n "$SHOWN" ]] && plymouth hide-message --text="$SHOWN" || true
    plymouth display-message --text="$TEXT" || true
    SHOWN="$TEXT"
    for ((tick = 0; tick < 10; tick++)); do
      [[ -s "$KEYFILE" ]] && break 2
      sleep 0.1
    done
  done
  KEY="$(<"$KEYFILE")"
  kill "$WATCHER" 2>/dev/null || true
  rm -f "$KEYFILE"
  plymouth hide-message --text="$SHOWN" || true
else
  # The console font may have no Cyrillic, so the console gets English.
  instructions en
  echo
  echo "Restarting in $COUNTDOWN s."
  sleep "$COUNTDOWN"
fi

case "$KEY" in
  s | S | ы | Ы)
    echo "MOK enrollment skipped; asking again at the next boot."
    exit 0
    ;;
esac

mokutil --timeout -1 || true
mokutil --generate-hash="$PASSWORD" >"$HASH"
mokutil --import "$DER" --hash-file "$HASH"
rm -f "$HASH"

echo "Rebooting into MokManager"
systemctl --no-block reboot
