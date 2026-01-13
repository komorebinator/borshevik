#!/usr/bin/env gjs -m
import Adw from "gi://Adw?version=1";
import GLib from "gi://GLib";
import GObject from "gi://GObject";

import { makeTranslator } from "./i18n.js";
import { AppWindow } from "./window.js";

function parseLangArg(argv) {
  // Supports: --lang=ru / --lang=en or --lang ru
  const args = argv ?? [];
  for (let i = 0; i < args.length; i++) {
    const a = String(args[i]);
    const next = i + 1 < args.length ? String(args[i + 1]) : null;

    if (a === "--lang" && next) return next.trim();
    if (a.startsWith("--lang=")) return a.substring("--lang=".length).trim();
  }
  return null;
}


const BorshevikAppManager = GObject.registerClass(
class BorshevikAppManager extends Adw.Application {
  _init() {
    super._init({
      application_id: "org.borshevik.AppManager",
      flags: 0,
    });
  }

  vfunc_activate() {
    const env = {
      LANG: GLib.getenv("LANG") ?? "",
      LC_ALL: GLib.getenv("LC_ALL") ?? "",
      LANGUAGE: GLib.getenv("LANGUAGE") ?? "",
    };
    const forcedLang = parseLangArg(ARGV);
    const i18n = makeTranslator(forcedLang, env);

    const win = new AppWindow(this, i18n);
    win.present();
  }
});

Adw.init();
const app = new BorshevikAppManager();
app.run(ARGV);
