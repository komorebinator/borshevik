#!/usr/bin/env bash
# Runs @ImageBuild#build-borshevik-packages and @ImageBuild#install-borshevik-packages on the
# base image they run on: the build as build-borshevik-packages.yml runs it, the install as the
# base layer does, with what the build made mounted where the packages stage puts it. With the
# repository's patches, which must be built and installed, and with patch sets and builds made
# from them that must be refused, saying why. See @ImageBuild#tests#borshevik-packages in spec/.
# Runs on the host (podman); prints `ok <case>` or `FAIL <case>: ...` per case.
set -uo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
image="ghcr.io/ublue-os/silverblue-main:${FEDORA_MAJOR_VERSION:-44}"
work="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/borshevik-packages-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failed=0
ok() { echo "ok $1"; }
fail() { echo "FAIL $1: $2"; failed=1; }

shopt -s nullglob
# the first Fedora package, with patches, and the first of Borshevik's own, with a spec
src="" own=""
for d in "$repo"/build_files/scripts/borshevik-packages/*/; do
    name="$(basename "$d")"
    p=("$d"*.patch)
    [[ -n "$src" || ${#p[@]} -eq 0 ]] || src="$name"
    [[ -n "$own" || ! -f "$d$name.spec" ]] || own="$name"
done
[[ -n "$src$own" ]] || { echo "no Borshevik packages in the repository: nothing to test"; exit 0; }

only() { # name package: a copy of build_files/scripts whose borshevik-packages holds <package> alone
    rm -rf "$work/$1"
    cp -a "$repo/build_files/scripts" "$work/$1"
    find "$work/$1/borshevik-packages" -mindepth 1 -maxdepth 1 ! -name "$2" -exec rm -rf {} +
    echo "$work/$1"
}

variant() { # name: such a copy whose borshevik-packages/<source>/ is empty
    only "$1" "$src" >/dev/null
    rm -rf "$work/$1/borshevik-packages/$src"
    mkdir -p "$work/$1/borshevik-packages/$src"
    echo "$work/$1/borshevik-packages/$src"
}

build_run() { # scripts-dir out log args...: as build-borshevik-packages.yml runs it
    local scripts="$1" out="$2" log="$3"
    shift 3
    mkdir -p "$out"
    podman run --rm --security-opt label=disable -v "$scripts:/build_scripts:ro" -v "$out:/out" "$image" \
        bash -c '/build_scripts/configure-repos.sh >/dev/null && /build_scripts/build-borshevik-packages.sh "$@"' \
        _ "$@" >"$log" 2>&1
}

install_run() { # scripts-dir rpms-dir log [full]: as the base layer runs it; with `full`, after
    # mutter-devkit is layered, as install-rpm-packages does - the refusals come before any of it
    local layer=true
    [[ "${4:-}" == full ]] && layer='dnf -y install mutter-devkit'
    podman run --rm --security-opt label=disable -v "$1:/build_scripts:ro" -v "$2:/tmp/borshevik-rpms:ro" \
        "$image" bash -c "/build_scripts/configure-repos.sh && $layer && /build_scripts/install-borshevik-packages.sh" \
        >"$3" 2>&1
}

expect_refusal() { # case script pattern run...: the run must fail with a message matching pattern
    local name="$1" script="$2" pattern="$3"
    shift 3
    if "$@"; then
        fail "$name" "went through, should have refused"
    elif grep -qE "^$script: .*$pattern" "$work/$name.log"; then
        ok "$name ($(grep -m1 "^$script: " "$work/$name.log" | cut -c$((${#script} + 3))-))"
    else
        fail "$name" "refused otherwise: $(grep -m1 -E "^$script: |error" "$work/$name.log")"
    fi
}

if [[ -n "$src" ]]; then
patches=("$repo/build_files/scripts/borshevik-packages/$src/"*.patch)
first="${patches[0]}"
vr="$(podman run --rm "$image" rpm -q --qf '%{VERSION}-%{RELEASE}' "$src" 2>/dev/null)"
scripts="$(only scripts "$src")"

# --- the build of a Fedora package --------------------------------------------------

# plan: the tag of the version the base image has
if build_run "$scripts" "$work/plan-out" "$work/plan.log" plan &&
    grep -qxE "$src $src-${vr//./\\.}-[0-9a-f]{12}" "$work/plan.log"; then
    ok "plan ($(cat "$work/plan.log"))"
else
    fail plan "$(tail -3 "$work/plan.log" | tr '\n' ' ')"
fi

# The repository's patches: every RPM at the suffixed release, from a signed source RPM
rpms="$work/rpms"
if build_run "$scripts" "$rpms" "$work/build.log" build /out "$src" &&
    grep -q 'digests signatures OK' "$work/build.log" && [[ -f "$rpms/$src/build-info" ]]; then
    made=("$rpms/$src"/*.rpm)
    odd="$(printf '%s\n' "${made[@]##*/}" | grep -v "\.borshevik\." | tr '\n' ' ')"
    if [[ "$src" == mutter && ! -f "$(echo "$rpms/$src"/mutter-devkit-*.rpm)" ]]; then
        fail build "no mutter-devkit, which the base layer has"
    elif [[ -n "$odd" || ${#made[@]} -eq 0 ]]; then
        fail build "RPMs not at the suffixed release: ${odd:-none at all}"
    else
        ok "build (${#made[@]} RPMs: $(printf '%s ' "${made[@]##*/}"))"
    fi
else
    fail build "see the end of the log: $(tail -3 "$work/build.log" | tr '\n' ' ')"
fi
# ...printing its own account only, not the package manager's and the build's output
printed="$(sed -n "/^== $src\$/,\$p" "$work/build.log" | wc -l)"
((printed > 0 && printed < 100)) && ok "build-quiet ($printed lines)" || fail build-quiet "the script printed $printed lines"

# A patch the source already carries: the first patch turned around, so the source
# as Fedora ships it is what that patch would produce
d="$(variant upstream)"
python3 - "$first" >"$d/0001-reversed.patch" <<'PY'
import re, sys
for line in open(sys.argv[1]):
    if line.startswith("--- a/"): line = "+++ b/" + line[6:]
    elif line.startswith("+++ b/"): line = "--- a/" + line[6:]
    elif m := re.match(r"@@ -(\S+) \+(\S+) @@(.*)", line, re.S): line = f"@@ -{m[2]} +{m[1]} @@{m[3]}"
    elif line.startswith("-") and not line.startswith("---"): line = "+" + line[1:]
    elif line.startswith("+") and not line.startswith("+++"): line = "-" + line[1:]
    sys.stdout.write(line)
PY
# git wants the old file's header first
python3 - "$d/0001-reversed.patch" <<'PY'
import sys
lines = open(sys.argv[1]).readlines()
for i in range(len(lines) - 1):
    if lines[i].startswith("+++ b/") and lines[i + 1].startswith("--- a/"):
        lines[i], lines[i + 1] = lines[i + 1], lines[i]
open(sys.argv[1], "w").writelines(lines)
PY
expect_refusal upstream build-borshevik-packages "is already in" \
    build_run "$work/upstream" "$work/upstream-out" "$work/upstream.log" build /out "$src"

# A patch whose context the source does not have
d="$(variant conflict)"
awk 'BEGIN { h = 0; d = 0 } /^@@/ { h = 1 } { if (h && !d && /^ ./) { print $0 " /* changed */"; d = 1 } else print }' \
    "$first" >"$d/0001-conflict.patch"
expect_refusal conflict build-borshevik-packages "conflicts with" \
    build_run "$work/conflict" "$work/conflict-out" "$work/conflict.log" build /out "$src"

# A patch that applies but does not build: the build stops, and what it prints shows why
d="$(variant build-fails)"
python3 - "$first" >"$d/0001-build-fails.patch" <<'PY'
import re, sys
done = False
for line in open(sys.argv[1]):
    m = None if done else re.match(r"@@ -(\S+) \+(\d+)(?:,(\d+))? @@(.*)", line, re.S)
    if m:
        count = int(m[3]) if m[3] is not None else 1
        sys.stdout.write(f"@@ -{m[1]} +{m[2]},{count + 1} @@{m[4]}")
        sys.stdout.write("+#error borshevik-packages test\n")
        done = True
    else:
        sys.stdout.write(line)
PY
expect_refusal build-fails build-borshevik-packages "the rebuild of $src" \
    build_run "$work/build-fails" "$work/build-fails-out" "$work/build-fails.log" build /out "$src"
if grep -q '#error borshevik-packages test' "$work/build-fails.log"; then
    ok "build-fails-reason (the compiler's error is in what it printed)"
else
    fail build-fails-reason "the compiler's error is not in what it printed"
fi

# --- the install of a Fedora package ------------------------------------------------

if [[ ! -f "$rpms/$src/build-info" ]]; then
    fail install "no build to install"
else
    # What the build made, installed: each subpackage at the suffixed release, in the manifest
    if install_run "$scripts" "$rpms" "$work/install.log" full &&
        sed -n '/^Borshevik packages installed:/,$p' "$work/install.log" | grep -q "^  $src-.*\.borshevik\..* replaces "; then
        ok "install ($(sed -n '/^Borshevik packages installed:/,$p' "$work/install.log" | grep ' replaces ' | cut -d' ' -f3 | tr '\n' ' '))"
    else
        fail install "see the end of the log: $(tail -3 "$work/install.log" | tr '\n' ' ')"
    fi

    # No build of the source at all
    mkdir -p "$work/rpms-missing"
    expect_refusal missing install-borshevik-packages "no build of $src" \
        install_run "$scripts" "$work/rpms-missing" "$work/missing.log"

    # A build of another version, as when the base image moved on since the build was made
    cp -a "$rpms" "$work/rpms-version"
    sed -i 's/^version-release .*/version-release 0-0.fc0/' "$work/rpms-version/$src/build-info"
    expect_refusal version install-borshevik-packages "is of 0-0.fc0, the image has" \
        install_run "$scripts" "$work/rpms-version" "$work/version.log"

    # A build made from other patches than the image is built with
    d="$(variant patches)"
    cp "${patches[@]}" "$d/"
    echo "-- changed after the build" >>"$d/${first##*/}"
    expect_refusal patches install-borshevik-packages "other patches, files or scripts" \
        install_run "$work/patches" "$rpms" "$work/patches.log"

    # A build missing one of the subpackages the image has
    cp -a "$rpms" "$work/rpms-partial"
    rm -f "$work/rpms-partial/$src/$src"-[0-9]*.rpm
    expect_refusal partial install-borshevik-packages "has no $src " \
        install_run "$scripts" "$work/rpms-partial" "$work/partial.log"
fi

fi

# --- a package of Borshevik's own ----------------------------------------------------

if [[ -n "$own" ]]; then
    spec="$repo/build_files/scripts/borshevik-packages/$own/$own.spec"
    ovr="$(sed -n 's/^Version:[[:space:]]*//p' "$spec")-$(sed -n 's/^Release:[[:space:]]*//p' "$spec")"
    oscripts="$(only own-scripts "$own")"

    # plan: the tag of the version its spec gives
    if build_run "$oscripts" "$work/own-plan-out" "$work/own-plan.log" plan &&
        grep -qxE "$own $own-${ovr//./\\.}-[0-9a-f]{12}" "$work/own-plan.log"; then
        ok "own-plan ($(cat "$work/own-plan.log"))"
    else
        fail own-plan "$(tail -3 "$work/own-plan.log" | tr '\n' ' ')"
    fi

    # The build: RPMs at the spec's version-release, with the build's key
    orpms="$work/own-rpms"
    if build_run "$oscripts" "$orpms" "$work/own-build.log" build /out "$own" &&
        [[ -f "$orpms/$own/build-info" ]]; then
        made=("$orpms/$own"/*.rpm)
        odd="$(for f in "${made[@]}"; do rpm -qp --qf '%{VERSION}-%{RELEASE}\n' "$f" 2>/dev/null; done | grep -vxF "$ovr" | tr '\n' ' ')"
        if [[ ${#made[@]} -eq 0 || -n "$odd" ]]; then
            fail own-build "RPMs not at ${ovr}: ${odd:-none at all}"
        else
            ok "own-build (${#made[@]} RPMs: $(printf '%s ' "${made[@]##*/}"))"
        fi
    else
        fail own-build "see the end of the log: $(tail -3 "$work/own-build.log" | tr '\n' ' ')"
    fi

    if [[ -f "$orpms/$own/build-info" ]]; then
        # Installed, in the manifest, from the spec
        if install_run "$oscripts" "$orpms" "$work/own-install.log" &&
            sed -n '/^Borshevik packages installed:/,$p' "$work/own-install.log" | grep -q "^  $own-$ovr\..* from $own.spec="; then
            ok "own-install ($(sed -n '/^Borshevik packages installed:/,$p' "$work/own-install.log" | grep ' from ' | cut -d' ' -f3 | tr '\n' ' '))"
        else
            fail own-install "see the end of the log: $(tail -3 "$work/own-install.log" | tr '\n' ' ')"
        fi

        # A spec whose version moved on since the build
        d="$(only own-version "$own")"
        sed -i -E 's/^(Release:[[:space:]]*).*/\1999/' "$d/borshevik-packages/$own/$own.spec"
        expect_refusal own-version install-borshevik-packages "made before the spec changed" \
            install_run "$d" "$orpms" "$work/own-version.log"

        # A spec changed since the build at the same version
        d="$(only own-changed "$own")"
        echo "# changed after the build" >>"$d/borshevik-packages/$own/$own.spec"
        expect_refusal own-changed install-borshevik-packages "other patches, files or scripts" \
            install_run "$d" "$orpms" "$work/own-changed.log"
    else
        fail own-install "no build to install"
    fi
fi

[[ "$failed" -eq 0 ]] && echo "all checks pass"
exit "$failed"
