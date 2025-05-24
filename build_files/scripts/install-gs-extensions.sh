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
for cmd in jq curl unzip git glib-compile-schemas rsync tar patch; do
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
    forceGnomeVersion=$(jq -r '.forceGnomeVersion // false' <<<"$ENTRY")

    [[ -n "$repo_url" ]] || {
        echo "Error: entry missing repo" >&2
        exit 1
    }

    repo_path=$(sed -E 's|https://[^/]+/([^/]+/[^/]+).*|\1|' <<<"$repo_url")
    tmp=$(mktemp -d)
    ext_src=""

    # Resolve source → ext_src
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

    # Apply patches
    if jq -e '.patches? | type=="object" and (length>0)' <<<"$ENTRY" >/dev/null; then
        echo "   → Applying patches"
        while read -r patch_file rel_target; do
            patch_src="$SCRIPT_DIR/gs-extensions/$patch_file"
            [[ -f "$patch_src" ]] || {
                echo "Error: $patch_file not found" >&2
                exit 1
            }
            echo "     • $patch_file → $rel_target"
            patch "$ext_src/$rel_target" <"$patch_src"
        done < <(jq -r '.patches|to_entries[]|"\(.key) \(.value)"' <<<"$ENTRY")
    fi

    # Custom script override (use only local scripts next to list.json)
    if [[ -n "$script_rel" ]]; then
        script_path="$SCRIPT_DIR/gs-extensions/$script_rel"
        if [[ ! -x "$script_path" ]]; then
            alt_path="$ext_src/$script_rel"
            if [[ -x "$alt_path" ]]; then
                script_path="$alt_path"
            else
                echo "Error: script '$script_rel' not found or not executable" >&2
                rm -rf "$tmp"
                exit 1
            fi
        fi

        echo "   → Running custom script $script_rel"
        (cd "$ext_src" && exec "$script_path")

        # After custom install, extract UUID and validate installation directory
        uuid=$(jq -r '.uuid' "$ext_src/metadata.json")
        if [[ -z "$uuid" || "$uuid" == "null" ]]; then
            echo "Error: cannot determine UUID after custom install" >&2
            rm -rf "$tmp"
            exit 1
        fi

        dest="$DEST/$uuid"
        if [[ ! -d "$dest" ]]; then
            echo "Error: custom script did not install to $dest" >&2
            rm -rf "$tmp"
            exit 1
        fi

        # Compile schemas if requested
        if [[ -n "$schemas" ]]; then
            echo "   → Compiling schemas in $schemas"
            glib-compile-schemas "$dest/$schemas"
        fi

        rm -rf "$tmp"
        continue
    fi

    # Default install: validate metadata + copy + schemas
    meta="$ext_src/metadata.json"
    [[ -f "$meta" ]] || {
        echo "Error: metadata.json not found in $ext_src"
        rm -rf "$tmp"
        exit 1
    }

    uuid=$(jq -r '.uuid' "$meta")
    echo "   → Installing $uuid"
    mkdir -p "$DEST/$uuid"
    rsync -a --delete --exclude=.git "$ext_src/" "$DEST/$uuid/"

    if [[ -n "$schemas" ]]; then
        echo "   → Compiling schemas in $schemas"
        glib-compile-schemas "$DEST/$uuid/$schemas"
    fi

    # Force shell-version if requested
    if [[ "$forceGnomeVersion" == "true" ]]; then
        # Extract version from RPM package
        ver=$(rpm -q --queryformat '%{VERSION}' gnome-shell)
        meta_dest="$DEST/$uuid/metadata.json"
        jq --arg v "$ver" '.["shell-version"] = [$v]' "$meta_dest" >"$meta_dest.tmp" && mv "$meta_dest.tmp" "$meta_dest"
        echo " → Forced shell-version to [$ver]"
    fi

    rm -rf "$tmp"
done

echo "✔ All GNOME extensions installed."
