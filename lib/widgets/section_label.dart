import 'package:flutter/material.dart';

/// Small uppercase heading above a group: "SEND", "NEARBY · 4".
/// [trailing] sits on the right, e.g. a status or a "Clear" button.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}
