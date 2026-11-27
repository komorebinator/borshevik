#!/bin/bash
# Holds packages at a version older than the one Fedora ships, each until a
# release with the fix reaches Fedora. A held version comes from the release's
# own repository, which does not change for the release's lifetime.

set -ouex pipefail

hold() { # package version-release
    local have
    have="$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$1")"
    [[ "$have" == "$2" ]] && return 0
    dnf5 -y downgrade "$1-$2"
}

# podman 6.2 adds ridmap to a CDI device's mounts under --userns keep-id, and
# crun cannot idmap a file on the composefs root: such containers never start
# (containers/podman#30233; Borshevik #101).
hold podman 6.1.3-1.fc45
