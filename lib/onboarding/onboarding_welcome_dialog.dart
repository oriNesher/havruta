import 'package:flutter/material.dart';

import '../app_theme.dart';

/// The onboarding Welcome prompt, shown once on the user's first entry into
/// the real Home experience.
///
/// [onAccept] runs the real backend setup and must throw on failure — the
/// dialog then stays open with an error so the user can retry. It closes
/// only on an actual choice, so "has the user answered yet?" is never left
/// ambiguous.
Future<void> showOnboardingWelcomeDialog({
  required BuildContext context,
  required Future<void> Function() onAccept,
  required VoidCallback onSkip,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OnboardingWelcomeDialog(onAccept: onAccept, onSkip: onSkip),
  );
}

class _OnboardingWelcomeDialog extends StatefulWidget {
  final Future<void> Function() onAccept;
  final VoidCallback onSkip;

  const _OnboardingWelcomeDialog({required this.onAccept, required this.onSkip});

  @override
  State<_OnboardingWelcomeDialog> createState() =>
      _OnboardingWelcomeDialogState();
}

class _OnboardingWelcomeDialogState extends State<_OnboardingWelcomeDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAccept();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Onboarding welcome accept failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't start the guide. Check your connection and "
            'try again.';
      });
    }
  }

  void _skip() {
    widget.onSkip();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF2A2A42)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Welcome to Havruta',
                style: AppTheme.display(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Want to try our quick guide and see how the magic works?',
                style: textTheme.bodyLarge,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFFF5C7A),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : _accept,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Yes, show me'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _busy ? null : _skip,
                child: const Text('Skip'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
