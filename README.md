# Wisp

Send files between your devices on the same Wi-Fi: no accounts, no cables,
and no cloud storing your files.

Wisp runs on Android, iOS, Windows, macOS and Linux, and in the browser at
<https://domeepc.github.io/wisp/app/> for devices without the app.

## Features

- **Finds nearby devices by itself.** Open Wisp on two devices on the same
  network and they show up on each other's screens.
- **Device codes.** When the network hides devices from each other, type the
  other device's short code (like `7K3M-Q2XA`) to connect. The code is the
  device's address, packed with a check digit, so a typo can't send files to
  the wrong place.
- **Encrypted and verified.** Transfers between apps go over HTTPS. Each
  device has its own certificate and only accepts the one the other device
  announced. Both sides show the same security code, so you can check you're
  talking to the right device.
- **You decide.** Nothing arrives until you accept it. You can tick "always
  accept" for your own devices.
- **Files, folders, text and voice messages.** You can also drag and drop
  files on desktop. Folders arrive as folders.
- **Works in the browser.** The web app finds your devices through a small
  signaling server and sends files over WebRTC, directly between the devices.
  A QR code in the app opens it on your phone.

## How a transfer works

Between two apps:

1. The devices find each other by UDP multicast
   (`224.0.0.168:53318`). Each one also registers itself with the other
   over HTTPS, so discovery still works if multicast only gets through in
   one direction.
2. The sender offers the files (names and sizes) to
   `/api/wisp/v1/prepare-upload` and waits for you to accept on the other
   device.
3. The files are uploaded two at a time, each as its own HTTPS request, from
   a background isolate so the screen stays smooth. The receiver writes
   them to disk in 1 MB batches.

Browsers, and devices the Wi-Fi keeps apart, meet in a room on the
signaling server (devices behind the same public IP share a room). Then
they connect over WebRTC. Files go between the devices directly, or through
a TURN relay when that isn't possible. Nothing is stored on the server.

The full protocol is described at the top of
[lib/net/protocol.dart](lib/net/protocol.dart).

## Project layout

| Path | What it is |
| --- | --- |
| `lib/` | The Flutter app (every platform, including the web app) |
| `lib/net/` | Discovery, HTTPS client and server, device codes, WebRTC and signaling |
| `server/` | The signaling server, a Cloudflare Worker |
| `site/` | The website (Svelte + Vite), published together with the web app |
| `tool/` | Release helpers: version number and Linux packaging |
| `test/` | Tests, including real transfers between two services over localhost |

## Building

You need Flutter 3.47 or later.

```sh
flutter pub get
flutter run              # on the connected device or this computer
flutter test
```

Features that need the internet (the web app finding your devices, and
connecting across networks that keep devices apart) are only turned on when
you pass the signaling server's address:

```sh
flutter run --dart-define=SIGNALING_URL=wss://wisp-signal.<you>.workers.dev
```

On Linux, voice messages need `parecord` (the `pulseaudio-utils` package).

### Signaling server

```sh
cd server
npx wrangler login
npx wrangler deploy      # or: npx wrangler dev --port 8787
```

To add a TURN relay for networks where devices can't connect directly, set
`TURN_KEY_ID` and `TURN_KEY_API_TOKEN` with `npx wrangler secret put`.

### Website and web app

```sh
cd site && npm ci && npm run dev
```

Every push to `main` builds the site and the web app and publishes them to
GitHub Pages, with the web app under `app/`
(see [.github/workflows/pages.yml](.github/workflows/pages.yml)).

## Releases

Push a tag like `v1.2.0` and
[the release workflow](.github/workflows/release.yml) builds installers for
Android, Windows, macOS and Linux (`.tar.gz` and `.deb`), and attaches them
to a GitHub release. The version number is `1.0.<number of commits>`
([tool/version.sh](tool/version.sh)).

## License

[MIT](LICENSE)
