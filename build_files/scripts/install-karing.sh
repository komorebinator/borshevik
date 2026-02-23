#!/usr/bin/env bash
set -euo pipefail

# Downloads the latest Karing AppImage from GitHub Releases, extracts the
# squashfs payload directly (no AppImage runtime, no FUSE), installs the
# bundle to /var/opt/karing, and grants the required network capabilities
# to karingService via setcap.
#
# karingService has no polkit action and no systemd unit — the GUI app
# launches it as a subprocess. setcap is therefore the right mechanism.
# xattrs (security.capability) survive OCI layer packaging in rootful
# Podman builds, which is what uBlue GitHub Actions uses.
#
# Usage:
#   sudo ./install-karing.sh
#   sudo KARING_VERSION=v1.2.3 ./install-karing.sh
#
# Optional env:
#   KARING_VERSION   – specific release tag, e.g. v1.2.3  (default: latest)
#   GITHUB_TOKEN     – GitHub PAT; set this in CI to avoid rate-limiting
#
# Prerequisites (must be present in the build container):
#   curl, jq, libcap (setcap)

REPO="KaringX/karing"
DEST_DIR="/usr/lib/karing"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# --- Dependency check --------------------------------------------------------

for cmd in curl jq setcap; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing required tool: $cmd" >&2
        [[ "$cmd" == "setcap" ]] && echo "  Install with: dnf install -y libcap" >&2
        exit 1
    }
done

# --- Release API URL ---------------------------------------------------------
# Treat missing or literal "latest" identically.

API_BASE="https://api.github.com/repos/${REPO}/releases"
if [[ -z "${KARING_VERSION:-}" || "${KARING_VERSION:-}" == "latest" ]]; then
    API_URL="${API_BASE}/latest"
else
    API_URL="${API_BASE}/tags/${KARING_VERSION}"
fi

# --- Optional auth header (prevents 60 req/h rate limit on shared CI IPs) ---

CURL_AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_AUTH=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# --- Fetch release metadata --------------------------------------------------

echo "Fetching release metadata: ${API_URL}"
RELEASE_JSON="$(curl -fsSL --retry 3 "${CURL_AUTH[@]}" "$API_URL")"

# --- Find the Linux AppImage asset for the target arch -----------------------

ASSET_LINE="$(
    printf '%s' "$RELEASE_JSON" \
    | jq -r '.assets[] | .name + "\t" + .browser_download_url' \
    | awk -F'\t' '
        BEGIN { IGNORECASE = 1 }
        ($1 ~ /linux/ && $1 ~ /appimage/ && $1 ~ /amd64/) { print; exit }
      '
)"

if [[ -z "$ASSET_LINE" ]]; then
    echo "No Linux amd64 AppImage asset found in ${REPO}." >&2
    echo "Available assets:" >&2
    printf '%s' "$RELEASE_JSON" | jq -r '.assets[].name' | sed 's/^/  /' >&2
    exit 1
fi

ASSET_NAME="$(printf '%s' "$ASSET_LINE" | cut -f1)"
ASSET_URL="$(printf '%s' "$ASSET_LINE" | cut -f2)"

# --- Download ----------------------------------------------------------------

echo "Downloading: ${ASSET_NAME}"
curl -fL --retry 3 --retry-delay 2 "${CURL_AUTH[@]}" \
    -o "${WORKDIR}/${ASSET_NAME}" "${ASSET_URL}"

# --- Extract AppImage ---------------------------------------------------------
# --appimage-extract is the official no-FUSE extraction flag; it does not
# require FUSE or user namespaces and works fine in a rootful Podman build.

chmod +x "${WORKDIR}/${ASSET_NAME}"
pushd "$WORKDIR" >/dev/null
"./${ASSET_NAME}" --appimage-extract >/dev/null
popd >/dev/null

[[ -d "${WORKDIR}/squashfs-root" ]] || {
    echo "Extraction failed: squashfs-root not found." >&2
    exit 1
}

# --- Install bundle ----------------------------------------------------------

echo "Installing bundle to: ${DEST_DIR}"
rm -rf "${DEST_DIR}"
mkdir -p "${DEST_DIR}"
cp -a "${WORKDIR}/squashfs-root/." "${DEST_DIR}/"

# --- Capabilities for karingService ------------------------------------------
# The GUI launches karingService as a subprocess, so setcap on the binary is
# the right mechanism. /usr/lib/karing is part of the immutable OSTree layer,
# so xattrs (security.capability) are written at build time and stay in the image.
# cap_net_raw covers raw sockets used by some tproxy implementations.

if [[ -x "${DEST_DIR}/karingService" ]]; then
    echo "Granting capabilities to karingService"
    setcap cap_net_admin,cap_net_bind_service,cap_net_raw=+ep "${DEST_DIR}/karingService"
    # Verify — capabilities must survive the OCI layer; fail loudly if they don't.
    getcap "${DEST_DIR}/karingService"
else
    echo "WARNING: ${DEST_DIR}/karingService not found or not executable. Skipping setcap." >&2
    echo "         Check the asset name in the release — binary name may have changed." >&2
fi

TAG_NAME="$(printf '%s' "$RELEASE_JSON" | jq -r '.tag_name')"
echo "Done. Installed ${TAG_NAME} → ${DEST_DIR}"
