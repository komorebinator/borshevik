# Sourced by the scripts that install RPMs nobody signed: Borshevik's own builds and
# uBlue's kmod-nvidia. rpm from Fedora 45 installs only signed packages by default;
# with_unsigned_rpms runs one command with rpm checking digests instead, and puts
# Fedora's policy back after it, whether the command succeeded or not, so the image
# keeps it. See @ImageBuild#unsigned-rpms-lib in spec/.

UNSIGNED_RPMS_MACROS=/etc/rpm/macros.borshevik-unsigned

with_unsigned_rpms() { # command...
    local status=0
    echo '%_pkgverify_level digest' >"$UNSIGNED_RPMS_MACROS"
    "$@" || status=$?
    rm -f "$UNSIGNED_RPMS_MACROS"
    return "$status"
}
