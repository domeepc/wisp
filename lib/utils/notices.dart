import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/transfer.dart';
import '../screens/transfer_screen.dart';
import '../services/wisp_service.dart';
import '../theme/tokens.dart';
import '../widgets/device_avatar.dart';
import '../widgets/toasts.dart';
import '../widgets/transfer_icon.dart';
import 'format.dart';
import 'open_folder.dart';
import 'transfer_text.dart';

/// Turns what happens in [service] into toasts:
/// - someone opened Wisp in a browser (the QR code worked),
/// - the web app connected to a device, or lost it,
/// - files are coming in (live progress, then "Show in folder"),
/// - a send finished while its screen wasn't open.
///
/// Devices found on the Wi-Fi don't get one; the Nearby list shows them,
/// and there can be many.
class Notices {
  Notices({
    required this.service,
    required this.toasts,
    required this.openTransfer,
  }) {
    _devices = {for (final d in service.devices) d.id: d};
    _transfers = service.transfers.toSet();
    service.addListener(_onChange);
  }

  final WispService service;
  final ToastController toasts;
  final void Function(Transfer transfer) openTransfer;

  late Map<String, Device> _devices;
  late Set<Transfer> _transfers;

  void dispose() => service.removeListener(_onChange);

  void _onChange() {
    final now = {for (final d in service.devices) d.id: d};
    for (final device in now.values) {
      if (!_devices.containsKey(device.id)) _joined(device);
    }
    for (final device in _devices.values) {
      if (!now.containsKey(device.id)) _left(device);
    }
    _devices = now;

    for (final transfer in service.transfers) {
      if (_transfers.add(transfer)) _started(transfer);
    }
    _transfers.retainAll(service.transfers);
  }

  void _joined(Device device) {
    if (service.isWebClient) {
      _deviceToast(device, 'Connected to ${device.name}', ToastTone.success);
    } else if (device.platform == DevicePlatform.browser) {
      _deviceToast(
        device,
        '${device.name} joined from a browser',
        ToastTone.success,
      );
    }
  }

  void _left(Device device) {
    // Only the web app's devices matter here: they're all it has.
    if (!service.isWebClient) return;
    _deviceToast(
      device,
      'Lost connection to ${device.name}',
      ToastTone.error,
      subtitle: 'Trying again while this page is open',
    );
  }

  void _deviceToast(
    Device device,
    String title,
    ToastTone tone, {
    String? subtitle,
  }) => showDeviceToast(toasts, device, title, tone, subtitle: subtitle);

  void _started(Transfer transfer) {
    if (!transfer.status.isActive) return;
    if (transfer.direction == TransferDirection.receive) {
      _showReceive(transfer);
    } else {
      void onUpdate() {
        if (transfer.status.isActive) return;
        transfer.removeListener(onUpdate);
        // Its screen already says how it went.
        if (!TransferScreen.showing.contains(transfer)) _showSent(transfer);
      }

      transfer.addListener(onUpdate);
    }
  }

  void _showReceive(Transfer t) {
    toasts.show(
      key: 'transfer:${t.sessionId}',
      updates: t,
      content: () {
        final what = describeFiles(t);
        final from = t.peer.name;
        final folder = t.saveDir;
        return switch (t.status) {
          TransferStatus.waiting || TransferStatus.running => ToastContent(
            title: 'Receiving $what',
            subtitle: t.speed > 0
                ? '$from · ${formatBytes(t.speed)}/s'
                : 'From $from',
            leading: TransferIcon(transfer: t),
            progress: t.progress,
            sticky: true,
            onTap: () => openTransfer(t),
          ),
          TransferStatus.done => ToastContent(
            title: 'Received $what',
            subtitle: service.isWebClient
                ? 'From $from · in your downloads'
                : 'From $from · ${formatBytes(t.totalBytes)}',
            tone: ToastTone.success,
            leading: TransferIcon(transfer: t),
            onTap: () => openTransfer(t),
            actions: [
              if (folder != null && canOpenFolders)
                ToastAction('Show in folder', () => openFolder(folder)),
              ToastAction('View', () => openTransfer(t)),
            ],
          ),
          _ => ToastContent(
            title: transferTitle(t),
            subtitle: 'From $from',
            tone: ToastTone.error,
            leading: TransferIcon(transfer: t),
            onTap: () => openTransfer(t),
          ),
        };
      },
    );
  }

  void _showSent(Transfer t) {
    final what = describeFiles(t);
    final to = t.peer.name;
    final done = t.status == TransferStatus.done;
    toasts.show(
      key: 'transfer:${t.sessionId}',
      content: () => ToastContent(
        title: done ? 'Sent $what' : transferTitle(t),
        subtitle: done && t.peer.platform == DevicePlatform.browser
            ? 'Downloaded on $to'
            : 'To $to',
        tone: done ? ToastTone.success : ToastTone.error,
        leading: TransferIcon(transfer: t),
        onTap: () => openTransfer(t),
      ),
    );
  }
}

/// A toast about [device], with its icon. One per device: a newer one
/// replaces it.
void showDeviceToast(
  ToastController toasts,
  Device device,
  String title,
  ToastTone tone, {
  String? subtitle,
}) {
  toasts.show(
    key: 'device:${device.id}',
    content: () => ToastContent(
      title: title,
      subtitle: subtitle ?? device.subtitle,
      tone: tone,
      leading: _Badged(
        tone: tone,
        child: DeviceAvatar(platform: device.platform),
      ),
    ),
  );
}

/// A small check or cross on the corner of [child].
class _Badged extends StatelessWidget {
  const _Badged({required this.tone, required this.child});

  final ToastTone tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (tone) {
      ToastTone.success => (AppColors.success, Icons.check),
      ToastTone.error => (AppColors.danger, Icons.close),
      ToastTone.info => (null, null),
    };
    if (color == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(icon, size: 11, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
