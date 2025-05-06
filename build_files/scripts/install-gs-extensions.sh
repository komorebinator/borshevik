#!/usr/bin/env bash
#
# Installs GNOME Shell extensions listed in extensions.json.
# Supports:
#   • branch   – shallow git‑clone of a branch/tag
#   • asset    – named .zip asset from the latest GitHub release
#   • archive  – "zip" (default) or "tar": zipball/tarball of latest release
# Optional fields:
#   • dir      – sub‑directory where metadata.json lives
#   • schemas  – GSettings schemas to compile
#
# Tip for GitHub Actions:
#   env:
#     GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_JSON="${SCRIPT_DIR}/extensions.json"
DEST="/usr/share/gnome-shell/extensions"

for cmd in jq curl unzip git glib-compile-schemas rsync tar; do
    command -v "$cmd" >/dev/null || {
        echo "Error: $cmd is required" >&2
        exit 1
    }
done

# add auth header if GH_TOKEN is set
AUTH=()
[[ -n "${GH_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer $GH_TOKEN")

echo ">>> Installing GNOME extensions …"
jq -e 'type=="array"' "$EXT_JSON" >/dev/null || {
    echo "Error: JSON must be an array" >&2
    exit 1
}

jq -c '.[]' "$EXT_JSON" | while read -r ENTRY; do
    REPO_URL=$(jq -r '.repo' <<<"$ENTRY")
    BRANCH=$(jq -r '.branch  // empty' <<<"$ENTRY")
    ASSET=$(jq -r '.asset   // empty' <<<"$ENTRY")
    ARCHIVE=$(jq -r '.archive // "zip"' <<<"$ENTRY") # zip | tar
    DIR=$(jq -r '.dir     // empty' <<<"$ENTRY")
    SCHEMAS=$(jq -r '.schemas // empty' <<<"$ENTRY")

    [[ -n "$REPO_URL" ]] || {
        echo "Error: entry missing repo" >&2
        exit 1
    }

    REPO_PATH=$(sed -E 's|https://[^/]+/([^/]+/[^/]+).*|\1|' <<<"$REPO_URL")
    TMP=$(mktemp -d)
    EXT_SRC=""

    ##########################################################
    # 1. Resolve source → $EXT_SRC
    ##########################################################
    if [[ "$REPO_URL" =~ github\.com ]]; then
        API_REL="https://api.github.com/repos/$REPO_PATH/releases/latest"

        if [[ -n "$ASSET" ]]; then
            echo " • Downloading asset '$ASSET' of $REPO_PATH"
            DL=$(curl -fsSL "${AUTH[@]}" "$API_REL" |
                jq -r --arg a "$ASSET" '.assets[]? | select(.name==$a) | .browser_download_url' | head -n1)
            [[ -n "$DL" ]] || {
                echo "Error: asset '$ASSET' not found"
                rm -rf "$TMP"
                exit 1
            }

            ZIP="$TMP/ext.zip"
            curl -fsSL "${AUTH[@]}" "$DL" -o "$ZIP"
            unzip -q "$ZIP" -d "$TMP/unpacked"
            EXT_SRC="$TMP/unpacked"

        elif [[ -z "$BRANCH" ]]; then
            echo " • Downloading $ARCHIVE‑ball of latest release for $REPO_PATH"
            if [[ "$ARCHIVE" == "tar" ]]; then
                DL=$(curl -fsSL "${AUTH[@]}" "$API_REL" | jq -r '.tarball_url')
                FILE="$TMP/source.tar.gz"
                curl -fsSL "${AUTH[@]}" "$DL" -o "$FILE"
                mkdir "$TMP/unpacked"
                tar -xzf "$FILE" -C "$TMP/unpacked"
            else
                DL=$(curl -fsSL "${AUTH[@]}" "$API_REL" | jq -r '.zipball_url')
                FILE="$TMP/source.zip"
                curl -fsSL "${AUTH[@]}" "$DL" -o "$FILE"
                unzip -q "$FILE" -d "$TMP/unpacked"
            fi
            # strip first‑level wrapper directory
            EXT_SRC=$(find "$TMP/unpacked" -mindepth 1 -maxdepth 1 -type d | head -n1)

        else
            echo " • Cloning $REPO_PATH (branch/tag: $BRANCH)"
            git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP/repo"
            EXT_SRC="$TMP/repo"
        fi
    else
        echo " • Cloning $REPO_PATH${BRANCH:+ (branch/tag: $BRANCH)}"
        git clone --depth 1 ${BRANCH:+--branch "$BRANCH"} "$REPO_URL" "$TMP/repo"
        EXT_SRC="$TMP/repo"
    fi

    [[ -n "$DIR" ]] && EXT_SRC="$EXT_SRC/$DIR"

    ##########################################################
    # 2. Validate and install
    ##########################################################
    META="$EXT_SRC/metadata.json"
    [[ -f "$META" ]] || {
        echo "Error: metadata.json not found in $EXT_SRC"
        rm -rf "$TMP"
        exit 1
    }

    UUID=$(jq -r '.uuid' "$META")
    [[ "$UUID" != "null" && -n "$UUID" ]] || {
        echo "Error: invalid UUID"
        rm -rf "$TMP"
        exit 1
    }

    echo "   → Installing $UUID"
    mkdir -p "$DEST/$UUID"
    rsync -a --delete --exclude=.git "$EXT_SRC/" "$DEST/$UUID/"

    if [[ -n "$SCHEMAS" ]]; then
        echo "   → Compiling schemas in $SCHEMAS"
        glib-compile-schemas "$DEST/$UUID/$SCHEMAS"
    fi

    rm -rf "$TMP"
done

echo "✔ All GNOME extensions installed."
