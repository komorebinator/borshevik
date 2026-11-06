#!/usr/bin/env bash
# The vpn scenario's checks, run inside the test VM as root after tester's login and the image
# checks: Hiddify's core brings a tunnel up in VPN (TUN) mode both ways it is run - as tester,
# from the app's data folder, with the capabilities of its file, and as a system service, the
# way the app's own HiddifyAdminBG runs it in VPN mode, in the SELinux domain the file's label
# gives it - and traffic goes through the tunnel to a test server and stops when it goes down.
# Nothing leaves the machine. See @HiddifyApp#vm-scenario in spec/.
#
# The client and the server each get a network namespace of their own, joined by a veth pair:
# the tunnel's routes take all of a namespace's traffic, which in the guest's own would take
# the ssh session this script runs over. The server is a SOCKS5 proxy that answers a connection
# to 198.51.100.1:80 (TEST-NET-2, nowhere) itself with a token; with no tunnel that address
# reaches nothing.
set -u

user=tester
uid="$(id -u "$user" 2>/dev/null)" || { echo "FAIL vpn-setup: no user $user"; exit 1; }
home="$(getent passwd "$user" | cut -d: -f6)"
data="$home/.local/share/app.hiddify.com"
cli=/usr/libexec/hiddify/HiddifyCli
unit=borshevik-vpn-test
work=/var/tmp/scenario-vpn
target=198.51.100.1
token="$(cat /proc/sys/kernel/random/uuid)"
rm -rf "$work"
mkdir -p "$work"
chmod 755 "$work"

client=""
server=""
cleanup() {
    [[ -z "$client" ]] || kill "$client" 2>/dev/null
    pkill -u "$user" -x HiddifyCli 2>/dev/null
    systemctl stop "$unit" 2>/dev/null
    rm -rf "/var/lib/$unit"
    [[ -z "$server" ]] || kill "$server" 2>/dev/null
    sleep 1
    ip netns del vpn-client 2>/dev/null
    ip netns del vpn-server 2>/dev/null
}
trap cleanup EXIT

failed=0
ok() { echo "ok $1"; }
fail() { echo "FAIL $1: $2"; failed=1; }
finish() {
    [[ "$failed" -eq 0 ]] && echo "all checks pass"
    exit "$failed"
}
in_client() { ip netns exec vpn-client "$@"; }
fetch() { in_client curl -s --max-time 5 "http://$target/"; }
tun() { in_client ip -o link show type tun 2>/dev/null | awk -F': ' '{print $2}' | head -1; }

# --- the two namespaces --------------------------------------------------------------
ip netns add vpn-server
ip netns add vpn-client
ip link add vpn-c netns vpn-client type veth peer name vpn-s netns vpn-server
ip -n vpn-server addr add 10.99.0.1/24 dev vpn-s
ip -n vpn-client addr add 10.99.0.2/24 dev vpn-c
for ns in vpn-server vpn-client; do
    ip -n "$ns" link set lo up
done
ip -n vpn-server link set vpn-s up
ip -n vpn-client link set vpn-c up
ip -n vpn-client route add default via 10.99.0.1

# --- the server ----------------------------------------------------------------------
cat >"$work/server.py" <<'PY'
import socket, struct, sys, threading

host, port, target, token = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]

def read(c, n):
    b = b""
    while len(b) < n:
        part = c.recv(n - len(b))
        if not part:
            raise EOFError
        b += part
    return b

def serve(c):
    try:
        ver, n = read(c, 2)
        read(c, n)
        c.sendall(b"\x05\x00")
        ver, cmd, _, atyp = read(c, 4)
        if atyp == 1:
            addr = socket.inet_ntoa(read(c, 4))
        elif atyp == 3:
            addr = read(c, read(c, 1)[0]).decode()
        else:
            addr = socket.inet_ntop(socket.AF_INET6, read(c, 16))
        dport = struct.unpack(">H", read(c, 2))[0]
        print(f"CONNECT {addr}:{dport}", flush=True)
        if cmd != 1 or addr != target or dport != 80:
            c.sendall(b"\x05\x02\x00\x01" + bytes(6))
            return
        c.sendall(b"\x05\x00\x00\x01" + bytes(6))
        req = b""
        while b"\r\n\r\n" not in req:
            part = c.recv(4096)
            if not part:
                return
            req += part
        body = token.encode()
        c.sendall(b"HTTP/1.0 200 OK\r\nContent-Length: %d\r\n\r\n" % len(body) + body)
    except Exception as e:
        print(f"error: {e}", flush=True)
    finally:
        c.close()

s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((host, port))
s.listen()
print("listening", flush=True)
while True:
    c, _ = s.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
PY
ip netns exec vpn-server python3 "$work/server.py" 10.99.0.1 1080 "$target" "$token" >"$work/server.log" 2>&1 &
server=$!
for _ in $(seq 20); do grep -q listening "$work/server.log" && break; sleep 0.5; done
if ! grep -q listening "$work/server.log"; then
    fail vpn-setup "the test server did not start: $(tail -3 "$work/server.log" | tr '\n' ' ')"
    finish
fi

# with no tunnel, the address reaches nothing
if out="$(fetch)"; then
    fail vpn-no-tunnel "http://$target/ answered with no tunnel up: $out"
    finish
fi
ok "vpn-no-tunnel (http://$target/ reaches nothing without the tunnel)"

# --- the client, as tester, from the app's data folder --------------------------------
runuser -u "$user" -- mkdir -p "$data"
echo "socks://10.99.0.1:1080#borshevik-test" >"$work/profile.txt"
chmod 644 "$work/profile.txt"
if runuser -u "$user" -- sh -c "cd '$data' && exec '$cli' parse '$work/profile.txt' -o '$data/borshevik-test.json'" \
    >"$work/parse.log" 2>&1 && [[ -s "$data/borshevik-test.json" ]]; then
    ok "vpn-profile (HiddifyCli read the profile, started from $data)"
else
    fail vpn-profile "$(grep -m1 -iE 'error|fatal' "$work/parse.log" || tail -1 "$work/parse.log")"
    finish
fi

# --- a tunnel, each way HiddifyCli is run -------------------------------------------

# as tester, from the app's data folder: what the file's capabilities allow
start_user() {
    in_client runuser -u "$user" -- sh -c "cd '$data' && exec '$cli' run -c '$data/borshevik-test.json' --tun --log info" \
        >"$work/client-user.log" 2>&1 &
    client=$!
}
stop_user() {
    kill "$client" 2>/dev/null
    pkill -u "$user" -x HiddifyCli 2>/dev/null
    for _ in $(seq 10); do pgrep -u "$user" -x HiddifyCli >/dev/null || break; sleep 1; done
    client=""
}
who_user() { echo "as $user"; }

# as a system service, started by systemd like HiddifyAdminBG, with a folder of its own in
# /var/lib as that has: what the domain the file's SELinux label leads to allows
start_service() {
    : >"$work/client-service.log"
    systemd-run --quiet --collect --unit="$unit" -p NetworkNamespacePath=/run/netns/vpn-client \
        -p StateDirectory="$unit" -p WorkingDirectory="/var/lib/$unit" \
        -p StandardOutput="append:$work/client-service.log" -p StandardError="append:$work/client-service.log" \
        "$cli" run -c "$data/borshevik-test.json" --tun --log info
}
stop_service() {
    systemctl stop "$unit" 2>/dev/null
    for _ in $(seq 10); do systemctl is-active -q "$unit" || break; sleep 1; done
}
who_service() {
    local pid domain
    pid="$(systemctl show -p MainPID --value "$unit" 2>/dev/null)"
    domain="$(ps -o label= -p "${pid:-0}" 2>/dev/null | cut -d: -f3)"
    echo "as a service in ${domain:-a domain unknown, it has exited}"
}

tunnel() { # way: vpn-<way>-tunnel, -traffic and -down
    local way="$1" dev="" out="" who since
    since="$(date '+%Y-%m-%d %H:%M:%S')"
    "start_$way"
    for _ in $(seq 30); do
        dev="$(tun)"
        [[ -n "$dev" ]] && break
        sleep 1
    done
    who="$("who_$way")"
    if [[ -z "$dev" ]]; then
        fail "vpn-$way-tunnel" "no tun device, HiddifyCli ran ${who}: $(grep -m2 -iE 'error|fatal|permission|denied' "$work/client-$way.log" | tr '\n' ' ')$(journalctl --since "$since" -o cat 2>/dev/null | grep -m1 'AVC.*HiddifyCli' | sed -E 's/.*(denied .*) for .*(scontext=[^ ]*) (tcontext=[^ ]*).*/; SELinux: \1 \2 \3/')"
        "stop_$way"
        return
    fi
    ok "vpn-$way-tunnel (HiddifyCli brought up $dev, ${who})"

    # through the tunnel, the server answers for the address
    for _ in $(seq 10); do
        out="$(fetch)" && [[ "$out" == "$token" ]] && break
        sleep 1
    done
    if [[ "$out" == "$token" ]]; then
        ok "vpn-$way-traffic (http://$target/ answered through the tunnel by the test server)"
    else
        fail "vpn-$way-traffic" "got '${out:-nothing}', the server saw: $(grep CONNECT "$work/server.log" | tail -3 | tr '\n' ' ')"
    fi

    # down again
    "stop_$way"
    if [[ -z "$(tun)" ]] && ! fetch >/dev/null; then
        ok "vpn-$way-down (the tunnel went with HiddifyCli, and the address reaches nothing again)"
    else
        fail "vpn-$way-down" "tun device ${dev} still there or the address still answers"
    fi
}

tunnel user
tunnel service

finish
