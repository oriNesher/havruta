import 'package:flutter/material.dart';

import '../../app_theme.dart';

/// The "Are you sure?" card in front of an action that can't be undone —
/// deleting a challenge, removing a participant. Its confirm button stays
/// disabled until "Yes, I'm sure" is ticked: deliberate friction, like the
/// hold-to-submit on Add Progress, so a stray tap can never do it.
///
/// [what] names the action in the title ("Delete Run club?"), [consequences]
/// are short lines spelling out what happens, and [confirmLabel] is the
/// destructive button's text. With [reasonHint], an optional free-text
/// reason field is shown too (it goes in the organizer audit log).
///
/// Resolves to null when cancelled, otherwise to the trimmed reason ('' when
/// none was asked for or given).
Future<String?> confirmIrreversible(
  BuildContext context, {
  required String what,
  required List<String> consequences,
  required String confirmLabel,
  String? reasonHint,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ConfirmIrreversibleDialog(
      what: what,
      consequences: consequences,
      confirmLabel: confirmLabel,
      reasonHint: reasonHint,
    ),
  );
}

class _ConfirmIrreversibleDialog extends StatefulWidget {
  final String what;
  final List<String> consequences;
  final String confirmLabel;
  final String? reasonHint;

  const _ConfirmIrreversibleDialog({
    required this.what,
    required this.consequences,
    required this.confirmLabel,
    this.reasonHint,
  });

  @override
  State<_ConfirmIrreversibleDialog> createState() =>
      _ConfirmIrreversibleDialogState();
}

class _ConfirmIrreversibleDialogState
    extends State<_ConfirmIrreversibleDialog> {
  bool _sure = false;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = theme.colorScheme.error;

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: danger, size: 32),
      title: Text(
        'Are you sure?',
        style: AppTheme.display(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.what,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: danger.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in widget.consequences)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('•  ', style: TextStyle(color: danger)),
                          Expanded(child: Text(line)),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Text('•  ', style: TextStyle(color: danger)),
                        Expanded(
                          child: Text(
                            "This can't be undone.",
                            style: TextStyle(
                              color: danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.reasonHint != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                maxLength: 500,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(labelText: widget.reasonHint),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _sure,
              onChanged: (value) => setState(() => _sure = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text("Yes, I'm sure"),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _sure
              ? () => Navigator.of(context).pop(_reason.text.trim())
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
