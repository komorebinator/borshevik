import Adw from "gi://Adw?version=1";
import Gtk from "gi://Gtk?version=4.0";
import GLib from "gi://GLib";
import GObject from "gi://GObject";
import Gdk from "gi://Gdk?version=4.0";

import Gio from "gi://Gio";

import { fetchJson, fetchBytes } from "./net.js";
import * as flatpak from "./flatpak.js";
import * as android from "./android.js";

const BUILD = "21";

// The kinds of app this version installs, in the order a run installs them.
// Every service has `isValid`, `displayName` and `installApps`; a kind that needs
// a module before its apps can go in also has `isReady` and a `MODULE`, the name
// borshevik-modules installs it by. flatpak has neither: the image ships Flatpak
// with Flathub set up. An entry of any other type is dropped when the list loads.
const KINDS = { flatpak, android };

const MODULES_CMD = "/usr/libexec/borshevik/borshevik-modules";

export const AppWindow = GObject.registerClass(
class AppWindow extends Adw.ApplicationWindow {
  _init(app, i18n) {
    super._init({
      application: app,
      title: `${i18n.t("appTitle")} (v${BUILD})`,
      default_width: 760,
      default_height: 760,
    });

    this._i18n = i18n;
    this._categories = [];
    this._categoryRows = []; // [{row, cat}]

    // Header bar via ToolbarView
    this._headerBar = new Adw.HeaderBar();
    this._headerBar.set_title_widget(new Adw.WindowTitle({ title: i18n.t("appTitle") }));

    this._toastOverlay = new Adw.ToastOverlay();
    this._stack = new Gtk.Stack({ transition_type: Gtk.StackTransitionType.CROSSFADE });

    this._toolbarView = new Adw.ToolbarView();
    this._toolbarView.add_top_bar(this._headerBar);
    this._toolbarView.set_content(this._toastOverlay);

    this._toastOverlay.set_child(this._stack);
    this.set_content(this._toolbarView);

    this._cancelCtl = { cancelled: false, currentProc: null };
    this._cacheDir = this._initIconCache();

    this._buildLoadingPage();
    this._buildErrorPage();
    this._buildMainPage();
    this._buildInstallingPage();
    this._buildResultsPage();

    this._setMode("loading");
    this._loadCategories();
  }

  _toast(text) {
    this._toastOverlay.add_toast(new Adw.Toast({ title: text, timeout: 3 }));
  }

  _setMode(mode) {
    this._mode = mode;
    this._stack.set_visible_child_name(mode);

    const allowClose = mode !== "installing";
    if (this._installBox) this._installBox.set_visible(mode === "main");
    this._headerBar.set_show_end_title_buttons(allowClose);
    this._headerBar.set_show_start_title_buttons(allowClose);
    this.set_deletable(allowClose);
  }

  async _loadCategories() {
    const url = "https://borshevik.org/share/applications-v2.json";
    try {
      const json = await fetchJson(url);
      if (!Array.isArray(json))
        throw new Error("Invalid JSON format (expected array)");

      this._categories = json
        .filter((x) => x && typeof x === "object")
        .map((x) => {
          const fallback = String(x.name ?? "");
          const loc = this._i18n.lang;
          const localized =
            typeof x?.[loc] === "string" && String(x[loc]).trim()
              ? String(x[loc]).trim()
              : (typeof x?.en === "string" && String(x.en).trim() ? String(x.en).trim() : fallback);

          // Entries of a kind this version does not install, or missing what
          // their kind needs, are dropped silently, so the list can gain a kind
          // before every installed App Manager knows it.
          const apps = (Array.isArray(x.apps) ? x.apps : [])
            .filter((a) => a && typeof a === "object" && Object.hasOwn(KINDS, a.type) && KINDS[a.type].isValid(a));

          return {
            name: localized || fallback,
            apps,
            default: Boolean(x.default),
          };
        })
        .filter((x) => x.name && x.apps.length);

      if (!this._categories.length)
        throw new Error("No categories found in JSON");

      this._renderCategories();
      this._setMode("main");
    } catch (e) {
      this._errorDetailsLabel.set_text(String(e?.message ?? e));
      this._setMode("load_error");
    }
  }

  _buildLoadingPage() {
    const box = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 12,
      margin_top: 48,
      margin_bottom: 48,
      margin_start: 48,
      margin_end: 48,
      halign: Gtk.Align.CENTER,
      valign: Gtk.Align.CENTER,
    });

    box.append(new Gtk.Spinner({ spinning: true }));
    box.append(new Gtk.Label({
      label: this._i18n.t("loadingTitle"),
      wrap: true,
      justify: Gtk.Justification.CENTER,
    }));
    box.append(new Gtk.Label({
      label: this._i18n.t("loadingBody"),
      wrap: true,
      justify: Gtk.Justification.CENTER,
    }));

    this._stack.add_named(box, "loading");
  }

  _buildErrorPage() {
    const box = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 12,
      margin_top: 48,
      margin_bottom: 48,
      margin_start: 48,
      margin_end: 48,
      halign: Gtk.Align.CENTER,
      valign: Gtk.Align.CENTER,
    });

    box.append(new Gtk.Label({
      label: this._i18n.t("loadFailedTitle"),
      wrap: true,
      justify: Gtk.Justification.CENTER,
    }));
    box.append(new Gtk.Label({
      label: this._i18n.t("loadFailedBody"),
      wrap: true,
      justify: Gtk.Justification.CENTER,
    }));

    this._errorDetailsLabel = new Gtk.Label({
      label: "",
      wrap: true,
      justify: Gtk.Justification.CENTER,
      selectable: true,
    });
    box.append(this._errorDetailsLabel);

    const retry = new Gtk.Button({
      label: this._i18n.t("retry"),
      halign: Gtk.Align.CENTER,
    });
    retry.connect("clicked", () => {
      this._setMode("loading");
      this._loadCategories();
    });
    box.append(retry);

    this._stack.add_named(box, "load_error");
  }
  _buildMainPage() {
    const page = new Adw.PreferencesPage();

    this._catGroup = new Adw.PreferencesGroup({
      description: this._i18n.t("welcomeBody"),
    });
    page.add(this._catGroup);

    // --- Custom (as part of categories list) ---
    // We create the custom rows here, but we will attach them to _catGroup in _renderCategories()
    // so that they always appear after the fetched categories.
    this._customSwitchRow = new Adw.SwitchRow({
      title: this._i18n.t("enableCustom"),
      active: false,
    });

    // Custom text (hidden until enabled)
    this._customBuffer = new Gtk.TextBuffer();
    this._customTextView = new Gtk.TextView({
      buffer: this._customBuffer,
      wrap_mode: Gtk.WrapMode.WORD_CHAR,
      editable: true,
      cursor_visible: true,
      top_margin: 6,
      bottom_margin: 6,
      left_margin: 6,
      right_margin: 6,
    });

    const tvScroller = new Gtk.ScrolledWindow({
      min_content_height: 160,
      hscrollbar_policy: Gtk.PolicyType.NEVER,
      vscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
    });
    tvScroller.set_child(this._customTextView);

    const tvRow = new Adw.PreferencesRow();
    tvRow.set_child(tvScroller);

    const cmd = "flatpak list --app --columns=application,origin | awk 'NR>1 && $2==\"flathub\"{print $1}'";
    const cmdBox = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 6,
      margin_top: 6,
      margin_bottom: 6,
      margin_start: 6,
      margin_end: 6,
    });
    cmdBox.append(new Gtk.Label({ label: this._i18n.t("customPlaceholder"), xalign: 0, wrap: true }));
    cmdBox.append(new Gtk.Label({ label: this._i18n.t("copyCommandLabel"), xalign: 0, wrap: true }));
    cmdBox.append(new Gtk.Label({ label: cmd, xalign: 0, wrap: true, selectable: true }));

    const cmdRow = new Adw.PreferencesRow();
    cmdRow.set_child(cmdBox);

    const copyBtn = new Gtk.Button({
      label: this._i18n.t("copyInstalledBtn"),
      halign: Gtk.Align.START,
    });
    copyBtn.connect("clicked", async () => {
      try {
        const ids = await flatpak.listInstalledFlathubApps();
        if (!ids.length) {
          this._toast(this._i18n.t("copyNoAppsToast"));
          return;
        }
        await this._copyToClipboard(ids.join("\n") + "\n");
        this._toast(this._i18n.t("copiedToast"));
      } catch (e) {
        logError(e, "Copy installed apps failed");
        this._toast(this._i18n.t("copyFailedToast"));
      }
    });

    const copyRow = new Adw.PreferencesRow();
    copyRow.set_child(copyBtn);

    this._customDetailRows = [tvRow, cmdRow, copyRow];
    this._customAllRows = [this._customSwitchRow, ...this._customDetailRows];

    const setCustomVisible = (enabled) => {
      for (const r of this._customDetailRows) r.set_visible(enabled);
      this._customTextView.set_sensitive(enabled);
      this._customTextView.set_editable(enabled);
    };
    setCustomVisible(false);
    this._customSwitchRow.connect("notify::active", () =>
      setCustomVisible(this._customSwitchRow.get_active())
    );

    const scroller = new Gtk.ScrolledWindow({
      hscrollbar_policy: Gtk.PolicyType.NEVER,
      vscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
    });
    scroller.set_child(page);
    scroller.set_vexpand(true);
    scroller.set_hexpand(true);
    // Install button placed after categories (not in a separate bottom bar)
    if (!this._installBtn) {
      this._installBtn = new Gtk.Button({
        label: this._i18n.t("installBtn"),
      });
      this._installBtn.add_css_class("suggested-action");
      this._installBtn.add_css_class("pill");
      this._installBtn.connect("clicked", () => this._onInstallClicked());
    }

    this._installBtn.set_hexpand(false);
    this._installBtn.set_halign(Gtk.Align.CENTER);

    this._installBox = new Gtk.Box({
      orientation: Gtk.Orientation.HORIZONTAL,
      halign: Gtk.Align.CENTER,
      margin_top: 12,
      margin_bottom: 18,
      margin_start: 12,
      margin_end: 12,
    });
    this._installBox.set_vexpand(false);
    this._installBox.set_valign(Gtk.Align.END);


    // Avoid multiple parenting when reloading UI
    const parent = this._installBtn.get_parent();
    if (parent) parent.remove(this._installBtn);
    this._installBox.append(this._installBtn);

    const mainBox = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 0,
    });
    mainBox.set_vexpand(true);
    mainBox.set_hexpand(true);
    mainBox.append(scroller);
    mainBox.append(this._installBox);

    this._stack.add_named(mainBox, "main");
  }


  _buildInstallingPage() {
    const box = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 12,
      margin_top: 48,
      margin_bottom: 48,
      margin_start: 48,
      margin_end: 48,
      halign: Gtk.Align.FILL,
      valign: Gtk.Align.CENTER,
    });

    box.append(new Gtk.Label({
      label: this._i18n.t("installingTitle"),
      wrap: true,
      justify: Gtk.Justification.CENTER,
    }));

    this._installStatus = new Gtk.Label({
      label: this._i18n.t("preparing"),
      wrap: true,
      justify: Gtk.Justification.CENTER,
      selectable: true,
    });
    box.append(this._installStatus);

    // The latest line of a module's own output while it installs.
    this._moduleOutput = new Gtk.Label({
      label: "",
      wrap: true,
      justify: Gtk.Justification.CENTER,
      visible: false,
      css_classes: ["caption", "dim-label"],
    });
    box.append(this._moduleOutput);

    this._progress = new Gtk.ProgressBar({ fraction: 0 });
    box.append(this._progress);

    this._cancelBtn = new Gtk.Button({ label: this._i18n.t("cancelBtn"), halign: Gtk.Align.CENTER });
    this._cancelBtn.connect("clicked", () => this._requestCancel());
    box.append(this._cancelBtn);

    this._stack.add_named(box, "installing");
  }

  _buildResultsPage() {
    const box = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 12,
      margin_top: 24,
      margin_bottom: 24,
      margin_start: 24,
      margin_end: 24,
      halign: Gtk.Align.FILL,
      valign: Gtk.Align.FILL,
    });

    box.append(new Gtk.Label({ label: this._i18n.t("resultsTitle"), xalign: 0, wrap: true }));
    this._resultsBody = new Gtk.Label({ label: this._i18n.t("resultsBody"), xalign: 0, wrap: true });
    box.append(this._resultsBody);

    this._resultsText = new Gtk.TextView({
      editable: false,
      cursor_visible: false,
      wrap_mode: Gtk.WrapMode.WORD_CHAR,
      monospace: true,
    });
    this._resultsBuffer = this._resultsText.get_buffer();

    const scroller = new Gtk.ScrolledWindow({
      min_content_height: 280,
      hscrollbar_policy: Gtk.PolicyType.NEVER,
      vscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
    });
    scroller.set_child(this._resultsText);
    scroller.set_vexpand(true);
    scroller.set_hexpand(true);
    box.append(scroller);

    const actions = new Gtk.Box({ orientation: Gtk.Orientation.HORIZONTAL, spacing: 12, halign: Gtk.Align.END });

    const copyReport = new Gtk.Button({ label: this._i18n.t("copyResultsBtn") });
    copyReport.connect("clicked", async () => {
      try {
        const start = this._resultsBuffer.get_start_iter();
        const end = this._resultsBuffer.get_end_iter();
        const text = this._resultsBuffer.get_text(start, end, true) ?? "";
        await this._copyToClipboard(text);
        this._toast(this._i18n.t("reportCopiedToast"));
      } catch (e) {
        logError(e, "Copy report failed");
        this._toast(this._i18n.t("copyFailedToast"));
      }
    });
    actions.append(copyReport);

    const ok = new Gtk.Button({ label: this._i18n.t("ok") });
    ok.connect("clicked", () => {
      // Go back to the main page (do not quit)
      try { this._installBtn?.set_sensitive(true); } catch {}
      this._setMode("main");
    });
    actions.append(ok);

    box.append(actions);

    this._stack.add_named(box, "results");
  }

  _initIconCache() {
    const dir = GLib.build_filenamev([GLib.get_user_cache_dir(), "borshevik-app-manager", "icons"]);
    try { Gio.File.new_for_path(dir).make_directory_with_parents(null); } catch {}
    return dir;
  }

  async _fetchAppIcon(entry) {
    const appId = entry.id;
    const cachePath = GLib.build_filenamev([this._cacheDir, `${entry.type}-${appId}.png`]);
    const cacheFile = Gio.File.new_for_path(cachePath);

    if (cacheFile.query_exists(null)) return cachePath;

    let iconUrl = null;
    if (entry.type === "flatpak") {
      const data = await fetchJson(`https://flathub.org/api/v2/appstream/${appId}`, 10000);
      iconUrl = typeof data?.icon === "string" ? data.icon : null;
    } else if (typeof entry.icon === "string") {
      iconUrl = entry.icon;
    }
    if (!iconUrl) return null;

    const bytes = await fetchBytes(iconUrl, 10000);

    await new Promise((resolve, reject) => {
      cacheFile.replace_contents_bytes_async(
        bytes, null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null,
        (f, res) => { try { f.replace_contents_finish(res); resolve(); } catch (e) { reject(e); } }
      );
    });
    return cachePath;
  }

  _buildCategoryRow(cat) {
    // Left: title + icon strip stacked vertically
    const leftBox = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      hexpand: true,
      margin_top: 10,
      margin_bottom: 8,
      margin_start: 12,
    });

    const title = new Gtk.Label({
      label: cat.name,
      xalign: 0,
      valign: Gtk.Align.CENTER,
    });
    leftBox.append(title);

    // Icon strip (hidden until first icon loads)
    const scrolled = new Gtk.ScrolledWindow({
      hscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
      vscrollbar_policy: Gtk.PolicyType.NEVER,
      min_content_height: 16,
      margin_top: 8,
    });

    const iconBox = new Gtk.Box({
      orientation: Gtk.Orientation.HORIZONTAL,
      spacing: 4,
    });
    scrolled.set_child(iconBox);
    leftBox.append(scrolled);

    // Switch on the right, centered vertically across full row height
    const sw = new Gtk.Switch({
      active: Boolean(cat.default),
      valign: Gtk.Align.CENTER,
      margin_end: 12,
    });

    const hbox = new Gtk.Box({ orientation: Gtk.Orientation.HORIZONTAL });
    hbox.append(leftBox);
    hbox.append(sw);

    const row = new Adw.PreferencesRow({ activatable: false });
    row.set_child(hbox);

    return { row, sw, iconBox, scrolled };
  }

  async _loadIconsForCategory(apps, iconBox) {
    await Promise.allSettled(apps.map(async (entry) => {
      try {
        const path = await this._fetchAppIcon(entry);
        if (!path) return;
        const texture = Gdk.Texture.new_from_filename(path);
        const picture = new Gtk.Picture({
          paintable: texture,
          content_fit: Gtk.ContentFit.SCALE_DOWN,
          halign: Gtk.Align.START,
          valign: Gtk.Align.CENTER,
        });
        picture.set_size_request(16, 16);
        picture.set_tooltip_text(KINDS[entry.type].displayName(entry));
        iconBox.append(picture);
      } catch {}
    }));
  }

  _clearCategoryRows() {
    for (const item of this._categoryRows ?? []) {
      try { this._catGroup.remove(item.row); } catch {}
    }
    this._categoryRows = [];
  }
  _renderCategories() {
    this._clearCategoryRows();

    // Remove custom rows if they were already added (e.g. after reload)
    if (this._customAllRows) {
      for (const r of this._customAllRows) {
        try {
          const p = r.get_parent?.();
          if (p === this._catGroup)
            this._catGroup.remove(r);
        } catch {}
      }
    }

    for (const cat of this._categories) {
      const { row, sw, iconBox } = this._buildCategoryRow(cat);
      this._catGroup.add(row);
      this._categoryRows.push({ row, sw, cat });
      this._loadIconsForCategory(cat.apps, iconBox).catch(() => {});
    }

    // Append Custom at the end of the same list
    if (this._customAllRows) {
      for (const r of this._customAllRows) this._catGroup.add(r);
    }
  }

  _getCustomText() {
    const start = this._customBuffer.get_start_iter();
    const end = this._customBuffer.get_end_iter();
    return this._customBuffer.get_text(start, end, true) ?? "";
  }

  _collectSelectedApps() {
    const apps = [];

    for (const { sw, cat } of this._categoryRows) {
      if (sw.get_active()) apps.push(...cat.apps);
    }

    if (this._customSwitchRow.get_active()) {
      for (const id of flatpak.parseCustomList(this._getCustomText()))
        apps.push({ type: "flatpak", id });
    }

    // The same type and id count once, in the order first met.
    const seen = new Set();
    const out = [];
    for (const a of apps) {
      const key = `${a.type}:${String(a.id).trim()}`;
      if (!String(a.id).trim() || seen.has(key)) continue;
      seen.add(key);
      out.push(a);
    }
    return out;
  }

  _requestCancel() {
    this._cancelCtl.cancelled = true;
    this._cancelBtn.set_sensitive(false);
    this._installStatus.set_text(this._i18n.t("cancelling"));

    try { this._cancelCtl.currentProc?.force_exit(); } catch {}
  }

  _formatReport(result) {
    const lines = [];
    if (result.cancelled) lines.push(this._i18n.t("canceledNote"), "");

    lines.push(`${this._i18n.t("alreadyInstalledHeader")}: ${result.alreadyInstalled.length}`);
    for (const a of result.alreadyInstalled) lines.push(`  = ${a}`);
    lines.push("");

    lines.push(`${this._i18n.t("installedHeader")}: ${result.installed.length}`);
    for (const a of result.installed) lines.push(`  + ${a}`);
    lines.push("");

    lines.push(`${this._i18n.t("failedHeader")}: ${result.failed.length}`);
    for (const f of result.failed) {
      const msg = String(f.error ?? "").replace(/\s+$/g, "");
      lines.push(`  - ${f.appId}`);
      if (msg) lines.push(`      ${msg}`);
    }
    lines.push("");
    return lines.join("\n");
  }

  _repaint() {
    const ctx = GLib.MainContext.default();
    while (ctx.pending()) ctx.iteration(false);
  }

  // Runs `pkexec borshevik-modules prepare <modules>` and follows its output:
  // `::module <name>` announces the module being installed, `::result <name>
  // ok|failed <status>` records it, and any other line is that module's own
  // progress. Returns { refused, results: { [module]: { ok, error } } }.
  async _runModules(modules) {
    const proc = Gio.Subprocess.new(
      ["pkexec", MODULES_CMD, "prepare", ...modules],
      Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE
    );
    const stream = new Gio.DataInputStream({ base_stream: proc.get_stdout_pipe() });
    const readLine = () => new Promise((resolve, reject) => {
      stream.read_line_async(GLib.PRIORITY_DEFAULT, null, (s, res) => {
        try { resolve(s.read_line_finish_utf8(res)[0]); } catch (e) { reject(e); }
      });
    });

    const results = {};
    const lastLines = {};
    let current = null;
    for (;;) {
      let line;
      try { line = await readLine(); } catch { break; }
      if (line === null) break;

      const mod = line.match(/^::module (\S+)$/);
      const result = line.match(/^::result (\S+) (ok|failed)(?: (\d+))?$/);
      if (mod) {
        current = mod[1];
        this._installStatus.set_text(this._i18n.t("installingModuleFmt", { module: this._moduleName(current) }));
        this._moduleOutput.set_text("");
      } else if (result) {
        results[result[1]] = result[2] === "ok"
          ? { ok: true, error: "" }
          : { ok: false, error: lastLines[result[1]] || `exit status ${result[3] ?? "?"}` };
      } else if (current && line.trim()) {
        lastLines[current] = line.trim();
        this._moduleOutput.set_text(line.trim());
      }
      this._progress.pulse();
    }

    await new Promise((resolve) => proc.wait_async(null, (p, res) => {
      try { p.wait_finish(res); } catch {}
      resolve();
    }));
    const status = proc.get_exit_status();
    // pkexec returns 126 or 127 when the password is dismissed or denied;
    // borshevik-modules never does.
    return { refused: status === 126 || status === 127, results };
  }

  _moduleName(module) {
    return module === android.MODULE ? "Android" : module;
  }

  // Makes sure every kind with apps in the selection can install them, before
  // any app is installed. Ready kinds need nothing, so a machine that already
  // has every module is never asked for a password. Otherwise one pkexec for all
  // missing modules. Returns { refused, failures: { [type]: error } }.
  async _prepareKinds(byType) {
    const missing = Object.keys(KINDS).filter((type) =>
      byType[type]?.length && KINDS[type].isReady && !KINDS[type].isReady());
    if (!missing.length)
      return { refused: false, failures: {} };

    this._installStatus.set_text(this._i18n.t("preparing"));
    this._moduleOutput.set_text("");
    this._moduleOutput.set_visible(true);
    this._cancelBtn.set_sensitive(false);
    this._setMode("installing");

    let run;
    try {
      run = await this._runModules(missing.map((type) => KINDS[type].MODULE));
    } catch (e) {
      logError(e, "borshevik-modules failed");
      run = { refused: false, results: {} };
    } finally {
      this._moduleOutput.set_visible(false);
      this._cancelBtn.set_sensitive(true);
    }
    if (run.refused)
      return { refused: true, failures: {} };

    const failures = {};
    for (const type of missing) {
      const r = run.results[KINDS[type].MODULE];
      if (!r || !r.ok || !KINDS[type].isReady())
        failures[type] = this._i18n.t("moduleFailedFmt", {
          module: this._moduleName(KINDS[type].MODULE),
          details: r?.error || "",
        });
    }
    return { refused: false, failures };
  }

  async _onInstallClicked() {
    const apps = this._collectSelectedApps();
    if (!apps.length) {
      this._toast(this._i18n.t("nothingSelectedToast"));
      return;
    }

    const byType = {};
    for (const a of apps) (byType[a.type] ??= []).push(a);

    this._cancelCtl.cancelled = false;
    this._cancelCtl.currentProc = null;

    this._installBtn.set_sensitive(false);
    this._cancelBtn?.set_sensitive(true);
    this._progress.set_fraction(0);

    // Stage 1: modules. A refused password ends the run before it starts.
    const prep = await this._prepareKinds(byType);
    if (prep.refused) {
      this._installBtn.set_sensitive(true);
      this._setMode("main");
      return;
    }

    this._installStatus.set_text(this._i18n.t("preparing"));
    this._setMode("installing");

    // Stage 2: apps, kind by kind.
    const result = { installed: [], alreadyInstalled: [], failed: [], cancelled: false };
    const total = apps.length;
    let done = 0;
    const onStep = ({ appId, idx, skipped = false, starting = false }) => {
      if (starting)
        this._installStatus.set_text(this._i18n.t("startingAndroid"));
      else
        this._installStatus.set_text(this._i18n.t(skipped ? "alreadyInstalledFmt" : "installingFmt",
          { app: appId, idx: done + idx, total }));
      this._progress.set_fraction(total > 0 ? (done + Math.max(idx - 1, 0)) / total : 0);
      this._repaint();
    };

    for (const type of Object.keys(KINDS)) {
      const entries = byType[type];
      if (!entries?.length) continue;

      if (result.cancelled || this._cancelCtl.cancelled) {
        result.cancelled = true;
        break;
      }

      if (prep.failures[type]) {
        for (const e of entries)
          result.failed.push({ appId: KINDS[type].displayName(e), error: prep.failures[type] });
        done += entries.length;
        continue;
      }

      let r;
      if (type === "flatpak") {
        let installedSet = new Set();
        try {
          installedSet = new Set(await flatpak.listInstalledApps());
        } catch (e) {
          // If flatpak is missing or list fails, continue without pre-check
          logError(e, "listInstalledApps failed");
        }
        r = await flatpak.installApps(entries.map((e) => e.id), onStep, this._cancelCtl, installedSet);
      } else {
        r = await KINDS[type].installApps(entries, onStep, this._cancelCtl);
      }

      result.installed.push(...r.installed);
      result.alreadyInstalled.push(...r.alreadyInstalled);
      result.failed.push(...r.failed);
      result.cancelled = result.cancelled || r.cancelled;
      done += entries.length;
    }

    this._progress.set_fraction(1);

    // Populate results page
    this._resultsBuffer.set_text(this._formatReport(result), -1);
    this._resultsBody.set_text(this._i18n.t("resultsBody"));

    this._setMode("results");
  }

  async _copyToClipboard(text) {
    const display = this.get_display() ?? Gdk.Display.get_default();
    const clipboard = display.get_clipboard();

    if (clipboard.set_text) {
      clipboard.set_text(text);
      if (clipboard.store_async) {
        await new Promise((resolve) => clipboard.store_async(null, () => resolve()));
      }
      return;
    }

    if (clipboard.set_content && Gdk.ContentProvider?.new_for_value) {
      const provider = Gdk.ContentProvider.new_for_value(text);
      clipboard.set_content(provider);
      return;
    }

    throw new Error("Clipboard API is not available in this GTK/Gdk build");
  }
});
