// The Wisp wire protocol, version 2.
//
// Discovery: every visible device sends its info (Device.toJson — including
// its certificate fingerprint — plus `"protocol": "wisp/2"`) as UDP
// multicast to [multicastGroup]:[discoveryPort] every few seconds. A device
// that hears a new peer also POSTs its own info to that peer's /register,
// so both sides find each other even if multicast only works one way.
//
// Transfers between apps use HTTPS on [defaultServerPort]. Each device has
// a self-made certificate (see identity.dart); a client only accepts the
// certificate whose fingerprint the device announced, so nobody else on
// the network can read the files or pose as that device.
//   GET  /api/wisp/v1/info              → this device's info
//   POST /api/wisp/v1/register          ← sender's info, → this device's info
//   POST /api/wisp/v1/prepare-upload    ← {sessionId, code, info, files: [{id, name, size}]}
//                                       → 200 {tokens: {fileId: token}} once the user accepts
//                                         403 declined or hidden, 409 busy
//   POST /api/wisp/v1/upload?sessionId=&fileId=&token=   ← raw file bytes
//   POST /api/wisp/v1/cancel?sessionId=
//
// Browsers, and devices the Wi-Fi hides from each other, meet in a room on
// the signaling server instead and send over WebRTC (rtc_peers.dart).

import 'dart:io';
import 'dart:math';

const protocolVersion = 'wisp/2';
const discoveryPort = 53318;
const defaultServerPort = 53318;
final multicastGroup = InternetAddress('224.0.0.168');

const announceEvery = Duration(seconds: 3);

/// A device that hasn't announced itself for this long is dropped.
const deviceTimeout = Duration(seconds: 10);

/// How long a sender waits for the receiver to tap Accept.
const acceptTimeout = Duration(minutes: 2);

abstract final class Api {
  static const info = '/api/wisp/v1/info';
  static const register = '/api/wisp/v1/register';
  static const prepareUpload = '/api/wisp/v1/prepare-upload';
  static const upload = '/api/wisp/v1/upload';
  static const cancel = '/api/wisp/v1/cancel';
}

final _random = Random.secure();

/// Random hex string, [bytes] bytes long (so twice as many characters).
String randomHex(int bytes) => List.generate(
  bytes,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

/// "Connect with code" didn't work; [message] says why, for the user.
class ConnectException implements Exception {
  const ConnectException(this.message);

  final String message;

  @override
  String toString() => message;
}
