# Hiddify, the VPN client, as an RPM made from its release's Debian package: the files as
# Hiddify built them, in /usr/lib/hiddify, with the capabilities a VPN needs. See
# @HiddifyApp#package in spec/. A new release is a change to Version: and the checksum.

%global deb_sha256 2cd4b830a3db146a123fb3a69b02e7d6e6f5399c2b12236a5e3a639ba6b61492

# Prebuilt binaries: nothing to strip or make debug info of, and the Flutter libraries must
# stay exactly as built. Their libraries are private, under /usr/lib/hiddify/lib, and what
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
mkdir -p %{buildroot}%{_prefix}/lib/hiddify %{buildroot}%{_datadir}/icons
cp -a deb/opt/hiddify/. %{buildroot}%{_prefix}/lib/hiddify/
cp -a deb/usr/share/icons/hicolor %{buildroot}%{_datadir}/icons/
# A binary with capabilities runs in secure mode, where the loader expands no relative
# RUNPATH outside the trusted directories: both get the absolute one.
patchelf --set-rpath %{_prefix}/lib/hiddify/lib %{buildroot}%{_prefix}/lib/hiddify/hiddify
# TEMPORARY (#90), until a Hiddify release fixes it (hiddify/hiddify-app#2411, #2423): HiddifyCli
# needs its core as ./lib/hiddify-core.so, relative to the working directory and never looked
# up in RUNPATH, so it starts only from its own folder - and the app runs it from its data
# folder to connect in VPN mode. On a release that fixed it, this changes nothing.
patchelf --replace-needed ./lib/hiddify-core.so hiddify-core.so \
    --set-rpath %{_prefix}/lib/hiddify/lib %{buildroot}%{_prefix}/lib/hiddify/HiddifyCli

%files
%dir %{_prefix}/lib/hiddify
%caps(cap_net_raw,cap_net_admin,cap_net_bind_service=eip) %{_prefix}/lib/hiddify/hiddify
%caps(cap_net_raw,cap_net_admin,cap_net_bind_service=eip) %{_prefix}/lib/hiddify/HiddifyCli
%{_prefix}/lib/hiddify/lib
%{_prefix}/lib/hiddify/data
%{_datadir}/icons/hicolor/*/apps/hiddify.png
