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
    super({
      application_id: 'org.borshevik.ImageManager',
      flags: Gio.ApplicationFlags.FLAGS_NONE
    });

    const baseDir = GLib.path_get_dirname(import.meta.url.replace('file://', ''));
    this.i18n = new I18n(GLib.build_filenamev([baseDir, 'i18n']));

    this.connect('activate', () => this._onActivate());
  }

  _onActivate() {
    let win = this.active_window;
    if (!win) {
      win = new MainWindow(this);
    }
    win.present();
  }
});
