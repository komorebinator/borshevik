// Android (Waydroid) state, read without privileges, and the commands that
// change it. The counterpart of rpm_ostree.js for @WaydroidApp.

import GLib from 'gi://GLib';

import { runCommandCapture } from './util.js';
import { formatTimestamp } from './rpm_ostree.js';

export const CONTROL = '/usr/libexec/borshevik/borshevik-waydroid';
export const UPDATE_TIMER = 'borshevik-waydroid-update.timer';

const STAMP = '/var/lib/borshevik/waydroid-installed';
const BUSY = '/run/borshevik/waydroid-busy';
const WAYDROID_CFG = '/var/lib/waydroid/waydroid.cfg';
const CONFIG = '/usr/share/borshevik/waydroid/config.json';

function _readText(path) {
  try {
    const [ok, bytes] = GLib.file_get_contents(path);
    return ok ? new TextDecoder('utf-8').decode(bytes) : null;
  } catch (_e) {
    return null;
  }
}

// The only test of "Android is installed": the stamp borshevik-waydroid install
// writes last, holding the Android version it installed for.
export function isInstalled() {
  const text = _readText(STAMP);
  if (text === null)
    return { installed: false, version: null };
  return { installed: true, version: text.trim() || null };
}

// The operation borshevik-waydroid is running right now — 'install',
// 'upgrade' or 'remove' — or null. The busy file holds `<operation> <pid>`
// while one runs and is empty otherwise; a pid no longer alive means one that
// crashed, not one still running.
export function busyOperation() {
  const text = _readText(BUSY);
  const m = (text ?? '').trim().match(/^(install|upgrade|remove) (\d+)$/);
  if (!m)
    return null;
  return GLib.file_test(`/proc/${m[2]}`, GLib.FileTest.EXISTS) ? m[1] : null;
}

// The installed images' build times, as waydroid.cfg records them — what
// `waydroid upgrade` itself compares against.
export function readImage() {
  const text = _readText(WAYDROID_CFG);
  if (text === null)
    return null;

  const values = {};
  let section = '';
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    const header = line.match(/^\[(.+)\]$/);
    if (header) {
      section = header[1];
      continue;
    }
    if (section !== 'waydroid')
      continue;
    const kv = line.match(/^([^=]+?)\s*=\s*(.*)$/);
    if (kv)
      values[kv[1]] = kv[2];
  }

  const systemTime = Number(values.system_datetime) || null;
  const vendorTime = Number(values.vendor_datetime) || null;
  return {
    systemTime,
    vendorTime,
    systemBuilt: systemTime ? formatTimestamp(systemTime) : null,
    vendorBuilt: vendorTime ? formatTimestamp(vendorTime) : null
  };
}

// The system and vendor images this Borshevik approves, from config.json.
function _approvedImages() {
  const text = _readText(CONFIG);
  if (text === null)
    throw new Error(`${CONFIG}: cannot read`);
  const images = JSON.parse(text)?.images;
  if (!images?.system || !images?.vendor)
    throw new Error(`${CONFIG}: no approved images`);
  return images;
}

// Compares the installed images with the pair this Borshevik approves, read
// from config.json rather than through waydroid.cfg, which on a machine
// installed earlier may still name another channel. An image differing either
// way needs updating — the same test borshevik-waydroid upgrade acts on.
export async function checkForUpdate(image) {
  const approved = _approvedImages();
  let available = false;
  let bytes = 0;
  const pairs = [
    [approved.system, image?.systemTime],
    [approved.vendor, image?.vendorTime]
  ];
  for (const [entry, installed] of pairs) {
    if (Number(entry.datetime) !== installed) {
      available = true;
      bytes += Number(entry.size) || 0;
    }
  }
  return { available, downloadSize: available && bytes ? GLib.format_size(bytes) : null };
}

// Where this Android stands with Google, read by borshevik-waydroid under
// pkexec: the ID to register it with, and whether it has signed in to a Google
// account — the one sign registration went through. `notYet` when Android has
// not checked in with Google (exit status 3); `refused` when the password was
// not given.
export async function googleStatus() {
  const res = await runCommandCapture(['pkexec', CONTROL, 'google']);
  if (res.exitStatus === 126 || res.exitStatus === 127)
    return { refused: true };
  if (res.exitStatus === 3)
    return { notYet: true };
  if (!res.success)
    throw new Error((res.stderr || '').trim() || `google exited ${res.exitStatus}`);
  const values = {};
  for (const line of (res.stdout || '').split('\n')) {
    const kv = line.match(/^(\w+)=(.*)$/);
    if (kv)
      values[kv[1]] = kv[2].trim();
  }
  if (!values.android_id)
    throw new Error('no android_id in the answer');
  return { id: values.android_id, signedIn: values.google_account === 'yes' };
}

// Asked of borshevik-waydroid rather than worked out again, so the tab's
// warning and what install does always agree.
export async function hasHardwareRendering() {
  try {
    const res = await runCommandCapture([CONTROL, 'rendering']);
    return (res.stdout || '').trim() !== 'software';
  } catch (_e) {
    return true;
  }
}
