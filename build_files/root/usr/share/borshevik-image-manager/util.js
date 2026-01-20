import GLib from 'gi://GLib';
import Gio from 'gi://Gio';

function _dbusCall(conn, busName, objectPath, iface, method, parameters) {
  return new Promise((resolve, reject) => {
    conn.call(
      busName,
      objectPath,
      iface,
      method,
      parameters ?? null,
      null,
      Gio.DBusCallFlags.NONE,
      -1,
      null,
      (c, res) => {
        try {
          const value = c.call_finish(res);
          resolve(value);
        } catch (e) {
          reject(e);
        }
      }
    );
  });
}

export function readOsRelease() {
  const path = '/etc/os-release';
  try {
    const bytes = GLib.file_get_contents(path)[1];
    const text = new TextDecoder('utf-8').decode(bytes);
    const lines = text.split(/\r?\n/);
    const kv = {};
    for (const line of lines) {
      const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
      if (!m) continue;
      let val = m[2];
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'")))
        val = val.slice(1, -1);
      kv[m[1]] = val;
    }
    return kv;
  } catch {
    return {};
  }
}

export function pickLogoCandidates() {
  // Prefer SVG/PNG paths that are common for distro branding.
  return [
    '/usr/share/pixmaps/borshevik_logo.svg',
    '/usr/share/pixmaps/borshevik_logo.png',
    '/usr/share/pixmaps/borshevik-logo.svg',
    '/usr/share/pixmaps/borshevik-logo.png',
    '/usr/share/pixmaps/fedora-logo-icon.svg',
    '/usr/share/pixmaps/fedora-logo-icon.png'
  ];
}

export function firstExistingPath(paths) {
  for (const p of paths) {
    if (GLib.file_test(p, GLib.FileTest.EXISTS))
      return p;
  }
  return null;
}

export async function requestRebootInteractive() {
  // Prefer GNOME SessionManager so GNOME shows its native reboot confirmation UI.
  // This avoids pkexec prompts and does not require us to present a "busy" view.
  try {
    await _dbusCall(
      Gio.DBus.session,
      'org.gnome.SessionManager',
      '/org/gnome/SessionManager',
      'org.gnome.SessionManager',
      'Reboot',
      null
    );
    return;
  } catch (e) {
    // If the user cancels GNOME's reboot confirmation dialog, we must not fall back
    // to any other mechanism; otherwise we'd reboot even after pressing Cancel.
    const msg = (e?.message ?? '').toLowerCase();
    if (msg.includes('cancel'))
      return;

    // This app targets GNOME sessions only.
    // Surface the error to the caller so the UI can show a friendly message.
    throw e;
  }
}

export function isAuthorizationError(text) {
  const t = (text ?? '').toString().toLowerCase();
  // Common strings across rpm-ostree/polkit backends.
  return (
    t.includes('not authorized') ||
    t.includes('authentication is required') ||
    t.includes('authentication required') ||
    t.includes('polkit') ||
    t.includes('permission denied')
  );
}

function _communicateUtf8(proc, stdinText) {
  // Wrap callback-style GIO async APIs to avoid relying on implicit
  // promisification differences across GJS versions.
  return new Promise((resolve, reject) => {
    proc.communicate_utf8_async(stdinText, null, (p, res) => {
      try {
        const [, stdout, stderr] = p.communicate_utf8_finish(res);
        resolve({ stdout: stdout ?? '', stderr: stderr ?? '' });
      } catch (e) {
        reject(e);
      }
    });
  });
}

export async function runCommandCapture(argv, stdinText = null) {
  const proc = new Gio.Subprocess({
    argv,
    flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
  });
  proc.init(null);

  let stdout = '';
  let stderr = '';
  try {
    ({ stdout, stderr } = await _communicateUtf8(proc, stdinText));
  } catch (e) {
    // If communicate fails, surface the error but still attempt to collect
    // exit status for diagnostics.
    throw e;
  }

  const success = proc.get_successful();
  const exitStatus = proc.get_exit_status();

  return {
    success,
    exitStatus,
    stdout,
    stderr
  };
}
