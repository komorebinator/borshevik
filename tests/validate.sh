#!/usr/bin/env bash
# Static checks over the repository, run before a change is committed. Not tests: nothing here
# builds or boots an image — it catches what breaks silently before a build ever runs, such as a
# translation file that no longer parses (the app swallows the error and falls back to English)
# or a message key the dictionaries do not have (the user sees the key itself).
#
# Needs bash, python3 (with PyYAML), jq, gjs and desktop-file-validate — all present on Borshevik.
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."   # the repository root; every path below is relative to it

FAILED=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=1; }

APP_MANAGER=build_files/root/usr/share/borshevik-app-manager
IMAGE_MANAGER=build_files/root/usr/share/borshevik-image-manager

echo "shell syntax"
while IFS= read -r f; do
    if out="$(bash -n "$f" 2>&1)"; then pass "$f"; else fail "$f: $out"; fi
done < <(
    find build_files installer tests -type f \( -name '*.sh' -o -perm -u+x \) 2>/dev/null |
        while IFS= read -r f; do
            head -n1 "$f" | grep -qE '^#!.*\b(ba)?sh\b' && echo "$f"
        done | sort
)

echo "json"
while IFS= read -r f; do
    if out="$(jq empty "$f" 2>&1)"; then pass "$f"; else fail "$f: $out"; fi
done < <(find build_files -name '*.json' | sort)

echo "yaml"
for f in .github/workflows/*.yml .github/dependabot.yml; do
    if out="$(python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$f" 2>&1)"; then
        pass "$f"
    else
        fail "$f: $out"
    fi
done

echo "toml"
for f in *.toml; do
    if out="$(python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$f" 2>&1)"; then
        pass "$f"
    else
        fail "$f: $out"
    fi
done

echo "desktop entries"
for f in build_files/root/usr/share/applications/*.desktop; do
    if out="$(desktop-file-validate "$f" 2>&1)" && [[ -z "$out" ]]; then pass "$f"; else fail "$f: $out"; fi
done

# Every module is imported, which parses it and resolves its imports. The two main.js files are
# left out: importing them starts the application.
echo "gjs modules"
modules=()
for f in "$APP_MANAGER"/*.js "$IMAGE_MANAGER"/*.js; do
    [[ "$(basename "$f")" == main.js ]] || modules+=("$(readlink -f "$f")")
done
probe="$(mktemp --suffix=.mjs)"
trap 'rm -f "$probe"' EXIT
{
    printf 'const modules = %s;\n' "$(printf '%s\n' "${modules[@]}" | jq -R . | jq -s .)"
    cat <<'EOF'
for (const m of modules) {
    try { await import(`file://${m}`); print(`ok ${m}`); }
    catch (e) { print(`FAIL ${m}: ${e}`); }
}
EOF
} > "$probe"
while IFS= read -r line; do
    case "$line" in
        ok\ *) pass "${line#ok }" ;;
        FAIL\ *) fail "${line#FAIL }" ;;
    esac
done < <(gjs -m "$probe" 2>&1)

# Both apps fall back quietly when a key is missing — the Image Manager to English, the App
# Manager to the key itself — so an incomplete dictionary never shows up as an error anywhere.
echo "translations"
cat > "$probe" <<EOF
import { TRANSLATIONS } from "file://$(readlink -f "$APP_MANAGER/i18n.js")";
print(JSON.stringify(Object.fromEntries(Object.entries(TRANSLATIONS).map(([l, d]) => [l, Object.keys(d)]))));
EOF
app_manager_keys="$(gjs -m "$probe" 2>&1)"
while IFS= read -r line; do
    case "$line" in
        ok\ *) pass "${line#ok }" ;;
        *) fail "$line" ;;
    esac
done < <(python3 - "$APP_MANAGER" "$IMAGE_MANAGER" "$app_manager_keys" <<'EOF'
import glob, json, os, re, sys

app_manager, image_manager, app_manager_keys = sys.argv[1:4]

def used_keys(files):
    """Keys passed to t(): every quoted identifier before the first comma of the call, so a
    ternary such as t(skipped ? "a" : "b", vars) yields both."""
    keys = set()
    for f in files:
        for args in re.findall(r'\bt\(([^,)]*)', open(f, encoding='utf-8').read()):
            keys |= set(re.findall(r'[\'"]([A-Za-z_][\w.]*)[\'"]', args))
    return keys

def report(app, dictionaries, code_files):
    en = dictionaries.get('en', set())
    ok = True
    for lang, keys in sorted(dictionaries.items()):
        missing, extra = sorted(en - keys), sorted(keys - en)
        if missing or extra:
            ok = False
            print(f'{app}: {lang} differs from en — missing {missing}, not in en {extra}')
    unknown = sorted(used_keys(code_files) - en)
    if unknown:
        ok = False
        print(f'{app}: keys used in the code but absent from en: {unknown}')
    if ok:
        print(f'ok {app}: {len(dictionaries)} languages, {len(en)} keys each, every key used exists')

try:
    dictionaries = {l: set(k) for l, k in json.loads(app_manager_keys).items()}
except ValueError:
    print(f'app-manager: could not read the dictionaries from i18n.js: {app_manager_keys}')
else:
    report('app-manager', dictionaries, glob.glob(os.path.join(app_manager, '*.js')))

dictionaries = {}
for f in sorted(glob.glob(os.path.join(image_manager, 'i18n', '*.json'))):
    try:
        dictionaries[os.path.basename(f)[:-5]] = set(json.load(open(f, encoding='utf-8')))
    except ValueError as e:
        print(f'image-manager: {f} does not parse: {e}')
report('image-manager', dictionaries, glob.glob(os.path.join(image_manager, '*.js')))
EOF
)

echo
if ((FAILED)); then echo "validation failed"; exit 1; fi
echo "all checks pass"
