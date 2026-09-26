import 'package:flutter/material.dart';

import '../net/identity.dart';

enum DevicePlatform {
  macos(Icons.laptop_outlined, 'macOS'),
  windows(Icons.desktop_windows_outlined, 'Windows'),
  linux(Icons.desktop_windows_outlined, 'Linux'),
  android(Icons.smartphone_outlined, 'Android'),
  ios(Icons.smartphone_outlined, 'iOS'),
  browser(Icons.language, 'Browser');

  const DevicePlatform(this.icon, this.label);

  final IconData icon;
  final String label;

  static DevicePlatform fromName(String? name) =>
      values.asNameMap()[name] ?? DevicePlatform.browser;
}

class Device {
  const Device({
    required this.name,
    required this.platform,
    this.id = '',
    this.detail,
    this.host,
    this.port,
    this.fingerprint,
  });

  /// Random id the device picks for itself; stable while the app runs.
  final String id;
  final String name;
  final DevicePlatform platform;

  /// Extra info shown after the platform, e.g. "Safari" for a browser.
  final String? detail;

  /// Where its Wisp server listens. Null for this device.
  final String? host;
  final int? port;

  /// SHA-256 of the device's TLS certificate. Connections to it only go
  /// through if it presents exactly this certificate. Null for browsers.
  final String? fingerprint;

  /// "macOS", or "Browser · Safari" when there's a detail.
  String get subtitle =>
      detail == null ? platform.label : '${platform.label} · $detail';

  Device copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? fingerprint,
  }) => Device(
    id: id ?? this.id,
    name: name ?? this.name,
    platform: platform,
    detail: detail,
    host: host ?? this.host,
    port: port ?? this.port,
    fingerprint: fingerprint ?? this.fingerprint,
  );

  /// What goes over the wire. The host isn't included — the receiver takes
  /// it from the packet or connection the info arrived on.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform.name,
    'detail': ?detail,
    'port': port,
    'fingerprint': ?fingerprint,
  };

  /// Returns null if [json] isn't a valid device description.
  static Device? fromJson(Object? json, {String? host}) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final port = json['port'];
    if (id is! String || id.isEmpty || name is! String || port is! int) {
      return null;
    }
    final detail = json['detail'];
    final fingerprint = json['fingerprint'];
    return Device(
      id: id,
      name: name.length > 64 ? name.substring(0, 64) : name,
      platform: DevicePlatform.fromName(json['platform'] as String?),
      detail: detail is String ? detail : null,
      host: host,
      port: port,
      fingerprint: isFingerprint(fingerprint) ? fingerprint as String : null,
    );
  }
}
