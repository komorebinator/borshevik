#!/usr/bin/env bash
set -euo pipefail

# Swaps Borshevik's builds of the distribution packages it patches in for the base
# image's, and refuses the build unless what got installed is a build of exactly the
# version the image has, made from these patches by these scripts. Builds nothing:
# the builds are mounted at RPMS_DIR from the image build-borshevik-packages.yml
# keeps. See @ImageBuild#install-borshevik-packages in spec/.

source "$(dirname "$(readlink -f "$0")")/borshevik-packages-lib.sh"

MANIFEST=/usr/share/borshevik/borshevik-packages

WORK="$(mktemp -d /tmp/borshevik-packages.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$(dirname "$MANIFEST")"
: >"$MANIFEST"

mapfile -t sources < <(patched_sources)
if ((${#sources[@]} == 0)); then
    echo "No Borshevik packages to install"
    exit 0
fi

for src in "${sources[@]}"; do
    echo "== ${src}"
    vr="$(installed_version "$src")" || exit 1
    mapfile -t names < <(installed_from "$src" | cut -d' ' -f1)
    echo "Installed from ${src}-${vr}: ${names[*]}"

    # The build must be of this version, from these patches, by these scripts.
    dir="$RPMS_DIR/$src"
    [[ -f "$dir/build-info" ]] ||
        die "no build of ${src} in ${dir}/ - the packages image (PACKAGES_TAG in the Containerfile) has none; build-borshevik-packages.yml makes it"
    want="$(build_key "$src" "$vr")" || exit 1
    if [[ "$(cat "$dir/build-info")" != "$want" ]]; then
        built_vr="$(sed -n 's/^version-release //p' "$dir/build-info")"
        [[ "$built_vr" == "$vr" ]] ||
            die "the build of ${src} is of ${built_vr:-no version}, the image has ${vr}: the base image moved on since the packages image was made, or a package transaction upgraded ${src}; the next base build makes the build for ${vr}"
        echo "The build of ${src} differs from what this image is built with:" >&2
        { diff "$dir/build-info" <(echo "$want") || true; } | sed -n 's/^< /  the build: /p; s/^> /  this image: /p' >&2
        die "the build of ${src} was made from other patches or scripts than these"
    fi

    declare -A built=()
    for f in "$dir"/*.rpm; do
        built["$(rpm -qp --qf '%{NAME}' "$f")"]="$f"
    done
    replace=()
    for name in "${names[@]}"; do
        [[ -n "${built[$name]:-}" ]] || die "the build of ${src} has no ${name} - refusing a partial swap"
        replace+=("${built[$name]}")
    done
    echo "Replacing with:"; printf '  %s\n' "${replace[@]##*/}"
    quiet "rpm-ostree override replace ${src}" rpm-ostree override replace "${replace[@]}" ||
        die "rpm-ostree could not replace ${src}'s packages"

    # What is installed now is the very RPM from the build, file for file.
    patchlist=""
    for p in "$PATCHES_DIR/$src"/*.patch; do
        patchlist+=" ${p##*/}=$(sha256sum <"$p" | cut -d' ' -f1)"
    done
    for name in "${names[@]}"; do
        f="${built[$name]}"
        have="$(rpm -q --qf '%{VERSION}-%{RELEASE} %{SHA256HEADER}' "$name")"
        want="$(rpm -qp --qf '%{VERSION}-%{RELEASE} %{SHA256HEADER}' "$f")"
        [[ "$have" == "$want" && "${have%% *}" == "${vr}.${SUFFIX}" ]] ||
            die "${name} is ${have}, not the build ${want}"
        rpm -V "$name" || die "${name}'s files are not as packaged"
        echo "$(rpm -q "$name") replaces ${vr}${patchlist}" >>"$MANIFEST"
    done
    unset built
done

echo "Borshevik packages installed:"
sed 's/^/  /' "$MANIFEST"
