# <img src="assets/borshevik_logo.svg" alt="Logo" width="26"> Borshevik


Borshevik is an immutable desktop image for laptops and desktops, built on Fedora Atomic and the uBlue ecosystem, designed to be simple to use and ready to go right after installation. It’s delivered as a single, read-only system image with atomic updates and easy rollbacks. It includes stock Fedora GNOME tuned with a small set of GNOME Shell extensions, plus multimedia support, Chrome, Steam, Android apps from Google Play, a built-in VPN client with VLESS and other censorship-resistant protocols, and a curated Flatpak set — so you can install it and get straight to work, even if you’re new to Linux.

More on the site, with news: [borshevik.org](https://borshevik.org).

## 🎯 Who is this image for?

Borshevik is built as a practical daily driver with a clear target audience:

- **Laptops and desktops alike:** defaults and UX are tuned for modern laptops and desktop machines.
- **Built for daily work:** tuned for everyday productivity and daily use.
- **Also good for gaming:** Steam is included and works out of the box.
- **Predictable and low-maintenance:** the “turn it on and start working” mindset, with consistent behavior and easy recovery.

## 🌸 Core Image

Borshevik is built as a single, read-only system image on top of Fedora Atomic with help from the uBlue ecosystem. Updates land as complete images: you install the new one, and if something breaks you can simply boot back into the previous version. Common multimedia codecs are included so video and audio work right after install. There is also a separate NVIDIA build with the proprietary driver preinstalled.

## 🌐 Chrome

Chrome comes preinstalled using the official RPM from Google. It runs natively on Wayland and supports smooth touchpad gestures out of the box, with no extra setup required.

## 🎮 Steam

Steam comes preinstalled, so you can play right away without extra setup. Many games work out of the box, and PortProton, installed from the App Manager, runs any other launcher — Battle.net, EA app, Epic Games Store and the rest.

## 🤖 Android Apps

Borshevik can run Android apps in windows of their own, alongside your desktop apps. Android support is optional and installed on demand — from the Android tab of the Image Manager, or by checking it in the App Manager — and downloads about 1.4 GB. It runs on [Waydroid](https://waydro.id) with Google Play services, so apps install from Google Play and keep themselves up to date. Google asks for the device to be registered with your account once before Google Play signs in; the Image Manager shows the device ID and links to the registration page. Game controllers work too.

## 📦 Application Set

Borshevik includes Borshevik App Manager, which opens on first login. Its **New installation** tab offers a recommended set of Flatpak apps grouped by use case (work, media, development, communication, and more) and additional modules, such as support for Android apps — a solid starter pack without hunting for apps one by one.

Its **From another PC** tab carries your setup over from an older computer: copy its configuration there — with the App Manager on Borshevik, or with a short script on any other Linux — and paste it here to install the same apps and modules in one go. Pairing both computers with GSConnect gives them a shared clipboard to carry it.

## 🔒 VPN

[Hiddify](https://github.com/hiddify/hiddify-app) comes preinstalled — a native desktop VPN client powered by [sing-box](https://github.com/SagerNet/sing-box). It runs as a tray application and supports VLESS + Reality and the other modern censorship-resistant protocols. Import a share link or a subscription and connect.

## 🧩 GNOME Extensions

Borshevik ships with a set of GNOME Shell extensions preinstalled during the image build. The full list and any patches are documented in [list.json](build_files/scripts/gs-extensions/list.json), so you can always see what’s included.

These extensions add small quality-of-life improvements like clipboard history, a color picker, picture-in-picture, workspace tweaks, and a few visual enhancements.

## 🛡️ Privacy & Telemetry

Borshevik does not add extra telemetry or tracking on top of what Fedora already ships. There are no required online accounts, and the system image is fully documented and reproducible via the public build files in this repository.

## 💿 Install

The full installation guide is on the site, step by step, with videos and pictures: [borshevik.org/install](https://borshevik.org/install).
