#!/usr/bin/env bash
set -euo pipefail

# Downloads Hiddify (Flutter/sing-box VPN client) from hiddify/hiddify-app
# GitHub releases as a linux-x64 AppImage, extracts it, installs to
# /usr/lib/hiddify/, and sets network capabilities on the VPN service binary.
#
# The AppImage is extracted (not run via FUSE) so it works without FUSE at
# runtime and so setcap can target the inner service binary that actually opens
# TUN interfaces. setcap on the AppImage wrapper itself would not propagate
# across exec() to the inner binary.
#
# setcap on ELF binaries survives OCI layer packaging in rootful Podman builds.
#
# Optional env:
#   HIDDIFY_VERSION  – specific tag, e.g. v2.5.7 (default: latest)
#   GITHUB_TOKEN     – GitHub PAT; set in CI to avoid rate-limiting
#
# Prerequisites (present in the uBlue build container):
#   curl, jq

HIDDIFY_REPO="hiddify/hiddify-app"
DEST_DIR="/usr/lib/hiddify"
DEST_ICON="/usr/share/icons/hicolor/256x256/apps/hiddify.png"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

CURL_AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_AUTH=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# --- Hiddify release metadata ------------------------------------------------

API_BASE="https://api.github.com/repos/${HIDDIFY_REPO}/releases"
if [[ -z "${HIDDIFY_VERSION:-}" || "${HIDDIFY_VERSION:-}" == "latest" ]]; then
    API_URL="${API_BASE}/latest"
else
    API_URL="${API_BASE}/tags/${HIDDIFY_VERSION}"
fi

echo "Fetching Hiddify release metadata: ${API_URL}"
RELEASE_JSON="$(curl -fsSL --retry 3 "${CURL_AUTH[@]}" "$API_URL")"

ASSET_NAME="$(printf '%s' "$RELEASE_JSON" \
    | jq -r '[.assets[] | select(.name | test("Linux-x64.*\\.AppImage$"))] | first | .name // empty')"
ASSET_URL="$(printf '%s' "$RELEASE_JSON" \
    | jq -r '[.assets[] | select(.name | test("Linux-x64.*\\.AppImage$"))] | first | .browser_download_url // empty')"

if [[ -z "$ASSET_NAME" ]]; then
    echo "Hiddify linux-x64 AppImage not found. Available assets:" >&2
    printf '%s' "$RELEASE_JSON" | jq -r '.assets[].name' | sed 's/^/  /' >&2
    exit 1
fi

echo "Downloading Hiddify: ${ASSET_NAME}"
APPIMAGE_PATH="${WORKDIR}/${ASSET_NAME}"
curl -fL --retry 3 --retry-delay 2 "${CURL_AUTH[@]}" \
    -o "$APPIMAGE_PATH" "$ASSET_URL"
chmod +x "$APPIMAGE_PATH"

# --- Extract AppImage --------------------------------------------------------
# --appimage-extract does not need FUSE; it unpacks the embedded squashfs into
# squashfs-root/ in the current directory.

echo "Extracting AppImage..."
cd "$WORKDIR"
"$APPIMAGE_PATH" --appimage-extract
EXTRACT_DIR="${WORKDIR}/squashfs-root"

mkdir -p "$DEST_DIR"
cp -a "${EXTRACT_DIR}/." "$DEST_DIR/"

# --- Fix RUNPATH and apply setcap --------------------------------------------
# hiddify and HiddifyCli use RUNPATH=$ORIGIN/lib. The dynamic linker does not
# expand $ORIGIN in AT_SECURE mode (triggered by file capabilities), so we
# replace the relative RUNPATH with an absolute path before applying setcap.
# patchelf is installed temporarily for this step.

dnf install -y patchelf
patchelf --set-rpath "${DEST_DIR}/lib" "${DEST_DIR}/hiddify"
patchelf --set-rpath "${DEST_DIR}/lib" "${DEST_DIR}/HiddifyCli"
dnf remove -y patchelf

CAPS="cap_net_raw,cap_net_admin,cap_net_bind_service+eip"
setcap "$CAPS" "${DEST_DIR}/hiddify"
setcap "$CAPS" "${DEST_DIR}/HiddifyCli"
echo "setcap → ${DEST_DIR}/hiddify, ${DEST_DIR}/HiddifyCli"

# --- Icon --------------------------------------------------------------------

for icon_candidate in \
    "${DEST_DIR}/hiddify.png" \
    "${DEST_DIR}/.DirIcon" \
    "${DEST_DIR}/usr/share/pixmaps/hiddify.png"
do
    if [[ -f "$icon_candidate" ]]; then
        mkdir -p "$(dirname "$DEST_ICON")"
        install -m 0644 "$icon_candidate" "$DEST_ICON"
        echo "Icon → ${DEST_ICON}"
        break
    fi
done

TAG_NAME="$(printf '%s' "$RELEASE_JSON" | jq -r '.tag_name')"
echo "Hiddify ${TAG_NAME} → ${DEST_DIR} (capabilities set)"
echo "Done."
