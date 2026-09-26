#!/usr/bin/env bash
# Builds the Flutter web app and packs it into assets/webapp/webapp.zip.
# The installed app serves it at http://<its address>:53319/app/, and the
# QR code in Connect with code points there. Run this before building the
# desktop or mobile app; without the zip, only the simple page is served.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build web --release --base-href /app/ --no-web-resources-cdn
# The web build bundles the app's assets too, including the previous zip.
rm -rf build/web/assets/assets/webapp

rm -f assets/webapp/webapp.zip
# Debug symbols aren't needed to run it.
(cd build/web && zip -qr9 ../../assets/webapp/webapp.zip . -x '*.symbols')
echo "Packed $(du -h assets/webapp/webapp.zip | cut -f1) into assets/webapp/webapp.zip"
