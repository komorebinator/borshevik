# <img src="borshevik_logo.svg" alt="Logo" width="26"> Borshevik
[🇬🇧 English](README.md) | [🇷🇺 Русский](README.ru.md)

## 🌸 Core Image

Borshevik ships as a single, immutable image built on Fedora Atomic with help from the uBlue project and compiled in GitHub Actions. You get the whole system in one read‑only layer that updates atomically; if something goes wrong, you can boot the previous image and keep working. Fedora’s rapid package stream and SELinux safeguards are already there. Unlike stock Fedora, the base image also ships with the most‑used multimedia codecs, pre‑built by the uBlue team, so you can play media right after install. For NVIDIA GPUs a separate build includes the proprietary driver out of the box, so graphics work without extra steps. As part of the wider uBlue family—think Bazzite for gaming or Bluefin for workstation tweaks—you can jump to Borshevik or back again with a single rpm‑ostree rebase, no reinstall needed.

## 🌐 Google Chrome

Google Chrome comes preinstalled in Borshevik using the latest official RPM directly from Google. It runs natively on Wayland by default and supports smooth touchpad gestures like swipe and pinch out of the box, with no tweaks required.

## 📦 Application Set

Borshevik includes a background service that auto-installs a hand-picked set of creative and essential apps from Flathub. The full list lives in [flatpaks.txt](build_files/root/usr/share/app-choice-subscription/flatpaks.txt). Removed apps won’t come back, but new additions are brought in automatically.

This out-of-the-box suite covers daily work and creative needs: GIMP, video editor, LibreOffice, Contacts, Calendar, VLC, OBS Studio, audio editor, Bottles (for Windows apps), Steam, Telegram, and even a local AI runner for models like Alpaca.

## 🧩 GNOME Extensions

Borshevik comes with a set of GNOME Shell extensions preinstalled during image build. Most of them are cloned directly from Git repositories, while GSConnect is included via RPM. Some extensions are patched for compatibility with the current GNOME version — all patches are visible in the same [list.json](build_files/scripts/gs-extensions/list.json), so nothing is hidden or undocumented. The set includes useful additions like clipboard history, color picker, always-on-top Picture-in-Picture, fullscreen-to-workspace behavior, and a charge limiter for laptops. Some extras like TwitchLive and Blur My Shell are also included.

## 🧬 Kernel

The kernel is the default one from Fedora, with no custom modifications. Borshevik includes a systemd service that manages kernel arguments automatically: preempt=full is enabled for all systems, and recommended flags for Wayland/NVIDIA setups are applied when an NVIDIA GPU is detected.

## ⚙️ GNOME Control Center

Rebuilt with patches to enable Fractional Scaling and VRR (Variable Refresh Rate). Delivered through a custom RPM built via COPR.

## 🌱 Development Tools

Ghostty is included as the terminal emulator. Zsh is available as an alternative shell. Distrobox is included for easily launching full Linux environments inside containers.
