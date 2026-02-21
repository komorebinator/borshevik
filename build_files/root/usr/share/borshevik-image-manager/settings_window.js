import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';

import { CommandRunner } from './command_runner.js';
import { ProgressWindow } from './progress_window.js';
import { isAuthorizationError, requestRebootInteractive } from './util.js';
import {
  buildTargetRef,
  inferVariantAndChannelFromOrigin
} from './rpm_ostree.js';

const DEFAULT_STANDARD = 'ostree-image-signed:docker://ghcr.io/komorebinator/borshevik';
const DEFAULT_NVIDIA = 'ostree-image-signed:docker://ghcr.io/komorebinator/borshevik-nvidia';

export const SettingsWindow = GObject.registerClass(
  {
    Signals: {
      'rebase-done': {}
    }
  },
  class SettingsWindow extends Adw.Window {
    constructor({ application, transient_for, currentOrigin }) {
      super({
        application,
        transient_for,
        title: application.i18n.t('settings_title'),
        default_width: 580,
        default_height: 650
      });

      this._app = application;
      this._initialOrigin = currentOrigin || '';
      this._initial = this._inferInitialState(this._initialOrigin);
      this._current = { ...this._initial };

      this._initUi();
      this._syncUiFromState();
      this._updateDerived();
    }

    _inferInitialState(origin) {
      const inf = inferVariantAndChannelFromOrigin(origin);
      // 'custom' variant no longer exists in UI — fall back to standard.
      const variant = (inf.variant === 'nvidia') ? 'nvidia' : 'standard';

      return {
        variant,
        channel: inf.channel,
        customTag: inf.customTag
      };
    }

    _initUi() {
      const i18n = this._app.i18n;

      const header = new Adw.HeaderBar();
      const toolbarView = new Adw.ToolbarView();
      toolbarView.add_top_bar(header);

      this._stack = new Gtk.Stack({
        transition_type: Gtk.StackTransitionType.CROSSFADE
      });

      this._stack.add_named(this._buildSettingsView(), 'settings');

      toolbarView.set_content(this._stack);
      this.set_content(toolbarView);

      // Bottom buttons
      this._applyBtn = new Gtk.Button({ label: i18n.t('apply'), sensitive: false });
      this._applyBtn.add_css_class('suggested-action');
      this._applyBtn.connect('clicked', () => this._onApply());

      this._resetBtn = new Gtk.Button({ label: i18n.t('reset') });
      this._resetBtn.connect('clicked', () => this._onReset());

      // This is a separate window; no explicit Back button is needed.
      header.pack_end(this._applyBtn);
      header.pack_end(this._resetBtn);
    }

    _buildSettingsView() {
      const i18n = this._app.i18n;
      const clamp = new Adw.Clamp({ maximum_size: 720, tightening_threshold: 560 });

      const scroller = new Gtk.ScrolledWindow({ vexpand: true });
      const box = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL,
        spacing: 14,
        margin_top: 16,
        margin_bottom: 16,
        margin_start: 16,
        margin_end: 16
      });

      const makeFieldRow = (title, widget) => {
        // A PreferencesRow that puts the label above the control to fit narrow widths.
        const row = new Adw.PreferencesRow();
        const v = new Gtk.Box({
          orientation: Gtk.Orientation.VERTICAL,
          spacing: 6,
          margin_top: 10,
          margin_bottom: 10,
          margin_start: 12,
          margin_end: 12
        });

        const lbl = new Gtk.Label({ label: title, xalign: 0 });
        lbl.add_css_class('caption');
        lbl.add_css_class('dim-label');
        v.append(lbl);

        widget.set_hexpand?.(true);
        v.append(widget);
        row.set_child(v);
        return row;
      };

      // Image URL (shows full ref, editable for custom variant)
      const previewGroup = new Adw.PreferencesGroup();
      this._targetPreview = new Gtk.Entry({ 
        editable: true,
        can_focus: true, 
        hexpand: true 
      });
      previewGroup.add(makeFieldRow(i18n.t('image_url'), this._targetPreview));
      box.append(previewGroup);

      // Variant (radio)
      const variantGroup = new Adw.PreferencesGroup({ title: i18n.t('variant') });
      this._variantStandardBtn = new Gtk.CheckButton();
      this._variantNvidiaBtn = new Gtk.CheckButton({ group: this._variantStandardBtn });

      const v1 = new Adw.ActionRow({ title: i18n.t('variant_standard') });
      v1.add_prefix(this._variantStandardBtn);
      v1.set_activatable_widget(this._variantStandardBtn);
      variantGroup.add(v1);

      const v2 = new Adw.ActionRow({ title: i18n.t('variant_nvidia') });
      v2.add_prefix(this._variantNvidiaBtn);
      v2.set_activatable_widget(this._variantNvidiaBtn);
      variantGroup.add(v2);

      box.append(variantGroup);

      // Channel (radio)
      const channelGroup = new Adw.PreferencesGroup({ title: i18n.t('channel_choice') });
      this._channelLatestBtn = new Gtk.CheckButton();
      this._channelStableBtn = new Gtk.CheckButton({ group: this._channelLatestBtn });
      this._channelCustomBtn = new Gtk.CheckButton({ group: this._channelLatestBtn });

      const c1 = new Adw.ActionRow({ title: i18n.t('channel_latest') });
      c1.add_prefix(this._channelLatestBtn);
      c1.set_activatable_widget(this._channelLatestBtn);
      channelGroup.add(c1);

      const c2 = new Adw.ActionRow({ title: i18n.t('channel_stable') });
      c2.add_prefix(this._channelStableBtn);
      c2.set_activatable_widget(this._channelStableBtn);
      channelGroup.add(c2);

      const c3 = new Adw.ActionRow({ title: i18n.t('channel_custom') });
      c3.add_prefix(this._channelCustomBtn);
      c3.set_activatable_widget(this._channelCustomBtn);
      channelGroup.add(c3);

      box.append(channelGroup);

      // Custom tag
      const tagGroup = new Adw.PreferencesGroup();
      this._customTagEntry = new Gtk.Entry({ hexpand: true });
      this._tagRow = makeFieldRow(i18n.t('custom_tag'), this._customTagEntry);
      tagGroup.add(this._tagRow);
      box.append(tagGroup);

      scroller.set_child(box);
      clamp.set_child(scroller);

      // Wire signals
      this._variantStandardBtn.connect('toggled', () => {
        if (!this._variantStandardBtn.get_active()) return;
        this._current.variant = 'standard';
        this._updateDerived();
      });
      this._variantNvidiaBtn.connect('toggled', () => {
        if (!this._variantNvidiaBtn.get_active()) return;
        this._current.variant = 'nvidia';
        this._updateDerived();
      });

      this._channelLatestBtn.connect('toggled', () => {
        if (!this._channelLatestBtn.get_active()) return;
        this._current.channel = 'latest';
        this._updateDerived();
      });
      this._channelStableBtn.connect('toggled', () => {
        if (!this._channelStableBtn.get_active()) return;
        this._current.channel = 'stable';
        this._updateDerived();
      });
      this._channelCustomBtn.connect('toggled', () => {
        if (!this._channelCustomBtn.get_active()) return;
        this._current.channel = 'custom';
        this._updateDerived();
      });

      this._targetPreview.connect('changed', () => {
        if (this._settingText) return;
      });

      this._customTagEntry.connect('changed', () => {
        this._current.customTag = this._customTagEntry.get_text();
        this._updateDerived();
      });

      return clamp;
    }

    _syncUiFromState() {
      // Variant
      this._variantStandardBtn.set_active(this._current.variant === 'standard');
      this._variantNvidiaBtn.set_active(this._current.variant === 'nvidia');

      // Channel
      this._channelLatestBtn.set_active(this._current.channel === 'latest');
      this._channelStableBtn.set_active(this._current.channel === 'stable');
      this._channelCustomBtn.set_active(this._current.channel === 'custom');

      this._customTagEntry.set_text(this._current.customTag || '');
    }

    _setPreviewText(text) {
      // Guard against recursive changed signals: set_text() triggers 'changed',
      // which would call _updateDerived() again infinitely.
      if (this._settingText) return;
      this._settingText = true;
      try {
        this._targetPreview.set_text(text || '');
      } finally {
        this._settingText = false;
      }
    }

    _updateDerived() {
      const i18n = this._app.i18n;

      // Image URL preview — always read-only now that custom variant is removed
      this._targetPreview.set_editable(false);
      this._targetPreview.set_can_focus(false);

      // Custom tag visibility/enabling
      const isCustomChannel = this._current.channel === 'custom';
      this._customTagEntry.set_sensitive(isCustomChannel);
      this._tagRow.set_visible(true);

      // Compute and display the target ref
      const base = (this._current.variant === 'standard') ? DEFAULT_STANDARD : DEFAULT_NVIDIA;

      const target = buildTargetRef(base, this._current.channel, this._current.customTag);

      // For non-editable fields always sync; for editable only sync when not focused
      // (to avoid clobbering user's cursor position while typing).
      // is_focus() is the correct GJS/GTK method (has_focus() does not exist).
      if (!this._targetPreview.get_editable() || !this._targetPreview.is_focus()) {
        this._setPreviewText(target);
      }

      const dirty = JSON.stringify(this._current) !== JSON.stringify(this._initial);
      const valid = Boolean(target);
      this._applyBtn.set_sensitive(dirty && valid);

      // Update a small hint in window title to show dirty state.
      this.set_title(dirty ? `${i18n.t('settings_title')} *` : i18n.t('settings_title'));
    }

    _onReset() {
      this._current = { ...this._initial };
      this._syncUiFromState();
      this._updateDerived();
    }

    async _onApply() {
      const i18n = this._app.i18n;
      const base = (this._current.variant === 'standard') ? DEFAULT_STANDARD : DEFAULT_NVIDIA;

      const target = buildTargetRef(base, this._current.channel, this._current.customTag);
      if (!target)
        return;

      const command = ['rpm-ostree', 'rebase', target];

      const progressWin = new ProgressWindow({
        application: this._app,
        transient_for: this,
        title: i18n.t('applying_rebase')
      });

      progressWin.setCommand(command);
      progressWin.startProgress();
      progressWin.present();

      let collected = '';

      const runner = new CommandRunner({
        onStdout: (t) => { collected += t; progressWin.appendOutput(t); },
        onStderr: (t) => { collected += t; progressWin.appendOutput(t); },
        onExit: () => progressWin.stopProgress()
      });

      progressWin.setRunner(runner);

      let result = await runner.run(command, { root: false });
      if (!result.success && isAuthorizationError(collected)) {
        progressWin.appendOutput('\nAuthorization required; retrying with elevated privileges…\n');
        progressWin.setCommand(['pkexec', ...command]);
        result = await runner.run(command, { root: true });
      }

      if (result.success) {
        this._initial = { ...this._current };
        this._updateDerived();

        // Close the progress window first (it has deletable:false so user can't close it manually)
        progressWin.close();
        // Then close the settings window
        this.close();

        this.emit('rebase-done');

        // Trigger the native GNOME reboot confirmation dialog
        try {
          await requestRebootInteractive();
        } catch (e) {
          logError(e, 'Reboot prompt failed after rebase');
        }
      }
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
  }
);
