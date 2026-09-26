import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../models/device.dart';
import '../../models/shared_file.dart';
import '../../models/transfer.dart';
import '../browser_bridge.dart' show BrowserApi;
import '../device_code.dart';
import '../protocol.dart';
import '../server.dart' show Offer;
import 'browser_http.dart';

/// The Wisp app running in a web browser.
///
/// A browser can't be discovered and can't run a server, so it connects
/// out to Wisp devices by their browser address and uses the same API as
/// the browser page (see browser_bridge.dart): it checks in every couple
/// of seconds, which keeps it on their device lists; it offers files
/// through prepare-upload/upload; and files shared with it show up in its
/// inbox, which become normal incoming requests here.
class WebLinks {
  WebLinks({
    required this.http,
    required this.self,
    required this.onChanged,
    required this.onOffer,
    required this.onConnected,
  });

  final BrowserHttp http;

  /// Our name and id, as shown on the other devices.
  final Device Function() self;

  /// Devices came online, went offline or were renamed.
  final VoidCallback onChanged;

  /// Asks the user about files shared with us; null means declined.
  final Future<Transfer?> Function(Offer offer) onOffer;

  /// A device was connected by hand — worth remembering for next time.
  final void Function(Uri address) onConnected;

  static const pollEvery = Duration(seconds: 2);

  final _links = <String, _Link>{};
  Timer? _timer;
  Future<void> _offers = Future.value();

  /// While paused (this device "hidden"), we stop checking in, so the
  /// other devices drop us after a few seconds.
  bool paused = false;

  List<Device> get devices => [
    for (final link in _links.values)
      if (link.online && link.host != null) link.host!,
  ];

  bool owns(String deviceId) => _linkFor(deviceId) != null;

  /// Starts checking in with [addresses]. Unsaved ones (a guess, like the
  /// page's own address) are dropped if they don't answer the first time.
  void start(Iterable<({Uri address, bool saved})> addresses) {
    for (final (:address, :saved) in addresses) {
      _links.putIfAbsent('$address', () => _Link(address, saved: saved));
    }
    _timer = Timer.periodic(pollEvery, (_) => pollAll());
    pollAll();
  }

  void stop() {
    _timer?.cancel();
    for (final link in _links.values) {
      if (link.token != null) {
        http.send('POST', _uri(link, BrowserApi.bye)).ignore();
      }
    }
  }

  Future<void> pollAll() async {
    await Future.wait([for (final link in _links.values.toList()) _poll(link)]);
    // Links can also go offline just by time passing.
    for (final link in _links.values) {
      if (link.online != link.wasOnline) {
        link.wasOnline = link.online;
        onChanged();
      }
    }
  }

  /// Connects to a device by the browser address it shows (see
  /// [parseBrowserAddress]). Throws [ConnectException] if that fails.
  Future<Device> connect(String code) async {
    final address = parseBrowserAddress(code);
    if (address == null) {
      throw const ConnectException(
        'That code doesn\'t look right. Check it and try again.',
      );
    }
    final link = _links['$address'] ?? _Link(address, saved: true);
    try {
      await _hello(link);
    } on Exception {
      throw ConnectException(
        onInternet
            ? 'Browsers don\'t let a website reach devices on your Wi-Fi. '
                  'Scan the QR code in Connect with code on the other device '
                  'instead: that opens Wisp from the device itself.'
            : 'No Wisp device answered. Is it on the same Wi-Fi, with Wisp open?',
      );
    }
    link
      ..saved = true
      ..lastOk = DateTime.now()
      ..wasOnline = true;
    _links['$address'] = link;
    onConnected(address);
    onChanged();
    return link.host!;
  }

  /// Our name changed: tell everyone.
  void renamed() {
    for (final link in _links.values) {
      if (link.token != null) _hello(link).ignore();
    }
  }

  Future<void> _poll(_Link link) async {
    if (paused || link.polling) return;
    link.polling = true;
    try {
      if (link.token == null) await _hello(link);
      var res = await http.send('GET', _uri(link, BrowserApi.inbox));
      if (res.status == 403) {
        // The other app restarted and forgot us: say hello again.
        link.token = null;
        await _hello(link);
        res = await http.send('GET', _uri(link, BrowserApi.inbox));
      }
      if (res.status != 200) throw BrowserHttpException('${res.status}');
      final body = jsonDecode(res.body) as Map;
      _setHost(link, body['host']);
      link.lastOk = DateTime.now();
      _offerNew(link, (body['items'] as List).cast<Map>());
    } on Exception {
      if (!link.saved && link.lastOk == DateTime(0)) {
        _links.remove('${link.address}'); // a guess that didn't work out
      }
    } finally {
      link.polling = false;
    }
  }

  Future<void> _hello(_Link link) async {
    final res = await http.send(
      'POST',
      link.address.replace(path: BrowserApi.hello),
      json: jsonEncode({
        // Our own id, so "always accept" on their side survives restarts.
        'id': link.id ?? self().id,
        'token': link.token,
        'name': self().name,
        'detail': http.browserName,
      }),
    );
    if (res.status != 200) throw BrowserHttpException('${res.status}');
    final body = jsonDecode(res.body) as Map;
    link
      ..id = body['id'] as String
      ..token = body['token'] as String;
    _setHost(link, body['host']);
  }

  void _setHost(_Link link, Object? json) {
    if (json is! Map) return;
    final host = Device(
      id: json['id'] as String? ?? '${link.address}',
      name: json['name'] as String? ?? link.address.host,
      platform: DevicePlatform.fromName(json['platform'] as String?),
      host: link.address.host,
      port: link.address.port,
    );
    final old = link.host;
    link.host = host;
    if (old?.name != host.name || old?.id != host.id) onChanged();
  }

  /// Files shared with us that we haven't asked about yet become offers,
  /// one batch at a time.
  void _offerNew(_Link link, List<Map> items) {
    final batches = <String, List<Map>>{};
    for (final item in items) {
      final id = item['item'] as String;
      if (!link.asked.add(id)) continue;
      batches.putIfAbsent(item['batch'] as String? ?? id, () => []).add(item);
    }
    for (final MapEntry(key: batch, value: items) in batches.entries) {
      _offers = _offers.then((_) => _offer(link, batch, items));
    }
  }

  Future<void> _offer(_Link link, String batch, List<Map> items) async {
    final host = link.host;
    if (host == null) return;
    final files = [
      for (final item in items)
        SharedFile(
          item['name'] as String,
          item['size'] as int,
          text: item['text'] as String?,
        ),
    ];
    final transfer = await onOffer(
      Offer(sessionId: batch, from: host, files: files, securityCode: ''),
    );
    if (transfer == null) return; // declined: just don't download them

    // Browsers save downloads themselves; we can only start them. Right
    // after the Accept tap, so the browser doesn't block them.
    transfer.setStatus(TransferStatus.running);
    for (final (i, item) in items.indexed) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 300));
      http.download(
        _uri(link, BrowserApi.download, {'item': item['item'] as String}),
      );
      transfer.setFileProgress(i, files[i].bytes);
    }
    transfer.setStatus(TransferStatus.done);
  }

  /// Sends [transfer]'s files to its peer (one of our links).
  Future<void> send(Transfer transfer) async {
    final peer = transfer.peer;
    final link = _linkFor(peer.id);
    if (link == null || link.token == null) {
      transfer.setStatus(
        TransferStatus.failed,
        error: 'Not connected to ${peer.name}',
      );
      return;
    }

    void Function()? abort;
    var cancelled = false;
    transfer.onCancel = () {
      cancelled = true;
      abort?.call();
      http
          .send(
            'POST',
            link.address.replace(
              path: Api.cancel,
              queryParameters: {'sessionId': transfer.sessionId},
            ),
          )
          .ignore();
      transfer.setStatus(TransferStatus.cancelled);
    };

    try {
      // Waits until someone taps Accept or Decline on the other device.
      final res = await http.send(
        'POST',
        link.address.replace(path: Api.prepareUpload),
        json: jsonEncode({
          'sessionId': transfer.sessionId,
          'code': transfer.securityCode,
          'info': {
            'id': link.id,
            'name': self().name,
            'platform': DevicePlatform.browser.name,
            'detail': http.browserName,
            'port': 0,
          },
          'files': [
            for (final (i, f) in transfer.files.indexed)
              {'id': '$i', 'name': f.name, 'size': f.bytes},
          ],
        }),
        onStart: (a) => abort = a,
      );
      if (cancelled) return;
      switch (res.status) {
        case 200:
          break;
        case 403:
          transfer.setStatus(TransferStatus.declined);
          return;
        case 409:
          transfer.setStatus(
            TransferStatus.failed,
            error: '${peer.name} is busy with another request',
          );
          return;
        default:
          throw BrowserHttpException('Unexpected reply (${res.status})');
      }
      final tokens = (jsonDecode(res.body) as Map)['tokens'] as Map;
      transfer.setStatus(TransferStatus.running);

      for (final (i, file) in transfer.files.indexed) {
        if (cancelled) return;
        final status = await http.upload(
          link.address.replace(
            path: Api.upload,
            queryParameters: {
              'sessionId': transfer.sessionId,
              'fileId': '$i',
              'token': '${tokens['$i']}',
            },
          ),
          await _readAll(file),
          onProgress: (sent) => transfer.setFileProgress(i, sent),
          onStart: (a) => abort = a,
        );
        if (status == 410) {
          transfer.setStatus(
            TransferStatus.cancelled,
            error: 'Cancelled on ${peer.name}',
          );
          return;
        }
        if (status != 200) {
          throw BrowserHttpException('Upload failed ($status)');
        }
        transfer.setFileProgress(i, file.bytes);
      }
      transfer.setStatus(TransferStatus.done);
    } on Exception {
      if (!cancelled) {
        transfer.setStatus(
          TransferStatus.failed,
          error: 'Lost connection to ${peer.name}',
        );
      }
    }
  }

  /// The browser can only upload whole files from memory.
  static Future<Uint8List> _readAll(SharedFile file) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  _Link? _linkFor(String deviceId) =>
      _links.values.where((l) => l.host?.id == deviceId).firstOrNull;

  static Uri _uri(_Link link, String path, [Map<String, String>? extra]) =>
      link.address.replace(
        path: path,
        queryParameters: {
          'id': link.id ?? '',
          'token': link.token ?? '',
          ...?extra,
        },
      );
}

/// This page came from the internet (like GitHub Pages), not from a Wisp
/// device. Browsers block https pages from reaching local addresses, so
/// it can't connect to anything.
bool get onInternet => Uri.base.scheme == 'https';

/// Reads a device's code (see device_code.dart), or a browser address:
/// `192.168.1.24`,
/// `192.168.1.24:53319` or `http://192.168.1.24:53319`. The app's own
/// code (HTTPS port, or no port) is fine too — it's mapped to the browser
/// port. Returns null if it makes no sense.
Uri? parseBrowserAddress(String code) {
  if (normalizeDeviceCode(code) != null) {
    final address = decodeDeviceCode(code);
    if (address == null) return null;
    return Uri(scheme: 'http', host: address.host, port: address.browserPort);
  }
  var text = code.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'http' ||
      !RegExp(r'^[A-Za-z0-9.\-]+$').hasMatch(uri.host)) {
    return null;
  }
  final port = !uri.hasPort || uri.port == defaultServerPort
      ? defaultBrowserPort
      : uri.port;
  return Uri(scheme: 'http', host: uri.host, port: port);
}

class _Link {
  _Link(this.address, {required this.saved});

  final Uri address;

  /// Remembered across restarts (connected by hand).
  bool saved;

  /// Our session there.
  String? id;
  String? token;

  /// The device at [address], once it answered.
  Device? host;

  DateTime lastOk = DateTime(0);
  bool wasOnline = false;
  bool polling = false;

  /// Inbox items we already asked about.
  final asked = <String>{};

  bool get online => DateTime.now().difference(lastOk) < deviceTimeout;
}
