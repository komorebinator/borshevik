#!/usr/bin/env bash
set -euo pipefail
DER="/etc/pki/akmods/certs/akmods-ublue.der"

SB_STATE="$(mokutil --sb-state 2>/dev/null || true)"
if ! grep -qi 'SecureBoot enabled' <<<"$SB_STATE"; then
  echo "Secure Boot is OFF; skipping MOK enroll."
  exit 0
fi

[ -r "$DER" ] || { echo "Akmods cert is missing: $DER" >&2; exit 1; }
mokutil --test-key "$DER" >/dev/null 2>&1 || true

PIN="$(systemd-ask-password 'Please choose a temporary PIN for MOK; you will be asked to enter it once on the next reboot. (4-32 alnum):')"
[[ "$PIN" =~ ^[A-Za-z0-9]{4,32}$ ]] || { echo "bad PIN" >&2; exit 2; }

HASH=/run/mok.pin.hash
mokutil --generate-hash="$PIN" > "$HASH"
mokutil --timeout -1 || true
mokutil --password --hash-file "$HASH"
mokutil --import  "$DER" --hash-file "$HASH"

echo "Rebooting"
systemctl --no-block reboot