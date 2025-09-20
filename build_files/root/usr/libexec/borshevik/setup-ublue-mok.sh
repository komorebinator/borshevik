#!/usr/bin/env bash
set -euo pipefail
DER="/etc/pki/akmods/certs/akmods-ublue.der"

SB_STATE="$(mokutil --sb-state 2>/dev/null || true)"
if ! grep -qi 'SecureBoot enabled' <<<"$SB_STATE"; then
  echo "Secure Boot is OFF; skipping MOK enroll."
  exit 0
fi

if ! mokutil --test-key "$DER" >/dev/null 2>&1; then
  echo "MOK key already enrolled; nothing to do."
  exit 0
fi

while :; do
  if PIN="$(systemd-ask-password 'Please choose a temporary PIN for MOK; you will be asked to enter it once on the next reboot:')"; then
    if [ -n "$PIN" ]; then 
      break
    fi
  else
    echo "cancelled" >&2
    exit 130
  fi  
done

HASH=/run/mok.pin.hash
mokutil --generate-hash="$PIN" > "$HASH"
mokutil --timeout -1 || true
mokutil --password --hash-file "$HASH"
mokutil --import  "$DER" --hash-file "$HASH"

echo "Rebooting"
systemctl --no-block reboot