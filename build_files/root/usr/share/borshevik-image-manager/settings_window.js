import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';

import { CommandRunner } from './command_runner.js';
import { isAuthorizationError } from './util.js';
import {
  buildTargetRef,
  inferVariantAndChannelFromOrigin,
  stripDockerTagIfPresent
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
        default_height: 500
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
      let imageUrl = '';
      if (inf.variant === 'standard') imageUrl = DEFAULT_STANDARD;
      else if (inf.variant === 'nvidia') imageUrl = DEFAULT_NVIDIA;
      else imageUrl = stripDockerTagIfPresent(origin) || '';

      return {
        variant: inf.variant,
        channel: inf.channel,
        customTag: inf.customTag,
        imageUrl
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
      this._stack.add_named(this._buildBusyView(), 'busy');

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

      // Variant (radio)
      const variantGroup = new Adw.PreferencesGroup({ title: i18n.t('variant') });
      this._variantStandardBtn = new Gtk.CheckButton();
      this._variantNvidiaBtn = new Gtk.CheckButton({ group: this._variantStandardBtn });
      this._variantCustomBtn = new Gtk.CheckButton({ group: this._variantStandardBtn });

      const v1 = new Adw.ActionRow({ title: i18n.t('variant_standard') });
      v1.add_prefix(this._variantStandardBtn);
      v1.set_activatable_widget(this._variantStandardBtn);
      variantGroup.add(v1);

      const v2 = new Adw.ActionRow({ title: i18n.t('variant_nvidia') });
      v2.add_prefix(this._variantNvidiaBtn);
      v2.set_activatable_widget(this._variantNvidiaBtn);
      variantGroup.add(v2);

      const v3 = new Adw.ActionRow({ title: i18n.t('variant_custom') });
      v3.add_prefix(this._variantCustomBtn);
      v3.set_activatable_widget(this._variantCustomBtn);
      variantGroup.add(v3);

      box.append(variantGroup);

      // Image URL
      const imageGroup = new Adw.PreferencesGroup();
      this._imageEntry = new Gtk.Entry({ hexpand: true });
      imageGroup.add(makeFieldRow(i18n.t('image_url'), this._imageEntry));
      box.append(imageGroup);

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

      // Target ref (preview)
      const previewGroup = new Adw.PreferencesGroup();
      this._targetPreview = new Gtk.Entry({ editable: false, can_focus: false, hexpand: true });
      previewGroup.add(makeFieldRow(i18n.t('target_ref'), this._targetPreview));
      box.append(previewGroup);

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
      this._variantCustomBtn.connect('toggled', () => {
        if (!this._variantCustomBtn.get_active()) return;
        this._current.variant = 'custom';
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

      this._imageEntry.connect('changed', () => {
        this._current.imageUrl = this._imageEntry.get_text();
        this._updateDerived();
      });

      this._customTagEntry.connect('changed', () => {
        this._current.customTag = this._customTagEntry.get_text();
        this._updateDerived();
      });

      return clamp;
    }

    _buildBusyView() {
      const i18n = this._app.i18n;
      const clamp = new Adw.Clamp({ maximum_size: 720, tightening_threshold: 560 });

      const box = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL,
        spacing: 12,
        margin_top: 16,
        margin_bottom: 16,
        margin_start: 16,
        margin_end: 16
      });

      this._busyTitle = new Gtk.Label({ xalign: 0, label: i18n.t('running'), css_classes: ['title-3'] });
      box.append(this._busyTitle);

      this._progress = new Gtk.ProgressBar({ show_text: false });
      this._progress.set_pulse_step(0.05);
      box.append(this._progress);

      const frame = new Gtk.Frame({ label: i18n.t('command_output') });
      const scroller = new Gtk.ScrolledWindow({ hexpand: true, vexpand: true });
      this._textBuffer = new Gtk.TextBuffer();
      const tv = new Gtk.TextView({ buffer: this._textBuffer, editable: false, monospace: true, wrap_mode: Gtk.WrapMode.WORD_CHAR });
      scroller.set_child(tv);
      frame.set_child(scroller);
      box.append(frame);

      this._busyClose = new Gtk.Button({ label: i18n.t('close'), sensitive: false });
      this._busyClose.connect('clicked', () => {
        this._stack.set_visible_child_name('settings');
      });
      box.append(this._busyClose);

      clamp.set_child(box);
      return clamp;
    }

    _syncUiFromState() {
      // Variant
      this._variantStandardBtn.set_active(this._current.variant === 'standard');
      this._variantNvidiaBtn.set_active(this._current.variant === 'nvidia');
      this._variantCustomBtn.set_active(this._current.variant === 'custom');

      // Channel
      this._channelLatestBtn.set_active(this._current.channel === 'latest');
      this._channelStableBtn.set_active(this._current.channel === 'stable');
      this._channelCustomBtn.set_active(this._current.channel === 'custom');

      this._imageEntry.set_text(this._current.imageUrl || '');
      this._customTagEntry.set_text(this._current.customTag || '');
    }

    _updateDerived() {
      const i18n = this._app.i18n;

      // Image URL enabling
      if (this._current.variant === 'standard') {
        this._current.imageUrl = DEFAULT_STANDARD;
        this._imageEntry.set_sensitive(false);
      } else if (this._current.variant === 'nvidia') {
        this._current.imageUrl = DEFAULT_NVIDIA;
        this._imageEntry.set_sensitive(false);
      } else {
        this._imageEntry.set_sensitive(true);
      }

      // Custom tag visibility/enabling
      const isCustomChannel = this._current.channel === 'custom';
      this._customTagEntry.set_sensitive(isCustomChannel);
      this._tagRow.set_visible(isCustomChannel);

      // Compute preview
      const base = (this._current.variant === 'standard') ? DEFAULT_STANDARD
        : (this._current.variant === 'nvidia') ? DEFAULT_NVIDIA
        : (this._current.imageUrl || '');

      const target = buildTargetRef(base, this._current.channel, this._current.customTag);
      this._targetPreview.set_text(target || '');

      const dirty = JSON.stringify(this._current) !== JSON.stringify(this._initial);
      const valid = Boolean(target);
      this._applyBtn.set_sensitive(dirty && valid);

      // If channel isn't custom, keep customTag but it won't be used; that's okay.
      if (!isCustomChannel) {
        this._customTagEntry.set_text(this._current.customTag || '');
      }

      // Update a small hint in window title to show dirty state.
      this.set_title(dirty ? `${i18n.t('settings_title')} *` : i18n.t('settings_title'));
    }

    _onReset() {
      this._current = { ...this._initial };
      this._syncUiFromState();
      this._updateDerived();
    }

    _enterBusy(title) {
      const i18n = this._app.i18n;
      this._busyTitle.set_label(title || i18n.t('running'));
      this._busyClose.set_sensitive(false);
      this._textBuffer.set_text('', -1);
      this._stack.set_visible_child_name('busy');

      this._progress.set_fraction(0);
      if (this._pulseId) {
        GLib.source_remove(this._pulseId);
        this._pulseId = null;
      }
      this._pulseId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 80, () => {
        this._progress.pulse();
        return GLib.SOURCE_CONTINUE;
      });
    }

    _leaveBusy() {
      if (this._pulseId) {
        GLib.source_remove(this._pulseId);
        this._pulseId = null;
      }
      this._progress.set_fraction(1.0);
      this._busyClose.set_sensitive(true);
    }

    _appendOutput(text) {
      const iter = this._textBuffer.get_end_iter();
      this._textBuffer.insert(iter, text, -1);
    }

    async _onApply() {
      const i18n = this._app.i18n;
      const base = (this._current.variant === 'standard') ? DEFAULT_STANDARD
        : (this._current.variant === 'nvidia') ? DEFAULT_NVIDIA
        : (this._current.imageUrl || '');

      const target = buildTargetRef(base, this._current.channel, this._current.customTag);
      if (!target)
        return;

      this._enterBusy(i18n.t('apply'));

      let collected = '';

      const runner = new CommandRunner({
        onStdout: (t) => { collected += t; this._appendOutput(t); },
        onStderr: (t) => { collected += t; this._appendOutput(t); },
        onExit: () => this._leaveBusy()
      });

      let result = await runner.run(['rpm-ostree', 'rebase', target], { root: false });
      if (!result.success && isAuthorizationError(collected)) {
        this._appendOutput('\nAuthorization required; retrying with elevated privileges…\n');
        result = await runner.run(['rpm-ostree', 'rebase', target], { root: true });
      }

      if (result.success) {
        this._initial = { ...this._current };
        this._updateDerived();
        this._showInfo(i18n.t('rebase_complete_reboot_required'));
        this.emit('rebase-done');
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
