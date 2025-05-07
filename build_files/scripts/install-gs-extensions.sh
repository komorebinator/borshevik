#!/usr/bin/env bash
#
# Installs GNOME Shell extensions listed in extensions/list.json.
# Supports:
#   • branch   – shallow git-clone of a branch/tag
#   • asset    – named .zip asset from the latest GitHub release
#   • archive  – "zip" (default) or "tar": zipball/tarball of latest release
#   • script   – run a custom install script you provide alongside list.json
# Optional fields:
#   • dir      – sub-directory inside the source (for metadata root)
#   • schemas  – relative path to GSettings schemas to compile
#
# For GitHub Actions:
#   env: GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_JSON="${SCRIPT_DIR}/gs-extensions/list.json"
DEST="/usr/share/gnome-shell/extensions"

# Dependencies: jq curl unzip git glib-compile-schemas rsync tar
for cmd in jq curl unzip git glib-compile-schemas rsync tar; do
    command -v "$cmd" >/dev/null || {
        echo "Error: $cmd is required" >&2
        exit 1
    }
done

# GitHub API auth if token provided
auth=()
[[ -n "${GH_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GH_TOKEN")

echo ">>> Installing GNOME extensions…"
jq -e 'type=="array"' "$EXT_JSON" >/dev/null || {
    echo "Error: JSON must be an array" >&2
    exit 1
}

# Iterate each extension entry
jq -c '.[]' "$EXT_JSON" | while read -r ENTRY; do
    repo_url=$(jq -r '.repo' <<<"$ENTRY")
    branch=$(jq -r '.branch  // empty' <<<"$ENTRY")
    asset=$(jq -r '.asset   // empty' <<<"$ENTRY")
    archive=$(jq -r '.archive // "zip"' <<<"$ENTRY")
    dir=$(jq -r '.dir     // empty' <<<"$ENTRY")
    script_rel=$(jq -r '.script // empty' <<<"$ENTRY")
    schemas=$(jq -r '.schemas // empty' <<<"$ENTRY")

    [[ -n "$repo_url" ]] || {
        echo "Error: entry missing repo" >&2
        exit 1
    }

    repo_path=$(sed -E 's|https://[^/]+/([^/]+/[^/]+).*|\1|' <<<"$repo_url")
    tmp=$(mktemp -d)
    ext_src=""

    # 1. Resolve source → ext_src
    if [[ "$repo_url" =~ github\.com ]]; then
        api_rel="https://api.github.com/repos/$repo_path/releases/latest"

        if [[ -n "$asset" ]]; then
            echo " • Downloading asset '$asset' from $repo_path"
            dl=$(curl -fsSL "${auth[@]}" "$api_rel" |
                jq -r --arg a "$asset" '.assets[]? | select(.name==$a) | .browser_download_url' | head -n1)
            [[ -n "$dl" ]] || {
                echo "Error: asset '$asset' not found"
                rm -rf "$tmp"
                exit 1
            }
            curl -fsSL "${auth[@]}" "$dl" -o "$tmp/ext.zip"
            unzip -q "$tmp/ext.zip" -d "$tmp/unpacked"
            ext_src="$tmp/unpacked"

        elif [[ -z "$branch" ]]; then
            echo " • Downloading $archive-ball of latest release for $repo_path"
            if [[ "$archive" == "tar" ]]; then
                dl=$(curl -fsSL "${auth[@]}" "$api_rel" | jq -r '.tarball_url')
                curl -fsSL "${auth[@]}" "$dl" -o "$tmp/source.tar.gz"
                mkdir "$tmp/unpacked" && tar -xzf "$tmp/source.tar.gz" -C "$tmp/unpacked"
            else
                dl=$(curl -fsSL "${auth[@]}" "$api_rel" | jq -r '.zipball_url')
                curl -fsSL "${auth[@]}" "$dl" -o "$tmp/source.zip"
                unzip -q "$tmp/source.zip" -d "$tmp/unpacked"
            fi
            # strip first-level wrapper
            ext_src=$(find "$tmp/unpacked" -mindepth 1 -maxdepth 1 -type d | head -n1)

        else
            echo " • Cloning $repo_path (branch/tag: $branch)"
            git clone --depth 1 --branch "$branch" "$repo_url" "$tmp/repo"
            ext_src="$tmp/repo"
        fi
    else
        echo " • Cloning $repo_path${branch:+ (branch/tag: $branch)}"
        git clone --depth 1 ${branch:+--branch "$branch"} "$repo_url" "$tmp/repo"
        ext_src="$tmp/repo"
    fi

    # apply dir
    [[ -n "$dir" ]] && ext_src="$ext_src/$dir"

    # 2. Custom script override
    if [[ -n "$script_rel" ]]; then
        script_path="$SCRIPT_DIR/gs-extensions/$script_rel"
        [[ -x "$script_path" ]] || {
            echo "Error: script '$script_rel' not found or not executable" >&2
            rm -rf "$tmp"
            exit 1
        }

        echo "   → Running custom script $script_rel"
        (cd "$ext_src" && exec "$script_path")
        # after script installation, still compile schemas if requested
        if [[ -n "$schemas" ]]; then
            echo "   → Compiling schemas in $schemas"
            glib-compile-schemas "$DEST/$(jq -r '.uuid' <<<"$ENTRY")/$schemas"
        fi
        rm -rf "$tmp"
        continue
    fi

    # 3. Default install: validate metadata + copy + schemas
    meta="$ext_src/metadata.json"
    [[ -f "$meta" ]] || {
        echo "Error: metadata.json not found in $ext_src"
        rm -rf "$tmp"
        exit 1
    }

    uuid=$(jq -r '.uuid' <<<"$ENTRY")
    echo "   → Installing $uuid"
    mkdir -p "$DEST/$uuid"
    rsync -a --delete --exclude=.git "$ext_src/" "$DEST/$uuid/"

    if [[ -n "$schemas" ]]; then
        echo "   → Compiling schemas in $schemas"
        glib-compile-schemas "$DEST/$uuid/$schemas"
    fi

    rm -rf "$tmp"
done

echo "✔ All GNOME extensions installed."
