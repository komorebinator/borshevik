#!/bin/bash

set -oue pipefail

#flatpak remote-delete fedora
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

flatpak install -y --noninteractive flathub \
  com.valvesoftware.Steam \
  org.gnome.Weather \
  org.gnome.clocks \
  org.gnome.Calculator \
  org.gnome.Contacts \
  org.gnome.Calendar \
  org.libreoffice.LibreOffice \
  com.usebottles.bottles \
  io.github.dvlv.boxbuddyrs \
  org.gnome.baobab \
  org.gnome.Evince \
  org.gnome.Loupe \
  org.fedoraproject.MediaWriter \
  org.gnome.TextEditor \
  org.gnome.Characters \
  org.gnome.font-viewer \
  org.gnome.Logs \
  org.videolan.VLC \
  org.tenacityaudio.Tenacity \
  com.mattjakeman.ExtensionManager \
  it.mijorus.gearlever \
  com.github.tchx84.Flatseal \
  org.gimp.GIMP \
  io.gitlab.adhami3310.Footage \
  org.shotcut.Shotcut \
  com.obsproject.Studio \
  org.gnome.Snapshot \
  io.gitlab.theevilskeleton.Upscaler \
  org.gnome.World.Secrets \
  com.github.unrud.VideoDownloader \
  com.transmissionbt.Transmission \
  org.localsend.localsend_app
