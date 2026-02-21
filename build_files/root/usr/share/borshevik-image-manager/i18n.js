// Simple JSON-based i18n loader.
// - Looks at LC_MESSAGES/LANG
// - Falls back to English
// - If a key is missing, returns the key itself

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

function _readJson(path) {
  try {
    const bytes = GLib.file_get_contents(path)[1];
    const text = new TextDecoder('utf-8').decode(bytes);
    return JSON.parse(text);
  } catch (e) {
    return null;
  }
}

function _getLocale() {
  // Стандартная иерархия Linux: LANGUAGE > LC_ALL > LC_MESSAGES > LANG
  const env = GLib.getenv('LANGUAGE') ||
              GLib.getenv('LC_ALL') ||
              GLib.getenv('LC_MESSAGES') ||
              GLib.getenv('LANG') ||
              'en';
  // LANGUAGE может быть списком через двоеточие: "ru:en_US" — берём первый
  const first = env.split(':')[0];
  const m = first.match(/^([a-zA-Z]{2})/);
  return (m ? m[1] : 'en').toLowerCase();
}

export class I18n {
  constructor(baseDir) {
    this._baseDir = baseDir;
    this._en = _readJson(GLib.build_filenamev([baseDir, 'en.json'])) || {};

    const locale = _getLocale();
    if (locale === 'en') {
      this._dict = this._en;
    } else {
      this._dict = _readJson(GLib.build_filenamev([baseDir, `${locale}.json`])) || {};
    }
  }

  t(key) {
    if (key in this._dict)
      return this._dict[key];
    if (key in this._en)
      return this._en[key];
    return key;
  }
}
