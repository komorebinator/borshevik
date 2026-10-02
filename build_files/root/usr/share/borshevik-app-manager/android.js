// The android kind: whether Android (its module) is installed, and Android
// apps installed into it as the user, without privileges. Installing Android
// itself is borshevik-modules' (see window.js, _prepareKinds).

import Gio from "gi://Gio";
import GLib from "gi://GLib";

import { fetchBytes } from "./net.js";

export const MODULE = "android";

const STAMP = "/var/lib/borshevik/waydroid-installed";
const SESSION_TIMEOUT_S = 120;
const BOOT_TIMEOUT_S = 180;
const INSTALL_TIMEOUT_S = 60;

function strip(s) {
  return (s ?? "").toString().replace(/\r/g, "").trim();
}

function str(v) {
  return typeof v === "string" && v.trim() !== "";
}

// An entry this version can install: a package name, an APK and its checksum.
export function isValid(entry) {
  return str(entry?.id) && str(entry?.url) && /^[0-9a-f]{64}$/.test(String(entry?.sha256 ?? ""));
}

// The same test the Image Manager uses: the stamp borshevik-waydroid writes
// last when it installs Android.
export function isReady() {
  return Gio.File.new_for_path(STAMP).query_exists(null);
}

async function run(argv, cancelCtl = null) {
  const proc = Gio.Subprocess.new(
    argv,
    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
  );
  if (cancelCtl) cancelCtl.currentProc = proc;
  try {
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
  } finally {
    if (cancelCtl) cancelCtl.currentProc = null;
  }
}

function sleep(ms) {
  return new Promise((resolve) => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
    resolve();
    return GLib.SOURCE_REMOVE;
  }));
}

async function sessionRunning() {
  const res = await run(["waydroid", "status"]);
  return /^Session:\s*RUNNING/m.test(res.stdout);
}

// Starts a session in the background and waits for it to report itself running.
async function startSession() {
  Gio.Subprocess.new(["waydroid", "session", "start"], Gio.SubprocessFlags.NONE);
  for (let waited = 0; waited < SESSION_TIMEOUT_S; waited += 2) {
    if (await sessionRunning())
      return;
    await sleep(2000);
  }
  throw new Error("Android did not start");
}

// A session reports itself running as soon as the container is up, while Android
// is still booting; `waydroid app install` then does nothing and says nothing.
async function waitBooted() {
  for (let waited = 0; waited < BOOT_TIMEOUT_S; waited += 3) {
    const res = await run(["waydroid", "prop", "get", "sys.boot_completed"]);
    if (strip(res.stdout) === "1")
      return;
    await sleep(3000);
  }
  throw new Error("Android did not finish starting");
}

async function installedPackages() {
  const res = await run(["waydroid", "app", "list"]);
  if (!res.ok)
    throw new Error(strip(res.stderr) || strip(res.stdout) || `waydroid exited ${res.exitStatus}`);
  const out = new Set();
  for (const line of res.stdout.split("\n")) {
    const m = line.match(/^packageName:\s*(\S+)/);
    if (m) out.add(m[1]);
  }
  return out;
}

// The package list once it shows `id`, or as it stands after the timeout.
async function waitForPackage(id) {
  let present = new Set();
  for (let waited = 0; waited < INSTALL_TIMEOUT_S; waited += 3) {
    present = await installedPackages();
    if (present.has(id))
      return present;
    await sleep(3000);
  }
  return present;
}

function apkCacheDir() {
  const dir = GLib.build_filenamev([GLib.get_user_cache_dir(), "borshevik-app-manager", "apk"]);
  try { Gio.File.new_for_path(dir).make_directory_with_parents(null); } catch {}
  return dir;
}

// Downloads the entry's APK and refuses it unless its SHA-256 is the one the
// list names: the list points at a binary on someone else's server, and the
// checksum is what makes it the file the list's maintainer checked.
async function downloadApk(entry) {
  const bytes = await fetchBytes(entry.url, 120000);
  const data = bytes.get_data();
  const sum = GLib.compute_checksum_for_data(GLib.ChecksumType.SHA256, data);
  if (sum !== entry.sha256)
    throw new Error(`checksum mismatch: expected ${entry.sha256}, got ${sum}`);

  const path = GLib.build_filenamev([apkCacheDir(), `${entry.id}.apk`]);
  const file = Gio.File.new_for_path(path);
  await new Promise((resolve, reject) => {
    file.replace_contents_bytes_async(
      bytes, null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null,
      (f, res) => { try { f.replace_contents_finish(res); resolve(); } catch (e) { reject(e); } }
    );
  });
  return path;
}

export function displayName(entry) {
  return str(entry?.name) ? `${entry.name} (${entry.id})` : String(entry?.id ?? "");
}

/**
 * Install Android apps one at a time, skipping the ones already installed.
 * Starts a session when none runs, and stops it at the end if it started it.
 * Returns the same shape as flatpak.js installApps.
 */
export async function installApps(entries, onStep, cancelCtl = null) {
  const total = entries.length;
  const installed = [];
  const alreadyInstalled = [];
  const failed = [];
  let cancelled = false;

  let startedSession = false;
  let present = new Set();
  try {
    if (!(await sessionRunning())) {
      onStep?.({ starting: true, idx: 0, total });
      await startSession();
      startedSession = true;
    }
    await waitBooted();
    present = await installedPackages();
  } catch (e) {
    const msg = strip(e?.message ?? String(e));
    for (const entry of entries)
      failed.push({ appId: displayName(entry), error: msg || "Unknown error" });
    if (startedSession) await run(["waydroid", "session", "stop"]).catch(() => {});
    return { installed, alreadyInstalled, failed, cancelled };
  }

  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    const appId = displayName(entry);
    const idx = i + 1;

    if (cancelCtl?.cancelled) {
      cancelled = true;
      break;
    }

    if (present.has(entry.id)) {
      alreadyInstalled.push(appId);
      onStep?.({ appId, idx, total, skipped: true });
      continue;
    }

    onStep?.({ appId, idx, total, skipped: false });

    try {
      const apk = await downloadApk(entry);
      if (cancelCtl?.cancelled) {
        cancelled = true;
        break;
      }
      const res = await run(["waydroid", "app", "install", apk], cancelCtl);
      if (cancelCtl?.cancelled) {
        cancelled = true;
        break;
      }
      // `waydroid app install` returns at once and Android installs the package
      // a few seconds later — and it does not fail when Android refuses one — so
      // the package list, read until it shows the package, says whether it went in.
      present = await waitForPackage(entry.id);
      if (present.has(entry.id))
        installed.push(appId);
      else
        failed.push({ appId, error: strip(res.stderr) || strip(res.stdout) || "the package did not appear in Android" });
    } catch (e) {
      failed.push({ appId, error: strip(e?.message ?? String(e)) || "Unknown error" });
    }
  }

  if (startedSession)
    await run(["waydroid", "session", "stop"]).catch(() => {});

  return { installed, alreadyInstalled, failed, cancelled };
}
