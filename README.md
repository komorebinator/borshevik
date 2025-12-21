# <img src="assets/borshevik_logo.svg" alt="Logo" width="26"> Borshevik


Borshevik is an immutable, laptop-first desktop image built on top of Fedora Atomic and the uBlue ecosystemaiming to be a more capable alternative to ChromeOS. It ships as a single read-only system image with atomic updates and simple rollbacks, the stock Fedora GNOME desktop tuned with a small set of preinstalled GNOME Shell extensions, multimedia support, Chrome, Steam, and a curated Flatpak set — so you can install it and start using it right away, even if you’re new to Linux.

## 🎯 Who is this image for?

Borshevik is built as a practical daily driver with a clear target audience:

- **Laptop-first (but desktops are supported too):** defaults and UX are tuned primarily for modern laptops, while still working great on desktop machines.
- **Built for daily work:** tuned for everyday productivity and daily use.
- **Also good for gaming:** Steam is included and works out of the box.
- **A “ChromeOS, but more capable” alternative:** the same “turn it on and start working” mindset, but with a full Linux desktop that runs native apps out of the box.

## 🌸 Core Image

Borshevik is built as a single, read-only system image on top of Fedora Atomic with help from the uBlue ecosystem. Updates land as complete images: you install the new one, and if something breaks you can simply boot back into the previous version. Common multimedia codecs are included so video and audio work right after install. There is also a separate NVIDIA build with the proprietary driver preinstalled.

## 🌐 Chrome

Chrome comes preinstalled using the official RPM from Google. It runs natively on Wayland and supports smooth touchpad gestures out of the box, with no extra setup required.

## 📦 Application Set

A small background service automatically installs a curated set of apps from Flathub after the first boot. The full list lives in [flatpaks.txt](build_files/root/usr/share/app-choice-subscription/flatpaks.txt). Apps you remove stay removed, but new additions from that list are pulled in for you.

This set covers everyday work, media, gaming, and communication, so most people can just sign in and start using the system right away.

## 🧩 GNOME Extensions

Borshevik ships with a set of GNOME Shell extensions preinstalled during the image build. The full list and any patches are documented in [list.json](build_files/scripts/gs-extensions/list.json), so you can always see what’s included.

These extensions add small quality-of-life improvements like clipboard history, a color picker, picture-in-picture, workspace tweaks, and a few visual enhancements.

## 👷 Rebasing from another uBlue

If you’re already on another Fedora Atomic or uBlue image, you can switch to Borshevik with a single rebase command:

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/komorebinator/borshevik:stable
```

or, for NVIDIA GPUs:

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/komorebinator/borshevik-nvidia:stable
```

After the rebase, reboot into the new image and you’re done.

## 🛡️ Privacy & Telemetry

Borshevik does not add extra telemetry or tracking on top of what Fedora already ships. There are no required online accounts, and the system image is fully documented and reproducible via the public build files in this repository.

[![Download](assets/download.svg)](https://borshevik.org/iso/borshevik-stable.iso)  
[![Download](assets/download-nvidia.svg)](https://borshevik.org/iso/borshevik-nvidia-stable.iso)