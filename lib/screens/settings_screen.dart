import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/protocol.dart';
import '../services/wisp_service.dart';
import '../theme/tokens.dart';
import '../utils/open_folder.dart';
import '../utils/pick_files.dart';
import '../widgets/device_avatar.dart';
import '../widgets/section_label.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wisp can\'t save files in that folder')),
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
                      if (service.browserUrl case final url?) ...[
                        const Divider(),
                        ListTile(
                          title: const Text('Browser address'),
                          subtitle: Text('$url — for devices without Wisp'),
                          trailing: IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy_outlined),
                            onPressed: () =>
                                Clipboard.setData(ClipboardData(text: url)),
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
                        Text('Wisp', style: text.titleMedium),
                        Text(
                          'Protocol $protocolVersion. Files go straight between your '
                          'devices over your Wi-Fi. Transfers between Wisp apps '
                          'are encrypted; the browser page isn\'t, so use it on '
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
