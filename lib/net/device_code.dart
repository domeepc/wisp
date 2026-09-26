import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'protocol.dart';

/// A device's address as a short code people can read out and type,
/// like `7K3M-Q2XA`, so nobody has to deal with IP addresses.
///
/// The code *is* the address, not a key to look it up: it packs the IPv4
/// address (and both ports, only if they aren't the usual ones) behind a
/// check byte, in Crockford base32. So it works without any server, a
/// typo is caught instead of connecting somewhere else, and every device
/// gets a different-looking code even on the same network.
typedef DeviceAddress = ({String host, int port, int browserPort});

/// Crockford base32: no I, L, O or U, so nothing looks alike.
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// The code for [host] (an IPv4 address) with this device's ports.
/// Null if [host] isn't an IPv4 address.
String? encodeDeviceCode(
  String host, {
  int port = defaultServerPort,
  int browserPort = defaultBrowserPort,
}) {
  final ip = _parseIpv4(host);
  if (ip == null) return null;
  final usual = port == defaultServerPort && browserPort == defaultBrowserPort;
  final payload = [
    ...ip,
    if (!usual) ...[
      port >> 8,
      port & 0xff,
      browserPort >> 8,
      browserPort & 0xff,
    ],
  ];
  final check = _check(payload);
  final bytes = [check, for (final b in payload) b ^ check];
  return _group(_toBase32(bytes));
}

/// Reads a code made by [encodeDeviceCode]. Case, dashes and spaces
/// don't matter, and O/I/L are read as 0/1/1. Null if it isn't a valid
/// code (wrong length or a typo).
DeviceAddress? decodeDeviceCode(String code) {
  final chars = normalizeDeviceCode(code);
  if (chars == null) return null;
  final bytes = _fromBase32(chars, chars.length == 8 ? 5 : 9);
  if (bytes == null) return null;
  final check = bytes[0];
  final payload = [for (final b in bytes.skip(1)) b ^ check];
  if (_check(payload) != check) return null;
  final host = payload.take(4).join('.');
  if (payload.length == 4) {
    return (
      host: host,
      port: defaultServerPort,
      browserPort: defaultBrowserPort,
    );
  }
  return (
    host: host,
    port: payload[4] << 8 | payload[5],
    browserPort: payload[6] << 8 | payload[7],
  );
}

/// [code] in canonical form (upper case, no dashes, look-alikes fixed), if
/// it has the shape of a code at all — so callers can tell "mistyped
/// code" apart from "not meant as a code".
String? normalizeDeviceCode(String code) {
  final chars = code
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');
  if (chars.length != 8 && chars.length != 15) return null;
  if (chars.split('').any((c) => !_alphabet.contains(c))) return null;
  return chars;
}

int _check(List<int> payload) => sha256
    .convert(['wisp-code'.codeUnits, payload].expand((b) => b).toList())
    .bytes[0];

List<int>? _parseIpv4(String host) {
  try {
    return Uri.parseIPv4Address(host);
  } on FormatException {
    return null;
  }
}

String _toBase32(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(_alphabet[(buffer >> bits) & 31]);
    }
  }
  if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

Uint8List? _fromBase32(String chars, int length) {
  final out = Uint8List(length);
  var buffer = 0;
  var bits = 0;
  var i = 0;
  for (final c in chars.split('')) {
    buffer = ((buffer << 5) | _alphabet.indexOf(c)) & 0xffff;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      if (i == length) return null;
      out[i++] = (buffer >> bits) & 0xff;
    }
  }
  // The leftover padding bits must be zero, or it's a typo.
  if (i != length || (buffer & ((1 << bits) - 1)) != 0) return null;
  return out;
}

/// `7K3MQ2XA` → `7K3M-Q2XA`.
String _group(String chars) =>
    chars.replaceAllMapped(RegExp(r'.{4}(?!$)'), (m) => '${m[0]}-');
