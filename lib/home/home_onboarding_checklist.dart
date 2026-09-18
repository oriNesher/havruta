import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../app_theme.dart';
import '../onboarding/onboarding_controller.dart';

const Color _accent = Color(0xFF8B5CF6);
const Color _surface = Color(0xFF181824);
const Color _elevated = Color(0xFF202033);
const Color _rim = Color(0xFF2A2A42);
const Color _muted = Color(0xFF8888A0);

/// Home's onboarding checklist: suggested tutorials the user can start,
/// continue or dismiss one by one. Everything shown — which modules, their
/// copy, their state — comes from OnboardingController.checklist (built
/// from OnboardingModuleRegistry); this widget only renders it, and takes
/// no space at all when there's nothing to suggest.
class HomeOnboardingChecklist extends StatelessWidget {
  const HomeOnboardingChecklist({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = OnboardingController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.checklist;
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _rim),
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'GET STARTED',
                          style: AppTheme.display(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      Text(
                        '${items.length} left',
                        style: AppTheme.mono(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                ),
                for (final item in items) _ChecklistRow(item: item),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChecklistRow extends StatefulWidget {
  final OnboardingChecklistItem item;

  const _ChecklistRow({required this.item});

  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow> {
  bool _starting = false;

  OnboardingController get _controller => OnboardingController.instance;

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await _controller.startModule(widget.item.id);
    } catch (e) {
      debugPrint('Checklist start failed (${widget.item.id.name}): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't start this guide right now. Check your connection "
              'and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final entry = item.entry;
    final textTheme = Theme.of(context).textTheme;
    final inProgress = item.state == OnboardingChecklistItemState.inProgress;

    final Widget action;
    if (_starting) {
      action = const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (inProgress) {
      action = TextButton(
        onPressed: () => _controller.deferModule(item.id),
        style: TextButton.styleFrom(
          foregroundColor: _muted,
          visualDensity: VisualDensity.compact,
        ),
        child: const Text(OnboardingController.finishLaterLabel),
      );
    } else {
      action = FilledButton(
        onPressed: _start,
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Text(
          item.state == OnboardingChecklistItemState.deferred
              ? 'Continue'
              : 'Start',
        ),
      );
    }

    return InkWell(
      onTap: inProgress || _starting ? null : _start,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _elevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: inProgress ? _accent : _rim,
                ),
              ),
              alignment: Alignment.center,
              child: PhosphorIcon(entry.icon, size: 18, color: _accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    inProgress ? 'In progress' : entry.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: inProgress ? _accent : _muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            action,
            if (entry.dismissible)
              IconButton(
                tooltip: 'Dismiss',
                onPressed: _starting
                    ? null
                    : () => _controller.dismissModule(item.id),
                visualDensity: VisualDensity.compact,
                icon: PhosphorIcon(
                  PhosphorIconsRegular.x,
                  size: 16,
                  color: _muted,
                ),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
