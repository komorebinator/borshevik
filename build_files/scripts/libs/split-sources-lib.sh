# Sourced by the scripts whose dnf5 transactions can upgrade packages of the base:
# install-steam and build-base-nvidia. dnf5 upgrades a package of the base only as
# far as a dependency asks, so of one source package's binary packages some can end
# up at the updates' version and the rest at the base's - zstd 1.5.7 beside
# libzstd 1.6.0, which Steam's libzstd.i686 brought, and zstd refuses to run with.
# sync_split_sources brings the ones left behind up to the version their siblings
# already have, so the image holds no mix Fedora never built or tested.
# See @ImageBuild#split-sources-lib in spec/.

sync_split_sources() { # [dnf5 option...]
    local lagging=() nevras=() line src nevra was
    mapfile -t lagging < <(
        rpm -qa --qf '%{SOURCERPM}\t%{NAME}\t%{EPOCHNUM}\t%{ARCH}\n' |
            python3 -c '
import subprocess, sys
from collections import defaultdict

def source(srpm):  # name, version-release of a source RPM file name
    base = srpm.removesuffix(".src.rpm").removesuffix(".nosrc.rpm")
    name, version, release = base.rsplit("-", 2)
    return name, f"{version}-{release}"

def newer(a, b):  # whether version-release a is newer than b, by rpm
    out = subprocess.run(["rpm", "--eval", f"%{{lua: print(rpm.vercmp(\"{a}\", \"{b}\"))}}"],
                         capture_output=True, text=True, check=True).stdout.strip()
    return int(out) > 0

by_source = defaultdict(list)
for line in sys.stdin:
    srpm, name, epoch, arch = line.rstrip("\n").split("\t")
    if srpm == "(none)":
        continue
    src, vr = source(srpm)
    by_source[src].append((vr, name, epoch, arch))

for src, pkgs in sorted(by_source.items()):
    vrs = {vr for vr, *_ in pkgs}
    if len(vrs) < 2:
        continue
    top = vrs.pop()
    for vr in vrs:
        if newer(vr, top):
            top = vr
    for vr, name, epoch, arch in sorted(pkgs):
        if vr != top:
            print(f"{src}\t{name}-{epoch}:{top}.{arch}\t{vr}")
'
    )
    if ((${#lagging[@]} == 0)); then
        echo "Every source package's binary packages are at one version"
        return 0
    fi
    echo "Binary packages behind their source package's other ones:"
    for line in "${lagging[@]}"; do
        IFS=$'\t' read -r src nevra was <<<"$line"
        echo "  ${src}: ${nevra} (was ${was})"
        nevras+=("$nevra")
    done
    dnf5 -y --setopt=allow_vendor_change=False "$@" upgrade "${nevras[@]}"
}
