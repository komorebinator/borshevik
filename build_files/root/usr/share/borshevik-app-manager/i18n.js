export const TRANSLATIONS = {
  en: {
    appTitle: "Borshevik App Manager",
    loadingTitle: "Loading…",
    loadingBody: "Downloading the application list…",
    loadFailedTitle: "Couldn’t load application list",
    loadFailedBody: "Check your internet connection and try again.",
    retry: "Retry",

    welcomeTitle: "Welcome!",
    welcomeBody:
      "Choose categories to install, or enable Custom to paste a list from another computer.",
    categoriesHeader: "Categories",
    customHeader: "Custom",
    enableCustom: "Custom",
    customPlaceholder:
      "Paste Flatpak app IDs here, one per line.\nExample:\norg.gnome.Calculator\norg.gnome.Weather",
    copyCommandLabel: "Command to get a compatible list on another machine:",
    copyInstalledBtn: "Copy my installed Flathub apps",
    copiedToast: "Copied to clipboard",
    copyFailedToast: "Couldn’t copy (is flatpak installed?)",
    installBtn: "Install",
    nothingSelectedToast: "Nothing selected",
    installingTitle: "Installing…",
    installingFmt: "Installing {app} ({idx} of {total})",
    alreadyInstalledFmt: "Already installed {app} ({idx} of {total})",
    alreadyInstalledHeader: "Already installed",
    preparing: "Preparing…",
    doneTitle: "All set!",
    doneBody: "Selected applications have been installed.",
    ok: "OK",
    errorTitle: "Installation failed",
    errorBodyFmt: "The installer failed while installing:\n{app}\n\nDetails:\n{details}",
    cancelBtn: "Cancel",
    cancelling: "Cancelling…",
    resultsTitle: "Done",
    resultsBody: "Installation finished.",
    installedHeader: "Installed",
    failedHeader: "Failed",
    canceledNote: "Cancelled by user.",
    copyResultsBtn: "Copy report",
    reportCopiedToast: "Report copied",
},

  ru: {
    appTitle: "Менеджер приложений Borshevik",
    loadingTitle: "Загрузка…",
    loadingBody: "Скачиваем список приложений…",
    loadFailedTitle: "Не удалось получить список приложений",
    loadFailedBody: "Проверьте интернет-соединение и попробуйте ещё раз.",
    retry: "Повторить",

    welcomeTitle: "Добро пожаловать!",
    welcomeBody:
      "Выберите категории для установки, или включите Custom и вставьте свой список с другого компьютера.",
    categoriesHeader: "Категории",
    customHeader: "Custom",
    enableCustom: "Свой список",
    customPlaceholder:
      "Вставьте сюда Flatpak ID приложений (по одному на строку).\nНапример:\norg.gnome.Calculator\norg.gnome.Weather",
    copyCommandLabel: "Команда, чтобы получить подходящий список на другой машине:",
    copyInstalledBtn: "Скопировать мои приложения из Flathub",
    copiedToast: "Скопировано в буфер обмена",
    copyFailedToast: "Не удалось скопировать (есть ли flatpak?)",
    installBtn: "Установить",
    nothingSelectedToast: "Ничего не выбрано",
    installingTitle: "Установка…",
    installingFmt: "Устанавливаем {app} ({idx} из {total})",
    alreadyInstalledFmt: "Уже установлено: {app} ({idx} из {total})",
    alreadyInstalledHeader: "Уже установлено",
    preparing: "Подготовка…",
    doneTitle: "Готово!",
    doneBody: "Выбранные приложения установлены.",
    ok: "ОК",
    errorTitle: "Ошибка установки",
    errorBodyFmt: "Ошибка при установке:\n{app}\n\nДетали:\n{details}",
    cancelBtn: "Отмена",
    cancelling: "Отмена…",
    resultsTitle: "Готово",
    resultsBody: "Установка завершена.",
    installedHeader: "Установлено",
    failedHeader: "Не удалось установить",
    canceledNote: "Отменено пользователем.",
    copyResultsBtn: "Скопировать отчет",
    reportCopiedToast: "Отчет скопирован",
},
};

export function detectLang(env = {}) {
  const s = (env.LC_ALL || env.LANG || env.LANGUAGE || "").toString().trim().toLowerCase();
  if (s.startsWith("ru") || s.includes("ru_") || s.includes("ru-")) return "ru";
  return "en";
}

function normalizeLang(lang) {
  if (!lang) return null;
  const s = String(lang).trim().toLowerCase().replace("_", "-");
  if (!s) return null;
  if (s.startsWith("ru")) return "ru";
  if (s.startsWith("en")) return "en";
  return null;
}

export function makeTranslator(forcedLang = null, env = {}) {
  const lang = normalizeLang(forcedLang) || detectLang(env);
  const dict = TRANSLATIONS[lang] || TRANSLATIONS.en;

  function t(key, vars = null) {
    let s = dict[key] ?? TRANSLATIONS.en[key] ?? key;
    if (vars) for (const [k, v] of Object.entries(vars)) s = s.replaceAll(`{${k}}`, String(v));
    return s;
  }

  return { t, lang };
}
