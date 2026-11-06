# Sourced by build-borshevik-packages.sh and install-borshevik-packages.sh, so that the build
# the one makes and the build the other accepts are named by the same code. See
# @ImageBuild#borshevik-packages-lib in spec/.
#
#   borshevik-packages/<source package>/*.patch   a Fedora package, rebuilt with these applied in
#                                                 name order, replacing the image's
#   borshevik-packages/<package>/<package>.spec   a package of Borshevik's own, built from this
#                                                 spec and installed; Version: and Release:
#                                                 written out, with no macros

LIB_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
PATCHES_DIR="$LIB_DIR/borshevik-packages"
RPMS_DIR=/tmp/borshevik-rpms
SUFFIX=borshevik

shopt -s nullglob

die() { echo "$(basename "$0" .sh): $*" >&2; exit 1; }

# Every package under borshevik-packages/, one per line.
package_sources() {
    local dir
    for dir in "$PATCHES_DIR"/*/; do
        basename "$dir"
    done
}

# Which installed binary packages were built from <source>, and at which
# version-release: "<name> <version> <release>" per package.
installed_from() {
    rpm -qa --qf '%{NAME} %{VERSION} %{RELEASE} %{SOURCERPM}\n' |
        awk -v s="$1" '$4 == s "-" $2 "-" $3 ".src.rpm" { print $1, $2, $3 }' | sort
}

# The one version-release every installed subpackage of <source> is at; refuses
# when none is installed or they differ.
installed_version() {
    local src="$1" first="" name v r
    while read -r name v r; do
        [[ -n "$first" ]] || first="$v-$r"
        [[ "$v-$r" == "$first" ]] || die "${src}'s subpackages are at different versions (${name} ${v}-${r}, others ${first})"
    done < <(installed_from "$src")
    [[ -n "$first" ]] || die "no installed package is built from ${src} - drop borshevik-packages/${src}/ or install it first"
    echo "$first"
}

# The spec of <package> when it is one of Borshevik's own, nothing for a Fedora one.
own_spec() {
    local spec="$PATCHES_DIR/$1/$1.spec"
    [[ ! -f "$spec" ]] || echo "$spec"
}

# The version-release <package>'s own spec builds, from its Version: and Release: lines.
spec_version() {
    local spec v r
    spec="$(own_spec "$1")"
    v="$(sed -n 's/^Version:[[:space:]]*//p' "$spec")"
    r="$(sed -n 's/^Release:[[:space:]]*//p' "$spec")"
    [[ "$v" =~ ^[A-Za-z0-9._+~^]+$ && "$r" =~ ^[A-Za-z0-9._+~^]+$ ]] ||
        die "${spec##*/} must write out Version: and Release:, with no macros (has '${v}', '${r}')"
    echo "$v-$r"
}

# The version-release a build of <source> is for: the spec's for an own package, the
# installed one for a Fedora package.
wanted_version() {
    if [[ -n "$(own_spec "$1")" ]]; then
        spec_version "$1"
    else
        installed_version "$1"
    fi
}

# The lines a build of <source> at <version-release> is known by; a build is made
# again exactly when one of them changes: for a Fedora package its patches, for an own
# one every file of its directory.
build_key() {
    local src="$1" vr="$2" p f patches=("$PATCHES_DIR/$1"/*.patch)
    echo "source $src"
    echo "version-release $vr"
    if [[ -n "$(own_spec "$src")" ]]; then
        for f in "$PATCHES_DIR/$src"/*; do
            echo "file ${f##*/} $(sha256sum <"$f" | cut -d' ' -f1)"
        done
    else
        ((${#patches[@]})) || die "borshevik-packages/${src}/ has neither patches nor ${src}.spec"
        echo "suffix $SUFFIX"
        for p in "${patches[@]}"; do
            echo "patch ${p##*/} $(sha256sum <"$p" | cut -d' ' -f1)"
        done
    fi
    for f in build-borshevik-packages.sh borshevik-packages-lib.sh; do
        echo "script $f $(sha256sum <"$LIB_DIR/$f" | cut -d' ' -f1)"
    done
}

# The tag the build is stored under: <source>-<version-release>-<12 hex digits of
# the key>, with what an OCI tag does not allow turned into _.
build_tag() {
    local key hash
    key="$(build_key "$1" "$2")" || exit 1
    hash="$(sha256sum <<<"$key" | cut -c1-12)"
    printf '%s-%s-%s' "$1" "$2" "$hash" | tr -c 'A-Za-z0-9_.-' '_'
    echo
}

# Runs one of the heavy steps - the package manager's, the build's, rpm-ostree's -
# with its output kept in $WORK rather than in the log, where thousands of lines of
# it would bury the script's own. When it fails, prints why: the lines of its output
# that say so, from before its last lines, and then its last lines.
quiet() { # step command...
    local step="$1" log n
    log="$WORK/$(tr -c 'A-Za-z0-9_.-' '_' <<<"$step").log"
    shift
    "$@" >"$log" 2>&1 && return 0
    echo "$(basename "$0" .sh): ${step} failed:" >&2
    n="$(wc -l <"$log")"
    head -n "$((n > 25 ? n - 25 : 0))" "$log" |
        grep -E '(^|[^[:alpha:]])(error|Error|ERROR|FAILED|Problem)([^[:alpha:]]|$)|No match for|nothing provides' |
        tail -n 10 | sed 's/^/  /' >&2
    echo "  ..." >&2
    tail -n 25 "$log" | sed 's/^/  /' >&2
    return 1
}
