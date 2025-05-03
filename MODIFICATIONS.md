# Borshevik — MODIFICATIONS.md

## 🎨 Plymouth Boot Splash

* Replaced logo at `/usr/share/plymouth/themes/spinner/watermark.png`
* Using the default `spinner` theme
* No custom `scriptfile` or animation
* Logo is embedded into initramfs during ISO build

## 🧩 GNOME Shell Extensions

* Implemented user-space extension management system:

  * Python script `gnome-extension-subscription`
  * Uses `venv` at `$HOME/.local/share/gnome-extension-subscription/`
  * Automatically installs and upgrades `gnome-extensions-cli`
  * Installs extensions from list at `/usr/share/gnome-extension-subscription/extensions.txt` via extensions.gnome.org
  * Logs installed UUIDs to `installed.txt` to avoid reinstalling removed extensions
* Service:

  * systemd user unit: `gnome-extension-subscription.service`
  * Enabled by default via preset: `/usr/lib/systemd/user-preset/99-gnome-extension-subscription.preset`
  * Starts after `graphical-session.target` with `sleep 5` delay

## 📦 Flatpak Auto-Installer

* Bash script `app-choice-subscription.sh`

  * Reads `/usr/share/app-choice-subscription/flatpaks.txt`
  * Installs missing Flatpak apps from Flathub
  * Tracks installed apps in `$HOME/.local/share/app-choice-subscription/flatpaks-installed.txt`
  * Removed apps by user are not reinstalled
* Launched via systemd user service (enabled via preset)

## 🧹 System Component Removal

* Removed:

  * `gnome-shell-extension-*`
  * `gnome-classic-session`
* Retained:

  * `gnome-initial-setup`

## ⚙️ GNOME Control Center

* Rebuilt `gnome-control-center` with the following patches:

  * Enabled **Fractional Scaling**
  * Enabled **VRR (Variable Refresh Rate)**
* Installed via custom RPM
* Built from custom source with COPR: [https://copr.fedorainfracloud.org/coprs/komorebithrows/borshevik/](https://copr.fedorainfracloud.org/coprs/komorebithrows/borshevik/)

## 🌐 Google Chrome

* Included by default via:

  * `rpm-ostree install -y google-chrome-stable`
  * Official Google RPM used
* Default features:

  * **Wayland backend**
  * **Touchpad gestures** (swipe, pinch)
* Optionally launched with custom flags via `.desktop` override

## 🧬 Kernel and Boot Parameters

* Kernel boot parameter `preempt=full` added

  * Applied via `rpm-ostree kargs`
* initramfs is regenerated during ISO build, so changes are effective immediately post-install

## 🌀 Project Philosophy

This project is, in essence, a vibe-coded distribution built with the help of ChatGPT and some deeply personal choices about how a system should behave.
