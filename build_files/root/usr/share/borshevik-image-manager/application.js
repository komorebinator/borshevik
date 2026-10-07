import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';

import { MainWindow } from './main_window.js';
import { I18n } from './i18n.js';

// GObject subclasses must be registered; otherwise instantiation fails
// with "Tried to construct an object without a GType".
export const Application = GObject.registerClass(
class Application extends Adw.Application {
  constructor() {
    // CAN_OVERRIDE_APP_ID: a copy run from the working tree takes
    // --gapplication-app-id=org.borshevik.ImageManager.Devel, so it runs beside
    // the installed one on the session's own bus (@ImageManagerApp#recipes#run).
    super({
      application_id: 'org.borshevik.ImageManager',
      flags: Gio.ApplicationFlags.CAN_OVERRIDE_APP_ID
    });

    // Use Gio.File to properly convert file:// URI to path
    const scriptFile = Gio.File.new_for_uri(import.meta.url);
    const baseDir = scriptFile.get_parent().get_path();
    this.i18n = new I18n(GLib.build_filenamev([baseDir, 'i18n']));

    // `--page android` opens the window on that tab — the App Manager's way
    // of handing a user who just installed Android to its registration steps.
    // Passed as an action, so an instance already running switches its window.
    this.add_main_option('page', 0, GLib.OptionFlags.NONE, GLib.OptionArg.STRING,
      'The tab to show: system or android', 'TAB');
    this.connect('handle-local-options', (_app, options) => {
      const page = options.lookup_value('page', new GLib.VariantType('s'))?.unpack();
      if (page) {
        this.register(null);
        this.activate_action('show-page', new GLib.Variant('s', page));
      }
      return -1;
    });

    const showPage = new Gio.SimpleAction({ name: 'show-page', parameter_type: new GLib.VariantType('s') });
    showPage.connect('activate', (_action, param) => {
      const win = this._window();
      win.showPage(param.unpack());
      win.present();
    });
    this.add_action(showPage);

    this.connect('activate', () => this._onActivate());
  }

  _window() {
    return this.active_window ?? new MainWindow(this);
  }

  _onActivate() {
    this._window().present();
  }
});
