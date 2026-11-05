#!/usr/bin/env bash
set -euo pipefail

# Rebuilds every distribution package that has patches under borshevik-packages/
# from the source RPM of exactly the version the base image carries. Runs in a
# throwaway container of the base image, started by build-borshevik-packages.yml,
# never inside an image build: what it installs to build goes away with the
# container. Why it works this way, and what each patch is for, is said at
# @ImageBuild#build-borshevik-packages in spec/.
#
#   build-borshevik-packages.sh plan                    <source> <tag> per patched source
#   build-borshevik-packages.sh build <out> <source>... <out>/<source>/: RPMs and build-info

source "$(dirname "$(readlink -f "$0")")/borshevik-packages-lib.sh"

plan() {
    local src vr
    for src in $(patched_sources); do
        vr="$(installed_version "$src")" || exit 1
        echo "$src $(build_tag "$src" "$vr")"
    done
}

rpmb() { rpmbuild --define "_topdir $TOPDIR" "$@"; }

build_one() { # out source
    local out="$1/$2" src="$2" vr rel srpm spec gitdir tree p spec_rel last started f name names
    local patches=("$PATCHES_DIR/$src"/*.patch)
    echo "== ${src}"
    ((${#patches[@]})) || die "borshevik-packages/${src}/ has no patches"
    vr="$(installed_version "$src")" || exit 1
    rel="${vr##*-}"
    mapfile -t names < <(installed_from "$src" | cut -d' ' -f1)
    echo "Installed from ${src}-${vr}: ${names[*]}"
    echo "Patches:"; printf '  %s\n' "${patches[@]##*/}"

    TOPDIR="$WORK/rpmbuild-$src"
    quiet "dnf download --srpm ${src}" dnf -y download --srpm --destdir "$WORK" "${src}-${vr}" ||
        die "the source RPM ${src}-${vr} is not in the source repositories"
    srpm="$WORK/${src}-${vr}.src.rpm"
    [[ -f "$srpm" ]] || die "dnf did not leave ${srpm##*/} in ${WORK}"

    # The source that gets patched and built is the distribution's own, by its
    # signature, against the keys the image already trusts.
    rpmkeys --checksig "$srpm" || die "${srpm##*/} is not signed by a key this image trusts"

    quiet "dnf install rpm-build" dnf -y install --setopt=install_weak_deps=False rpm-build ||
        die "rpm-build could not be installed"
    quiet "dnf builddep ${src}" dnf -y builddep --setopt=install_weak_deps=False "$srpm" ||
        die "${src}'s build dependencies could not be installed"
    quiet "rpm -i ${srpm##*/}" rpm -i --define "_topdir $TOPDIR" "$srpm" || die "${srpm##*/} could not be unpacked"
    spec="$TOPDIR/SPECS/${src}.spec"
    [[ -f "$spec" ]] || die "no ${src}.spec in ${srpm##*/}"
    grep -qE '^%(autosetup|autopatch)' "$spec" ||
        die "${src}.spec applies its patches one by one, which this script cannot add to"

    # Each patch against the source as Fedora's spec prepares it, in order, with
    # no fuzz; in reverse it means upstream already has it.
    quiet "rpmbuild -bp ${src}" rpmb -bp --nodeps "$spec" || die "${src}.spec's %prep failed"
    gitdir="$(find "$TOPDIR/BUILD" -mindepth 1 -maxdepth 4 -name .git -print -quit)"
    [[ -n "$gitdir" ]] || die "${src}.spec's %prep left no git tree under BUILD"
    tree="$(dirname "$gitdir")"
    for p in "${patches[@]}"; do
        if git -C "$tree" apply --check "$p" 2>/dev/null; then
            git -C "$tree" apply "$p"
        elif git -C "$tree" apply --check -R "$p" 2>/dev/null; then
            die "${p##*/} is already in ${src} ${vr}: drop it"
        else
            git -C "$tree" apply --check "$p" || true # again, for git's own report of where
            die "${p##*/} conflicts with ${src} ${vr}: port it"
        fi
    done
    rm -rf "$TOPDIR/BUILD"

    # The rebuild: Fedora's spec, its patches and ours, under Fedora's release plus
    # the suffix - written out, since Release: is usually a macro and a parametric
    # one would swallow anything appended to it.
    spec_rel="$(rpmspec -q --srpm --qf '%{RELEASE}\n' "$spec")"
    [[ "$spec_rel" == "$rel" ]] || die "${src}.spec gives release ${spec_rel} here, the image has ${rel}"
    last="$(grep -nE '^(Patch|Source)[0-9]*:' "$spec" | tail -1 | cut -d: -f1)"
    [[ -n "$last" ]] || die "${src}.spec has no Source: or Patch: line to add the patches after"
    for p in "${patches[@]}"; do
        cp "$p" "$TOPDIR/SOURCES/"
        sed -i "${last}a Patch: ${p##*/}" "$spec"
        last=$((last + 1))
    done
    sed -i -E "s/^Release:.*/Release: ${rel}.${SUFFIX}/" "$spec"
    echo "Building ${src}-${vr}.${SUFFIX}"
    started=$SECONDS
    quiet "rpmbuild -bb ${src}" rpmb -bb --nocheck --define 'debug_package %{nil}' "$spec" ||
        die "the rebuild of ${src} ${vr} failed"
    echo "Built in $(((SECONDS - started) / 60))m$(((SECONDS - started) % 60))s"

    # Every binary RPM the build made - the base layer may install subpackages the
    # base image does not - but only if it has each installed one, at the suffixed release.
    rm -rf "$out"
    mkdir -p "$out"
    declare -A built=()
    for f in "$TOPDIR"/RPMS/*/*.rpm; do
        [[ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$f")" == "${vr}.${SUFFIX}" ]] ||
            die "the rebuild of ${src} made ${f##*/}, not at ${vr}.${SUFFIX}"
        built["$(rpm -qp --qf '%{NAME}' "$f")"]=1
        cp "$f" "$out/"
    done
    for name in "${names[@]}"; do
        [[ -n "${built[$name]:-}" ]] || die "the rebuild of ${src} made no ${name}"
    done
    build_key "$src" "$vr" >"$out/build-info"
    echo "Wrote:"; (cd "$out" && printf '  %s\n' *)
    rm -rf "$TOPDIR" "$srpm"
}

build() { # out source...
    local out="${1:?usage: $0 build <out> <source>...}" src
    shift
    WORK="$(mktemp -d /tmp/borshevik-packages.XXXXXX)"
    trap 'rm -rf "$WORK"' EXIT
    for src in "$@"; do
        [[ -d "$PATCHES_DIR/$src" ]] || die "no borshevik-packages/${src}/"
        build_one "$out" "$src"
    done
}

case "${1:-}" in
    plan) plan ;;
    build) shift; build "$@" ;;
    *) echo "usage: $0 plan | build <out> <source>..." >&2; exit 2 ;;
esac
