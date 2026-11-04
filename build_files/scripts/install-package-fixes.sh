#!/usr/bin/env bash
set -euo pipefail

# Rebuilds every distribution package that has patches under package-fixes/ from
# the source RPM of exactly the version this image carries, swaps the rebuilt
# subpackages in, and refuses the build unless what got installed is that
# rebuild. Leaves the image as it found it but for the swapped packages, the
# build happening inside this very layer. Why it works this way, and what each
# patch is for, is said at @ImageBuild#install-package-fixes in spec/.
#
#   package-fixes/<source package>/<major version>/*.patch   applied in name order

FIXES_DIR="$(dirname "$(readlink -f "$0")")/package-fixes"
SUFFIX=borshevik
MANIFEST=/usr/share/borshevik/package-fixes

WORK="$(mktemp -d /tmp/package-fixes.XXXXXX)"
TOPDIR="$WORK/rpmbuild"
cleanup() { rm -rf "$WORK"; dnf -q clean all >/dev/null 2>&1 || true; }
trap cleanup EXIT

die() { echo "install-package-fixes: $*" >&2; exit 1; }
rpmb() { rpmbuild --define "_topdir $TOPDIR" "$@"; }

mkdir -p "$(dirname "$MANIFEST")"
: >"$MANIFEST"

shopt -s nullglob
sources=("$FIXES_DIR"/*/)
if ((${#sources[@]} == 0)); then
    echo "No package fixes to apply"
    exit 0
fi

# Which installed binary packages were built from <source>, and at which
# version-release: "<name> <version> <release>" per package.
installed_from() {
    rpm -qa --qf '%{NAME} %{VERSION} %{RELEASE} %{SOURCERPM}\n' |
        awk -v s="$1" '$4 == s "-" $2 "-" $3 ".src.rpm" { print $1, $2, $3 }' | sort
}

snapshot() { # dir: what a build may not leave behind. gpg-pubkey entries are
    # left out: they are the repositories' signing keys dnf imports, not packages,
    # and any later install from those repositories would import them anyway.
    mkdir -p "$1"
    rpm -qa --qf '%{NAME}.%{ARCH}\n' | grep -v '^gpg-pubkey\.' | sort -u >"$1/names"
    rpm -qa --qf '%{NAME}.%{ARCH} %{EPOCHNUM}:%{VERSION}-%{RELEASE}\n' | grep -v '^gpg-pubkey\.' | sort >"$1/versions"
    cut -d: -f1 /etc/passwd | sort >"$1/users"
    cut -d: -f1 /etc/group | sort >"$1/groups"
}

for dir in "${sources[@]}"; do
    src="$(basename "$dir")"
    echo "== ${src}"

    mapfile -t pkgs < <(installed_from "$src")
    ((${#pkgs[@]})) || die "no installed package is built from ${src} - drop package-fixes/${src}/ or install it first"
    read -r _ ver rel <<<"${pkgs[0]}"
    for p in "${pkgs[@]}"; do
        read -r name v r <<<"$p"
        [[ "$v-$r" == "$ver-$rel" ]] || die "${src}'s subpackages are at different versions (${name} ${v}-${r}, others ${ver}-${rel})"
    done
    names=("${pkgs[@]%% *}")
    echo "Installed from ${src}-${ver}-${rel}: ${names[*]}"

    major="${ver%%.*}"
    patches=("$dir$major"/*.patch)
    if ((${#patches[@]} == 0)); then
        echo "No patches for ${src} ${major}; there are for: $(cd "$dir" && ls -d -- */ 2>/dev/null | tr -d / | tr '\n' ' ')" >&2
        die "${src} is now ${ver}: port its patches to package-fixes/${src}/${major}/, or drop them if ${major} carries the fix"
    fi
    echo "Patches:"; printf '  %s\n' "${patches[@]##*/}"

    before="$WORK/before-$src"
    snapshot "$before"

    dnf -y download --srpm --destdir "$WORK" "${src}-${ver}-${rel}" ||
        die "the source RPM ${src}-${ver}-${rel} is not in the source repositories"
    srpm="$WORK/${src}-${ver}-${rel}.src.rpm"
    [[ -f "$srpm" ]] || die "dnf did not leave ${srpm##*/} in ${WORK}"

    # The source that gets patched and built is the distribution's own, by its
    # signature, against the keys the image already trusts.
    rpmkeys --checksig "$srpm" || die "${srpm##*/} is not signed by a key this image trusts"

    dnf -y install --setopt=install_weak_deps=False rpm-build
    dnf -y builddep --setopt=install_weak_deps=False "$srpm"
    rpm -i --define "_topdir $TOPDIR" "$srpm"
    spec="$TOPDIR/SPECS/${src}.spec"
    [[ -f "$spec" ]] || die "no ${src}.spec in ${srpm##*/}"
    grep -qE '^%(autosetup|autopatch)' "$spec" ||
        die "${src}.spec applies its patches one by one, which this script cannot add to"

    # Each patch against the source as Fedora's spec prepares it, in order, with
    # no fuzz; in reverse it means upstream already has it.
    rpmb -bp --nodeps "$spec" >"$WORK/prep.log" 2>&1 || { cat "$WORK/prep.log" >&2; die "${src}.spec's %prep failed"; }
    gitdir="$(find "$TOPDIR/BUILD" -mindepth 1 -maxdepth 4 -name .git -print -quit)"
    [[ -n "$gitdir" ]] || die "${src}.spec's %prep left no git tree under BUILD"
    tree="$(dirname "$gitdir")"
    for p in "${patches[@]}"; do
        if git -C "$tree" apply --check "$p" 2>/dev/null; then
            git -C "$tree" apply "$p"
        elif git -C "$tree" apply --check -R "$p" 2>/dev/null; then
            die "${p##*/} is already in ${src} ${ver}-${rel}: drop it"
        else
            git -C "$tree" apply --check "$p" || true # again, for git's own report of where
            die "${p##*/} conflicts with ${src} ${ver}-${rel}: port it"
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
    rpmb -bb --nocheck --define 'debug_package %{nil}' "$spec"

    # Remove what the build brought in, and check nothing of it stays.
    after="$WORK/after-$src"
    snapshot "$after"
    mapfile -t added < <(comm -13 "$before/names" "$after/names")
    if ((${#added[@]})); then
        echo "Removing the ${#added[@]} packages the build installed"
        rpm -e "${added[@]}"
    fi
    snapshot "$after"
    missing="$(comm -23 "$before/names" "$after/names" | tr '\n' ' ')"
    left="$(comm -13 "$before/names" "$after/names" | tr '\n' ' ')"
    [[ -z "$missing$left" ]] || die "the build changed the installed packages: gone ${missing:-none}, left ${left:-none}"
    upgraded="$(comm -13 "$before/versions" "$after/versions")"
    if [[ -n "$upgraded" ]]; then
        echo "Upgraded by the build dependencies (Fedora updates the next base would bring anyway):"
        sed 's/^/  /' <<<"$upgraded"
    fi
    for db in users groups; do
        new="$(comm -13 "$before/$db" "$after/$db" | tr '\n' ' ')"
        [[ -z "$new" ]] || die "the build dependencies left ${db} behind: ${new}"
    done

    # Swap in exactly the subpackages the image has.
    declare -A built=()
    for f in "$TOPDIR"/RPMS/*/*.rpm; do
        built["$(rpm -qp --qf '%{NAME}' "$f")"]="$f"
    done
    replace=()
    for name in "${names[@]}"; do
        [[ -n "${built[$name]:-}" ]] || die "the rebuild of ${src} made no ${name} - refusing a partial swap"
        replace+=("${built[$name]}")
    done
    echo "Replacing with:"; printf '  %s\n' "${replace[@]##*/}"
    rpm-ostree override replace "${replace[@]}"

    patchlist=""
    for p in "${patches[@]}"; do
        patchlist+=" ${p##*/}=$(sha256sum "$p" | cut -d' ' -f1)"
    done
    for name in "${names[@]}"; do
        f="${built[$name]}"
        have="$(rpm -q --qf '%{VERSION}-%{RELEASE} %{SHA256HEADER}' "$name")"
        want="$(rpm -qp --qf '%{VERSION}-%{RELEASE} %{SHA256HEADER}' "$f")"
        [[ "$have" == "$want" && "${have%% *}" == "${ver}-${rel}.${SUFFIX}" ]] ||
            die "${name} is ${have}, not the rebuild ${want}"
        rpm -V "$name" || die "${name}'s files are not as packaged"
        echo "$(rpm -q "$name") replaces ${ver}-${rel}${patchlist}" >>"$MANIFEST"
    done
    unset built
done

echo "Package fixes installed:"
sed 's/^/  /' "$MANIFEST"
