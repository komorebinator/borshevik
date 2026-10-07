#!/usr/bin/bash

set -eoux pipefail

# The final layer's last step: regenerates what is derived from the image once
# everything else is in place.

# The MIME cache of the desktop entries: COPY replaced entries the base layer's
# packages installed, while the cache, written when they were installed, still
# names them as handlers, and GNOME and xdg-mime read the cache.
update-desktop-database /usr/share/applications

# The initramfs, so newly layered kernel modules and hooks are picked up.

if [[ "${KERNEL_FLAVOR:-}" == "surface" ]]; then
    KERNEL_SUFFIX="surface"
else
    KERNEL_SUFFIX=""
fi

QUALIFIED_KERNEL="$(dnf5 repoquery --installed --queryformat='%{evr}.%{arch}' "kernel${KERNEL_SUFFIX:+-${KERNEL_SUFFIX}}")"
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v --add ostree -f "/usr/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

chmod 0600 /usr/lib/modules/"$QUALIFIED_KERNEL"/initramfs.img
