#!/usr/bin/bash
set -euo pipefail

QUALIFIED_KERNEL="$(rpm -qa | grep -E '^kernel(-core)?-[0-9]' \
                     | head -n1 | sed 's/^kernel[^-]*-//')"

/usr/libexec/rpm-ostree/wrapped/dracut \
    --no-hostonly --reproducible --add ostree -v \
    --kver "$QUALIFIED_KERNEL" \
    -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
