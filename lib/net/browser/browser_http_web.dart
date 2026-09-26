import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser_http.dart';

BrowserHttp createBrowserHttp() => _XhrBrowserHttp();

/// XMLHttpRequest rather than fetch: only XHR reports upload progress.
class _XhrBrowserHttp implements BrowserHttp {
  @override
  Future<({int status, String body})> send(
    String method,
    Uri url, {
    String? json,
    void Function(void Function() abort)? onStart,
  }) {
    final done = Completer<({int status, String body})>();
    final xhr = web.XMLHttpRequest()..open(method, url.toString());
    if (json != null) xhr.setRequestHeader('Content-Type', 'application/json');
    _whenDone(xhr, done, () => (status: xhr.status, body: xhr.responseText));
    onStart?.call(() => xhr.abort());
    xhr.send(json?.toJS);
    return done.future;
  }

  @override
  Future<int> upload(
    Uri url,
    Uint8List bytes, {
    required void Function(int sent) onProgress,
    void Function(void Function() abort)? onStart,
  }) {
    final done = Completer<int>();
    final xhr = web.XMLHttpRequest()..open('POST', url.toString());
    xhr.upload.onprogress = ((web.ProgressEvent e) {
      onProgress(e.loaded);
    }).toJS;
    _whenDone(xhr, done, () => xhr.status);
    onStart?.call(() => xhr.abort());
    xhr.send(bytes.toJS);
    return done.future;
  }

  static void _whenDone<T>(
    web.XMLHttpRequest xhr,
    Completer<T> done,
    T Function() result,
  ) {
    void fail(String message) {
      if (!done.isCompleted) done.completeError(BrowserHttpException(message));
    }

    xhr
      ..onload = ((web.Event _) {
        if (!done.isCompleted) done.complete(result());
      }).toJS
      ..onerror = ((web.Event _) => fail('No answer')).toJS
      ..onabort = ((web.Event _) => fail('Cancelled')).toJS
      ..ontimeout = ((web.Event _) => fail('Timed out')).toJS;
  }

  @override
  void download(Uri url) {
    // The server marks it as an attachment, so this saves instead of
    // navigating away.
    final link = web.HTMLAnchorElement()
      ..href = url.toString()
      ..download = '';
    web.document.body?.append(link);
    link.click();
    link.remove();
  }

  @override
  String get browserName {
    final ua = web.window.navigator.userAgent;
    // Order matters: Edge and Opera also say Chrome; Chrome says Safari.
    if (ua.contains('Edg/')) return 'Edge';
    if (ua.contains('OPR/')) return 'Opera';
    if (ua.contains('SamsungBrowser')) return 'Samsung Internet';
    if (ua.contains('Firefox/') || ua.contains('FxiOS')) return 'Firefox';
    if (ua.contains('Chrome/') || ua.contains('CriOS')) return 'Chrome';
    if (ua.contains('Safari/')) return 'Safari';
    return 'Browser';
  }
}
