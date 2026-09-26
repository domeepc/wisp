import 'browser_http.dart';

/// Outside a browser there's no [BrowserHttp] (the app uses dart:io).
BrowserHttp createBrowserHttp() =>
    throw UnsupportedError('BrowserHttp only exists in a web browser');
