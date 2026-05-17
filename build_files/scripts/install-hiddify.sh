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
DEST_ICON="/usr/share/pixmaps/Hiddify.png"

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

ASSET_LINE="$(
    printf '%s' "$RELEASE_JSON" \
    | jq -r '.assets[] | .name + "\t" + .browser_download_url' \
    | awk -F'\t' 'tolower($1) ~ /linux-x64.*\.appimage$/ { print; exit }'
)"

if [[ -z "$ASSET_LINE" ]]; then
    echo "Hiddify linux-x64 AppImage not found. Available assets:" >&2
    printf '%s' "$RELEASE_JSON" | jq -r '.assets[].name' | sed 's/^/  /' >&2
    exit 1
fi

ASSET_NAME="$(printf '%s' "$ASSET_LINE" | cut -f1)"
ASSET_URL="$(printf '%s' "$ASSET_LINE" | cut -f2)"

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

# --- setcap on the VPN service binary ----------------------------------------
# hiddify-service is the sing-box-based core that opens TUN interfaces and
# binds privileged ports. The Flutter UI binary itself does not need caps.

CAPS="cap_net_raw,cap_net_admin,cap_net_bind_service+eip"
SETCAP_DONE=0

for candidate in \
    "${DEST_DIR}/hiddify-service" \
    "${DEST_DIR}/usr/bin/hiddify-service" \
    "${DEST_DIR}/lib/hiddify-service"
do
    if [[ -f "$candidate" ]] && file "$candidate" | grep -q ELF; then
        setcap "$CAPS" "$candidate"
        echo "setcap → ${candidate}"
        SETCAP_DONE=1
    fi
done

if [[ $SETCAP_DONE -eq 0 ]]; then
    # Fallback: look for any sing-box or hiddify binary that is an ELF
    FALLBACK="$(find "$DEST_DIR" -maxdepth 3 \( -name 'sing-box' -o -name 'hiddify' \) -type f \
        | xargs -I{} sh -c 'file "{}" | grep -q ELF && echo "{}"' 2>/dev/null | head -1 || true)"
    if [[ -n "$FALLBACK" ]]; then
        setcap "$CAPS" "$FALLBACK"
        echo "setcap (fallback) → ${FALLBACK}"
        SETCAP_DONE=1
    fi
fi

if [[ $SETCAP_DONE -eq 0 ]]; then
    echo "WARNING: No ELF service binary found for setcap — VPN core may lack required capabilities." >&2
fi

# --- Icon --------------------------------------------------------------------

for icon_candidate in \
    "${DEST_DIR}/hiddify.png" \
    "${DEST_DIR}/.DirIcon" \
    "${DEST_DIR}/usr/share/pixmaps/hiddify.png"
do
    if [[ -f "$icon_candidate" ]]; then
        install -m 0644 "$icon_candidate" "$DEST_ICON"
        echo "Icon → ${DEST_ICON}"
        break
    fi
done

TAG_NAME="$(printf '%s' "$RELEASE_JSON" | jq -r '.tag_name')"
echo "Hiddify ${TAG_NAME} → ${DEST_DIR} (capabilities set)"
echo "Done."
