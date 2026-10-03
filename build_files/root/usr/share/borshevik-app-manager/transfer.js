// The configuration that carries a setup from one computer to another, and the
// two ways of producing it — both through export-config.sh, so a Borshevik
// machine and any other give the same format. See @AppManagerApp#transfer-service.

import GLib from "gi://GLib";
import Gio from "gi://Gio";

export const CONFIG_VERSION = 1;
export const CATEGORIES = ["applications", "modules"];

const SCRIPT = GLib.build_filenamev([
  GLib.path_get_dirname(GLib.filename_from_uri(import.meta.url)[0]),
  "export-config.sh",
]);
const HEREDOC_END = "BORSHEVIK_EXPORT";

// Ids of the form Flathub uses, and module names: nothing pasted can reach a
// command line as an option or a path.
const APP_ID = /^[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z_][A-Za-z0-9_-]*)+$/;
const MODULE_NAME = /^[a-z0-9][a-z0-9-]*$/;

// Why a pasted text is not a configuration to import, as a code the window
// turns into a message: notJson, notConfig, tooNew, empty.
export class ConfigError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

// Reads a configuration into { apps: [{type, id}], modules: [name] }.
export function parseConfig(text, { allowEmpty = false } = {}) {
  let json;
  try {
    json = JSON.parse(String(text ?? ""));
  } catch {
    throw new ConfigError("notJson");
  }
  if (!json || typeof json !== "object" || Array.isArray(json))
    throw new ConfigError("notConfig");
  const version = json["borshevik-config"];
  if (!Number.isInteger(version) || version < 1)
    throw new ConfigError("notConfig");
  if (version > CONFIG_VERSION)
    throw new ConfigError("tooNew");

  const apps = [];
  const flatpaks = json.applications?.flatpak;
  for (const id of Array.isArray(flatpaks) ? flatpaks : []) {
    if (typeof id === "string" && APP_ID.test(id.trim()))
      apps.push({ type: "flatpak", id: id.trim() });
  }

  const modules = [];
  for (const name of Array.isArray(json.modules) ? json.modules : []) {
    if (typeof name === "string" && MODULE_NAME.test(name) && !modules.includes(name))
      modules.push(name);
  }

  if (!allowEmpty && !apps.length && !modules.length)
    throw new ConfigError("empty");
  return { apps, modules };
}

function communicate(argv) {
  return new Promise((resolve, reject) => {
    let proc;
    try {
      proc = Gio.Subprocess.new(argv,
        Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
    } catch (e) {
      reject(e);
      return;
    }
    proc.communicate_utf8_async(null, null, (p, res) => {
      try {
        const [, stdout, stderr] = p.communicate_utf8_finish(res);
        if (!p.get_successful())
          reject(new Error((stderr || "").trim() || `export-config.sh exited ${p.get_exit_status()}`));
        else
          resolve(stdout ?? "");
      } catch (e) {
        reject(e);
      }
    });
  });
}

// This machine's configuration for the given categories, as text to copy.
export async function readThisPc(categories) {
  const text = await communicate(["bash", SCRIPT, "--print", ...categories]);
  parseConfig(text, { allowEmpty: true });
  return text;
}

// export-config.sh as text to paste into a terminal on another computer: the
// given categories written in, inside a quoted bash here-document, so it runs in
// a bash of its own and nothing in it is expanded on the way.
export function exportScript(categories) {
  const [, bytes] = GLib.file_get_contents(SCRIPT);
  const body = new TextDecoder("utf-8").decode(bytes)
    .replace(/^CATEGORIES=.*$/m, `CATEGORIES="${categories.join(" ")}"`);
  if (body.split("\n").includes(HEREDOC_END))
    throw new Error(`export-config.sh contains a line ${HEREDOC_END}`);
  return `bash <<'${HEREDOC_END}'\n${body.replace(/\n*$/, "\n")}${HEREDOC_END}\n`;
}
