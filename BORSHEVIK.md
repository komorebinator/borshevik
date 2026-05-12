# BORSHEVIK — Project Map

> This is the single entry point for understanding the project. Read this first.
> For AI assistants: architecture, file roles, and key decisions are all here.

## What This Is

**Borshevik** is an immutable Linux desktop OS image for laptops (and desktops),
built on top of Fedora Atomic (Silverblue) and the [Universal Blue](https://universal-blue.org/) ecosystem.

The system ships as an OCI container image, updates atomically, and supports rollback to any
previous version. Goal: "install and get to work" — Chrome, Steam, VPN (GoXRay), GNOME extensions,
multimedia codecs all included out of the box.

**Two image variants:**
- `borshevik` — Intel/AMD GPU
- `borshevik-nvidia` — with proprietary NVIDIA driver

**Image registry:** `ghcr.io/komorebinator/borshevik`
**Tags:** `latest` (current build), `stable` (manually promoted), `DD.MM.YYYY` (by date)

---

## Build Architecture

The build is split into two layers — this is the key architectural decision:

```
[Upstream]  ghcr.io/ublue-os/silverblue-main:44
                     │
          ┌──────────┴──────────┐
     borshevik-base        borshevik-base-nvidia
   (RPMs, Chrome, Steam)   (+ NVIDIA drivers)
          │                    │
     borshevik           borshevik-nvidia
   (+ GoXRay, extensions,  (+ GoXRay, extensions,
    configs, UI tools)      configs, UI tools)
```

**Why two layers?**
The base layer is rebuilt **daily** (cron) to pull in RPM package updates.
The final layer (`borshevik`) rebuilds on every push to `main` — it depends on the already-built
base and is therefore fast.

The **Containerfile** defines all 4 targets (`borshevik-base`, `borshevik-base-nvidia`,
`borshevik`, `borshevik-nvidia`). Each target ends with `ostree container commit`.

---

## File Structure

```
borshevik/
├── Containerfile                  # Multi-stage OCI build
├── Justfile                       # Local commands (build/run VM, lint)
├── README.md                      # Public documentation
├── BORSHEVIK.md                   # ← YOU ARE HERE: main project map
│
├── image.toml                     # BIB config: minimum FS size for ISO
├── borshevik.toml                 # Kickstart config for Anaconda installer
├── borshevik-nvidia.toml          # Same for the NVIDIA variant
│
├── cosign.pub                     # Sigstore/cosign public key (image verification)
├── cosign.key                     # Private key (CI uses GitHub Secrets — do not leak)
├── artifacthub-repo.yml           # ArtifactHub registration
│
├── assets/                        # Logos and download buttons for README
│
├── installer/
│   └── lorax_templates/           # Templates for Anaconda ISO installer
│       ├── partitioning.tmpl      # Disk layout
│       ├── bootc-switch.tmpl          # Switch to borshevik:latest
│       ├── bootc-switch-stable.tmpl   # Switch to borshevik:stable
│       ├── bootc-switch-nvidia.tmpl
│       └── bootc-switch-nvidia-stable.tmpl
│
├── build_files/
│   ├── scripts/                   # Shell scripts, run inside the build container
│   └── root/                      # Filesystem tree, copied into the image as /
│
└── .github/
    ├── workflows/                 # GitHub Actions CI/CD
    ├── dependabot.yml
    └── renovate.json5
```

---

## build_files/scripts/ — Build Scripts

All scripts run **inside rootful Podman** during `docker build`.

### Orchestrators

| File | When it runs | What it does |
|------|--------------|--------------|
| `build-base.sh` | target `borshevik-base` | RPM packages → Chrome → Steam → cleanup → podman.socket |
| `build-base-nvidia.sh` | target `borshevik-base-nvidia` | Installs NVIDIA kmod + userspace from the akmod image |
| `build-addons.sh` | targets `borshevik`, `borshevik-nvidia` | os-info → GoXRay → GNOME extensions → schemas → dconf → services → initramfs |

### Atomic Scripts

| File | Purpose |
|------|---------|
| `install-rpm-packages.sh` | `rpm-ostree install`: htop, mc, gnome-tweaks, pwgen, openssl, distrobox, zsh, gh, adw-gtk3-theme, meson/cmake/gcc (for building extensions), libxcrypt-compat |
| `install-google-chrome.sh` | Chrome from the official Google RPM repo |
| `install-steam.sh` | Steam via rpm-ostree |
| `install-goxray.sh` | Downloads GoXRay from GitHub Releases, installs to `/usr/lib/goxray/goxray`, sets `setcap` (cap_net_raw+cap_net_admin+cap_net_bind_service) |
| `install-gs-extensions.sh` | Reads `gs-extensions/list.json`, clones extension repos, patches defaults, installs |
| `apply-schemas.sh` | Installs GSchema overrides from `schemas/` |
| `apply-dconf.sh` | Applies dconf system defaults from `dconf/` |
| `enable-services.sh` | `systemctl enable` for system and user units |
| `rebuild-initramfs.sh` | Rebuilds initramfs after everything is installed |
| `cleanup.sh` | Cleans package manager caches and temp files |
| `os-info.sh` | Updates `/usr/lib/os-release` with Borshevik branding |

### gs-extensions/

| File | Purpose |
|------|---------|
| `list.json` | List of GNOME extensions to install (repo, branch, patches) |
| `*.patch` | Patches for extension gschema files (set extension defaults) |
| `appindicator.sh`, `color-picker.sh`, `gsconnect.sh` | Special install scripts for extensions with non-standard build steps |

### schemas/

GSchema overrides — system-wide GNOME defaults that users don't accidentally override:

| File | What it sets |
|------|-------------|
| `90-pink-by-default.gschema.override` | Pink accent color |
| `90-dark-by-default.gschema.override` | Dark theme |
| `90-disable-hot-corners.gschema.override` | Disables hot corners |
| `90-favorites.gschema.override` | Dock: Chrome, Telegram, Nautilus, Calendar, Secrets, Steam, GNOME Software |
| `90-touchpad.gschema.override` | Laptop touchpad settings |
| `90-wm-button-layout.gschema.override` | Window button layout |

### dconf/

dconf profiles applied as system-wide defaults (via `dconf update`):

| File | What it sets |
|------|-------------|
| `local.d/00-dark-by-default` | Adwaita dark theme |
| `local.d/00-enable-app-folders` | App Folders in GNOME Overview |
| `local.d/00-hotkeys` | Super+1..9 → switch workspace; Shift+Super+1..9 → move window; Super+Space → switch input source |
| `gdm.d/gdm` | GDM (login screen) settings |

---

## build_files/root/ — Image Filesystem Tree

Copied into the image root on the final stage (`COPY build_files/root/ /`).

```
root/
├── etc/
│   ├── containers/
│   │   ├── policy.json            # Container image signature verification policy
│   │   └── registries.d/          # Per-registry sigstore verification config
│   ├── gnome-initial-setup/
│   │   └── vendor.conf            # Skips GNOME Initial Setup (software page)
│   └── wireplumber/
│       └── wireplumber.conf.d/    # Audio config (WirePlumber)
│
├── usr/
│   ├── bin/                       # CLI utilities (see below)
│   ├── etc/opt/                   # Vendor configs for /opt applications
│   ├── lib/
│   │   ├── os-release             # Custom os-release (NAME=Borshevik, ID=borshevik)
│   │   ├── systemd/               # systemd units (see below)
│   │   └── tmpfiles.d/            # tmpfiles rules
│   ├── libexec/borshevik/         # Internal scripts (not in PATH)
│   └── share/
│       ├── applications/          # .desktop files (GoXRay, AppManager, ImageManager)
│       ├── borshevik-app-manager/ # Borshevik App Manager source (GJS)
│       ├── borshevik-image-manager/ # Borshevik Image Manager source (GJS)
│       ├── icons/                 # Application icons
│       ├── pixmaps/               # GoXRay icon
│       └── plymouth/              # Custom plymouth boot splash
```

### usr/bin/ — Executables

| File | What it does |
|------|-------------|
| `borshevik-app-manager` | Launches App Manager: `gjs -m /usr/share/borshevik-app-manager/main.js` |
| `borshevik-app-manager-first-run` | Launches App Manager on first login (checks a stamp file) |
| `borshevik-image-manager` | Launches Image Manager: `gjs -m /usr/share/borshevik-image-manager/main.js` |
| `borshevik-promote-to-stable` | CLI wrapper: triggers `gh workflow run promote-image-to-stable.yml` and watches it |
| `goxray` | Wrapper: launches `/usr/lib/goxray/goxray` only if not already running |

### usr/libexec/borshevik/ — Internal Scripts

| File | What it does |
|------|-------------|
| `setup-kargs.sh` | Sets kernel args: adds `preempt=full`; for NVIDIA — `nvidia-drm.modeset=1`, blacklists nouveau/nova_core. Reboots if args changed. |
| `setup-ublue-mok.sh` | Enrolls MOK key for NVIDIA under Secure Boot |
| `borshevik-kill-gnome-if-hung.sh` | Watchdog: kills a hung GNOME Shell |

### usr/lib/systemd/

**System (system/):**

| Unit | Purpose |
|------|---------|
| `setup-kargs.service` | Oneshot at boot: checks and sets kernel args. Reboots after changes. Runs before display-manager, not in recovery mode. |
| `setup-ublue-mok.service` | Enrolls MOK for NVIDIA Secure Boot (borshevik-nvidia only) |

**User (user/):**

| Unit | Purpose |
|------|---------|
| `borshevik-app-manager-first-run.service` | Shows App Manager on first login (stamp in `~/.local/state/borshevik/`) |
| `borshevik-kill-gnome-if-hung.service` | Kills a hung GNOME Shell |
| `borshevik-kill-gnome-if-hung.timer` | Fires watchdog every 1 minute starting 1 minute after boot |

**user-preset/:**

| File | Purpose |
|------|---------|
| `90-borshevik.preset` | Enables required user units via `systemctl --global preset` |

---

## Custom Applications (GJS / GTK4 + libadwaita)

Both apps are written in GJS (JavaScript for GNOME), using GTK4 + libadwaita.

### Borshevik App Manager

**Source:** `build_files/root/usr/share/borshevik-app-manager/`

GUI tool for installing Flatpak apps from Flathub. Shows categories (work, media, development, …),
lets the user pick apps and install them in one click. Supports importing a custom list of app IDs.
Opens automatically on first login via a systemd user service.

| File | Purpose |
|------|---------|
| `main.js` | GApplication entry point |
| `window.js` | Main window: categories, app selection, installation |
| `flatpak.js` | Flatpak interaction: list installed, parse custom list, install |
| `net.js` | HTTP: fetchJson / fetchBytes (via GLib/Gio) |
| `i18n.js` | Internationalization |

### Borshevik Image Manager

**Source:** `build_files/root/usr/share/borshevik-image-manager/`

GUI OS update manager. Shows the current image, checks for updates via `rpm-ostree`,
runs updates, manages auto-updates (via a systemd timer), supports rollback to the previous image.

| File | Purpose |
|------|---------|
| `main.js` | Entry point |
| `main_window.js` | Main window: status, update/rollback buttons, auto-updates toggle |
| `rpm_ostree.js` | rpm-ostree interaction: status, update, rollback, digest |
| `app_state.js` | Computes UI state from rpm-ostree facts |
| `command_runner.js` | Async command execution via GLib |
| `progress_window.js` | Progress window during updates |
| `settings_window.js` | Settings: auto-updates, image channel |
| `util.js` | Helpers: os-release, reboot, polkit authorization |
| `i18n.js` | Internationalization |

---

## GNOME Shell Extensions

Installed at build time from `gs-extensions/list.json`.

**Project-owned extensions:**
- `borshevik-app-search` — app search integration in GNOME Overview
- `borshevik-workspace-manager` — workspace management

**Third-party extensions (with patched defaults):**
- `blur-my-shell` — blur behind panel/dash
- `clipboard-indicator` — clipboard history
- `battery_time` — battery time remaining in status bar
- `caffeine` — temporary sleep inhibitor
- `notification-timeout` — auto-hide notifications
- `primary-input-on-lockscreen` — primary language on lock screen
- `weather-oclock` — weather in status bar
- `twitchlive-extension` — Twitch stream notifications
- `legacy-theme-auto-switcher` — legacy theme switching for dark/light mode
- `emoji-copy` — emoji picker
- `color-picker` — color eyedropper
- `bluetooth-battery-meter` — Bluetooth device battery levels
- `status-area-horizontal-spacing` — spacing between status bar icons
- `gsconnect` — Android integration (KDE Connect)
- `appindicator` — legacy tray icon support

---

## CI/CD (GitHub Actions)

### Build Pipeline

```
[Daily at 10:00 UTC]
build-base.yml
  → borshevik-base:latest        (ghcr.io)
  → borshevik-base-nvidia:latest (ghcr.io)
  → cosign sign by digest
        │
        │ workflow_run: completed
        ▼
build-borshevik.yml  (also: push to main)
  → borshevik:latest + DD.MM.YYYY
  → borshevik-nvidia:latest + DD.MM.YYYY
  → cosign sign by digest
```

**Promoting to stable (manual):**

```
borshevik-promote-to-stable <digest> <variant>
  → promote-image-to-stable.yml (workflow_dispatch)
      → docker buildx imagetools create --tag :stable
      → cosign sign
```

**Building ISOs (manual):**
```
build-iso.yml (workflow_dispatch)
  → borshevik-stable.iso
  → borshevik-nvidia-stable.iso
  → uploaded as GitHub Actions artifact (0-day retention)
```

### Workflow Files

| File | Trigger | What it does |
|------|---------|-------------|
| `build-base.yml` | cron 10:00 UTC daily + manual | Builds base images, pushes to GHCR, signs |
| `build-borshevik.yml` | push to main + after build-base + manual | Builds final images, pushes, signs |
| `build-iso.yml` | manual + workflow_call | Builds ISO installers (stable tag), artifacts |
| `promote-image-to-stable.yml` | manual (digest + variant) | Tags image as `:stable`, signs |

---

## Installer (ISO)

The install ISO is built via [build-container-installer](https://github.com/jasonn3/build-container-installer).

- **Anaconda**: most modules disabled — Storage only. No network, user, timezone, or security steps — minimal install flow.
- **Lorax templates**: post-install `bootc switch` points the system at the correct image.
- **borshevik.toml / borshevik-nvidia.toml**: kickstart configs for image builder (LVM, ext4, auto-partition).

---

## Image Verification

Images are signed via [Sigstore cosign](https://github.com/sigstore/cosign).

- `cosign.pub` — public key, baked into the image at `/etc/pki/containers/cosign.pub`
- `/etc/containers/policy.json` + `registries.d/` — enforce signature verification on every `bootc`/`rpm-ostree rebase`
- CI uses `SIGNING_SECRET` from GitHub Secrets (private key)

---

## Local Development (Justfile)

```bash
just build           # Build the image with podman
just build-iso       # Build an ISO (via BIB)
just run-vm-qcow2    # Run a VM with qemu-docker
just lint            # shellcheck all .sh files
just format          # shfmt all .sh files
just clean           # Remove build artifacts
```

---

## Dependency Updates

- **Renovate** (`.github/renovate.json5`) — updates SHA-pinned GitHub Actions versions
- **Dependabot** (`.github/dependabot.yml`) — additional dependency monitoring
- The base image (`ghcr.io/ublue-os/silverblue-main:44`) rebuilds daily, pulling RPM updates automatically

---

## Quick Reference

| Question | Answer |
|----------|--------|
| Upstream base image | `ghcr.io/ublue-os/silverblue-main:44` |
| Fedora version | 44 (`ARG FEDORA_MAJOR_VERSION=44`) |
| Image registry | `ghcr.io/komorebinator/` |
| Where to add RPM packages | `build_files/scripts/install-rpm-packages.sh` |
| Where GNOME extensions are listed | `build_files/scripts/gs-extensions/list.json` |
| Where keybindings are set | `build_files/scripts/dconf/local.d/00-hotkeys` |
| Where dock favorites are set | `build_files/scripts/schemas/90-favorites.gschema.override` |
| Where App Manager UI is | `build_files/root/usr/share/borshevik-app-manager/window.js` |
| Where Image Manager UI is | `build_files/root/usr/share/borshevik-image-manager/main_window.js` |
| How to promote to stable | `borshevik-promote-to-stable <digest> <variant>` |
| Where kernel args are set | `build_files/root/usr/libexec/borshevik/setup-kargs.sh` |
| Website | https://borshevik.org |
