import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Thrown by request handlers; the server turns it into a JSON error reply.
class HttpError implements Exception {
  const HttpError(this.status, this.message);

  final int status;
  final String message;
}

/// The IP address the request came from.
String remoteAddress(HttpRequest req) =>
    req.connectionInfo?.remoteAddress.address ?? '';

/// Reads a JSON body of at most 1 MB.
Future<Object?> readJson(HttpRequest req) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in req) {
    bytes.add(chunk);
    if (bytes.length > 1024 * 1024) throw const HttpError(413, 'Too big');
  }
  try {
    return jsonDecode(utf8.decode(bytes.takeBytes()));
  } on FormatException {
    throw const HttpError(400, 'Bad JSON');
  }
}

Future<void> replyJson(HttpRequest req, int status, Object body) async {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..headers.set('Cache-Control', 'no-store')
    ..write(jsonEncode(body));
  await req.response.close();
}

/// Like [replyJson], but ignores errors (e.g. the client already left).
Future<void> tryReplyJson(HttpRequest req, int status, Object body) =>
    replyJson(req, status, body).catchError((_) {});

/// Whether a web page at [origin] may use the browser API: pages on this
/// computer or the local network only, so no website on the internet can
/// make your browser talk to your devices.
bool isLocalOrigin(String origin) {
  final uri = Uri.tryParse(origin);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return false;
  }
  final host = uri.host;
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null || p > 255)) {
    return false;
  }
  final (a, b) = (parts[0]!, parts[1]!);
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}
