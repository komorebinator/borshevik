// Installing an APK into Android, as the user and without privileges: reading
// what the file is, getting Android up, and installing it. The window is in
// main.js. See @WaydroidApp#apk-installer in spec/.

import Gio from "gi://Gio";
import GLib from "gi://GLib";

const STAMP = "/var/lib/borshevik/waydroid-installed";
const SESSION_TIMEOUT_S = 120;
const BOOT_TIMEOUT_S = 180;
// Long enough for the user to answer Android's own question, when Play
// Protect stops an app built for an old Android and asks whether to go on.
const INSTALL_TIMEOUT_S = 180;

// Why an install did not happen, as a code main.js turns into a message:
// notStarted, notBooted, notInstalled; `details` carries what Waydroid said.
export class InstallError extends Error {
  constructor(code, details = "") {
    super(details || code);
    this.code = code;
    this.details = details;
  }
}

// The same test the Image Manager uses: the stamp borshevik-waydroid writes
// last when it installs Android.
export function isAndroidInstalled() {
  return GLib.file_test(STAMP, GLib.FileTest.EXISTS);
}

function strip(s) {
  return (s ?? "").toString().replace(/\r/g, "").trim();
}

function run(argv) {
  return new Promise((resolve, reject) => {
    let proc;
    try {
      proc = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
    } catch (e) {
      reject(e);
      return;
    }
    proc.communicate_utf8_async(null, null, (p, res) => {
      try {
        const [, stdout, stderr] = p.communicate_utf8_finish(res);
        resolve({ ok: p.get_successful(), stdout: stdout ?? "", stderr: stderr ?? "" });
      } catch (e) {
        reject(e);
      }
    });
  });
}

function sleep(ms) {
  return new Promise((resolve) => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
    resolve();
    return GLib.SOURCE_REMOVE;
  }));
}

// Android's binary XML, read for the manifest's package and version: a string
// pool, then elements whose attributes point into it. An attribute's name can
// be stripped from the pool, so the resource map's ids name versionCode and
// versionName too.
const READ_APK = `
import json, struct, sys, zipfile

def pool(buf, off):
    _, hsz, size, count, _, flags, start, _ = struct.unpack_from("<HHIIIIII", buf, off)
    utf8 = flags & 0x100
    out = []
    for o in struct.unpack_from("<%dI" % count, buf, off + hsz):
        p = off + start + o
        if utf8:
            p += 2 if buf[p] & 0x80 else 1
            n = buf[p]
            if n & 0x80:
                n = ((n & 0x7f) << 8) | buf[p + 1]
                p += 2
            else:
                p += 1
            out.append(buf[p:p + n].decode("utf-8", "replace"))
        else:
            n = struct.unpack_from("<H", buf, p)[0]
            p += 2
            if n & 0x8000:
                n = ((n & 0x7fff) << 16) | struct.unpack_from("<H", buf, p)[0]
                p += 2
            out.append(buf[p:p + 2 * n].decode("utf-16-le", "replace"))
    return out

buf = zipfile.ZipFile(sys.argv[1]).read("AndroidManifest.xml")
if struct.unpack_from("<H", buf, 0)[0] != 0x0003:
    sys.exit("not Android binary XML")
strings, ids, found = [], [], None
off = struct.unpack_from("<H", buf, 2)[0]
while off + 8 <= len(buf) and found is None:
    kind, hsz, size = struct.unpack_from("<HHI", buf, off)
    if kind == 0x0001:
        strings = pool(buf, off)
    elif kind == 0x0180:
        ids = list(struct.unpack_from("<%dI" % ((size - hsz) // 4), buf, off + hsz))
    elif kind == 0x0102:
        name, astart, asize, count = struct.unpack_from("<IHHH", buf, off + hsz + 4)
        if strings[name] == "manifest":
            found = {}
            for i in range(count):
                a = off + hsz + astart + i * asize
                _, aname, raw, _, _, vtype, data = struct.unpack_from("<IIIHBBI", buf, a)
                key = strings[aname] if aname < len(strings) else ""
                rid = ids[aname] if aname < len(ids) else 0
                if rid == 0x0101021b:
                    key = "versionCode"
                elif rid == 0x0101021c:
                    key = "versionName"
                if raw != 0xFFFFFFFF:
                    found[key] = strings[raw]
                elif vtype == 0x03:
                    found[key] = strings[data]
                elif vtype in (0x10, 0x11):
                    found[key] = str(data)
    off += size
if not found or not found.get("package"):
    sys.exit("no package in the manifest")
print(json.dumps({"package": found["package"],
                  "version": found.get("versionName") or found.get("versionCode") or ""}))
`;

// What an APK declares itself to be: { package, version }. Throws for a file
// that is not one.
export async function readApk(path) {
  const res = await run(["python3", "-c", READ_APK, path]);
  if (!res.ok)
    throw new Error(strip(res.stderr).split("\n").pop() || "not an APK");
  return JSON.parse(res.stdout);
}

async function sessionRunning() {
  const res = await run(["waydroid", "status"]);
  return /^Session:\s*RUNNING/m.test(res.stdout);
}

// A sleeping Android has its container frozen. `waydroid app install` wakes it
// only for its own call and freezes it again at once, while Android installs
// the package after the call returns — so the install never finishes. Woken
// here instead, through the container service any user may ask, it stays
// awake until Android itself next goes to sleep.
async function wake() {
  const res = await run(["waydroid", "status"]);
  if (/^Container:\s*FROZEN/m.test(res.stdout))
    await run(["gdbus", "call", "--system", "--dest", "id.waydro.Container",
      "--object-path", "/ContainerManager", "--method", "id.waydro.ContainerManager.Unfreeze"]);
}

async function booted() {
  const res = await run(["waydroid", "prop", "get", "sys.boot_completed"]);
  return strip(res.stdout) === "1";
}

// The packages Android has, by name, from `waydroid app list`.
export async function installedPackages() {
  const res = await run(["waydroid", "app", "list"]);
  const out = new Set();
  for (const line of res.stdout.split("\n")) {
    const m = line.match(/^packageName:\s*(\S+)/);
    if (m) out.add(m[1]);
  }
  return out;
}

// Installs the APK at `path`, which declares `pkg`, telling `onStage` what it
// is doing: starting, booting, installing, verifying. Returns { updated }.
export async function installApk(path, pkg, onStage = () => {}) {
  if (!(await sessionRunning())) {
    onStage("starting");
    // Detached: the session is Android's, and outlives this window.
    Gio.Subprocess.new(["setsid", "waydroid", "session", "start"], Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
    let up = false;
    for (let waited = 0; waited < SESSION_TIMEOUT_S && !up; waited += 2) {
      await sleep(2000);
      up = await sessionRunning();
    }
    if (!up) throw new InstallError("notStarted");
  }

  // A session reports itself running while Android is still starting, and
  // `waydroid app install` then does nothing and says nothing.
  onStage("booting");
  let ready = await booted();
  for (let waited = 0; waited < BOOT_TIMEOUT_S && !ready; waited += 3) {
    await sleep(3000);
    ready = await booted();
  }
  if (!ready) throw new InstallError("notBooted");

  const had = (await installedPackages()).has(pkg);
  onStage("installing");
  await wake();
  const res = await run(["waydroid", "app", "install", path]);

  // The install returns at once and does not fail when Android refuses the
  // package, so a new one counts only once Android lists it — even when the
  // command failed, as Android may have taken the package all the same. An
  // update cannot be seen there, so it counts as done when the command
  // succeeded, and failed when it did not.
  if (had) {
    if (!res.ok)
      throw new InstallError("notInstalled", strip(res.stderr) || strip(res.stdout));
    return { updated: true };
  }
  onStage("verifying");
  for (let waited = 0; waited < INSTALL_TIMEOUT_S; waited += 3) {
    if ((await installedPackages()).has(pkg))
      return { updated: false };
    await wake();
    await sleep(3000);
  }
  throw new InstallError("notInstalled", strip(res.stderr) || strip(res.stdout));
}

export function launchApp(pkg) {
  Gio.Subprocess.new(["waydroid", "app", "launch", pkg], Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
}
