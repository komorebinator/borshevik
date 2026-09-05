#!/usr/bin/env bash
set -euo pipefail

# Installs the upstream build of Noto Color Emoji, replacing the one Fedora
# ships. Fedora 43 rebuilt google-noto-color-emoji-fonts as COLRv1
# (Noto-COLRv1.ttf, COLR/CPAL tables only) and renderers without COLRv1 support
# draw nothing at all for it - Google Chrome among them. The upstream build
# carries CBDT/CBLC colour bitmaps under the same "Noto Color Emoji" family
# name, so fontconfig's stock emoji configuration reaches it with no rules of
# our own; 09-borshevik-color-emoji.conf hides the Fedora file so exactly one
# font answers to that family.
#
# Releases carry no assets, so the tag resolved from the API is used to fetch
# the font out of the tree at that tag - a concrete immutable ref rather than a
# moving branch.
#
# Optional env:
#   NOTO_EMOJI_VERSION  - specific tag, e.g. v2.051 (default: latest)
#   GITHUB_TOKEN        - GitHub PAT; set in CI to avoid rate-limiting
#
# Prerequisites:
#   curl, jq, fontconfig

NOTO_EMOJI_REPO="googlefonts/noto-emoji"
FONT_DIR="/usr/share/fonts/noto-emoji"
FONT_PATH="${FONT_DIR}/NotoColorEmoji.ttf"

CURL_AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_AUTH=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# --- Resolve release tag -----------------------------------------------------

if [[ -z "${NOTO_EMOJI_VERSION:-}" || "${NOTO_EMOJI_VERSION}" == "latest" ]]; then
    API_URL="https://api.github.com/repos/${NOTO_EMOJI_REPO}/releases/latest"
    echo "Fetching Noto Color Emoji release metadata: ${API_URL}"
    NOTO_EMOJI_VERSION="$(curl -fsSL --retry 3 "${CURL_AUTH[@]}" "$API_URL" \
        | jq -r '.tag_name // empty')"
fi

if [[ -z "${NOTO_EMOJI_VERSION}" ]]; then
    echo "Could not resolve a Noto Color Emoji release tag" >&2
    exit 1
fi

# --- Download ----------------------------------------------------------------

FONT_URL="https://github.com/${NOTO_EMOJI_REPO}/raw/${NOTO_EMOJI_VERSION}/fonts/NotoColorEmoji.ttf"

echo "Installing Noto Color Emoji ${NOTO_EMOJI_VERSION}"
mkdir -p "$FONT_DIR"
curl -fL --retry 3 --retry-delay 2 "${CURL_AUTH[@]}" -o "$FONT_PATH" "$FONT_URL"

# The whole point of replacing Fedora's font is that this one has colour
# bitmaps. If upstream ever switches to COLRv1 too, fail loudly here instead of
# shipping an image whose emoji render blank.
if ! grep -qa 'CBDT' "$FONT_PATH"; then
    echo "Downloaded NotoColorEmoji.ttf has no CBDT table - upstream may have switched to COLRv1" >&2
    exit 1
fi

fc-cache -f
