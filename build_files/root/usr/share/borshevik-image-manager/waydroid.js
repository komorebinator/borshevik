// Android (Waydroid) state, read without privileges, and the commands that
// change it. The counterpart of rpm_ostree.js for @WaydroidApp.

import GLib from 'gi://GLib';

import { runCommandCapture } from './util.js';
import { formatTimestamp } from './rpm_ostree.js';

export const CONTROL = '/usr/libexec/borshevik/borshevik-waydroid';
export const UPDATE_TIMER = 'borshevik-waydroid-update.timer';

const STAMP = '/var/lib/borshevik/waydroid-installed';
const WAYDROID_CFG = '/var/lib/waydroid/waydroid.cfg';

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

// The [waydroid] section of waydroid.cfg: image build times and OTA channels.
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
    systemOta: values.system_ota || null,
    vendorOta: values.vendor_ota || null,
    imageTime: systemTime ? formatTimestamp(systemTime) : null
  };
}

async function _fetchNewest(url) {
  const res = await runCommandCapture(['curl', '-fsSL', '--max-time', '30', url]);
  if (!res.success)
    throw new Error(`${url}: ${(res.stderr || '').trim() || 'download failed'}`);
  const json = JSON.parse(res.stdout);
  const entries = Array.isArray(json?.response) ? json.response : [];
  let newest = null;
  for (const e of entries) {
    if (!newest || Number(e.datetime) > Number(newest.datetime))
      newest = e;
  }
  return newest;
}

// Compares each OTA channel's newest image with the installed one — the same
// comparison `waydroid upgrade` makes, so what is offered is what an upgrade
// would fetch. Throws when a channel cannot be read.
export async function checkForUpdate(image) {
  if (!image?.systemOta || !image?.vendorOta)
    throw new Error('waydroid.cfg names no OTA channel');

  let available = false;
  let bytes = 0;
  const pairs = [
    [image.systemOta, image.systemTime],
    [image.vendorOta, image.vendorTime]
  ];
  for (const [url, installed] of pairs) {
    const newest = await _fetchNewest(url);
    if (newest && Number(newest.datetime) > (installed ?? 0)) {
      available = true;
      bytes += Number(newest.size) || 0;
    }
  }
  return { available, downloadSize: available && bytes ? GLib.format_size(bytes) : null };
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
