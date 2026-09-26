import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum ToastTone {
  info(AppColors.accent, AppColors.accentSoft),
  success(AppColors.success, AppColors.successSoft),
  error(AppColors.danger, AppColors.dangerSoft);

  const ToastTone(this.color, this.soft);

  final Color color;
  final Color soft;

  (Color, Color) get colors => (color, soft);
}

class ToastAction {
  const ToastAction(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;
}

/// What a toast shows at the moment.
class ToastContent {
  const ToastContent({
    required this.title,
    this.subtitle,
    this.leading,
    this.icon = Icons.info_outline,
    this.tone = ToastTone.info,
    this.progress,
    this.sticky = false,
    this.actions = const [],
    this.onTap,
  });

  final String title;
  final String? subtitle;

  /// Shown on the left; [icon] in a tinted circle if null.
  final Widget? leading;
  final IconData icon;
  final ToastTone tone;

  /// 0–1 shows a progress bar; null shows none.
  final double? progress;

  /// Stays until it isn't sticky any more (e.g. a transfer that's still
  /// running), instead of going away after a few seconds.
  final bool sticky;
  final List<ToastAction> actions;
  final VoidCallback? onTap;
}

/// The toasts on screen. Get it with [ToastController.of].
class ToastController extends ChangeNotifier {
  static const maxShown = 3;

  /// The nearest [ToastHost]'s controller. Without one (a screen tested on
  /// its own), toasts go nowhere.
  static ToastController of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ToastScope>()?.controller ??
      _nowhere;

  static final _nowhere = ToastController();

  final _entries = <_ToastEntry>[];

  /// Shows a toast, or updates the one with the same [key]. With
  /// [updates], [content] is read again whenever it changes, so a toast
  /// can follow something live (like a transfer's progress).
  void show({
    required String key,
    required ToastContent Function() content,
    Listenable? updates,
  }) {
    final old = _entries.where((e) => e.key == key).firstOrNull;
    if (old != null) _remove(old);
    final entry = _ToastEntry(key, content, updates, this);
    _entries.insert(0, entry);
    // Too many: the oldest ones go, but not ones still in progress.
    while (_entries.length > maxShown) {
      final extra = _entries.lastWhere(
        (e) => !e.content().sticky,
        orElse: () => _entries.last,
      );
      _remove(extra);
    }
    entry.schedule();
    notifyListeners();
  }

  /// A simple one-off message.
  void message(
    String title, {
    String? subtitle,
    IconData icon = Icons.info_outline,
    ToastTone tone = ToastTone.info,
  }) => show(
    key: 'message:$title',
    content: () =>
        ToastContent(title: title, subtitle: subtitle, icon: icon, tone: tone),
  );

  void dismiss(String key) {
    final entry = _entries.where((e) => e.key == key).firstOrNull;
    if (entry == null) return;
    _remove(entry);
    notifyListeners();
  }

  void _remove(_ToastEntry entry) {
    _entries.remove(entry);
    entry.dispose();
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }
}

class _ToastEntry {
  _ToastEntry(this.key, this.content, this.updates, this.owner) {
    updates?.addListener(schedule);
  }

  final String key;
  final ToastContent Function() content;
  final Listenable? updates;
  final ToastController owner;

  Timer? _timer;
  bool hovered = false;

  /// Starts the countdown to going away, unless it has to stay for now.
  void schedule() {
    _timer?.cancel();
    final now = content();
    if (now.sticky || hovered) return;
    final time = now.actions.isEmpty
        ? const Duration(seconds: 4)
        : const Duration(seconds: 7);
    _timer = Timer(time, () => owner.dismiss(key));
  }

  void dispose() {
    _timer?.cancel();
    updates?.removeListener(schedule);
  }
}

/// Shows [controller]'s toasts over [child]: at the top on phones, at the
/// bottom right on wide screens. Put it in `MaterialApp.builder`.
class ToastHost extends StatefulWidget {
  const ToastHost({super.key, required this.controller, required this.child});

  final ToastController controller;
  final Widget child;

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost> {
  // Its own overlay: the toasts sit above the Navigator, whose overlay
  // (needed by tooltips) is below them.
  late final _layer = OverlayEntry(builder: _buildLayer);

  @override
  void didUpdateWidget(ToastHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _layer.markNeedsBuild();
  }

  @override
  void dispose() {
    _layer
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ToastScope(
    controller: widget.controller,
    child: Stack(
      children: [
        widget.child,
        Positioned.fill(child: Overlay(initialEntries: [_layer])),
      ],
    ),
  );

  Widget _buildLayer(BuildContext context) {
    final controller = widget.controller;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return SafeArea(
      child: Align(
        alignment: wide ? Alignment.bottomRight : Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.all(wide ? AppSpacing.xxl : AppSpacing.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Column(
                mainAxisSize: .min,
                verticalDirection: wide ? .up : .down,
                children: [
                  for (final entry in controller._entries)
                    _ToastCard(
                      key: ValueKey(entry),
                      entry: entry,
                      fromTop: !wide,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastScope extends InheritedWidget {
  const _ToastScope({required this.controller, required super.child});

  final ToastController controller;

  @override
  bool updateShouldNotify(_ToastScope old) => controller != old.controller;
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({super.key, required this.entry, required this.fromTop});

  final _ToastEntry entry;
  final bool fromTop;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final curve = CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic);
    // Grows into place. Not a SizeTransition: that clips the shadow.
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Align(
        alignment: widget.fromTop
            ? Alignment.bottomCenter
            : Alignment.topCenter,
        heightFactor: curve.value,
        child: child,
      ),
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: Offset(0, widget.fromTop ? -0.3 : 0.3),
            end: Offset.zero,
          ).animate(curve),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Dismissible(
              key: ValueKey(entry),
              onDismissed: (_) => entry.owner.dismiss(entry.key),
              child: MouseRegion(
                // Reading it: don't go away meanwhile.
                onEnter: (_) {
                  entry.hovered = true;
                  entry.schedule();
                },
                onExit: (_) {
                  entry.hovered = false;
                  entry.schedule();
                },
                child: ListenableBuilder(
                  listenable: Listenable.merge([entry.updates]),
                  builder: (context, _) =>
                      _ToastBody(entry: entry, content: entry.content()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastBody extends StatelessWidget {
  const _ToastBody({required this.entry, required this.content});

  final _ToastEntry entry;
  final ToastContent content;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (fg, bg) = content.tone.colors;
    void close() => entry.owner.dismiss(entry.key);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: content.onTap == null
              ? null
              : () {
                  close();
                  content.onTap!();
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: .start,
              children: [
                content.leading ??
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(content.icon, color: fg, size: 20),
                    ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          content.title,
                          style: text.titleSmall,
                          maxLines: 2,
                          overflow: .ellipsis,
                        ),
                        if (content.subtitle case final subtitle?)
                          Text(
                            subtitle,
                            style: text.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: .ellipsis,
                          ),
                        if (content.progress case final progress?) ...[
                          const SizedBox(height: AppSpacing.sm),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              color: fg,
                              backgroundColor: bg,
                            ),
                          ),
                        ],
                        if (content.actions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Wrap(
                              children: [
                                for (final action in content.actions)
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                      ),
                                      minimumSize: const Size(0, 36),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () {
                                      close();
                                      action.onPressed();
                                    },
                                    child: Text(action.label),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: AppColors.textSecondary,
                  onPressed: close,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
