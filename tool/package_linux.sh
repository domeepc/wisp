#!/usr/bin/env bash
# Packs the Linux release build into build/installers/:
#   wisp-<version>-linux-x64.tar.gz  (unpack anywhere, run ./wisp)
#   wisp_<version>_amd64.deb         (installs to /opt/wisp, with a menu entry)
# Run after `flutter build linux --release`. Usage: package_linux.sh 1.2.0
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: package_linux.sh <version>}"
bundle=build/linux/x64/release/bundle
out=build/installers
# Must match APPLICATION_ID in linux/CMakeLists.txt, so desktops (Wayland
# especially) match the window to this entry and show its icon.
app_id=com.example.wisp
mkdir -p "$out"

tar -czf "$out/wisp-$version-linux-x64.tar.gz" -C "$(dirname "$bundle")" \
  --transform "s|^bundle|wisp|" bundle

pkg=$(mktemp -d)
trap 'rm -rf "$pkg"' EXIT
mkdir -p "$pkg/DEBIAN" "$pkg/opt/wisp" "$pkg/usr/bin" \
  "$pkg/usr/share/applications" "$pkg/usr/share/icons/hicolor/scalable/apps"
cp -r "$bundle/." "$pkg/opt/wisp/"
ln -s /opt/wisp/wisp "$pkg/usr/bin/wisp"
cp assets/brand/wisp_icon.svg "$pkg/usr/share/icons/hicolor/scalable/apps/$app_id.svg"
cat > "$pkg/usr/share/applications/$app_id.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Wisp
Comment=Send files to devices on your Wi-Fi
Exec=/opt/wisp/wisp
Icon=$app_id
Categories=Network;FileTransfer;
StartupWMClass=$app_id
DESKTOP
cat > "$pkg/DEBIAN/control" <<CONTROL
Package: wisp
Version: $version
Architecture: amd64
Maintainer: Wisp
Depends: libgtk-3-0
Recommends: zenity, pulseaudio-utils
Section: net
Priority: optional
Description: Send files to devices on your Wi-Fi
 Wisp sends files between your devices over the local network,
 encrypted, with no account and no internet needed.
CONTROL
dpkg-deb --build --root-owner-group "$pkg" "$out/wisp_${version}_amd64.deb" >/dev/null
ls -lh "$out"
