#!/usr/bin/env bash
# Runs @ImageBuild#install-package-fixes in the base image it runs on in the build:
# with the repository's patches, which it must install printing little of its own, and
# with four patch sets made from them that it must refuse, saying why. See
# @ImageBuild#tests#package-fixes in spec/.
# Runs on the host (podman); prints `ok <case>` or `FAIL <case>: ...` per case.
set -uo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
image="ghcr.io/ublue-os/silverblue-main:${FEDORA_MAJOR_VERSION:-44}"
work="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/borshevik-package-fixes.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failed=0
ok() { echo "ok $1"; }
fail() { echo "FAIL $1: $2"; failed=1; }

shopt -s nullglob
dirs=("$repo"/build_files/scripts/package-fixes/*/*/)
((${#dirs[@]})) || { echo "no package fixes in the repository: nothing to test"; exit 0; }
srcdir="${dirs[0]%/}"             # .../package-fixes/<source>/<major>
major="$(basename "$srcdir")"
src="$(basename "$(dirname "$srcdir")")"
patches=("$srcdir"/*.patch)
first="${patches[0]}"

variant() { # name: a copy of build_files/scripts whose package-fixes holds only <source>, empty
    rm -rf "$work/$1"
    cp -a "$repo/build_files/scripts" "$work/$1"
    rm -rf "$work/$1/package-fixes"
    mkdir -p "$work/$1/package-fixes/$src"
    echo "$work/$1/package-fixes/$src"
}

run() { # scripts-dir log: the base layer up to this step, as far as the step depends on it
    podman run --rm --security-opt label=disable -v "$1:/build_scripts:ro" "$image" bash -c \
        '/build_scripts/configure-repos.sh && dnf -y install mutter-devkit && /build_scripts/install-package-fixes.sh' \
        >"$2" 2>&1
}

expect_refusal() { # case pattern: the case's scripts must be refused with a message matching pattern
    if run "$work/$1" "$work/$1.log"; then
        fail "$1" "installed, should have refused"
    elif grep -qE "^install-package-fixes: .*$2" "$work/$1.log"; then
        ok "$1 ($(grep -m1 '^install-package-fixes: ' "$work/$1.log" | cut -c24-))"
    else
        fail "$1" "refused otherwise: $(grep -m1 -E '^install-package-fixes: |error' "$work/$1.log")"
    fi
}

# The repository's own patches: installed, each subpackage at the suffixed release
if run "$repo/build_files/scripts" "$work/install.log" &&
    grep -q 'digests signatures OK' "$work/install.log" &&
    sed -n '/^Package fixes installed:/,$p' "$work/install.log" | grep -q "^  $src-.*\.borshevik\..* replaces "; then
    ok "install ($(sed -n '/^Package fixes installed:/,$p' "$work/install.log" | grep -c ' replaces ') packages)"
else
    fail install "see the end of the log: $(tail -3 "$work/install.log" | tr '\n' ' ')"
fi
# ...printing its own account only, not the package manager's and the build's output
own="$(sed -n "/^== $src\$/,\$p" "$work/install.log" | wc -l)"
((own > 0 && own < 100)) && ok "quiet ($own lines)" || fail quiet "the script printed $own lines"

# No folder for the major version the image has, as when the next major arrives
d="$(variant major)"; mkdir -p "$d/$((major - 1))"; cp "${patches[@]}" "$d/$((major - 1))/"
expect_refusal major "port its patches to package-fixes/$src/$major/"

# A patch the source already carries: the first patch turned around, so the source
# as Fedora ships it is what that patch would produce
d="$(variant upstream)"; mkdir -p "$d/$major"
python3 - "$first" >"$d/$major/0001-reversed.patch" <<'PY'
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
python3 - "$d/$major/0001-reversed.patch" <<'PY'
import sys
lines = open(sys.argv[1]).readlines()
for i in range(len(lines) - 1):
    if lines[i].startswith("+++ b/") and lines[i + 1].startswith("--- a/"):
        lines[i], lines[i + 1] = lines[i + 1], lines[i]
open(sys.argv[1], "w").writelines(lines)
PY
expect_refusal upstream "is already in"

# A patch whose context the source does not have
d="$(variant conflict)"; mkdir -p "$d/$major"
awk 'BEGIN { h = 0; d = 0 } /^@@/ { h = 1 } { if (h && !d && /^ ./) { print $0 " /* changed */"; d = 1 } else print }' \
    "$first" >"$d/$major/0001-conflict.patch"
expect_refusal conflict "conflicts with"

# A patch that applies but does not build: the build stops, and what it prints shows why
d="$(variant build-fails)"; mkdir -p "$d/$major"
python3 - "$first" >"$d/$major/0001-build-fails.patch" <<'PY'
import re, sys
done = False
for line in open(sys.argv[1]):
    m = None if done else re.match(r"@@ -(\S+) \+(\d+)(?:,(\d+))? @@(.*)", line, re.S)
    if m:
        count = int(m[3]) if m[3] is not None else 1
        sys.stdout.write(f"@@ -{m[1]} +{m[2]},{count + 1} @@{m[4]}")
        sys.stdout.write("+#error package-fixes test\n")
        done = True
    else:
        sys.stdout.write(line)
PY
expect_refusal build-fails "the rebuild of $src"
if grep -q '#error package-fixes test' "$work/build-fails.log"; then
    ok "build-fails-reason (the compiler's error is in what it printed)"
else
    fail build-fails-reason "the compiler's error is not in what it printed"
fi

[[ "$failed" -eq 0 ]] && echo "all checks pass"
exit "$failed"
