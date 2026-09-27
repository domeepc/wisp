import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';
import '../models/shared_file.dart';
import '../models/transfer.dart';
import '../net/client.dart';
import '../net/device_code.dart';
import '../net/discovery.dart';
import '../net/identity.dart';
import '../net/protocol.dart';
import '../net/rtc_peers.dart';

export '../net/protocol.dart' show ConnectException;
import '../net/server.dart';
import '../net/signaling.dart';
import '../utils/random_name.dart';

/// An incoming offer waiting for the user to accept or decline.
class IncomingRequest {
  IncomingRequest(this.offer);

  final Offer offer;
  final _decision = Completer<bool>();
  final _transfer = Completer<Transfer?>();
  bool alwaysAccept = false;

  /// The receiving transfer once accepted, or null if declined.
  Future<Transfer?> get transfer => _transfer.future;

  /// Becomes true if the sender gives up or the request times out, so an
  /// open sheet can close itself.
  final cancelled = ValueNotifier(false);

  void accept({bool always = false}) {
    alwaysAccept = always;
    if (!_decision.isCompleted) _decision.complete(true);
  }

  void decline() {
    if (!_decision.isCompleted) _decision.complete(false);
  }
}

/// Everything networking, in one object the screens can listen to:
/// this device, nearby devices, transfers and incoming requests.
class WispService extends ChangeNotifier {
  WispService({
    String? name,
    this.saveDir,
    this.port = defaultServerPort,
    this.prefs,
  }) : self = Device(
         id: randomHex(8),
         name: name ?? randomDeviceName(),
         platform: _currentPlatform(),
       );

  /// Running as a web app: no discovery and no server, so it only has
  /// the room on the signaling server ([RtcPeers]).
  bool get isWebClient => kIsWeb;

  /// Everyone in our room on the signaling server, reached over WebRTC.
  /// Null without a signaling server.
  RtcPeers? _rtc;

  Device self;

  /// The HTTPS port other apps connect to. Another is picked if it's taken.
  final int port;

  /// Where settings are saved. Null means nothing is remembered (tests).
  final SharedPreferencesAsync? prefs;

  /// Where received files go. Picked automatically in [start] if null.
  String? saveDir;

  /// This device's LAN address, e.g. 192.168.1.24.
  String? localAddress;

  bool get running => _running;
  bool _running = false;

  /// Why [start] failed, if it did.
  String? startError;

  bool get visible => _visible;
  bool _visible = true;
  set visible(bool value) {
    _visible = value;
    if (value) _discovery?.announce();
    _updateRoom();
    notifyListeners();
  }

  /// Whether the web app on the internet can find this device (through
  /// the signaling server, which then knows its name).
  bool get showOnWeb => _showOnWeb;
  bool _showOnWeb = true;

  Future<void> setShowOnWeb(bool value) async {
    _showOnWeb = value;
    _updateRoom();
    notifyListeners();
    await prefs?.setBool(_Keys.showOnWeb, value);
  }

  /// Joins the room on the signaling server, if there is one.
  void _joinRoom() {
    if (signalingUrl.isEmpty) return;
    _rtc = RtcPeers(
      self: () => self,
      onChanged: notifyListeners,
      onOffer: _onOffer,
    );
    _updateRoom();
  }

  /// In the room while visible (and, for apps, shown on the web app).
  void _updateRoom() =>
      _rtc?.paused = !_visible || !(isWebClient || _showOnWeb);

  /// Nearby devices: found on the Wi-Fi, or in the room (like browsers).
  List<Device> get devices => [
    ..._devices.values.map((s) => s.device),
    // Found both ways: the Wi-Fi wins, it's faster.
    ...?_rtc?.devices.where((d) => !_devices.containsKey(d.id)),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final _devices = <String, ({Device device, DateTime lastSeen})>{};

  /// Newest last.
  List<Transfer> get transfers => List.unmodifiable(_transfers);
  final _transfers = <Transfer>[];

  Stream<IncomingRequest> get incoming => _incoming.stream;
  final _incoming = StreamController<IncomingRequest>.broadcast();
  IncomingRequest? _pending;

  /// Devices whose offers are accepted without asking.
  final _trusted = <String>{};
  int get trustedCount => _trusted.length;

  /// Devices added with "Connect with code", and when they last answered.
  /// Multicast doesn't reach them, so they're kept alive by polling.
  final _manual = <String, ({Device device, DateTime lastOk})>{};

  late final _client = WispClient(self: () => self);
  late final _server = WispServer(
    self: () => self,
    onRegister: (device) => _seen(device, registerBack: false),
    onOffer: _onOffer,
    onOfferCancelled: _onOfferCancelled,
  );
  Discovery? _discovery;
  Timer? _tick;

  static const _multicastChannel = MethodChannel('wisp/multicast');

  Future<void> start({bool discovery = true}) async {
    if (_running) return;
    if (isWebClient) return _startWebClient();
    try {
      await _loadSettings();
      saveDir ??= await _defaultSaveDir();
      localAddress = await _findLocalAddress();
      final identity = await _loadIdentity();
      await _server.start(port: port, tls: identity.serverContext);
      self = self.copyWith(
        port: _server.port,
        fingerprint: identity.fingerprint,
      );

      if (discovery) {
        // Android drops multicast packets unless the app holds a lock.
        if (Platform.isAndroid) {
          await _multicastChannel.invokeMethod<void>('acquire');
        }
        _discovery = Discovery(
          self: () => _visible ? self : null,
          onDevice: _seen,
        );
        await _discovery!.start();
      }

      _tick = Timer.periodic(const Duration(seconds: 2), (_) => _onTick());
      _running = true;
      startError = null;
      _joinRoom();
    } catch (e) {
      startError = '$e';
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _rtc?.stop();
    _running = false;
    if (isWebClient) return;
    _tick?.cancel();
    _discovery?.stop();
    await _server.stop();
    if (Platform.isAndroid && _discovery != null) {
      await _multicastChannel.invokeMethod<void>('release');
    }
  }

  @override
  void dispose() {
    stop();
    _incoming.close();
    super.dispose();
  }

  /// Starts sending [files] to [peer]. Watch the returned transfer.
  Transfer send(Device peer, List<SharedFile> files) {
    final sessionId = randomHex(16);
    // Devices on the Wi-Fi announce a certificate; ones only in the room
    // don't, and are reached over WebRTC.
    final fingerprint = peer.fingerprint;
    final transfer = Transfer(
      direction: TransferDirection.send,
      peer: peer,
      files: files,
      sessionId: sessionId,
      // Over WebRTC it comes from the connection, once that's up.
      securityCode: fingerprint == null
          ? ''
          : securityCode(fingerprint, sessionId),
    );
    _addTransfer(transfer);
    if (fingerprint == null) {
      _rtc?.send(transfer);
    } else {
      _client.send(transfer);
    }
    return transfer;
  }

  /// This device's code for "Connect with code", like `7K3M-Q2XA`: its
  /// address in a form that's easy to read out (see device_code.dart).
  String? get connectCode {
    final address = localAddress;
    final port = self.port; // null until the server is listening
    if (address == null || port == null) return null;
    return encodeDeviceCode(address, port: port);
  }

  /// Connects to a device by its code (see [parseConnectCode]), for when
  /// discovery doesn't find it. Throws [ConnectException] with a message
  /// for the user if that doesn't work.
  Future<Device> connect(String code) async {
    final target = decodeDeviceCode(code);
    if (target == null) {
      throw const ConnectException(
        'That code doesn\'t look right. Check it and try again.',
      );
    }
    final device = await _client.register(
      Device(
        name: target.host,
        platform: DevicePlatform.browser,
        host: target.host,
        port: target.port,
      ),
    );
    if (device == null) {
      throw const ConnectException(
        'No Wisp device answered. Is it on the same Wi-Fi, with Wisp open?',
      );
    }
    if (device.id == self.id) {
      throw const ConnectException('That\'s this device\'s own code.');
    }
    _manual[device.id] = (device: device, lastOk: DateTime.now());
    _seen(device, registerBack: false);
    return device;
  }

  /// Changes the name other devices see.
  Future<void> rename(String name) async {
    name = name.trim();
    if (name.isEmpty) return;
    if (name.length > 40) name = name.substring(0, 40);
    self = self.copyWith(name: name);
    _discovery?.announce();
    _rtc?.renamed();
    notifyListeners();
    await prefs?.setString(_Keys.name, name);
  }

  /// Saves received files to [dir] from now on. Returns false (and changes
  /// nothing) if Wisp can't write there.
  Future<bool> setSaveDir(String dir) async {
    if (!await _isWritable(dir)) return false;
    saveDir = dir;
    notifyListeners();
    await prefs?.setString(_Keys.saveDir, dir);
    return true;
  }

  /// Makes every device ask again before sending.
  Future<void> forgetTrusted() async {
    _trusted.clear();
    notifyListeners();
    await prefs?.remove(_Keys.trusted);
  }

  Future<void> _loadSettings() async {
    final prefs = this.prefs;
    if (prefs == null) return;

    // Keep the same id across restarts so "always accept" keeps working.
    final id = await prefs.getString(_Keys.id);
    if (id == null) {
      await prefs.setString(_Keys.id, self.id);
    } else {
      self = self.copyWith(id: id);
    }
    final name = await prefs.getString(_Keys.name);
    if (name != null && name.isNotEmpty) {
      self = self.copyWith(name: name);
    } else {
      await prefs.setString(_Keys.name, self.name); // keep the random name
    }
    if (isWebClient) return; // the browser decides where downloads go
    _showOnWeb = await prefs.getBool(_Keys.showOnWeb) ?? true;
    final dir = await prefs.getString(_Keys.saveDir);
    // The folder may be gone, or (on macOS) no longer allowed.
    if (dir != null && await _isWritable(dir)) saveDir ??= dir;
    _trusted.addAll(await prefs.getStringList(_Keys.trusted) ?? const []);
  }

  Future<void> _startWebClient() async {
    await _loadSettings();
    self = Device(
      id: self.id,
      name: self.name,
      platform: DevicePlatform.browser,
      detail: browserName,
    );
    _running = true;
    _joinRoom();
    notifyListeners();
  }

  /// This device's certificate: the saved one, or a new one on first run.
  Future<Identity> _loadIdentity() async {
    final prefs = this.prefs;
    final saved = Identity.fromPem(
      await prefs?.getString(_Keys.cert),
      await prefs?.getString(_Keys.key),
    );
    if (saved != null) return saved;

    final identity = await Identity.generate();
    await prefs?.setString(_Keys.cert, identity.certPem);
    await prefs?.setString(_Keys.key, identity.keyPem);
    return identity;
  }

  /// Adds a device by hand, e.g. in tests.
  @visibleForTesting
  void addDevice(Device device) => _seen(device, registerBack: false);

  @visibleForTesting
  void addTransfer(Transfer transfer) => _addTransfer(transfer);

  void _seen(Device device, {bool registerBack = true}) {
    final known = _devices[device.id]?.device;
    _devices[device.id] = (device: device, lastSeen: DateTime.now());
    if (known == null) {
      // Make sure they know about us too, even if our multicast doesn't
      // reach them.
      if (registerBack && _running && _visible) _client.register(device);
    }
    if (known == null ||
        known.name != device.name ||
        known.host != device.host ||
        known.port != device.port) {
      notifyListeners();
    }
  }

  Future<void> _onTick() async {
    final cutoff = DateTime.now().subtract(deviceTimeout);
    final before = _devices.length;
    _devices.removeWhere((_, s) => s.lastSeen.isBefore(cutoff));

    _pollManualDevices();

    final address = await _findLocalAddress();
    if (_devices.length != before || address != localAddress) {
      localAddress = address;
      notifyListeners();
    }
  }

  void _pollManualDevices() {
    final giveUp = DateTime.now().subtract(const Duration(minutes: 1));
    _manual.removeWhere((_, m) => m.lastOk.isBefore(giveUp));
    for (final m in _manual.values) {
      // Registering also keeps us on their list; when hidden, only look.
      final check = _visible
          ? _client.register(m.device)
          : _client.info(m.device);
      check.then((fresh) {
        if (fresh == null || !_manual.containsKey(fresh.id)) return;
        _manual[fresh.id] = (device: fresh, lastOk: DateTime.now());
        _seen(fresh, registerBack: false);
      });
    }
  }

  Future<Transfer?> _onOffer(Offer offer) async {
    if (!_visible) return null;

    if (!_trusted.contains(offer.from.id)) {
      final request = _pending = IncomingRequest(offer);
      _incoming.add(request);
      final accepted = await request._decision.future.timeout(
        acceptTimeout,
        onTimeout: () {
          request.cancelled.value = true;
          return false;
        },
      );
      _pending = null;
      if (!accepted) {
        request._transfer.complete(null);
        return null;
      }
      if (request.alwaysAccept) {
        _trusted.add(offer.from.id);
        prefs?.setStringList(_Keys.trusted, _trusted.toList());
      }
      final transfer = _receive(offer);
      request._transfer.complete(transfer);
      return transfer;
    }
    return _receive(offer);
  }

  Transfer _receive(Offer offer) {
    final transfer = Transfer(
      direction: TransferDirection.receive,
      peer: offer.from,
      files: offer.files,
      securityCode: offer.securityCode,
      saveDir: saveDir,
    );
    _addTransfer(transfer);
    return transfer;
  }

  void _onOfferCancelled(String sessionId) {
    final request = _pending;
    if (request == null || request.offer.sessionId != sessionId) return;
    request.cancelled.value = true;
    request.decline();
  }

  void _addTransfer(Transfer transfer) {
    _transfers.add(transfer);
    if (_transfers.length > 50) _transfers.removeAt(0);
    notifyListeners();
  }

  /// Name of the folder received files go to, e.g. "Downloads".
  String get saveDirName =>
      saveDir == null ? 'Downloads' : p.basename(saveDir!);

  static DevicePlatform _currentPlatform() {
    if (kIsWeb) return DevicePlatform.browser;
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => DevicePlatform.macos,
      TargetPlatform.windows => DevicePlatform.windows,
      TargetPlatform.android => DevicePlatform.android,
      TargetPlatform.iOS => DevicePlatform.ios,
      TargetPlatform.linux || TargetPlatform.fuchsia => DevicePlatform.linux,
    };
  }

  static Future<String> _defaultSaveDir() async {
    if (Platform.isAndroid) {
      // The public Download folder, where people look for files. Writable
      // without permissions on Android 11+; older versions fall back to the
      // app's own folder.
      const public = '/storage/emulated/0/Download';
      if (await _isWritable(public)) return public;
      return ((await getDownloadsDirectory()) ??
              await getApplicationDocumentsDirectory())
          .path;
    }
    if (Platform.isIOS) {
      // Shows up in the Files app under "On My iPhone › Wisp".
      return (await getApplicationDocumentsDirectory()).path;
    }
    return ((await getDownloadsDirectory()) ??
            await getApplicationDocumentsDirectory())
        .path;
  }

  static Future<bool> _isWritable(String dir) async {
    try {
      final probe = File(p.join(dir, '.wisp-${randomHex(4)}'));
      await probe.writeAsString('');
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// The address other devices can reach us on: a private LAN address,
  /// preferring the usual home-router range.
  static Future<String?> _findLocalAddress() async {
    try {
      final addresses = [
        for (final i in await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        ))
          for (final a in i.addresses)
            if (!a.isLoopback && !a.isLinkLocal) a.address,
      ];
      int rank(String a) => a.startsWith('192.168.')
          ? 0
          : a.startsWith('10.')
          ? 1
          : a.startsWith('172.')
          ? 2
          : 3;
      addresses.sort((a, b) => rank(a).compareTo(rank(b)));
      return addresses.firstOrNull;
    } on SocketException {
      return null;
    }
  }
}

/// Makes the [WispService] available to every screen:
/// `WispScope.of(context)`. Widgets that call it rebuild when it changes.
class WispScope extends InheritedNotifier<WispService> {
  const WispScope({
    super.key,
    required WispService service,
    required super.child,
  }) : super(notifier: service);

  static WispService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WispScope>()!.notifier!;
}

abstract final class _Keys {
  static const id = 'deviceId';
  static const name = 'deviceName';
  static const saveDir = 'saveDir';
  static const trusted = 'trustedDevices';
  static const cert = 'tlsCertificate';
  static const key = 'tlsPrivateKey';
  static const showOnWeb = 'showOnWeb';
}
