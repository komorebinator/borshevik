# Hiddify, the VPN client, as an RPM made from its release's Debian package: the files as
# Hiddify built them, in /usr/libexec/hiddify. See @HiddifyApp#package in spec/. A new release
# is a change to Version: and the checksum.
#
# /usr/libexec rather than /usr/lib: SELinux labels files there bin_t, and in VPN mode the app
# installs a system service (HiddifyAdminBG) running HiddifyCli from where the app is. A
# service started from a lib_t file stays in init_t, which may not open /dev/net/tun; from a
# bin_t one it runs as unconfined_service_t, which may.
#
# No file capabilities: since 5.x the tunnel is that root service's, and the proxy modes need
# none, so on the binaries they would only hand cap_net_admin to whoever runs them.

%global deb_sha256 2cd4b830a3db146a123fb3a69b02e7d6e6f5399c2b12236a5e3a639ba6b61492

# Prebuilt binaries: nothing to strip or make debug info of, and the Flutter libraries must
# stay exactly as built. Their libraries are private, under /usr/libexec/hiddify/lib, and what
# they need from the system is in the image already, as it was when the package was unpacked
# by hand.
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none
AutoReqProv: no

Name:           hiddify
Version:        5.5.5
Release:        1
Summary:        Hiddify VPN client
License:        GPL-3.0-only
URL:            https://github.com/hiddify/hiddify-app
Source0:        %{url}/releases/download/v%{version}/Hiddify-Debian-x64.deb
ExclusiveArch:  x86_64
BuildRequires:  binutils
BuildRequires:  patchelf

%description
Hiddify, a VPN and proxy client, from its release's Debian package.

%prep
echo "%{deb_sha256}  %{SOURCE0}" | sha256sum -c
rm -rf deb
mkdir deb
cd deb
ar x %{SOURCE0}
tar xf data.tar.*

%build

%install
mkdir -p %{buildroot}%{_libexecdir}/hiddify %{buildroot}%{_datadir}/icons
cp -a deb/opt/hiddify/. %{buildroot}%{_libexecdir}/hiddify/
cp -a deb/usr/share/icons/hicolor %{buildroot}%{_datadir}/icons/
# TEMPORARY (#90), until a Hiddify release fixes it (hiddify/hiddify-app#2411, #2423): HiddifyCli
# needs its core as ./lib/hiddify-core.so, relative to the working directory and never looked
# up in RUNPATH, so it starts only from its own folder - and the app runs it from its data
# folder to connect in VPN mode. On a release that fixed it, this changes nothing.
# Its own RUNPATH, $ORIGIN/lib, then finds the core.
patchelf --replace-needed ./lib/hiddify-core.so hiddify-core.so %{buildroot}%{_libexecdir}/hiddify/HiddifyCli

%files
%dir %{_libexecdir}/hiddify
%{_libexecdir}/hiddify/hiddify
%{_libexecdir}/hiddify/HiddifyCli
%{_libexecdir}/hiddify/lib
%{_libexecdir}/hiddify/data
%{_datadir}/icons/hicolor/*/apps/hiddify.png
