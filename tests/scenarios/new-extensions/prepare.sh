#!/usr/bin/env bash
# Before tester's login: makes every extension the image ships new to tester, so
# borshevik-enable-new-extensions has to enable all of them at once in the
# running shell. See @Services#extension-autoenable#vm-scenario in spec/.
set -euo pipefail

home="$(getent passwd tester | cut -d: -f6)"
# a private D-Bus session, since tester is not logged in yet; the writes go to
# tester's user-db, which then overrides the image's default list
runuser -u tester -- env -u XDG_RUNTIME_DIR HOME="$home" dbus-run-session -- sh -c '
    gsettings set org.gnome.shell enabled-extensions "[]"
    gsettings set org.gnome.shell disabled-extensions "[]"
    echo "enabled-extensions: $(gsettings get org.gnome.shell enabled-extensions)"
    echo "disabled-extensions: $(gsettings get org.gnome.shell disabled-extensions)"'
