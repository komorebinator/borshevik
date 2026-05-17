#!/usr/bin/env bash
set -euo pipefail

# Downloads Hiddify from hiddify/hiddify-app GitHub releases as a Debian
# package, extracts it directly into the image filesystem, then patches the
# RUNPATH from $ORIGIN/lib to an absolute path so the dynamic linker finds
# Flutter plugins in AT_SECURE mode (required after setcap).
#
# Using the .deb (not the AppImage) because it installs to a standard system
# layout (/usr/share/hiddify/) without bundled system libs, making it
# straightforward to apply setcap without LD_LIBRARY_PATH conflicts.
#
# Optional env:
#   HIDDIFY_VERSION  – specific tag, e.g. v2.5.7 (default: latest)
#   GITHUB_TOKEN     – GitHub PAT; set in CI to avoid rate-limiting
#
# Prerequisites:
#   curl, jq, ar (binutils), patchelf

HIDDIFY_REPO="hiddify/hiddify-app"
DEST_DIR="/usr/share/hiddify"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

CURL_AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_AUTH=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# --- Release metadata --------------------------------------------------------

API_BASE="https://api.github.com/repos/${HIDDIFY_REPO}/releases"
if [[ -z "${HIDDIFY_VERSION:-}" || "${HIDDIFY_VERSION:-}" == "latest" ]]; then
    API_URL="${API_BASE}/latest"
else
    API_URL="${API_BASE}/tags/${HIDDIFY_VERSION}"
fi

echo "Fetching Hiddify release metadata: ${API_URL}"
RELEASE_JSON="$(curl -fsSL --retry 3 "${CURL_AUTH[@]}" "$API_URL")"

ASSET_NAME="$(printf '%s' "$RELEASE_JSON" \
    | jq -r '[.assets[] | select(.name | test("Debian-x64\\.deb$"))] | first | .name // empty')"
ASSET_URL="$(printf '%s' "$RELEASE_JSON" \
    | jq -r '[.assets[] | select(.name | test("Debian-x64\\.deb$"))] | first | .browser_download_url // empty')"

if [[ -z "$ASSET_NAME" ]]; then
    echo "Hiddify Debian x64 deb not found. Available assets:" >&2
    printf '%s' "$RELEASE_JSON" | jq -r '.assets[].name' | sed 's/^/  /' >&2
    exit 1
fi

# --- Download and extract ----------------------------------------------------

echo "Downloading Hiddify: ${ASSET_NAME}"
curl -fL --retry 3 --retry-delay 2 "${CURL_AUTH[@]}" \
    -o "${WORKDIR}/hiddify.deb" "$ASSET_URL"

cd "$WORKDIR"
ar x hiddify.deb
tar xf data.tar.* -C /

# The deb ships its own hiddify.desktop — remove it; ours in
# /usr/share/applications/Hiddify.desktop (installed via COPY) takes precedence.
rm -f /usr/share/applications/hiddify.desktop

# --- Fix RUNPATH and apply setcap --------------------------------------------
# The binaries use RUNPATH=$ORIGIN/lib. $ORIGIN is not expanded in AT_SECURE
# mode (triggered by file capabilities), so replace it with an absolute path.

patchelf --set-rpath "${DEST_DIR}/lib" "${DEST_DIR}/hiddify"
patchelf --set-rpath "${DEST_DIR}/lib" "${DEST_DIR}/HiddifyCli"

CAPS="cap_net_raw,cap_net_admin,cap_net_bind_service+eip"
setcap "$CAPS" "${DEST_DIR}/hiddify"
setcap "$CAPS" "${DEST_DIR}/HiddifyCli"
echo "setcap → ${DEST_DIR}/hiddify, ${DEST_DIR}/HiddifyCli"

TAG_NAME="$(printf '%s' "$RELEASE_JSON" | jq -r '.tag_name')"
echo "Hiddify ${TAG_NAME} → ${DEST_DIR} (capabilities set)"
echo "Done."
