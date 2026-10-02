// The Android tab: installs, updates and removes Android (@WaydroidApp),
// reading its state through waydroid.js and changing it through
// borshevik-waydroid under pkexec, each run in a ProgressWindow.

import Adw from 'gi://Adw';
import Gdk from 'gi://Gdk';
import GLib from 'gi://GLib';
import Gtk from 'gi://Gtk';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';

import {
  CONTROL,
  UPDATE_TIMER,
  isInstalled,
  busyOperation,
  readImage,
  checkForUpdate,
  googleStatus,
  hasHardwareRendering
} from './waydroid.js';
import { runCommandCapture } from './util.js';

// Google's page for registering a device it has not certified.
const REGISTRATION_URL = 'https://www.google.com/android/uncertified';
// How often the tab looks again while an operation started elsewhere runs.
const BUSY_POLL_S = 3;

export const AndroidPage = GObject.registerClass(
class AndroidPage extends Adw.Bin {
  constructor({ window, app }) {
    super();
    this._window = window;
    this._app = app;
    this._loaded = false;

    this._android = {
      installed: false,
      busy: null,
      version: null,
      systemTime: null,
      vendorTime: null,
      check: { phase: 'idle', downloadSize: null, message: '' },
      autoUpdates: { enabled: null, busy: false },
      softwareRendering: false,
      google: { phase: 'hidden', id: null, signedIn: null, message: '' }
    };
    this._autoUpdatesGuard = false;
    this._busyPoll = 0;

    this._build();
    this.connect('destroy', () => this._stopBusyPoll());
  }

  // Called each time the tab is shown; reads the state the first time, again
  // after every operation, and whenever an operation started elsewhere has
  // begun or ended since the tab last looked.
  activate() {
    if (this._loaded && busyOperation() === this._android.busy)
      return;
    this._loaded = true;
    this._refresh().catch((e) => logError(e, 'Android state refresh failed'));
  }

  _build() {
    const i18n = this._app.i18n;

    const clamp = new Adw.Clamp({ maximum_size: 720, tightening_threshold: 560 });
    const box = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 16,
      margin_top: 20,
      margin_bottom: 20,
      margin_start: 20,
      margin_end: 20
    });

    // The waydroid icon comes with the waydroid package; fall back to a stock
    // one wherever it is missing rather than show a broken image.
    const icon = new Gtk.Image({
      gicon: Gio.ThemedIcon.new_from_names(['waydroid', 'phone-symbolic']),
      pixel_size: 96,
      halign: Gtk.Align.CENTER
    });
    box.append(icon);

    this._titleLabel = new Gtk.Label({
      label: 'Android',
      halign: Gtk.Align.CENTER,
      css_classes: ['title-1']
    });
    box.append(this._titleLabel);

    this._metaLabel = new Gtk.Label({
      halign: Gtk.Align.CENTER,
      wrap: true,
      selectable: true,
      css_classes: ['caption', 'dim-label']
    });
    box.append(this._metaLabel);

    this._renderingLabel = new Gtk.Label({
      label: i18n.t('android_software_rendering'),
      halign: Gtk.Align.CENTER,
      justify: Gtk.Justification.CENTER,
      wrap: true,
      visible: false,
      css_classes: ['warning']
    });
    box.append(this._renderingLabel);

    // An operation started elsewhere is changing Android: say which, offer
    // nothing until it ends.
    this._busyBox = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 12,
      visible: false
    });
    this._busyBox.append(new Gtk.Spinner({ spinning: true, halign: Gtk.Align.CENTER, width_request: 32, height_request: 32 }));
    this._busyLabel = new Gtk.Label({
      halign: Gtk.Align.CENTER,
      justify: Gtk.Justification.CENTER,
      wrap: true
    });
    this._busyBox.append(this._busyLabel);
    box.append(this._busyBox);

    // Not installed: what installing means, and Install.
    this._notInstalledBox = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 16,
      visible: false
    });
    this._notInstalledBox.append(new Gtk.Label({
      label: i18n.t('android_intro'),
      halign: Gtk.Align.CENTER,
      justify: Gtk.Justification.CENTER,
      wrap: true
    }));
    const installButton = new Gtk.Button({
      label: i18n.t('android_install'),
      halign: Gtk.Align.CENTER,
      width_request: 320,
      css_classes: ['suggested-action', 'pill']
    });
    installButton.connect('clicked', () => this._install());
    this._notInstalledBox.append(installButton);
    box.append(this._notInstalledBox);

    // Installed: check/update, automatic updates, remove.
    this._installedBox = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 16,
      visible: false
    });

    this._primaryStack = new Gtk.Stack({
      transition_type: Gtk.StackTransitionType.CROSSFADE,
      halign: Gtk.Align.CENTER
    });
    this._primaryButton = new Gtk.Button({
      halign: Gtk.Align.CENTER,
      width_request: 320,
      css_classes: ['suggested-action', 'pill']
    });
    this._primaryButton.connect('clicked', () => this._onPrimaryAction());
    this._primaryStack.add_named(this._primaryButton, 'button');
    this._primarySpinner = new Gtk.Spinner({ halign: Gtk.Align.CENTER });
    this._primaryStack.add_named(this._primarySpinner, 'spinner');
    this._installedBox.append(this._primaryStack);

    this._statusLabel = new Gtk.Label({
      halign: Gtk.Align.CENTER,
      wrap: true,
      selectable: true
    });
    this._installedBox.append(this._statusLabel);

    const autoGroup = new Adw.PreferencesGroup();
    this._autoUpdatesRow = new Adw.SwitchRow({
      title: i18n.t('android_auto_updates_title'),
      subtitle: i18n.t('android_auto_updates_subtitle')
    });
    this._autoUpdatesRow.connect('notify::active', () => this._onAutoUpdatesToggled());
    autoGroup.add(this._autoUpdatesRow);
    this._installedBox.append(autoGroup);

    // Google Play signs in only once this device's ID is registered with
    // Google under the user's own account; the ID needs root to read.
    const googleGroup = new Adw.PreferencesGroup({
      title: i18n.t('android_google_title'),
      description: i18n.t('android_google_description')
    });
    this._gsfRow = new Adw.ActionRow({ title: i18n.t('android_google_id_title') });
    this._gsfRow.set_activatable(false);
    this._gsfRow.set_subtitle_selectable(true);
    this._gsfStack = new Gtk.Stack({ valign: Gtk.Align.CENTER });
    const showIdButton = new Gtk.Button({
      label: i18n.t('android_google_show_id'),
      valign: Gtk.Align.CENTER
    });
    showIdButton.connect('clicked', () => this._showGsfId());
    this._gsfStack.add_named(showIdButton, 'show');
    const copyButton = new Gtk.Button({
      icon_name: 'edit-copy-symbolic',
      tooltip_text: i18n.t('android_google_copy'),
      valign: Gtk.Align.CENTER,
      css_classes: ['flat']
    });
    copyButton.connect('clicked', () => this._copyGsfId());
    this._gsfStack.add_named(copyButton, 'copy');
    this._gsfStack.add_named(new Gtk.Spinner({ spinning: true, valign: Gtk.Align.CENTER }), 'reading');
    this._gsfRow.add_suffix(this._gsfStack);
    googleGroup.add(this._gsfRow);
    // Shown once the status is read: a Google account in Android is the one
    // sign that registration went through.
    this._signInRow = new Adw.ActionRow({ title: i18n.t('android_google_signin_title'), visible: false });
    this._signInRow.set_activatable(false);
    this._signInIcon = new Gtk.Image({ valign: Gtk.Align.CENTER });
    this._signInRow.add_suffix(this._signInIcon);
    googleGroup.add(this._signInRow);
    const pageRow = new Adw.ActionRow({
      title: i18n.t('android_google_open_page'),
      subtitle: i18n.t('android_google_open_page_hint'),
      tooltip_text: REGISTRATION_URL
    });
    pageRow.add_suffix(new Gtk.Image({ icon_name: 'adw-external-link-symbolic' }));
    pageRow.set_activatable(true);
    pageRow.connect('activated', () => {
      try {
        Gio.AppInfo.launch_default_for_uri(REGISTRATION_URL, null);
      } catch (e) {
        logError(e, 'Opening the registration page failed');
      }
    });
    googleGroup.add(pageRow);
    this._installedBox.append(googleGroup);

    const removeGroup = new Adw.PreferencesGroup();
    const removeRow = new Adw.ActionRow({
      title: i18n.t('android_remove_title'),
      subtitle: i18n.t('android_remove_subtitle')
    });
    removeRow.set_activatable(false);
    const removeButton = new Gtk.Button({
      label: i18n.t('android_remove'),
      valign: Gtk.Align.CENTER,
      css_classes: ['destructive-action']
    });
    removeButton.connect('clicked', () => this._remove());
    removeRow.add_suffix(removeButton);
    removeGroup.add(removeRow);
    this._installedBox.append(removeGroup);

    box.append(this._installedBox);

    clamp.set_child(box);
    this.set_child(clamp);
  }

  async _refresh() {
    this._android.busy = busyOperation();
    if (this._android.busy) {
      this._applyState();
      this._startBusyPoll();
      return;
    }
    const state = isInstalled();
    const image = state.installed ? readImage() : null;
    this._android.installed = state.installed;
    this._android.version = state.version;
    this._android.systemTime = image?.systemBuilt ?? null;
    this._android.vendorTime = image?.vendorBuilt ?? null;
    this._android.softwareRendering = !(await hasHardwareRendering());
    this._applyState();

    if (state.installed) {
      await this._refreshAutoUpdates();
      await this._check();
    }
  }

  _applyState() {
    const i18n = this._app.i18n;
    const a = this._android;

    this._busyBox.visible = a.busy !== null;
    this._notInstalledBox.visible = a.busy === null && !a.installed;
    this._installedBox.visible = a.busy === null && a.installed;
    this._renderingLabel.visible = a.busy === null && a.softwareRendering;
    if (a.busy) {
      this._busyLabel.set_label(i18n.t({
        install: 'android_busy_install',
        upgrade: 'android_busy_upgrade',
        remove: 'android_busy_remove'
      }[a.busy]));
      this._metaLabel.visible = false;
      return;
    }

    this._titleLabel.set_label(a.installed && a.version ? `Android ${a.version}` : 'Android');
    const meta = [];
    if (a.installed && a.systemTime)
      meta.push(`${i18n.t('android_system_built')}: ${a.systemTime}`);
    if (a.installed && a.vendorTime)
      meta.push(`${i18n.t('android_vendor_built')}: ${a.vendorTime}`);
    this._metaLabel.set_label(meta.join('\n'));
    this._metaLabel.visible = meta.length > 0;

    const g = a.google;
    this._gsfStack.set_visible_child_name(
      g.phase === 'shown' ? 'copy' : g.phase === 'reading' ? 'reading' : 'show');
    if (g.phase === 'shown')
      this._gsfRow.set_subtitle(g.id);
    else if (g.phase === 'not_yet')
      this._gsfRow.set_subtitle(i18n.t('android_google_not_yet'));
    else if (g.phase === 'error')
      this._gsfRow.set_subtitle(g.message ? `${i18n.t('error')}: ${g.message}` : i18n.t('error'));
    else
      this._gsfRow.set_subtitle(i18n.t('android_google_id_hidden'));
    this._signInRow.visible = g.phase === 'shown';
    if (g.phase === 'shown') {
      this._signInRow.set_subtitle(i18n.t(g.signedIn ? 'android_google_signed_in' : 'android_google_not_signed_in'));
      this._signInIcon.set_from_icon_name(g.signedIn ? 'emblem-ok-symbolic' : 'dialog-information-symbolic');
    }

    const phase = a.check.phase;
    if (phase === 'checking') {
      this._primaryButton.set_sensitive(false);
      this._primarySpinner.start();
      this._primaryStack.set_visible_child_name('spinner');
    } else {
      this._primaryButton.set_sensitive(true);
      this._primarySpinner.stop();
      this._primaryStack.set_visible_child_name('button');
    }
    this._primaryButton.set_label(phase === 'available' ? i18n.t('primary_update') : i18n.t('primary_check'));

    let status = '';
    if (phase === 'available') {
      const size = a.check.downloadSize || i18n.t('unknown');
      status = `${i18n.t('updates_available')} ${i18n.t('download_size')}: ${size}.`;
    } else if (phase === 'no_updates') {
      status = i18n.t('no_new_updates');
    } else if (phase === 'error') {
      status = a.check.message ? `${i18n.t('error')}: ${a.check.message}` : i18n.t('error');
    }
    this._statusLabel.set_label(status);
  }

  async _check() {
    this._android.check = { phase: 'checking', downloadSize: null, message: '' };
    this._applyState();
    try {
      const res = await checkForUpdate(readImage());
      this._android.check = {
        phase: res.available ? 'available' : 'no_updates',
        downloadSize: res.downloadSize,
        message: ''
      };
    } catch (e) {
      logError(e, 'Android update check failed');
      this._android.check = { phase: 'error', downloadSize: null, message: e?.message ?? String(e) };
    }
    this._applyState();
  }

  // While an operation started elsewhere runs, look again every few seconds;
  // once it ends, read the whole state afresh.
  _startBusyPoll() {
    if (this._busyPoll)
      return;
    this._busyPoll = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, BUSY_POLL_S, () => {
      if (busyOperation())
        return GLib.SOURCE_CONTINUE;
      this._busyPoll = 0;
      this._refresh().catch((e) => logError(e, 'Android state refresh failed'));
      return GLib.SOURCE_REMOVE;
    });
  }

  _stopBusyPoll() {
    if (this._busyPoll) {
      GLib.source_remove(this._busyPoll);
      this._busyPoll = 0;
    }
  }

  async _showGsfId() {
    this._android.google = { phase: 'reading', id: null, signedIn: null, message: '' };
    this._applyState();
    try {
      const res = await googleStatus();
      if (res.refused)
        this._android.google = { phase: 'hidden', id: null, signedIn: null, message: '' };
      else if (res.notYet)
        this._android.google = { phase: 'not_yet', id: null, signedIn: null, message: '' };
      else
        this._android.google = { phase: 'shown', id: res.id, signedIn: res.signedIn, message: '' };
    } catch (e) {
      logError(e, 'Reading the Google status failed');
      this._android.google = { phase: 'error', id: null, signedIn: null, message: e?.message ?? String(e) };
    }
    this._applyState();
  }

  _copyGsfId() {
    const id = this._android.google.id;
    if (id)
      (this.get_display() ?? Gdk.Display.get_default()).get_clipboard().set_text(id);
  }

  async _onPrimaryAction() {
    if (this._android.check.phase === 'available')
      return this._run('upgrade', this._app.i18n.t('android_updating'));
    return this._check();
  }

  async _install() {
    await this._run('install', this._app.i18n.t('android_installing'));
  }

  async _remove() {
    const i18n = this._app.i18n;
    const ok = await this._window._confirm({
      heading: i18n.t('android_remove_confirm_title'),
      body: i18n.t('android_remove_confirm_body'),
      confirmId: 'remove',
      confirmLabel: i18n.t('android_remove'),
      appearance: Adw.ResponseAppearance.DESTRUCTIVE
    });
    if (ok)
      await this._run('remove', i18n.t('android_removing'));
  }

  // borshevik-waydroid refuses to run without root, so it goes under pkexec
  // from the start rather than through the unprivileged-first retry.
  async _run(subcommand, title) {
    await this._window._runWithProgress(['pkexec', CONTROL, subcommand], title, {
      withAuthRetry: false
    });
    this._android.check = { phase: 'idle', downloadSize: null, message: '' };
    // Every install brings a new ID; one shown before would be stale.
    this._android.google = { phase: 'hidden', id: null, signedIn: null, message: '' };
    await this._refresh();
  }

  _setAutoUpdatesActive(value) {
    this._autoUpdatesGuard = true;
    try {
      this._autoUpdatesRow.set_active(Boolean(value));
    } finally {
      this._autoUpdatesGuard = false;
    }
  }

  async _refreshAutoUpdates() {
    const res = await runCommandCapture(['systemctl', 'is-enabled', UPDATE_TIMER]);
    const state = (res.stdout ?? '').trim().toLowerCase();
    const enabled = state === 'enabled' || state === 'enabled-runtime';
    this._android.autoUpdates.enabled = enabled;
    this._setAutoUpdatesActive(enabled);
    this._autoUpdatesRow.set_sensitive(!this._android.autoUpdates.busy);
  }

  async _onAutoUpdatesToggled() {
    if (this._autoUpdatesGuard)
      return;

    const i18n = this._app.i18n;
    const enabled = this._autoUpdatesRow.get_active();
    this._android.autoUpdates.busy = true;
    this._autoUpdatesRow.set_sensitive(false);

    let res;
    try {
      res = await runCommandCapture(['systemctl', enabled ? 'enable' : 'disable', '--now', UPDATE_TIMER]);
    } catch (e) {
      res = { success: false, stdout: '', stderr: e?.message ?? String(e) };
    }

    this._android.autoUpdates.busy = false;
    if (!res.success) {
      const msg = `${(res.stdout ?? '').trim()}\n${(res.stderr ?? '').trim()}`.trim();
      const base = enabled ? i18n.t('auto_updates_error_enable') : i18n.t('auto_updates_error_disable');
      this._window._showInfo(msg ? `${base}\n\n${msg}` : base);
    }
    await this._refreshAutoUpdates();
  }
});
