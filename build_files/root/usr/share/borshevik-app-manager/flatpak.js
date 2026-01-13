import Gio from "gi://Gio";

function strip(s) {
  return (s ?? "").toString().replace(/\r/g, "").trim();
}

export function parseCustomList(text) {
  const out = [];
  for (const line of (text ?? "").split("\n")) {
    const s = strip(line);
    if (!s || s.startsWith("#")) continue;
    const id = strip(s.split(/\s+/)[0]);
    if (id) out.push(id);
  }
  return out;
}

function spawn(argv) {
  return Gio.Subprocess.new(
    argv,
    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
  );
}

async function communicate(proc) {
  const [_ok, stdout, stderr] = await new Promise((resolve, reject) => {
    proc.communicate_utf8_async(null, null, (_p, res) => {
      try {
        resolve(proc.communicate_utf8_finish(res));
      } catch (e) {
        reject(e);
      }
    });
  });

  const exitStatus = proc.get_exit_status();
  return { ok: exitStatus === 0, exitStatus, stdout: stdout ?? "", stderr: stderr ?? "" };
}

// Old Flatpak compatible: no --separator, no --no-heading
export async function listInstalledFlathubApps() {
  const argv = ["flatpak", "list", "--app", "--columns=application,origin"];
  const proc = spawn(argv);
  const res = await communicate(proc);
  if (!res.ok)
    throw new Error(res.stderr || res.stdout || `flatpak exited ${res.exitStatus}`);

  const ids = [];
  for (const line of res.stdout.split("\n")) {
    const s = strip(line);
    if (!s) continue;

    const parts = s.split(/\s+/);
    const appId = parts[0] ?? "";
    const origin = parts[parts.length - 1] ?? "";

    // Skip header-ish lines
    const a = appId.toLowerCase();
    const o = origin.toLowerCase();
    if (a === "application" || a === "applicationid" || a === "id") continue;
    if (o === "origin") continue;

    if (!appId.includes(".")) continue;

    if (origin === "flathub") ids.push(appId);
  }
  return ids;
}

// List all installed Flatpak apps (any origin) as app IDs.
// Uses only stable flags for older Flatpak versions.
export async function listInstalledApps() {
  const argv = ["flatpak", "list", "--app", "--columns=application"];
  const proc = spawn(argv);
  const res = await communicate(proc);
  if (!res.ok)
    throw new Error(res.stderr || res.stdout || `flatpak exited ${res.exitStatus}`);

  const ids = [];
  for (const line of res.stdout.split("\n")) {
    const s = strip(line);
    if (!s) continue;

    const parts = s.split(/\s+/);
    const appId = parts[0] ?? "";
    const a = appId.toLowerCase();
    if (a === "application" || a === "applicationid" || a === "id") continue;
    if (!appId.includes(".")) continue;

    ids.push(appId);
  }
  return ids;
}


/**
 * Install apps sequentially. Does NOT stop on per-app errors.
 *
 * @param {string[]} appIds
 * @param {(info: {appId: string, idx: number, total: number}) => void} onStep
 * @param {{cancelled?: boolean, currentProc?: any}} cancelCtl
 * @returns {Promise<{installed: string[], failed: {appId: string, error: string}[], cancelled: boolean}>}
 */
export async function installApps(appIds, onStep, cancelCtl = null, installedSet = null) {
  const unique = Array.from(new Set(appIds.map((x) => String(x).trim()).filter(Boolean)));
  const total = unique.length;

  const installed = [];
  const alreadyInstalled = [];
  const failed = [];
  let cancelled = false;

  const pre = installedSet instanceof Set ? installedSet : null;

  for (let i = 0; i < unique.length; i++) {
    const appId = unique[i];

    if (cancelCtl?.cancelled) {
      cancelled = true;
      break;
    }

    const idx = i + 1;
    if (pre && pre.has(appId)) {
      alreadyInstalled.push(appId);
      onStep?.({ appId, idx, total, skipped: true });
      continue;
    }

    onStep?.({ appId, idx, total, skipped: false });

    const argv = ["flatpak", "install", "-y", "--noninteractive", "flathub", appId];
    const proc = spawn(argv);
    if (cancelCtl) cancelCtl.currentProc = proc;

    let res;
    try {
      res = await communicate(proc);
    } catch (e) {
      const msg = strip(e?.message ?? String(e));
      failed.push({ appId, error: msg || "Unknown error" });
      continue;
    } finally {
      if (cancelCtl) cancelCtl.currentProc = null;
    }

    if (cancelCtl?.cancelled) {
      cancelled = true;
      break;
    }

    if (res.ok) {
      installed.push(appId);
    } else {
      const details = strip(res.stderr) || strip(res.stdout) || `flatpak exited ${res.exitStatus}`;
      failed.push({ appId, error: details });
    }
  }

  return { installed, alreadyInstalled, failed, cancelled };
}
