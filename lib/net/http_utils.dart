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
