#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_JSON="${SCRIPT_DIR}/extensions.json"
DEST="/usr/share/gnome-shell/extensions"

for cmd in jq curl unzip git glib-compile-schemas; do
    command -v "$cmd" >/dev/null || {
        echo "Error: $cmd is required" >&2
        exit 1
    }
done

echo ">>> Installing GNOME extensions from extensions.json …"

jq -e 'type == "array"' "$EXT_JSON" >/dev/null || {
    echo "Error: $EXT_JSON must be a JSON array" >&2
    exit 1
}

INDEX=0
jq -c '.[]' "$EXT_JSON" | while read -r ENTRY; do
    INDEX=$((INDEX + 1))

    REPO_URL=$(jq -r '.repo' <<<"$ENTRY")
    BRANCH=$(jq -r '.branch // empty' <<<"$ENTRY")
    SUBDIR=$(jq -r '.subdir // empty' <<<"$ENTRY")
    SCHEMAS_DIR=$(jq -r '.schemas // empty' <<<"$ENTRY")
    ASSET_NAME=$(jq -r '.asset // empty' <<<"$ENTRY")

    [[ -n "$REPO_URL" ]] || {
        echo "Error: entry #$INDEX missing 'repo'" >&2
        exit 1
    }

    REPO_PATH=$(echo "$REPO_URL" | sed -E 's|https://[^/]+/([^/]+/[^/]+).*|\1|')
    TMP_DIR="$(mktemp -d)"
    EXT_SRC=""

    if [[ "$REPO_URL" =~ github\.com ]]; then
        if [[ -n "$ASSET_NAME" ]]; then
            echo " • Fetching release asset '$ASSET_NAME' for $REPO_PATH"
            API_URL="https://api.github.com/repos/$REPO_PATH/releases/latest"
            DL_URL=$(curl -fsSL "$API_URL" |
                jq -r --arg name "$ASSET_NAME" '.assets[]? | select(.name == $name) | .browser_download_url' | head -n1 || true)
            [[ -n "$DL_URL" ]] || {
                echo "Error: asset '$ASSET_NAME' not found in latest release of $REPO_PATH" >&2
                rm -rf "$TMP_DIR"
                exit 1
            }

            ZIP_FILE="$TMP_DIR/ext.zip"
            curl -fsSL "$DL_URL" -o "$ZIP_FILE"
            unzip -q "$ZIP_FILE" -d "$TMP_DIR/unzipped"

            EXT_SRC="$TMP_DIR/unzipped"
            META_FILE="$EXT_SRC/metadata.json"
            [[ -f "$META_FILE" ]] || {
                echo "Error: metadata.json not found at archive root of $ASSET_NAME" >&2
                rm -rf "$TMP_DIR"
                exit 1
            }
        elif [[ -n "$BRANCH" ]]; then
            echo " • Cloning $REPO_PATH (branch: $BRANCH)"
            git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR/repo"
            EXT_SRC="$TMP_DIR/repo"
        else
            echo "Error: neither 'asset' nor 'branch' specified for GitHub repo $REPO_PATH" >&2
            rm -rf "$TMP_DIR"
            exit 1
        fi
    else
        echo " • Cloning $REPO_PATH${BRANCH:+ (branch: $BRANCH)}"
        if [[ -n "$BRANCH" ]]; then
            git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR/repo"
        else
            git clone --depth 1 "$REPO_URL" "$TMP_DIR/repo"
        fi
        EXT_SRC="$TMP_DIR/repo"
    fi

    [[ -n "$SUBDIR" ]] && EXT_SRC="$EXT_SRC/$SUBDIR"

    META_FILE="$EXT_SRC/metadata.json"
    [[ -f "$META_FILE" ]] || {
        echo "Error: metadata.json not found in $EXT_SRC" >&2
        rm -rf "$TMP_DIR"
        exit 1
    }

    UUID=$(jq -r '.uuid' "$META_FILE")
    [[ -n "$UUID" && "$UUID" != "null" ]] || {
        echo "Error: invalid UUID in $REPO_PATH" >&2
        rm -rf "$TMP_DIR"
        exit 1
    }

    echo "   → Installing $UUID"
    mkdir -p "$DEST/$UUID"
    rsync -a --exclude=.git "$EXT_SRC/" "$DEST/$UUID/"

    if [[ -n "$SCHEMAS_DIR" ]]; then
        echo "   → Compiling GSettings schema in $SCHEMAS_DIR"
        glib-compile-schemas "$DEST/$UUID/$SCHEMAS_DIR" || {
            echo "Error: glib-compile-schemas failed in $UUID/$SCHEMAS_DIR" >&2
            rm -rf "$TMP_DIR"
            exit 1
        }
    fi

    find "$DEST/$UUID" -type d -exec chmod 755 {} +
    find "$DEST/$UUID" -type f -exec chmod 644 {} +

    rm -rf "$TMP_DIR"
done

echo "✔ All GNOME extensions installed successfully."
