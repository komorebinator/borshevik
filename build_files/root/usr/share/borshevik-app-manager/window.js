import Adw from "gi://Adw?version=1";
import Gtk from "gi://Gtk?version=4.0";
import GLib from "gi://GLib";
import GObject from "gi://GObject";
import Gdk from "gi://Gdk?version=4.0";

import Gio from "gi://Gio";

import { fetchJson, fetchBytes } from "./net.js";
import * as flatpak from "./flatpak.js";
import * as transfer from "./transfer.js";

const BUILD = "22";

// The kinds of app this version installs, in the order a run installs them.
// Every service has `isValid`, `displayName` and `installApps`. An entry of any
// other type is dropped when the list loads: Android apps come from Google Play.
const KINDS = { flatpak };

const MODULES_CMD = "/usr/libexec/borshevik/borshevik-modules";
const WAYDROID_STAMP = "/var/lib/borshevik/waydroid-installed";

// The additional modules this version offers, in the order a run installs them,
// each the name borshevik-modules installs it by.
const MODULES = [
  {
    name: "android",
    label: "Android",
    title: "moduleAndroidTitle",
    subtitle: "moduleAndroidSubtitle",
    isInstalled: () => GLib.file_test(WAYDROID_STAMP, GLib.FileTest.EXISTS),
    // Where the user goes once it is installed: the Image Manager's Android tab,
    // which walks them through registering the device with Google.
    then: ["borshevik-image-manager", "--page", "android"],
  },
];

const GSCONNECT_UUID = "gsconnect@andyholmes.github.io";
// The logo the Image Manager shows too, by the same names.
const LOGO_CANDIDATES = [
  "/usr/share/pixmaps/borshevik_logo.svg",
  "/usr/share/pixmaps/borshevik_logo.png",
];

// Tiles keep this width and follow one another, as many to a row as the
// window's width fits.
const TILE_WIDTH = 240;

const DEFAULT_WIDTH = 1080;
const DEFAULT_HEIGHT = 400;
// The other tab's column: forms read badly wider than this.
const OTHER_TAB_WIDTH = 760;

const CSS = `
.category-tile { padding: 0; }
.category-tile:checked {
  background-color: alpha(@accent_bg_color, 0.12);
  box-shadow: inset 0 0 0 2px @accent_color;
}
.category-tile .tile-check { color: @accent_color; }
`;

export const AppWindow = GObject.registerClass(
class AppWindow extends Adw.ApplicationWindow {
  _init(app, i18n) {
    super._init({
      application: app,
      title: `${i18n.t("appTitle")} (v${BUILD})`,
      default_width: DEFAULT_WIDTH,
      default_height: DEFAULT_HEIGHT,
    });

    this._i18n = i18n;
    this._categories = [];
    this._tiles = [];
    this._moduleRows = [];

    const css = new Gtk.CssProvider();
    css.load_from_string(CSS);
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css,
      Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

    // Neither stack is vertically homogeneous: each tab and page is as tall as
    // its own content, so a short one is not left stretched to a tall one.
    this._tabs = new Adw.ViewStack({ vhomogeneous: false });
    this._tabs.connect("notify::visible-child-name", () => this._fitHeight());
    this._switcher = new Adw.ViewSwitcher({ stack: this._tabs, policy: Adw.ViewSwitcherPolicy.WIDE });
    this._headerBar = new Adw.HeaderBar();
    this._headerBar.set_title_widget(this._switcher);

    this._toastOverlay = new Adw.ToastOverlay();
    this._stack = new Gtk.Stack({ transition_type: Gtk.StackTransitionType.CROSSFADE, vhomogeneous: false });

    this._toolbarView = new Adw.ToolbarView();
    this._toolbarView.add_top_bar(this._headerBar);
    this._toolbarView.set_content(this._toastOverlay);

    this._toastOverlay.set_child(this._stack);
    this.set_content(this._toolbarView);

    this._cancelCtl = { cancelled: false, currentProc: null };
    this._cacheDir = this._initIconCache();

    this._tabs.add_titled_with_icon(this._buildNewInstallationTab(), "new",
      i18n.t("tabNew"), "system-software-install-symbolic");
    this._tabs.add_titled_with_icon(this._buildOtherPcTab(), "other",
      i18n.t("tabOtherPc"), "computer-symbolic");
    this._stack.add_named(this._tabs, "tabs");
    this._buildInstallingPage();
    this._buildResultsPage();

    this._setMode("tabs");
    this._loadCategories();
  }

  _toast(text) {
    this._toastOverlay.add_toast(new Adw.Toast({ title: text, timeout: 3 }));
  }

  // Makes the window as tall as what it shows now needs, at its current width,
  // but no taller than the screen leaves room for; the tabs scroll beyond that.
  // Their scrollers report their content's height, which GTK would not raise
  // the window to by itself, as it does to a minimum.
  _fitHeight() {
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
      const width = this.get_width() || DEFAULT_WIDTH;
      const [, natural] = this._toolbarView.measure(Gtk.Orientation.VERTICAL, width);
      let limit = 0;
      try {
        const surface = this.get_surface();
        const monitor = surface ? this.get_display().get_monitor_at_surface(surface) : null;
        limit = monitor ? monitor.get_geometry().height - 96 : 0;
      } catch {}
      const height = Math.max(DEFAULT_HEIGHT, limit > 0 ? Math.min(natural, limit) : natural);
      if (!this.is_maximized() && !this.is_fullscreen())
        this.set_default_size(width, height);
      return GLib.SOURCE_REMOVE;
    });
  }

  _setMode(mode) {
    this._mode = mode;
    this._stack.set_visible_child_name(mode);
    this._fitHeight();
    this._switcher.set_visible(mode === "tabs");

    const allowClose = mode !== "installing";
    this._headerBar.set_show_end_title_buttons(allowClose);
    this._headerBar.set_show_start_title_buttons(allowClose);
    this.set_deletable(allowClose);
  }

  // ── New installation ─────────────────────────────────────────────────────

  _buildNewInstallationTab() {
    this._newStack = new Gtk.Stack({ transition_type: Gtk.StackTransitionType.CROSSFADE, vhomogeneous: false });
    this._newStack.connect("notify::visible-child-name", () => this._fitHeight());

    const loading = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 12,
      halign: Gtk.Align.CENTER,
      valign: Gtk.Align.CENTER,
    });
    loading.append(new Gtk.Spinner({ spinning: true }));
    loading.append(new Gtk.Label({ label: this._i18n.t("loadingBody"), wrap: true }));
    this._newStack.add_named(loading, "loading");

    const failed = new Adw.StatusPage({
      icon_name: "network-offline-symbolic",
      title: this._i18n.t("loadFailedTitle"),
      description: this._i18n.t("loadFailedBody"),
    });
    const failedBox = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 12, halign: Gtk.Align.CENTER });
    this._errorDetailsLabel = new Gtk.Label({ wrap: true, selectable: true, css_classes: ["dim-label"] });
    failedBox.append(this._errorDetailsLabel);
    const retry = new Gtk.Button({ label: this._i18n.t("retry"), halign: Gtk.Align.CENTER, css_classes: ["pill"] });
    retry.connect("clicked", () => this._loadCategories());
    failedBox.append(retry);
    failed.set_child(failedBox);
    this._newStack.add_named(failed, "load_error");

    // Not an Adw.PreferencesPage, which narrows its content to 600 px: the
    // tiles take the window's whole width.
    const page = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 24,
      margin_top: 24,
      margin_bottom: 24,
      margin_start: 24,
      margin_end: 24,
    });

    const welcome = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 12, halign: Gtk.Align.CENTER });
    const logo = new Gtk.Image({ pixel_size: 96 });
    const logoPath = LOGO_CANDIDATES.find((p) => GLib.file_test(p, GLib.FileTest.EXISTS));
    if (logoPath)
      logo.set_from_file(logoPath);
    else
      logo.set_from_icon_name("computer-symbolic");
    welcome.append(logo);
    welcome.append(new Gtk.Label({
      label: this._i18n.t("welcomeTitle"),
      wrap: true,
      justify: Gtk.Justification.CENTER,
      css_classes: ["title-1"],
    }));
    page.append(welcome);

    const catGroup = new Adw.PreferencesGroup({
      title: this._i18n.t("recommendedTitle"),
      description: this._i18n.t("recommendedBody"),
    });
    this._tileBox = new Adw.WrapBox({ child_spacing: 12, line_spacing: 12, justify: Adw.JustifyMode.NONE });
    catGroup.add(this._tileBox);
    page.append(catGroup);

    const modGroup = new Adw.PreferencesGroup({ title: this._i18n.t("modulesTitle") });
    for (const mod of MODULES) {
      const check = new Gtk.CheckButton({ valign: Gtk.Align.CENTER });
      check.connect("toggled", () => this._updateInstallButton());
      const row = new Adw.ActionRow({ activatable_widget: check });
      row.add_prefix(check);
      modGroup.add(row);
      this._moduleRows.push({ row, check, mod });
    }
    page.append(modGroup);
    this._refreshModules();

    const content = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL });
    content.append(new Gtk.ScrolledWindow({
      child: page,
      hscrollbar_policy: Gtk.PolicyType.NEVER,
      propagate_natural_height: true,
      vexpand: true,
    }));

    // Insensitive while nothing is selected (_updateInstallButton).
    const installBtn = this._installBtn = new Gtk.Button({
      label: this._i18n.t("installBtn"),
      sensitive: false,
      halign: Gtk.Align.CENTER,
      margin_top: 12,
      margin_bottom: 18,
      css_classes: ["suggested-action", "pill"],
    });
    installBtn.connect("clicked", () => this._onInstallClicked());
    content.append(installBtn);
    this._newStack.add_named(content, "content");

    return this._newStack;
  }

  // Module rows as the machine stands: one already installed is checked and
  // cannot be unchecked, and a run never installs it again.
  _refreshModules() {
    for (const { row, check, mod } of this._moduleRows) {
      const installed = mod.isInstalled();
      row.set_title(this._i18n.t(mod.title));
      row.set_subtitle(this._i18n.t(installed ? "moduleInstalled" : mod.subtitle));
      if (installed) check.set_active(true);
      row.set_sensitive(!installed);
    }
    this._updateInstallButton();
  }

  async _loadCategories() {
    this._newStack.set_visible_child_name("loading");
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
          // their kind needs, are dropped silently, so the list can carry kinds
          // only other App Managers install.
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

      this._renderTiles();
      this._newStack.set_visible_child_name("content");
    } catch (e) {
      this._errorDetailsLabel.set_text(String(e?.message ?? e));
      this._newStack.set_visible_child_name("load_error");
    }
  }

  // Install is sensitive only while some category or module is selected.
  _updateInstallButton() {
    if (!this._installBtn) return;
    const { apps, modules } = this._collectSelection();
    this._installBtn.set_sensitive(apps.length > 0 || modules.length > 0);
  }

  _renderTiles() {
    this._tileBox.remove_all();
    this._tiles = [];
    for (const cat of this._categories) {
      const { button, iconBox } = this._buildTile(cat);
      this._tileBox.append(button);
      this._tiles.push({ button, cat });
      button.connect("notify::active", () => this._updateInstallButton());
      this._loadIcons(cat.apps, iconBox).catch(() => {});
    }
    this._updateInstallButton();
  }

  // A category as a tile that is a toggle as a whole: its name, a check mark
  // while selected, and its apps' icons, wrapping rather than scrolling.
  _buildTile(cat) {
    const button = new Gtk.ToggleButton({
      active: cat.default,
      css_classes: ["card", "category-tile"],
      width_request: TILE_WIDTH,
      // Set, so the title's hexpand does not make the tile take the row's room.
      hexpand: false,
      valign: Gtk.Align.START,
    });

    const box = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 10,
      margin_top: 12,
      margin_bottom: 12,
      margin_start: 14,
      margin_end: 14,
    });

    const header = new Gtk.Box({ spacing: 8 });
    header.append(new Gtk.Label({
      label: cat.name,
      xalign: 0,
      hexpand: true,
      wrap: true,
      max_width_chars: 1,
      css_classes: ["heading"],
    }));
    const check = new Gtk.Image({
      icon_name: "object-select-symbolic",
      css_classes: ["tile-check"],
      visible: button.get_active(),
    });
    header.append(check);
    box.append(header);
    button.connect("notify::active", () => check.set_visible(button.get_active()));

    // One row of icons, scrolling sideways when the category has more than fit.
    // A click on it still toggles the tile.
    const iconBox = new Gtk.Box({ spacing: 6, margin_bottom: 6, halign: Gtk.Align.START });
    const iconScroller = new Gtk.ScrolledWindow({
      child: iconBox,
      hscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
      vscrollbar_policy: Gtk.PolicyType.NEVER,
      propagate_natural_height: true,
    });
    box.append(iconScroller);

    button.set_child(box);
    return { button, iconBox };
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

    const data = await fetchJson(`https://flathub.org/api/v2/appstream/${appId}`, 10000);
    const iconUrl = typeof data?.icon === "string" ? data.icon : null;
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

  async _loadIcons(apps, iconBox) {
    // Icons appear in the list's order, whichever arrives first.
    const slots = apps.map(() => {
      const slot = new Gtk.Box({ width_request: 24, height_request: 24 });
      iconBox.append(slot);
      return slot;
    });
    await Promise.allSettled(apps.map(async (entry, i) => {
      try {
        const path = await this._fetchAppIcon(entry);
        if (!path) return;
        // pixel_size, not a size request: a picture would ask for its file's own size.
        const image = new Gtk.Image({
          paintable: Gdk.Texture.new_from_filename(path),
          pixel_size: 24,
          tooltip_text: KINDS[entry.type].displayName(entry),
        });
        slots[i].append(image);
      } catch {}
    }));
  }

  _collectSelection() {
    const apps = [];
    for (const { button, cat } of this._tiles) {
      if (button.get_active()) apps.push(...cat.apps);
    }
    const modules = this._moduleRows
      .filter(({ check, mod }) => check.get_active() && !mod.isInstalled())
      .map(({ mod }) => mod.name);
    return { apps: this._dedupe(apps), modules };
  }

  // The same type and id count once, in the order first met.
  _dedupe(apps) {
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

  _onInstallClicked() {
    const { apps, modules } = this._collectSelection();
    if (!apps.length && !modules.length) {
      this._toast(this._i18n.t("nothingSelectedToast"));
      return;
    }
    this._runInstall({ apps, modules, unsupported: [] });
  }

  // ── From another PC ──────────────────────────────────────────────────────

  _buildOtherPcTab() {
    const page = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 24,
      margin_top: 24,
      margin_bottom: 24,
      margin_start: 24,
      margin_end: 24,
    });

    const pairing = new Adw.PreferencesGroup({
      title: this._i18n.t("pairingTitle"),
      description: this._i18n.t("pairingBody"),
    });
    const pairRow = new Adw.ActionRow({
      title: "GSConnect",
      subtitle: this._i18n.t("pairingRowSubtitle"),
    });
    const pairBtn = new Gtk.Button({ label: this._i18n.t("openGsconnectBtn"), valign: Gtk.Align.CENTER });
    pairBtn.connect("clicked", () => this._openGsconnect());
    pairRow.add_suffix(pairBtn);
    pairing.add(pairRow);
    page.append(pairing);

    const exportGroup = new Adw.PreferencesGroup({
      title: this._i18n.t("exportTitle"),
      description: this._i18n.t("exportBody"),
    });
    // Both insensitive while no category is checked.
    const exportButtons = new Gtk.Box({ spacing: 12, margin_top: 12, homogeneous: true });
    const copyConfig = new Gtk.Button({ label: this._i18n.t("copyConfigBtn"), css_classes: ["suggested-action"] });
    copyConfig.connect("clicked", () => this._onCopyConfig());
    exportButtons.append(copyConfig);
    const copyScript = new Gtk.Button({ label: this._i18n.t("copyScriptBtn") });
    copyScript.connect("clicked", () => this._onCopyScript());
    exportButtons.append(copyScript);
    this._exportChecks = {};
    for (const category of transfer.CATEGORIES) {
      const check = new Gtk.CheckButton({ active: true, valign: Gtk.Align.CENTER });
      check.connect("toggled", () => {
        const any = this._exportCategories().length > 0;
        copyConfig.set_sensitive(any);
        copyScript.set_sensitive(any);
      });
      const row = new Adw.ActionRow({
        title: this._i18n.t(`export_${category}`),
        subtitle: this._i18n.t(`export_${category}_subtitle`),
        activatable_widget: check,
      });
      row.add_prefix(check);
      exportGroup.add(row);
      this._exportChecks[category] = check;
    }

    exportGroup.add(exportButtons);
    exportGroup.add(new Gtk.Label({
      label: this._i18n.t("copyScriptHint"),
      xalign: 0,
      wrap: true,
      margin_top: 8,
      css_classes: ["caption", "dim-label"],
    }));
    page.append(exportGroup);

    const importGroup = new Adw.PreferencesGroup({
      title: this._i18n.t("importTitle"),
      description: this._i18n.t("importBody"),
    });
    this._importBuffer = new Gtk.TextBuffer();
    const view = new Gtk.TextView({
      buffer: this._importBuffer,
      monospace: true,
      wrap_mode: Gtk.WrapMode.WORD_CHAR,
      top_margin: 8,
      bottom_margin: 8,
      left_margin: 8,
      right_margin: 8,
    });
    const scroller = new Gtk.ScrolledWindow({
      child: view,
      min_content_height: 140,
      hscrollbar_policy: Gtk.PolicyType.NEVER,
      css_classes: ["card"],
    });
    importGroup.add(scroller);
    this._importError = new Gtk.Label({
      xalign: 0,
      wrap: true,
      visible: false,
      margin_top: 8,
      css_classes: ["error"],
    });
    importGroup.add(this._importError);

    // Styled and placed as Install on the other tab: each tab's one action, and
    // likewise insensitive while there is nothing to act on — an empty box.
    const importBtn = new Gtk.Button({
      label: this._i18n.t("importBtn"),
      sensitive: false,
      halign: Gtk.Align.CENTER,
      margin_top: 18,
      css_classes: ["suggested-action", "pill"],
    });
    importBtn.connect("clicked", () => this._onImportClicked());
    this._importBuffer.connect("changed", () => {
      this._importError.set_visible(false);
      const start = this._importBuffer.get_start_iter();
      const end = this._importBuffer.get_end_iter();
      importBtn.set_sensitive((this._importBuffer.get_text(start, end, true) ?? "").trim() !== "");
    });
    importGroup.add(importBtn);
    page.append(importGroup);

    return new Gtk.ScrolledWindow({
      child: new Adw.Clamp({ child: page, maximum_size: OTHER_TAB_WIDTH }),
      hscrollbar_policy: Gtk.PolicyType.NEVER,
      propagate_natural_height: true,
      vexpand: true,
    });
  }

  _openGsconnect() {
    try {
      Gio.Subprocess.new(["gnome-extensions", "prefs", GSCONNECT_UUID], Gio.SubprocessFlags.NONE);
    } catch (e) {
      logError(e, "Opening GSConnect failed");
      this._toast(this._i18n.t("gsconnectFailedToast"));
    }
  }

  _exportCategories() {
    return transfer.CATEGORIES.filter((c) => this._exportChecks[c].get_active());
  }

  async _onCopyConfig() {
    const categories = this._exportCategories();
    if (!categories.length) {
      this._toast(this._i18n.t("nothingToExportToast"));
      return;
    }
    try {
      await this._copyToClipboard(await transfer.readThisPc(categories));
      this._toast(this._i18n.t("configCopiedToast"));
    } catch (e) {
      logError(e, "Reading this PC's configuration failed");
      this._toast(this._i18n.t("copyFailedToast"));
    }
  }

  async _onCopyScript() {
    const categories = this._exportCategories();
    if (!categories.length) {
      this._toast(this._i18n.t("nothingToExportToast"));
      return;
    }
    try {
      await this._copyToClipboard(transfer.exportScript(categories));
      this._toast(this._i18n.t("scriptCopiedToast"));
    } catch (e) {
      logError(e, "Copying the export script failed");
      this._toast(this._i18n.t("copyFailedToast"));
    }
  }

  _onImportClicked() {
    const start = this._importBuffer.get_start_iter();
    const end = this._importBuffer.get_end_iter();
    const text = (this._importBuffer.get_text(start, end, true) ?? "").trim();

    let config;
    try {
      if (!text) throw new transfer.ConfigError("blank");
      config = transfer.parseConfig(text);
    } catch (e) {
      const code = e instanceof transfer.ConfigError ? e.code : "notJson";
      this._importError.set_text(this._i18n.t(`import_${code}`));
      this._importError.set_visible(true);
      return;
    }

    const known = new Map(MODULES.map((m) => [m.name, m]));
    const modules = config.modules.filter((n) => known.has(n) && !known.get(n).isInstalled());
    const unsupported = config.modules.filter((n) => !known.has(n));
    this._runInstall({ apps: this._dedupe(config.apps), modules, unsupported });
  }

  // ── A run ────────────────────────────────────────────────────────────────

  _buildInstallingPage() {
    const box = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 12,
      margin_top: 48,
      margin_bottom: 48,
      margin_start: 96,
      margin_end: 96,
      halign: Gtk.Align.FILL,
      valign: Gtk.Align.CENTER,
    });

    box.append(new Gtk.Label({
      label: this._i18n.t("installingTitle"),
      wrap: true,
      justify: Gtk.Justification.CENTER,
      css_classes: ["title-2"],
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

    this._cancelBtn = new Gtk.Button({ label: this._i18n.t("cancelBtn"), halign: Gtk.Align.CENTER, css_classes: ["pill"] });
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
    });

    box.append(new Gtk.Label({ label: this._i18n.t("resultsTitle"), xalign: 0, css_classes: ["title-2"] }));
    box.append(new Gtk.Label({ label: this._i18n.t("resultsBody"), xalign: 0, wrap: true }));

    this._resultsText = new Gtk.TextView({
      editable: false,
      cursor_visible: false,
      wrap_mode: Gtk.WrapMode.WORD_CHAR,
      monospace: true,
      top_margin: 8,
      bottom_margin: 8,
      left_margin: 8,
      right_margin: 8,
    });
    this._resultsBuffer = this._resultsText.get_buffer();

    const scroller = new Gtk.ScrolledWindow({
      child: this._resultsText,
      hscrollbar_policy: Gtk.PolicyType.NEVER,
      min_content_height: 280,
      vexpand: true,
      css_classes: ["card"],
    });
    box.append(scroller);

    const actions = new Gtk.Box({ spacing: 12, halign: Gtk.Align.END });

    const copyReport = new Gtk.Button({ label: this._i18n.t("copyResultsBtn") });
    copyReport.connect("clicked", async () => {
      try {
        const start = this._resultsBuffer.get_start_iter();
        const end = this._resultsBuffer.get_end_iter();
        await this._copyToClipboard(this._resultsBuffer.get_text(start, end, true) ?? "");
        this._toast(this._i18n.t("reportCopiedToast"));
      } catch (e) {
        logError(e, "Copy report failed");
        this._toast(this._i18n.t("copyFailedToast"));
      }
    });
    actions.append(copyReport);

    const ok = new Gtk.Button({ label: this._i18n.t("ok"), css_classes: ["suggested-action"] });
    ok.connect("clicked", () => this._setMode("tabs"));
    actions.append(ok);

    box.append(actions);

    this._stack.add_named(box, "results");
  }

  _requestCancel() {
    this._cancelCtl.cancelled = true;
    this._cancelBtn.set_sensitive(false);
    this._installStatus.set_text(this._i18n.t("cancelling"));

    try { this._cancelCtl.currentProc?.force_exit(); } catch {}
  }

  _moduleLabel(name) {
    return MODULES.find((m) => m.name === name)?.label ?? name;
  }

  _formatReport(result) {
    const lines = [];
    if (result.cancelled) lines.push(this._i18n.t("canceledNote"), "");

    if (result.modules.installed.length || result.modules.failed.length || result.modules.unsupported.length) {
      lines.push(`${this._i18n.t("modulesTitle")}:`);
      for (const m of result.modules.installed) lines.push(`  + ${this._moduleLabel(m)}`);
      for (const f of result.modules.failed) {
        lines.push(`  - ${this._moduleLabel(f.name)}`);
        if (f.error) lines.push(`      ${f.error}`);
      }
      for (const m of result.modules.unsupported) lines.push(`  ? ${m}: ${this._i18n.t("moduleUnsupported")}`);
      lines.push("");
    }

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
  // progress. Returns { refused, installed: [name], failed: [{name, error}] }.
  async _runModules(modules) {
    if (!modules.length)
      return { refused: false, installed: [], failed: [] };

    this._installStatus.set_text(this._i18n.t("preparing"));
    this._moduleOutput.set_text("");
    this._moduleOutput.set_visible(true);
    this._cancelBtn.set_sensitive(false);
    this._setMode("installing");

    const results = {};
    let status = -1;
    try {
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
          this._installStatus.set_text(this._i18n.t("installingModuleFmt", { module: this._moduleLabel(current) }));
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
      status = proc.get_exit_status();
    } catch (e) {
      logError(e, "borshevik-modules failed");
    } finally {
      this._moduleOutput.set_visible(false);
      this._cancelBtn.set_sensitive(true);
    }

    // pkexec returns 126 or 127 when the password is dismissed or denied;
    // borshevik-modules never does.
    if (status === 126 || status === 127)
      return { refused: true, installed: [], failed: [] };

    const installed = [];
    const failed = [];
    for (const name of modules) {
      const r = results[name];
      const mod = MODULES.find((m) => m.name === name);
      if (r?.ok && mod?.isInstalled())
        installed.push(name);
      else
        failed.push({
          name,
          error: this._i18n.t("moduleFailedFmt", { module: this._moduleLabel(name), details: r?.error || "" }),
        });
    }
    return { refused: false, installed, failed };
  }

  // One run, from either tab: modules first, under one password prompt, then
  // the apps kind by kind. A refused password ends it before anything happens.
  async _runInstall({ apps, modules, unsupported }) {
    this._cancelCtl.cancelled = false;
    this._cancelCtl.currentProc = null;
    this._progress.set_fraction(0);

    const mods = await this._runModules(modules);
    if (mods.refused) {
      this._setMode("tabs");
      return;
    }

    this._installStatus.set_text(this._i18n.t("preparing"));
    this._setMode("installing");

    const byType = {};
    for (const a of apps) (byType[a.type] ??= []).push(a);

    const result = {
      modules: { installed: mods.installed, failed: mods.failed, unsupported },
      installed: [], alreadyInstalled: [], failed: [], cancelled: false,
    };
    const total = apps.length;
    let done = 0;
    const onStep = ({ appId, idx, skipped = false }) => {
      this._installStatus.set_text(this._i18n.t(skipped ? "alreadyInstalledFmt" : "installingFmt",
        { app: appId, idx: done + idx, total }));
      this._progress.set_fraction(total > 0 ? (done + Math.max(idx - 1, 0)) / total : 0);
      this._repaint();
    };

    for (const type of Object.keys(KINDS)) {
      const entries = byType[type];
      if (!entries?.length) continue;

      if (this._cancelCtl.cancelled) {
        result.cancelled = true;
        break;
      }

      let installedSet = new Set();
      try {
        installedSet = new Set(await flatpak.listInstalledApps());
      } catch (e) {
        // If flatpak is missing or list fails, continue without pre-check
        logError(e, "listInstalledApps failed");
      }
      const r = await KINDS[type].installApps(entries.map((e) => e.id), onStep, this._cancelCtl, installedSet);

      result.installed.push(...r.installed);
      result.alreadyInstalled.push(...r.alreadyInstalled);
      result.failed.push(...r.failed);
      result.cancelled = result.cancelled || r.cancelled;
      done += entries.length;
    }

    this._progress.set_fraction(1);
    this._resultsBuffer.set_text(this._formatReport(result), -1);
    this._refreshModules();
    this._setMode("results");

    for (const name of mods.installed) {
      const then = MODULES.find((m) => m.name === name)?.then;
      if (!then) continue;
      try {
        Gio.Subprocess.new(then, Gio.SubprocessFlags.NONE);
      } catch (e) {
        logError(e, `Opening what follows ${name} failed`);
      }
    }
  }

  async _copyToClipboard(text) {
    const display = this.get_display() ?? Gdk.Display.get_default();
    display.get_clipboard().set_content(Gdk.ContentProvider.new_for_value(text));
  }
});
