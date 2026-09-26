import 'dart:typed_data';

export 'browser_http_stub.dart'
    if (dart.library.js_interop) 'browser_http_web.dart';

/// HTTP from inside a web browser, for the Wisp app built for the web
/// (which can't use dart:io). Only [createBrowserHttp] makes one; tests
/// can pass their own implementation.
abstract class BrowserHttp {
  /// Sends a request and returns the status and body text.
  /// Throws [BrowserHttpException] if there's no answer at all.
  Future<({int status, String body})> send(
    String method,
    Uri url, {
    String? json,
    void Function(void Function() abort)? onStart,
  });

  /// Uploads [bytes], reporting progress. Returns the status code.
  Future<int> upload(
    Uri url,
    Uint8List bytes, {
    required void Function(int sent) onProgress,
    void Function(void Function() abort)? onStart,
  });

  /// Starts a normal browser download of [url].
  void download(Uri url);

  /// "Chrome", "Safari"…
  String get browserName;
}

class BrowserHttpException implements Exception {
  const BrowserHttpException(this.message);

  final String message;

  @override
  String toString() => message;
}
