#!/usr/bin/env bash
# The App Manager's transfer of a setup between computers, outside any window:
# export-config.sh under bash and transfer.js under gjs.
# See @AppManagerApp#tests#transfer in spec/.
set -uo pipefail

cd "$(dirname "$0")/.."
APP_MANAGER="$(readlink -f build_files/root/usr/share/borshevik-app-manager)"
SCRIPT="$APP_MANAGER/export-config.sh"

failures=0
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; failures=$((failures + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

json_ok() { # file, python expression over d
    python3 -c "import json, sys; d = json.load(open(sys.argv[1])); sys.exit(0 if ($2) else 1)" "$1" 2>/dev/null
}

echo "export-config.sh"
bash "$SCRIPT" --print > "$tmp/all.json" 2>"$tmp/err"
if json_ok "$tmp/all.json" "d['borshevik-config'] == 1 and isinstance(d['applications']['flatpak'], list) and isinstance(d['modules'], list)"; then
    pass "--print: valid JSON with both categories"
else
    fail "--print: $(head -c 300 "$tmp/all.json") $(head -c 200 "$tmp/err")"
fi
bash "$SCRIPT" --print modules > "$tmp/modules.json" 2>/dev/null
if json_ok "$tmp/modules.json" "'modules' in d and 'applications' not in d"; then
    pass "--print modules: only modules"
else
    fail "--print modules: $(head -c 300 "$tmp/modules.json")"
fi
bash "$SCRIPT" --print applications > "$tmp/apps.json" 2>/dev/null
if json_ok "$tmp/apps.json" "'applications' in d and 'modules' not in d"; then
    pass "--print applications: only applications"
else
    fail "--print applications: $(head -c 300 "$tmp/apps.json")"
fi

echo "transfer.js"
cat > "$tmp/probe.js" <<EOF
import * as t from "file://$APP_MANAGER/transfer.js";
const out = {};
const code = (text) => { try { t.parseConfig(text); return "ok"; } catch (e) { return e.code ?? String(e); } };
out.good = t.parseConfig('{"borshevik-config": 1, "applications": {"flatpak": ["org.gnome.Calculator", "--system", "x"]}, "modules": ["android", "--x", "android"]}');
out.notJson = code("not json");
out.array = code("[]");
out.noVersion = code('{"applications": {"flatpak": ["org.gnome.Calculator"]}}');
out.tooNew = code('{"borshevik-config": 2, "modules": ["android"]}');
out.empty = code('{"borshevik-config": 1, "applications": {"flatpak": ["--system"]}}');
out.unknownModule = t.parseConfig('{"borshevik-config": 1, "modules": ["windows"]}');
out.thisPc = t.parseConfig(await t.readThisPc(["applications", "modules"]), { allowEmpty: true });
out.script = t.exportScript(["modules"]);
print(JSON.stringify(out));
EOF
gjs -m "$tmp/probe.js" > "$tmp/probe.json" 2>"$tmp/probe.err"
check() { # name, expression
    if json_ok "$tmp/probe.json" "$2"; then pass "$1"; else fail "$1: $(head -c 300 "$tmp/probe.json") $(head -c 300 "$tmp/probe.err")"; fi
}
check "parseConfig keeps Flathub ids and module names, nothing option-shaped" \
    "d['good'] == {'apps': [{'type': 'flatpak', 'id': 'org.gnome.Calculator'}], 'modules': ['android']}"
check "parseConfig refuses what is not JSON" "d['notJson'] == 'notJson'"
check "parseConfig refuses an array and a missing version" "d['array'] == 'notConfig' and d['noVersion'] == 'notConfig'"
check "parseConfig refuses a newer format" "d['tooNew'] == 'tooNew'"
check "parseConfig refuses a configuration with nothing to install" "d['empty'] == 'empty'"
check "parseConfig passes on a module it does not know" "d['unknownModule']['modules'] == ['windows']"
check "readThisPc gives what export-config.sh prints" \
    "sorted(a['id'] for a in d['thisPc']['apps']) == sorted(json.load(open('$tmp/all.json'))['applications']['flatpak'])"

# The script as pasted into a terminal: run by an interactive-like shell, it
# prints the same configuration as the file itself.
python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['script'], end='')" "$tmp/probe.json" > "$tmp/pasted.sh"
if head -n1 "$tmp/pasted.sh" | grep -qx "bash <<'BORSHEVIK_EXPORT'" && grep -qx 'CATEGORIES="modules"' "$tmp/pasted.sh"; then
    pass "exportScript wraps the script in a quoted here-document with the categories written in"
else
    fail "exportScript: $(head -n 3 "$tmp/pasted.sh")"
fi
env -u WAYLAND_DISPLAY -u DISPLAY PATH="/usr/bin:/bin" bash "$tmp/pasted.sh" > "$tmp/pasted.json" 2>"$tmp/pasted.err"
if json_ok "$tmp/pasted.json" "d == json.load(open('$tmp/modules.json'))"; then
    pass "the pasted script prints the same configuration, and says it could not copy without a clipboard"
else
    fail "pasted script: $(head -c 300 "$tmp/pasted.json") $(head -c 300 "$tmp/pasted.err")"
fi

echo
if [[ "$failures" -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks pass"
