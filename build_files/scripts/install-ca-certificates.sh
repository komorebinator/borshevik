#!/usr/bin/env bash
set -euo pipefail

# ###########################################################################
# TEMPORARY WORKAROUND - added 2026-10-21, delete when no longer needed.
#
# Eight eMudhra intermediate CAs were compromised: their private keys could be
# derived from the public certificates (https://emudhra.we-have-a-problem.com/).
# They chain to emSign ECC Root CA - G3 and Comodo AAA Services root, which
# FIXED_EVR below is the first Fedora build to drop. Browsers are covered by
# their own revocation lists; curl, rpm-ostree, flatpak and the GJS apps read
# the system bundle and were not.
#
# The base layer upgrades nothing the uBlue base ships, so the fix would arrive
# only after Fedora pushes it to stable and Silverblue and uBlue rebuild. This
# installs it ahead of that.
#
# REMOVE WHEN: the base image itself ships FIXED_EVR or later - the script
# then only prints that it has nothing to do.
#
# TO REVERT: delete this script and its call in build-base.sh.
# ###########################################################################

FIXED_EVR="2026.2.92_v9.0.319-1.fc44"
# The very file checked against the advisory's chains on 2026-10-21.
RPM_SHA256="3d5881b39c123857cbf1283305bca2e1717f5748559ca753944a079c8c147dab"
# From Koji, not a repository: mirrors of updates-testing lag behind and fail
# the build at random, and the build leaves updates-testing once it is pushed
# to stable - before uBlue has rebuilt with it. A Koji build stays where it is.
RPM_URL="https://kojipkgs.fedoraproject.org/packages/ca-certificates/${FIXED_EVR%-*}/${FIXED_EVR##*-}/noarch/ca-certificates-${FIXED_EVR}.noarch.rpm"

installed="$(rpm -q --qf '%{EVR}' ca-certificates)"
echo "ca-certificates in the base image: ${installed}"

# rpm.vercmp: -1 when the installed build is older than the fixed one.
if [[ "$(rpm --eval "%{lua: print(rpm.vercmp('${installed}', '${FIXED_EVR}'))}")" == "-1" ]]; then
    rpm_file="/tmp/ca-certificates-${FIXED_EVR}.noarch.rpm"
    curl -fsSL --retry 5 -o "$rpm_file" "$RPM_URL"
    echo "${RPM_SHA256}  ${rpm_file}" | sha256sum -c -
    rpm-ostree override replace "$rpm_file"
    rm -f "$rpm_file"
else
    echo "Already ${FIXED_EVR} or later - this script can be removed"
fi

echo "ca-certificates now installed: $(rpm -q ca-certificates)"

# Only the emSign root is checked: Fedora already limited Comodo AAA Services
# root to e-mail and code signing, so its chains were never trusted for TLS.
# Both the trust source and the extracted bundle programs actually read.
# grep without -q: with pipefail, -q quitting early would SIGPIPE `trust` and
# turn a match into a failed pipeline, passing the very case this catches.
if trust list --filter=ca-anchors | grep 'emSign ECC Root CA - G3' >/dev/null ||
    grep -q '^# emSign ECC Root CA - G3$' /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem; then
    echo "emSign ECC Root CA - G3 is still trusted - the fix did not land" >&2
    exit 1
fi
