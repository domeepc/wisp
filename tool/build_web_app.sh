#!/usr/bin/env bash
# Builds the Flutter web app and packs it into assets/webapp/webapp.zip.
# The installed app serves it at http://<its address>:53319/app/, and the
# QR code in Connect with code points there. Run this before building the
# desktop or mobile app; without the zip, only the simple page is served.
#
# It builds into build/web_app, not build/web, so it never mixes with the
# GitHub Pages build (which needs a different base path).
# Set SIGNALING_URL to the signaling server (server/) to find devices
# through the internet too. Set BUILD_NAME (1.2.0) to show that version
# instead of pubspec.yaml's.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$PWD/build/web_app"

flutter build web --release --wasm --base-href /app/ --no-web-resources-cdn --output "$out" \
  ${BUILD_NAME:+--build-name "$BUILD_NAME"} \
  --dart-define=SIGNALING_URL="${SIGNALING_URL:-}"
# The web build bundles the app's assets too, including the previous zip.
rm -rf "$out/assets/assets/webapp"

rm -f assets/webapp/webapp.zip
# Debug symbols aren't needed to run it.
(cd "$out" && zip -qr9 "$OLDPWD/assets/webapp/webapp.zip" . -x '*.symbols')
echo "Packed $(du -h assets/webapp/webapp.zip | cut -f1) into assets/webapp/webapp.zip"
