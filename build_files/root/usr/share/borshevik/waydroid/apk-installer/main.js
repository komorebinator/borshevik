#!/usr/bin/env gjs -m
// The window that opens an APK once Android is installed: it asks first, then
// installs (install.js) and offers to open the app. One window per file.
// See @WaydroidApp#apk-installer in spec/.

import Adw from "gi://Adw?version=1";
import Gdk from "gi://Gdk?version=4.0";
import Gio from "gi://Gio";
import GLib from "gi://GLib";
import GObject from "gi://GObject";
import Gtk from "gi://Gtk?version=4.0";
import System from "system";

import { isAndroidInstalled, readApk, installedPackages, installApk, launchApp, InstallError } from "./install.js";

const TRANSLATIONS = {
  en: {
    title: "Install in Android",
    installQuestion: "Install {pkg} in Android?",
    updateQuestion: "Update {pkg} in Android?",
    fileLine: "{file} · {size}",
    versionLine: "Version {version}",
    cancel: "Cancel",
    install: "Install",
    update: "Update",
    starting: "Starting Android…",
    booting: "Waiting for Android…",
    installing: "Installing…",
    verifying: "Waiting for Android to finish installing…\nAndroid may ask you to confirm in its own window.",
    installed: "Installed",
    updated: "Updated",
    doneBody: "{pkg} is in Android.",
    open: "Open",
    close: "Close",
    failedTitle: "Couldn’t install",
    notAndroidInstalled: "Android is not installed. Install it from the Android tab of the Image Manager.",
    notApk: "This file is not an Android app.",
    notStarted: "Android did not start.",
    notBooted: "Android did not finish starting.",
    notInstalled: "Android did not install the app — it may not support this device, or conflict with a version already installed.",
  },
  ru: {
    title: "Установка в Android",
    installQuestion: "Установить {pkg} в Android?",
    updateQuestion: "Обновить {pkg} в Android?",
    fileLine: "{file} · {size}",
    versionLine: "Версия {version}",
    cancel: "Отмена",
    install: "Установить",
    update: "Обновить",
    starting: "Запускаем Android…",
    booting: "Ждём Android…",
    installing: "Устанавливаем…",
    verifying: "Ждём, пока Android закончит установку…\nAndroid может попросить подтвердить её в своём окне.",
    installed: "Установлено",
    updated: "Обновлено",
    doneBody: "{pkg} теперь в Android.",
    open: "Открыть",
    close: "Закрыть",
    failedTitle: "Не удалось установить",
    notAndroidInstalled: "Android не установлен. Установите его на вкладке Android в менеджере образов.",
    notApk: "Этот файл — не приложение Android.",
    notStarted: "Android не запустился.",
    notBooted: "Android не закончил запуск.",
    notInstalled: "Android не установил приложение — возможно, оно не поддерживает это устройство или конфликтует с уже установленной версией.",
  },
  uk: {
    title: "Встановлення в Android",
    installQuestion: "Встановити {pkg} в Android?",
    updateQuestion: "Оновити {pkg} в Android?",
    fileLine: "{file} · {size}",
    versionLine: "Версія {version}",
    cancel: "Скасувати",
    install: "Встановити",
    update: "Оновити",
    starting: "Запускаємо Android…",
    booting: "Чекаємо на Android…",
    installing: "Встановлюємо…",
    verifying: "Чекаємо, поки Android завершить встановлення…\nAndroid може попросити підтвердити його у своєму вікні.",
    installed: "Встановлено",
    updated: "Оновлено",
    doneBody: "{pkg} тепер в Android.",
    open: "Відкрити",
    close: "Закрити",
    failedTitle: "Не вдалося встановити",
    notAndroidInstalled: "Android не встановлено. Встановіть його на вкладці Android у менеджері образів.",
    notApk: "Цей файл — не застосунок Android.",
    notStarted: "Android не запустився.",
    notBooted: "Android не завершив запуск.",
    notInstalled: "Android не встановив застосунок — можливо, він не підтримує цей пристрій або конфліктує з уже встановленою версією.",
  },
  be: {
    title: "Усталёўка ў Android",
    installQuestion: "Усталяваць {pkg} у Android?",
    updateQuestion: "Абнавіць {pkg} у Android?",
    fileLine: "{file} · {size}",
    versionLine: "Версія {version}",
    cancel: "Скасаваць",
    install: "Усталяваць",
    update: "Абнавіць",
    starting: "Запускаем Android…",
    booting: "Чакаем Android…",
    installing: "Усталёўваем…",
    verifying: "Чакаем, пакуль Android скончыць усталёўку…\nAndroid можа папрасіць пацвердзіць яе ў сваім акне.",
    installed: "Усталявана",
    updated: "Абноўлена",
    doneBody: "{pkg} цяпер у Android.",
    open: "Адкрыць",
    close: "Закрыць",
    failedTitle: "Не ўдалося ўсталяваць",
    notAndroidInstalled: "Android не ўсталяваны. Усталюйце яго на ўкладцы Android у менеджары вобразаў.",
    notApk: "Гэты файл — не прыкладанне Android.",
    notStarted: "Android не запусціўся.",
    notBooted: "Android не скончыў запуск.",
    notInstalled: "Android не ўсталяваў прыкладанне — магчыма, яно не падтрымлівае гэту прыладу або канфліктуе з ужо ўсталяванай версіяй.",
  },
  ka: {
    title: "Android-ში დაყენება",
    installQuestion: "დავაყენოთ {pkg} Android-ში?",
    updateQuestion: "განვაახლოთ {pkg} Android-ში?",
    fileLine: "{file} · {size}",
    versionLine: "ვერსია {version}",
    cancel: "გაუქმება",
    install: "დაყენება",
    update: "განახლება",
    starting: "ვუშვებთ Android-ს…",
    booting: "ველოდებით Android-ს…",
    installing: "ვაყენებთ…",
    verifying: "ველოდებით, სანამ Android დაასრულებს დაყენებას…\nAndroid-მა შეიძლება თავის ფანჯარაში დადასტურება მოგთხოვოთ.",
    installed: "დაყენებულია",
    updated: "განახლებულია",
    doneBody: "{pkg} ახლა Android-შია.",
    open: "გახსნა",
    close: "დახურვა",
    failedTitle: "დაყენება ვერ მოხერხდა",
    notAndroidInstalled: "Android არ არის დაყენებული. დააყენეთ ის სურათების მენეჯერის Android ჩანართზე.",
    notApk: "ეს ფაილი არ არის Android აპლიკაცია.",
    notStarted: "Android არ გაეშვა.",
    notBooted: "Android-მა გაშვება ვერ დაასრულა.",
    notInstalled: "Android-მა აპლიკაცია ვერ დააყენა — შესაძლოა, ის ამ მოწყობილობას არ უჭერს მხარს ან კონფლიქტშია უკვე დაყენებულ ვერსიასთან.",
  },
  hy: {
    title: "Տեղադրում Android-ում",
    installQuestion: "Տեղադրե՞լ {pkg}-ը Android-ում:",
    updateQuestion: "Թարմացնե՞լ {pkg}-ը Android-ում:",
    fileLine: "{file} · {size}",
    versionLine: "Տարբերակ {version}",
    cancel: "Չեղարկել",
    install: "Տեղադրել",
    update: "Թարմացնել",
    starting: "Գործարկում ենք Android-ը…",
    booting: "Սպասում ենք Android-ին…",
    installing: "Տեղադրում ենք…",
    verifying: "Սպասում ենք, որ Android-ն ավարտի տեղադրումը…\nAndroid-ը կարող է իր պատուհանում խնդրել հաստատել այն:",
    installed: "Տեղադրված է",
    updated: "Թարմացված է",
    doneBody: "{pkg}-ն այժմ Android-ում է:",
    open: "Բացել",
    close: "Փակել",
    failedTitle: "Չհաջողվեց տեղադրել",
    notAndroidInstalled: "Android-ը տեղադրված չէ: Տեղադրեք այն պատկերների կառավարչի Android ներդիրում:",
    notApk: "Այս ֆայլը Android հավելված չէ:",
    notStarted: "Android-ը չգործարկվեց:",
    notBooted: "Android-ը չավարտեց գործարկումը:",
    notInstalled: "Android-ը չտեղադրեց հավելվածը. հնարավոր է, այն չի աջակցում այս սարքը կամ հակասում է արդեն տեղադրված տարբերակին:",
  },
};

function makeTranslator() {
  const env = (GLib.getenv("LC_ALL") || GLib.getenv("LC_MESSAGES") || GLib.getenv("LANG") || "").toLowerCase();
  const lang = Object.keys(TRANSLATIONS).find((l) => env.startsWith(l)) ?? "en";
  return (key, vars = {}) => {
    let s = TRANSLATIONS[lang][key] ?? TRANSLATIONS.en[key] ?? key;
    for (const [k, v] of Object.entries(vars)) s = s.replaceAll(`{${k}}`, String(v));
    return s;
  };
}

const t = makeTranslator();

const InstallerWindow = GObject.registerClass(
class InstallerWindow extends Adw.ApplicationWindow {
  _init(app, file) {
    super._init({ application: app, title: t("title"), default_width: 460, resizable: false });
    this._path = file?.get_path() ?? null;
    this._name = file?.get_basename() ?? "";

    this._status = new Adw.StatusPage({ icon_name: "waydroid", vexpand: true });
    this._buttons = new Gtk.Box({ spacing: 12, halign: Gtk.Align.CENTER, homogeneous: true });
    this._status.set_child(this._buttons);

    const view = new Adw.ToolbarView();
    view.add_top_bar(new Adw.HeaderBar({ show_title: false }));
    view.set_content(this._status);
    this.set_content(view);

    this._start();
  }

  _show({ icon, picture = null, title, body = "", spinner = false, buttons = [] }) {
    this._status.set_paintable(spinner ? new Adw.SpinnerPaintable({ widget: this._status }) : picture);
    if (!spinner && !picture) this._status.set_icon_name(icon);
    this._status.set_title(title);
    this._status.set_description(body);
    for (let c = this._buttons.get_first_child(); c; c = this._buttons.get_first_child())
      this._buttons.remove(c);
    for (const { label, suggested, action } of buttons) {
      const b = new Gtk.Button({ label, css_classes: suggested ? ["suggested-action", "pill"] : ["pill"] });
      b.connect("clicked", action);
      this._buttons.append(b);
    }
    // Closing mid-install would leave the user not knowing whether it happened.
    this.set_deletable(!spinner);
  }

  _fail(message) {
    this._show({
      icon: "dialog-error-symbolic",
      title: t("failedTitle"),
      body: message,
      buttons: [{ label: t("close"), action: () => this.close() }],
    });
  }

  async _start() {
    if (!isAndroidInstalled()) {
      this._fail(t("notAndroidInstalled"));
      return;
    }
    let apk;
    try {
      if (!this._path) throw new Error("no file");
      apk = await readApk(this._path);
    } catch (e) {
      this._fail(t("notApk"));
      return;
    }

    // Whether Android has it already, when that can be asked without starting
    // Android; a stopped Android answers with an empty list, and Install then.
    let had = false;
    try { had = (await installedPackages()).has(apk.package); } catch {}

    const size = GLib.format_size(Gio.File.new_for_path(this._path).query_info("standard::size", 0, null).get_size());
    const lines = [t("fileLine", { file: this._name, size })];
    if (apk.version) lines.push(t("versionLine", { version: apk.version }));
    this._show({
      icon: "waydroid",
      title: t(had ? "updateQuestion" : "installQuestion", { pkg: apk.package }),
      body: lines.join("\n"),
      buttons: [
        { label: t("cancel"), action: () => this.close() },
        { label: t(had ? "update" : "install"), suggested: true, action: () => this._install(apk) },
      ],
    });
  }

  // The installed app's own icon, which Waydroid writes for its launcher once
  // Android has the package — a moment after it appears, so waited for briefly.
  async _appIcon(pkg) {
    const path = GLib.build_filenamev([GLib.get_user_data_dir(), "waydroid", "data", "icons", `${pkg}.png`]);
    for (let i = 0; i < 10 && !GLib.file_test(path, GLib.FileTest.EXISTS); i++)
      await new Promise((r) => GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => { r(); return GLib.SOURCE_REMOVE; }));
    try { return Gdk.Texture.new_from_filename(path); } catch { return null; }
  }

  async _install(apk) {
    // A stage's first line is its title; any further line, a hint under it.
    const stage = (name) => {
      const [title, ...hint] = t(name).split("\n");
      this._show({ title, spinner: true, body: [...hint, apk.package].join("\n") });
    };
    stage("installing");
    try {
      const { updated } = await installApk(this._path, apk.package, stage);
      this._show({
        icon: "object-select-symbolic",
        picture: await this._appIcon(apk.package),
        title: t(updated ? "updated" : "installed"),
        body: t("doneBody", { pkg: apk.package }),
        buttons: [
          { label: t("close"), action: () => this.close() },
          { label: t("open"), suggested: true, action: () => { launchApp(apk.package); this.close(); } },
        ],
      });
    } catch (e) {
      const known = e instanceof InstallError ? t(e.code) : null;
      this._fail([known, known ? e.details : String(e?.message ?? e)].filter(Boolean).join("\n\n"));
    }
  }
});

const app = new Adw.Application({
  application_id: "org.borshevik.ApkInstaller",
  flags: Gio.ApplicationFlags.NON_UNIQUE | Gio.ApplicationFlags.HANDLES_OPEN,
});
app.connect("open", (_app, files) => {
  for (const file of files) new InstallerWindow(app, file).present();
});
app.connect("activate", () => new InstallerWindow(app, null).present());
// GApplication takes the program's name first; gjs's ARGV leaves it out.
app.run([System.programInvocationName, ...ARGV]);
