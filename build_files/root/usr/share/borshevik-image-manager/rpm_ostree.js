// rpm-ostree integration helpers.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

function _communicateUtf8(proc, stdin = null, cancellable = null) {
  // Avoid relying on implicit promisification, which is version-sensitive in GJS.
  return new Promise((resolve, reject) => {
    try {
      // Signature: (stdin_buf, cancellable, callback)
      proc.communicate_utf8_async(stdin, cancellable, (p, res) => {
        try {
          const [ok, stdout, stderr] = p.communicate_utf8_finish(res);
          resolve({ ok: Boolean(ok), stdout: stdout ?? '', stderr: stderr ?? '' });
        } catch (e) {
          reject(e);
        }
      });
    } catch (e) {
      reject(e);
    }
  });
}

function _decodeStdout(bytes) {
  if (!bytes) return '';
  return new TextDecoder('utf-8').decode(bytes);
}

export function stripDockerTagIfPresent(ref) {
  // Handles refs like:
  // ostree-image-signed:docker://ghcr.io/user/image:stable
  // Returns the same string without the trailing :tag (unless it has a digest).
  if (!ref || ref.includes('@sha256:'))
    return ref;

  // Find the last '/' and last ':'; if ':' is after last '/', treat as tag.
  const lastSlash = ref.lastIndexOf('/');
  const lastColon = ref.lastIndexOf(':');
  if (lastColon > lastSlash) {
    return ref.slice(0, lastColon);
  }
  return ref;
}

export function extractTag(ref) {
  if (!ref || ref.includes('@sha256:'))
    return null;
  const lastSlash = ref.lastIndexOf('/');
  const lastColon = ref.lastIndexOf(':');
  if (lastColon > lastSlash)
    return ref.slice(lastColon + 1);
  return null;
}

export function buildTargetRef(baseRef, channel, customTag) {
  if (!baseRef)
    return '';
  if (baseRef.includes('@sha256:'))
    return baseRef;

  const base = stripDockerTagIfPresent(baseRef.trim());
  let tag = null;
  if (channel === 'latest') tag = 'latest';
  else if (channel === 'stable') tag = 'stable';
  else if (channel === 'custom') tag = (customTag || '').trim();

  if (!tag)
    return '';
  return `${base}:${tag}`;
}

export async function runStatusJson() {
  // Returns { ok: true, json, stdout } on success.
  // On failure returns { ok: false, error, stdout }.
  const proc = Gio.Subprocess.new(
    ['rpm-ostree', 'status', '--json'],
    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
  );

  try {
    const { ok, stdout, stderr } = await _communicateUtf8(proc);
    // Some versions report ok=true even when exit is non-zero; prefer get_successful().
    if (!proc.get_successful())
      return { ok: false, error: stderr || stdout || 'rpm-ostree status --json failed', stdout };

    const json = JSON.parse(stdout);
    return { ok: true, json, stdout };
  } catch (e) {
    // Log the full error to console for diagnostics.
    logError(e, 'rpm-ostree status --json failed');
    return { ok: false, error: String(e), stdout: '' };
  }
}

export function parseStatusJson(json) {
  // Normalizes the JSON structure we need.
  // rpm-ostree JSON typically has "deployments" array.
  const deployments = Array.isArray(json?.deployments) ? json.deployments : [];
  const booted = deployments.find(d => d.booted) || null;

  // Pending/staged deployments vary by version; we check flags.
  const staged = deployments.find(d => d.staged) || null;
  const pending = deployments.find(d => d.pending) || null;

  // Rollback should point to the previous bootable deployment.
  // IMPORTANT: If a staged/pending deployment exists, the first non-booted deployment
  // might actually be that staged deployment. We must skip staged/pending here.
  const rollback = deployments.find(d => d.rollback) || deployments.find(d => !d.booted && !d.staged && !d.pending) || null;

  return {
    booted,
    staged,
    pending,
    rollback,
    deployments
  };
}

export function inferVariantAndChannelFromOrigin(origin) {
  // origin is expected to be an image ref.
  const lower = (origin || '').toLowerCase();
  let variant = 'custom';
  if (lower.includes('ghcr.io/komorebinator/borshevik-nvidia'))
    variant = 'nvidia';
  else if (lower.includes('ghcr.io/komorebinator/borshevik'))
    variant = 'standard';

  let channel = 'custom';
  let customTag = '';

  const tag = extractTag(origin);
  if (tag === 'latest')
    channel = 'latest';
  else if (tag === 'stable')
    channel = 'stable';
  else if (tag) {
    channel = 'custom';
    customTag = tag;
  }

  // Digest refs: treat as custom.
  if (origin && origin.includes('@sha256:')) {
    channel = 'custom';
    customTag = '';
  }

  return { variant, channel, customTag };
}

export function formatTimestamp(ts) {
  // Format rpm-ostree timestamps for display.
  // We prefer a stable, readable format and avoid showing milliseconds.
  if (ts === null || ts === undefined)
    return '';

  if (typeof ts === 'string') {
    const s = ts.trim();

    // Normalize common ISO strings like: 2026-01-13T20:02:39.000Z
    // into: 2026-01-13 20:02:39
    const isoLike = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;
    if (isoLike.test(s)) {
      let out = s;
      out = out.replace(/\.\d+Z$/, 'Z');
      out = out.replace('T', ' ');
      out = out.replace(/Z$/, '');
      return out;
    }

    return s;
  }

  // Some versions may expose numeric timestamps.
  if (typeof ts === 'number' && Number.isFinite(ts)) {
    // Heuristic: treat large values as milliseconds.
    const ms = ts > 1e12 ? ts : ts * 1000;
    try {
      // Match the string formatting rules above.
      return formatTimestamp(new Date(ms).toISOString());
    } catch {
      return String(ts);
    }
  }

  return String(ts);
}

export function extractBuildTime(deployment) {
  // Keys may contain hyphens in JSON.
  return deployment?.timestamp ?? deployment?.['base-timestamp'] ?? deployment?.base_timestamp ?? '';
}

export function extractOrigin(deployment) {
  // NOTE: do NOT fall back to checksum; it is not an image reference.
  // For container-based ostree images, rpm-ostree may expose either:
  // - origin
  // - container-image-reference
  // Older versions may also provide different spellings.
  return (
    deployment?.origin ??
    deployment?.['container-image-reference'] ??
    deployment?.container_image_reference ??
    ''
  );
}

export function needsReboot(parsed) {
  // If there is a staged or pending deployment, reboot is needed.
  return Boolean(parsed?.staged || parsed?.pending);
}
