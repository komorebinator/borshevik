// Unified progress window for all long-running operations.
import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';
import Pango from 'gi://Pango';
import Vte from 'gi://Vte?version=3.91';

export const ProgressWindow = GObject.registerClass(
  {
    Signals: {
      'operation-complete': { param_types: [GObject.TYPE_BOOLEAN] },
      'operation-cancelled': {}
    }
  },
  class ProgressWindow extends Adw.Window {
    constructor({ application, transient_for, title }) {
      super({
        application,
        transient_for,
        title: title || 'Progress',
        default_width: 700,
        default_height: 500,
        modal: true,
        deletable: false
      });

      this._app = application;
      this._pulseId = null;
      this._runner = null;
      this._commandText = '';
      this._initUi();
    }

    _initUi() {
      const i18n = this._app.i18n;
      
      const header = new Adw.HeaderBar();
      const toolbarView = new Adw.ToolbarView();
      toolbarView.add_top_bar(header);

      // Outer box for the whole content (without Clamp — VTE needs full width)
      const outerBox = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL,
        spacing: 12,
        margin_top: 16,
        margin_bottom: 16,
        margin_start: 16,
        margin_end: 16
      });

      // Top controls are clamped so they don't stretch too wide
      const clamp = new Adw.Clamp({ maximum_size: 720, tightening_threshold: 560 });
      const topControlsBox = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL,
        spacing: 8
      });

      // Horizontal box: [Command + Progress] [Cancel]
      const topBox = new Gtk.Box({
        orientation: Gtk.Orientation.HORIZONTAL,
        spacing: 8,
        valign: Gtk.Align.CENTER
      });

      // Left side: vertical box with command and progress
      const leftBox = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL,
        spacing: 4,
        hexpand: true,
        valign: Gtk.Align.CENTER
      });

      // Command label
      this._commandLabel = new Gtk.Label({
        xalign: 0,
        wrap: true,
        selectable: false,
        css_classes: ['caption']
      });
      leftBox.append(this._commandLabel);

      // Progress bar
      this._progress = new Gtk.ProgressBar({ 
        show_text: false,
        hexpand: true
      });
      this._progress.set_pulse_step(0.05);
      leftBox.append(this._progress);

      topBox.append(leftBox);

      // Cancel button on the right
      this._cancelButton = new Gtk.Button({ 
        label: i18n.t('cancel'),
        sensitive: true,
        valign: Gtk.Align.CENTER
      });
      this._cancelButton.connect('clicked', () => this._onCancel());
      topBox.append(this._cancelButton);

      topControlsBox.append(topBox);
      clamp.set_child(topControlsBox);
      outerBox.append(clamp);

      // VTE terminal — outside Clamp so it gets full width allocation.
      // ScrolledWindow must NOT wrap VTE (VTE implements GtkScrollable itself).
      // Instead, attach a plain Scrollbar to VTE's own vadjustment.
      const frame = new Gtk.Frame({
        vexpand: true,
        margin_top: 4
      });

      this._terminal = new Vte.Terminal({
        hexpand: true,
        vexpand: true
      });

      const scrollbar = new Gtk.Scrollbar({
        orientation: Gtk.Orientation.VERTICAL,
        adjustment: this._terminal.get_vadjustment()
      });

      const termBox = new Gtk.Box({
        orientation: Gtk.Orientation.HORIZONTAL
      });
      termBox.append(this._terminal);
      termBox.append(scrollbar);

      frame.set_child(termBox);
      outerBox.append(frame);

      this._closeButton = new Gtk.Button({ 
        label: i18n.t('close'), 
        sensitive: false 
      });
      this._closeButton.connect('clicked', () => this.close());
      outerBox.append(this._closeButton);

      toolbarView.set_content(outerBox);
      this.set_content(toolbarView);
    }

    setCommand(argv) {
      this._commandText = argv.join(' ');
      this._commandLabel.set_label(this._commandText);
    }

    setRunner(runner) {
      this._runner = runner;
    }

    _onCancel() {
      this.emit('operation-cancelled');
      this._cancelButton.set_sensitive(false);
      
      if (this._runner && this._runner.cancel) {
        this._runner.cancel();
      }
    }

    startProgress() {
      this._closeButton.set_sensitive(false);
      this._cancelButton.set_sensitive(true);
      this._terminal.reset(true, true);
      
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

    stopProgress(success = true) {
      if (this._pulseId) {
        GLib.source_remove(this._pulseId);
        this._pulseId = null;
      }
      this._progress.set_fraction(1.0);
      this._cancelButton.set_sensitive(false);
      this._closeButton.set_sensitive(true);
      this.emit('operation-complete', success);
    }

    _parseProgress(text) {
      // Ищем паттерны типа [19/42] или (19/42)
      const match = text.match(/[\[\(](\d+)\/(\d+)[\]\)]/);
      if (match) {
        const current = parseInt(match[1], 10);
        const total = parseInt(match[2], 10);
        if (total > 0) {
          const fraction = current / total;
          this._progress.set_fraction(fraction);
          // Останавливаем pulse когда есть реальный прогресс
          if (this._pulseId) {
            GLib.source_remove(this._pulseId);
            this._pulseId = null;
          }
          return true;
        }
      }
      return false;
    }

    appendOutput(text) {
      // VTE — настоящий терминал, ожидает \r\n, а не просто \n
      this._terminal.feed(text.replaceAll('\n', '\r\n'));
      
      // Парсим прогресс из текста
      this._parseProgress(text);
    }

    clearOutput() {
      this._terminal.reset(true, true);
    }
  }
);
