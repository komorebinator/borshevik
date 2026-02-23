#!/usr/bin/env bash
set -euo pipefail

# Downloads GoXRay (native Linux GUI for xray-core) from goxray/desktop GitHub
# releases and installs it to /usr/bin/desktop with the required network
# capabilities set via setcap.
#
# Also downloads geoip.dat and geosite.dat from XTLS/Xray-core releases and
# installs them to /usr/share/xray/ (one of xray's default lookup paths).
#
# setcap on ELF binaries survives OCI layer packaging in rootful Podman builds.
#
# Optional env:
#   GOXRAY_VERSION   – specific GoXRay tag, e.g. v0.0.10 (default: latest)
#   GITHUB_TOKEN     – GitHub PAT; set in CI to avoid rate-limiting
#
# Prerequisites (present in the uBlue build container):
#   curl, jq, unzip, tar

GOXRAY_REPO="goxray/desktop"
XRAY_REPO="XTLS/Xray-core"
DEST_BIN="/usr/bin/desktop"
DEST_ICON="/usr/share/pixmaps/GoXRay.png"
DEST_GEODIR="/usr/share/xray"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

CURL_AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_AUTH=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# --- GoXRay ------------------------------------------------------------------

API_BASE="https://api.github.com/repos/${GOXRAY_REPO}/releases"
if [[ -z "${GOXRAY_VERSION:-}" || "${GOXRAY_VERSION:-}" == "latest" ]]; then
    API_URL="${API_BASE}/latest"
else
    API_URL="${API_BASE}/tags/${GOXRAY_VERSION}"
fi

echo "Fetching GoXRay release metadata: ${API_URL}"
RELEASE_JSON="$(curl -fsSL --retry 3 "${CURL_AUTH[@]}" "$API_URL")"

ASSET_LINE="$(
    printf '%s' "$RELEASE_JSON" \
    | jq -r '.assets[] | .name + "\t" + .browser_download_url' \
    | awk -F'\t' 'tolower($1) ~ /linux_amd64\.tar$/ { print; exit }'
)"

if [[ -z "$ASSET_LINE" ]]; then
    echo "GoXRay linux amd64 asset not found. Available assets:" >&2
    printf '%s' "$RELEASE_JSON" | jq -r '.assets[].name' | sed 's/^/  /' >&2
    exit 1
fi

ASSET_NAME="$(printf '%s' "$ASSET_LINE" | cut -f1)"
ASSET_URL="$(printf '%s' "$ASSET_LINE" | cut -f2)"

echo "Downloading GoXRay: ${ASSET_NAME}"
curl -fL --retry 3 --retry-delay 2 "${CURL_AUTH[@]}" \
    -o "${WORKDIR}/${ASSET_NAME}" "${ASSET_URL}"

tar xf "${WORKDIR}/${ASSET_NAME}" -C "$WORKDIR"

install -m 0755 "${WORKDIR}/usr/local/bin/desktop" "$DEST_BIN"
install -m 0644 "${WORKDIR}/usr/local/share/pixmaps/GoXRay.png" "$DEST_ICON"

setcap cap_net_raw,cap_net_admin,cap_net_bind_service+eip "$DEST_BIN"

TAG_NAME="$(printf '%s' "$RELEASE_JSON" | jq -r '.tag_name')"
echo "GoXRay ${TAG_NAME} → ${DEST_BIN} (capabilities set)"

# --- Geo data from XTLS/Xray-core --------------------------------------------

echo "Fetching xray geo data from ${XRAY_REPO}"
XRAY_JSON="$(curl -fsSL --retry 3 "${CURL_AUTH[@]}" \
    "https://api.github.com/repos/${XRAY_REPO}/releases/latest")"

XRAY_ZIP_URL="$(
    printf '%s' "$XRAY_JSON" \
    | jq -r '.assets[] | select(.name == "Xray-linux-64.zip") | .browser_download_url'
)"

if [[ -z "$XRAY_ZIP_URL" ]]; then
    echo "WARNING: Xray-linux-64.zip not found, skipping geo data." >&2
else
    curl -fL --retry 3 --retry-delay 2 "${CURL_AUTH[@]}" \
        -o "${WORKDIR}/xray.zip" "$XRAY_ZIP_URL"

    mkdir -p "$DEST_GEODIR"
    unzip -q "${WORKDIR}/xray.zip" geoip.dat geosite.dat -d "$DEST_GEODIR"
    echo "Geo data → ${DEST_GEODIR}"
fi

echo "Done."
