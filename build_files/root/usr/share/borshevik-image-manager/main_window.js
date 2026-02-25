import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';

import {
  runStatusJson,
  parseStatusJson,
  getRegistryDigest
} from './rpm_ostree.js';
import { buildFacts, computeUiState } from './app_state.js';
import { CommandRunner } from './command_runner.js';
import { SettingsWindow } from './settings_window.js';
import { ProgressWindow } from './progress_window.js';
import { readOsRelease, pickLogoCandidates, firstExistingPath, requestRebootInteractive, isAuthorizationError, runCommandCapture } from './util.js';

export const MainWindow = GObject.registerClass(
class MainWindow extends Adw.ApplicationWindow {
  constructor(app) {
    super({
      application: app,
      title: app.i18n.t('app_name'),
      default_width: 580,
      default_height: 500
    });

    this._app = app;
    this._facts = null;
    this._check = {
      phase: 'idle',
      downloadSize: null,
      message: ''
    };

    // Automatic updates toggle state (driven by systemd timer).
    this._autoUpdates = {
      enabled: null,
      available: true,
      busy: false
    };
    this._autoUpdatesGuard = false;

    this._initUi();
    this._refreshStatus().then(() => {
      // Best-effort update check without auth prompts.
      this._checkForUpdates({ interactive: false }).catch((e) => {
        // Print full details to console for diagnostics.
        logError(e, 'Startup update check failed');
        // Never let startup checks crash the UI.
        const msg = e?.message ? e.message : String(e);
        this._check = { phase: 'error', downloadSize: null, message: msg };
        this._applyUiState();
      });
    });
  }

  _initUi() {
    const i18n = this._app.i18n;

    const header = new Adw.HeaderBar();

    // Menu — пересобирается при каждом обновлении фактов через _updatePromoteMenuItem
    this._menu = new Gio.Menu();
    this._menuShowPromote = false; // текущее состояние, чтобы не пересобирать без нужды
    this._rebuildMenu(false);

    const menuButton = new Gtk.MenuButton({
      icon_name: 'open-menu-symbolic',
      menu_model: this._menu
    });
    header.pack_end(menuButton);

    // App actions
    const actionSettings = new Gio.SimpleAction({ name: 'open-settings' });
    actionSettings.connect('activate', () => this._openSettings());
    this._app.add_action(actionSettings);

    const actionPromote = new Gio.SimpleAction({ name: 'promote-to-stable' });
    actionPromote.connect('activate', () => this._promoteToStable());
    this._app.add_action(actionPromote);
    this._promoteAction = actionPromote;

    const actionAbout = new Gio.SimpleAction({ name: 'about' });
    actionAbout.connect('activate', () => this._showAbout());
    this._app.add_action(actionAbout);

    // Main content stack: normal view only (busy operations now use separate window)
    this._stack = new Gtk.Stack({
      transition_type: Gtk.StackTransitionType.CROSSFADE
    });

    this._stack.add_named(this._buildMainView(), 'main');

    const toolbarView = new Adw.ToolbarView();
    toolbarView.add_top_bar(header);
    toolbarView.set_content(this._stack);
    this.set_content(toolbarView);
  }

  _buildMainView() {
    const i18n = this._app.i18n;

    const clamp = new Adw.Clamp({ maximum_size: 720, tightening_threshold: 560 });
    const box = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 16,
      margin_top: 20,
      margin_bottom: 20,
      margin_start: 20,
      margin_end: 20,
      halign: Gtk.Align.FILL
    });

    // Centered header content: logo -> distro name -> "<channel>, <build time>".
    // Keep overall header centered, but control spacing per-widget.
    // We want a larger gap between logo and name, and almost no gap
    // between name and the meta line.
    const headerBox = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL,
      spacing: 0,
      halign: Gtk.Align.CENTER
    });

    const logoPath = firstExistingPath(pickLogoCandidates());
    this._logoImage = new Gtk.Image({
      halign: Gtk.Align.CENTER,
      margin_bottom: 18
    });
    this._logoImage.pixel_size = 124;
    if (logoPath)
      this._logoImage.set_from_file(logoPath);
    else
      this._logoImage.set_from_icon_name('computer-symbolic');
    headerBox.append(this._logoImage);

    this._distroNameLabel = new Gtk.Label({
      halign: Gtk.Align.CENTER,
      selectable: false,
      css_classes: ['title-1']
    });
    headerBox.append(this._distroNameLabel);

    this._metaLabel = new Gtk.Label({
      halign: Gtk.Align.CENTER,
      margin_top: 0,
      wrap: true,
      selectable: true,
      css_classes: ['caption', 'dim-label']
    });
    headerBox.append(this._metaLabel);

    this._digestLabel = new Gtk.Label({
      halign: Gtk.Align.CENTER,
      margin_top: 2,
      wrap: true,
      selectable: true,
      css_classes: ['caption', 'dim-label']
    });
    headerBox.append(this._digestLabel);

    box.append(headerBox);

    // Primary action area (centered): Check/Update button OR spinner while checking.
    // Requirement: while checking for updates, replace the button with a spinner.
    this._primaryStack = new Gtk.Stack({
      transition_type: Gtk.StackTransitionType.CROSSFADE,
      halign: Gtk.Align.CENTER,
      margin_top: 12
    });

    this._primaryButton = new Gtk.Button({
      halign: Gtk.Align.CENTER,
      width_request: 320
    });
    this._primaryButton.add_css_class('suggested-action');
    this._primaryButton.add_css_class('pill');
    this._primaryButton.connect('clicked', () => this._onPrimaryAction());
    this._primaryStack.add_named(this._primaryButton, 'button');

    this._primarySpinner = new Gtk.Spinner({ halign: Gtk.Align.CENTER });
    this._primaryStack.add_named(this._primarySpinner, 'spinner');
    this._primaryStack.set_visible_child_name('button');

    box.append(this._primaryStack);

    // Status line (below the button).
    this._statusLabel = new Gtk.Label({
      halign: Gtk.Align.CENTER,
      wrap: true,
      selectable: true
    });
    box.append(this._statusLabel);

    // Update/Reboot + Rollback block (table-like)
    this._statusGroup = new Adw.PreferencesGroup();

    this._updateReadyRow = new Adw.ActionRow({
      title: i18n.t('reboot_to_apply_update'),
      subtitle: ''
    });
    this._updateReadyRow.set_activatable(false);

    this._rebootButton = new Gtk.Button({
      label: i18n.t('primary_reboot'),
      valign: Gtk.Align.CENTER
    });
    this._rebootButton.add_css_class('suggested-action');
    this._rebootButton.connect('clicked', () => this._doReboot());

    this._updateReadyRow.add_suffix(this._rebootButton);
    this._updateReadyRow.visible = false;
    this._statusGroup.add(this._updateReadyRow);

    this._rollbackRow = new Adw.ActionRow({
      title: i18n.t('rollback_to_previous'),
      subtitle: i18n.t('not_available')
    });
    this._rollbackRow.set_activatable(false);

    this._rollbackButton = new Gtk.Button({
      label: i18n.t('rollback'),
      valign: Gtk.Align.CENTER
    });
    this._rollbackButton.connect('clicked', async () => {
      const ok = await this._confirmRollback();
      if (ok)
        await this._doRollback();
    });
    this._rollbackRow.add_suffix(this._rollbackButton);

    this._statusGroup.add(this._rollbackRow);
    box.append(this._statusGroup);

    // Automatic updates toggle (systemd timer) placed at the bottom of the main page.
    // We intentionally keep it out of Settings as requested.
    this._autoUpdatesGroup = new Adw.PreferencesGroup();
    this._autoUpdatesRow = new Adw.SwitchRow({
      title: i18n.t('auto_updates_title'),
      subtitle: i18n.t('auto_updates_subtitle')
    });
    this._autoUpdatesRow.connect('notify::active', () => this._onAutoUpdatesToggled());
    this._autoUpdatesGroup.add(this._autoUpdatesRow);
    box.append(this._autoUpdatesGroup);

    clamp.set_child(box);
    return clamp;
  }

  async _refreshStatus() {
    const i18n = this._app.i18n;
    const osr = readOsRelease();

    const res = await runStatusJson();
    if (!res.ok) {
      this._facts = null;
      this._check = { phase: 'error', downloadSize: null, message: res.error };
      this._statusLabel.set_label(`${i18n.t('error')}: ${res.error}`);
      this._applyUiState();
      return;
    }

    const parsed = parseStatusJson(res.json);
    this._facts = buildFacts({ i18n, osRelease: osr, parsed });

    // Header
    this._distroNameLabel.set_label(this._facts.distroName);
    this._metaLabel.set_label(`${this._facts.channel}, ${this._facts.buildTime}`);
    this._digestLabel.set_label(this._facts.digest);

    // Update-ready row (staged/pending)
    if (this._facts.needsReboot) {
      this._updateReadyRow.set_subtitle(this._facts.nextTime);
      this._updateReadyRow.visible = true;
    } else {
      this._updateReadyRow.visible = false;
      this._updateReadyRow.set_subtitle('');
    }

    // Rollback info
    this._rollbackRow.set_subtitle(this._facts.rollbackTime);
    this._rollbackButton.set_sensitive(this._facts.hasRollback);

    // Update promote to stable menu item
    this._updatePromoteMenuItem();

    this._applyUiState();

    // Update auto-updates toggle in the background.
    this._refreshAutoUpdates().catch((e) => {
      logError(e, 'Failed to refresh automatic updates state');
    });
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
    if (!this._autoUpdatesRow)
      return;

    // `rpm-ostreed-automatic.timer` is the standard trigger for automatic rpm-ostree updates.
    const unit = 'rpm-ostreed-automatic.timer';

    const res = await runCommandCapture(['systemctl', 'is-enabled', unit]);
    const out = (res.stdout ?? '').trim();
    const err = (res.stderr ?? '').trim();

    // Important: `systemctl is-enabled` returns a non-zero exit status for some valid
    // states (e.g. "disabled" commonly exits with 1). Treat known states as valid.
    const state = out.toLowerCase();
    const known = new Set([
      'enabled',
      'enabled-runtime',
      'disabled',
      'static',
      'indirect',
      'generated',
      'transient',
      'masked',
    ]);

    if (!known.has(state)) {
      // If the unit doesn't exist or systemctl isn't available, disable the toggle.
      const msg = `${out}\n${err}`.trim().toLowerCase();
      this._autoUpdates.available = false;
      this._autoUpdatesRow.set_sensitive(false);
      if (msg.includes('not found') || msg.includes('no such file') || msg.includes('could not be found'))
        this._autoUpdatesRow.set_subtitle(this._app.i18n.t('auto_updates_unavailable'));
      return;
    }

    this._autoUpdates.available = true;
    this._autoUpdatesRow.set_sensitive(!this._autoUpdates.busy);

    const enabled = state === 'enabled' || state === 'enabled-runtime';
    this._autoUpdates.enabled = enabled;
    this._setAutoUpdatesActive(enabled);
  }

  async _onAutoUpdatesToggled() {
    if (!this._autoUpdatesRow || this._autoUpdatesGuard)
      return;

    const desired = this._autoUpdatesRow.get_active();
    await this._setAutoUpdatesEnabled(desired);
  }

  async _setAutoUpdatesEnabled(enabled) {
    const i18n = this._app.i18n;
    const unit = 'rpm-ostreed-automatic.timer';
    const previous = this._autoUpdates.enabled;

    this._autoUpdates.busy = true;
    this._autoUpdatesRow.set_sensitive(false);

    const argv = enabled
      ? ['systemctl', 'enable', '--now', unit]
      : ['systemctl', 'disable', '--now', unit];

    let res;
    try {
      res = await runCommandCapture(argv);
    } catch (e) {
      logError(e, 'systemctl command failed');
      res = { success: false, stdout: '', stderr: e?.message ? e.message : String(e) };
    }

    this._autoUpdates.busy = false;

    if (!res.success) {
      // Revert the UI state and show a concise error.
      this._autoUpdates.enabled = previous;
      this._setAutoUpdatesActive(previous);
      this._autoUpdatesRow.set_sensitive(true);

      const msg = `${(res.stdout ?? '').trim()}\n${(res.stderr ?? '').trim()}`.trim();
      const base = enabled ? i18n.t('auto_updates_error_enable') : i18n.t('auto_updates_error_disable');
      this._showInfo(msg ? `${base}\n\n${msg}` : base);
      await this._refreshAutoUpdates();
      return;
    }

    // Success: reflect current state.
    this._autoUpdatesRow.set_sensitive(true);
    await this._refreshAutoUpdates();
  }

  _applyUiState() {
    const i18n = this._app.i18n;
    if (!this._facts) {
      this._primaryMode = 'check';
      this._primaryButton.set_label(i18n.t('primary_check'));
      return;
    }

    const ui = computeUiState({ i18n, facts: this._facts, check: this._check });
    this._primaryMode = ui.primaryMode;
    this._primaryButton.set_label(ui.primaryLabel);

    if (ui.showCheckSpinner) {
      this._primaryButton.set_sensitive(false);
      this._primarySpinner.start();
      this._primaryStack.set_visible_child_name('spinner');
    } else {
      this._primaryButton.set_sensitive(true);
      this._primarySpinner.stop();
      this._primaryStack.set_visible_child_name('button');
    }

    this._statusLabel.set_label(ui.statusText || '');
  }

  async _onPrimaryAction() {
    if (this._primaryMode === 'check')
      return this._checkForUpdates({ interactive: true });
    if (this._primaryMode === 'update')
      return this._doUpgrade();
  }

  async _checkForUpdates({ interactive }) {
    const i18n = this._app.i18n;

    // Refresh status first so we do not misreport download sizes when an update
    // has already been staged by automatic updates.
    await this._refreshStatus();

    this._check = { phase: 'checking', downloadSize: null, message: '' };
    this._applyUiState();

    let output = '';
    const runner = new CommandRunner({
      onStdout: (t) => { output += t; },
      onStderr: (t) => { output += t; }
    });

    let success = false;
    try {
      // `rpm-ostree update --check` works unprivileged; never prompt for auth here.
      ({ success } = await runner.run(['rpm-ostree', 'update', '--check'], { root: false }));
    } catch (e) {
      logError(e, 'rpm-ostree update --check failed');
      success = false;
      output += `\n${e?.message ? e.message : String(e)}`;
    }

    // Filter informational notes; they are not actionable for end users.
    const filteredOutput = output
      .split(/\r?\n/)
      .map(l => l.replace(/\u00a0/g, ' ')) // normalize non-breaking spaces
      .filter((l) => {
        const t = l.trim();
        if (!t) return false;
        if (/^note\s*:/i.test(t)) return false;
        return true;
      })
      .join('\n');

    const hasAvailableUpdate = /\bAvailableUpdate\s*:/i.test(filteredOutput);
    const hasNoUpdates = /\bNo updates available\b/i.test(filteredOutput) && !hasAvailableUpdate;
    const hasStaged = Boolean(this._facts?.needsReboot);

    // Prefer Added layers size; Total layers often overstates the real download.
    let size = null;
    const addedSizeMatch = filteredOutput.match(/AvailableUpdate:[\s\S]*?\n\s*Added layers\s*:[\s\S]*?\n\s*Size\s*:\s*([^\n]+)/i);
    if (addedSizeMatch)
      size = addedSizeMatch[1].trim();
    if (!size) {
      const anySizeMatch = filteredOutput.match(/AvailableUpdate:[\s\S]*?\n\s*Size\s*:\s*([^\n]+)/i);
      if (anySizeMatch)
        size = anySizeMatch[1].trim();
    }

    if (!success) {
      // Some rpm-ostree versions exit non-zero when a deployment is already staged
      // (e.g. "Staged deployment exists") — that's not an error from the user's perspective.
      if (hasNoUpdates || hasStaged) {
        this._check = { phase: 'no_updates', downloadSize: null, message: '' };
      } else {
        this._check = {
          phase: 'error',
          downloadSize: null,
          message: filteredOutput.trim() || 'rpm-ostree update --check failed'
        };
      }
      this._applyUiState();
      return;
    }

    if (hasAvailableUpdate) {
      // If a deployment is already staged, verify the registry hasn't moved
      // past it before offering to download again.  skopeo inspect is fast
      // (manifest-only, no layer data) so the extra round-trip is acceptable.
      if (hasStaged && this._facts?.stagedDigest) {
        const dockerRef = this._facts.currentOrigin?.replace(/^ostree-image-signed:docker:\/\//, '');
        if (dockerRef && !dockerRef.includes('@sha256:')) {
          const registryDigest = await getRegistryDigest(dockerRef);
          if (registryDigest && registryDigest === this._facts.stagedDigest) {
            // Staged IS the registry-latest — nothing new to download.
            this._check = { phase: 'no_updates', downloadSize: null, message: '' };
            this._applyUiState();
            await this._refreshStatus();
            return;
          }
        }
      }
      this._check = { phase: 'available', downloadSize: size, message: '' };
    } else {
      this._check = { phase: 'no_updates', downloadSize: null, message: '' };
    }

    // Update UI and refresh status again in case staging changed while checking.
    this._applyUiState();
    await this._refreshStatus();
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  // Runs `command` inside a ProgressWindow.
  // `onSuccess(progressWin)` is called (and awaited) when the command exits 0.
  // Set `withAuthRetry: false` to skip the pkexec re-run on auth failures.
  async _runWithProgress(command, title, { onSuccess, withAuthRetry = true } = {}) {
    const i18n = this._app.i18n;

    const progressWin = new ProgressWindow({
      application: this._app,
      transient_for: this,
      title
    });

    progressWin.setCommand(command);
    progressWin.startProgress();
    progressWin.present();

    let collected = '';
    const runner = new CommandRunner({
      onStdout: (t) => { collected += t; progressWin.appendOutput(t); },
      onStderr: (t) => { collected += t; progressWin.appendOutput(t); },
      onExit:   () => progressWin.stopProgress()
    });
    progressWin.setRunner(runner);

    let result = await runner.run(command, { root: false });

    if (withAuthRetry && !result.success && isAuthorizationError(collected)) {
      progressWin.appendOutput('\nAuthorization required; retrying with elevated privileges…\n');
      progressWin.setCommand(['pkexec', ...command]);
      result = await runner.run(command, { root: true });
    }

    if (result.success && onSuccess)
      await onSuccess(progressWin);

    return result;
  }

  // Shows an Adw.MessageDialog with two buttons: cancel and a confirm button.
  // Returns a Promise<boolean> that resolves to true when the confirm button is pressed.
  _confirm({ heading, body, confirmId, confirmLabel, appearance = Adw.ResponseAppearance.SUGGESTED }) {
    const i18n = this._app.i18n;
    return new Promise((resolve) => {
      const dlg = new Adw.MessageDialog({
        transient_for: this,
        modal: true,
        heading,
        body
      });
      dlg.add_response('cancel', i18n.t('cancel'));
      dlg.add_response(confirmId, confirmLabel);
      dlg.set_default_response('cancel');
      dlg.set_close_response('cancel');
      dlg.set_response_appearance(confirmId, appearance);
      dlg.connect('response', (_d, resp) => {
        dlg.destroy();
        resolve(resp === confirmId);
      });
      dlg.present();
    });
  }

  async _doUpgrade() {
    const i18n = this._app.i18n;
    const command = ['rpm-ostree', 'update'];

    await this._runWithProgress(command, i18n.t('applying_update'), {
      onSuccess: async () => {
        this._check = { phase: 'idle', downloadSize: null, message: '' };
        try {
          await requestRebootInteractive();
        } catch (e) {
          logError(e, 'Reboot prompt failed after update');
        }
      }
    });

    await this._refreshStatus();
  }

  async _doRollback() {
    const i18n = this._app.i18n;
    const command = ['rpm-ostree', 'rollback'];

    await this._runWithProgress(command, i18n.t('rollback'), {
      onSuccess: async () => {
        this._check = { phase: 'idle', downloadSize: null, message: '' };
        try {
          await requestRebootInteractive();
        } catch (e) {
          logError(e, 'Reboot prompt failed after rollback');
        }
      }
    });

    await this._refreshStatus();
  }

  async _doReboot() {
    // Reboot should use the desktop environment's native confirmation UI.
    // We intentionally do NOT show the busy/console-output view for this action.
    // NOTE: GNOME's reboot prompt is handled out-of-process (gnome-shell).
    // The D-Bus method may return success even if the user presses Cancel.
    // Therefore, we only "debounce" the button briefly instead of disabling it permanently.
    this._rebootButton?.set_sensitive(false);
    try {
      await requestRebootInteractive();
    } catch (e) {
      logError(e, 'Reboot request failed');
      const msg = e?.message ? e.message : String(e);
      this._showInfo(`${this._app.i18n.t('error')}: ${msg}`);
    } finally {
      GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1200, () => {
        this._rebootButton?.set_sensitive(true);
        return GLib.SOURCE_REMOVE;
      });
    }
  }

  _openSettings() {
    const win = new SettingsWindow({
      transient_for: this,
      application: this._app,
      currentOrigin: this._facts?.currentOrigin || ''
    });
    win.connect('rebase-done', async () => {
      await this._refreshStatus();
    });
    win.present();
  }

  _rebuildMenu(showPromote) {
    const i18n = this._app.i18n;
    this._menu.remove_all();
    this._menu.append(i18n.t('menu_settings'), 'app.open-settings');
    if (showPromote)
      this._menu.append(i18n.t('promote_to_stable'), 'app.promote-to-stable');
    this._menu.append(i18n.t('menu_about'), 'app.about');
    this._menuShowPromote = showPromote;
  }

  _updatePromoteMenuItem() {
    const shouldShow = Boolean(
      this._facts &&
      this._facts.channel === 'latest' &&
      (this._facts.variant === 'borshevik' || this._facts.variant === 'borshevik-nvidia')
    );
    if (shouldShow !== this._menuShowPromote)
      this._rebuildMenu(shouldShow);
  }

  async _promoteToStable() {
    const i18n = this._app.i18n;

    const confirmed = await this._confirm({
      heading: i18n.t('promote_to_stable_confirm_title'),
      body: i18n.t('promote_to_stable_confirm_body'),
      confirmId: 'promote',
      confirmLabel: i18n.t('apply'),
      appearance: Adw.ResponseAppearance.SUGGESTED
    });
    if (!confirmed) return;

    if (!this._facts || !this._facts.digest || this._facts.digest === i18n.t('unknown')) {
      this._showInfo('Cannot promote: digest not available');
      return;
    }

    const argv = [
      '/usr/bin/borshevik-promote-to-stable',
      this._facts.digest,   // already has sha256: prefix
      this._facts.variant
    ];

    await this._runWithProgress(argv, i18n.t('promoting_to_stable'), {
      withAuthRetry: false,
      onSuccess: async () => this._showInfo(i18n.t('promote_complete'))
    });
  }

  _showAbout() {
    const i18n = this._app.i18n;
    const about = new Adw.AboutWindow({
      transient_for: this,
      application_name: i18n.t('app_name'),
      developer_name: 'Borshevik',
      version: '1.0',
      comments: i18n.t('about_details')
    });
    about.present();
  }

  async _confirmRollback() {
    const i18n = this._app.i18n;
    return this._confirm({
      heading: i18n.t('confirm_rollback_title'),
      body: i18n.t('confirm_rollback_body'),
      confirmId: 'rollback',
      confirmLabel: i18n.t('rollback'),
      appearance: Adw.ResponseAppearance.DESTRUCTIVE
    });
  }

  _showInfo(message) {
    const i18n = this._app.i18n;
    const dlg = new Adw.MessageDialog({
      transient_for: this,
      heading: i18n.t('app_name'),
      body: message
    });
    dlg.add_response('ok', i18n.t('ok'));
    dlg.set_default_response('ok');
    dlg.set_close_response('ok');
    dlg.present();
  }
});
