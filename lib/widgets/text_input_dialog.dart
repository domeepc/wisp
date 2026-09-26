import 'package:flutter/material.dart';

/// Asks for a line (or a few lines) of text. Returns null if cancelled.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialText = '',
  String? hint,
  String? helper,
  int? maxLength,
  int maxLines = 1,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialText: initialText,
      hint: hint,
      helper: helper,
      maxLength: maxLength,
      maxLines: maxLines,
    ),
  );
}

// A StatefulWidget so the controller lives exactly as long as the dialog —
// disposing it right after `showDialog` returns would crash while the
// dialog is still animating out.
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialText,
    required this.hint,
    required this.helper,
    required this.maxLength,
    required this.maxLines,
  });

  final String title;
  final String confirmLabel;
  final String initialText;
  final String? hint;
  final String? helper;
  final int? maxLength;
  final int maxLines;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiline = widget.maxLines > 1;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          minLines: multiline ? 3 : 1,
          maxLines: widget.maxLines,
          textInputAction: multiline ? null : TextInputAction.done,
          onSubmitted: multiline
              ? null
              : (value) => Navigator.pop(context, value),
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.helper,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
