import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/protocol.dart';
import '../net/signaling.dart';
import '../services/wisp_service.dart';
import '../theme/tokens.dart';
import '../utils/open_folder.dart';
import '../utils/pick_files.dart';
import '../widgets/device_avatar.dart';
import '../widgets/section_label.dart';
import '../widgets/toasts.dart';
import '../widgets/wisp_logo.dart';
import '../widgets/text_input_dialog.dart';

/// Device name, where files are saved, trusted devices.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _rename(BuildContext context, WispService service) async {
    final name = await showTextInputDialog(
      context,
      title: 'Device name',
      confirmLabel: 'Save',
      initialText: service.self.name,
      helper: 'This is what other devices see.',
      maxLength: 40,
    );
    if (name != null) await service.rename(name);
  }

  Future<void> _changeFolder(BuildContext context, WispService service) async {
    final dir = await pickFolder(title: 'Save received files to');
    if (dir == null) return;
    final ok = await service.setSaveDir(dir);
    if (!ok && context.mounted) {
      ToastController.of(context).message(
        'Wisp can\'t save files in that folder',
        subtitle: 'Pick another one',
        icon: Icons.folder_off_outlined,
        tone: ToastTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final service = WispScope.of(context);
    final code = service.connectCode;
    final trusted = service.trustedCount;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                const SectionLabel('This device'),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: DeviceAvatar(
                          platform: service.self.platform,
                          highlighted: true,
                        ),
                        title: Text(service.self.name),
                        subtitle: const Text('Name other devices see'),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _rename(context, service),
                      ),
                      if (!service.isWebClient) ...[
                        const Divider(),
                        ListTile(
                          title: const Text('Code'),
                          subtitle: Text(code ?? 'Not connected to a network'),
                          trailing: code == null
                              ? null
                              : IconButton(
                                  tooltip: 'Copy',
                                  icon: const Icon(Icons.copy_outlined),
                                  onPressed: () => Clipboard.setData(
                                    ClipboardData(text: code),
                                  ),
                                ),
                        ),
                      ],
                      if (signalingUrl.isNotEmpty && !service.isWebClient) ...[
                        const Divider(),
                        SwitchListTile(
                          title: const Text('Show on the web app'),
                          subtitle: const Text(
                            'Browsers on this Wi-Fi can find this device '
                            'through the internet, without a QR code',
                          ),
                          value: service.showOnWeb,
                          onChanged: service.setShowOnWeb,
                        ),
                        const Divider(),
                        ListTile(
                          title: const Text('Link for browsers'),
                          subtitle: const Text(
                            'Opens Wisp on devices without the app',
                          ),
                          trailing: IconButton(
                            tooltip: 'Copy link',
                            icon: const Icon(Icons.link),
                            onPressed: () => Clipboard.setData(
                              const ClipboardData(text: webAppUrl),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const SectionLabel('Receiving'),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Save files to'),
                        subtitle: Text(
                          service.saveDir ??
                              (service.isWebClient
                                  ? 'Your browser\'s downloads'
                                  : '—'),
                        ),
                        // Other folders need extra permissions on phones.
                        trailing: canOpenFolders
                            ? TextButton(
                                onPressed: () =>
                                    _changeFolder(context, service),
                                child: const Text('Change'),
                              )
                            : null,
                      ),
                      const Divider(),
                      ListTile(
                        title: const Text('Always accept'),
                        subtitle: Text(switch (trusted) {
                          0 => 'Every device asks first',
                          1 => '1 device can send without asking',
                          _ => '$trusted devices can send without asking',
                        }),
                        trailing: TextButton(
                          onPressed: trusted == 0
                              ? null
                              : service.forgetTrusted,
                          child: const Text('Forget all'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const SectionLabel('About'),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Row(
                          children: [
                            const WispLogo(size: 24),
                            const SizedBox(width: AppSpacing.sm),
                            Text('Wisp', style: text.titleMedium),
                            const Spacer(),
                            // Set by flutter build: --build-name, or pubspec.
                            Text(
                              'Version ${const String.fromEnvironment('FLUTTER_BUILD_NAME')}',
                              style: text.bodyMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Protocol $protocolVersion. Files go straight between your '
                          'devices over your Wi-Fi. Transfers between Wisp apps '
                          'are encrypted; the web app on your Wi-Fi isn\'t, so use it on '
                          'networks you trust.',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
