import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, HapticFeedback;

import '../../app_theme.dart';

// ─────────────────────────────────────────────
// Add progress button — shared by the home card and Challenge Details
// ─────────────────────────────────────────────

/// The "ADD PROGRESS" call to action. Callers own placement and any
/// feature-tip anchor; [isLoggingProgress] swaps the label for a spinner and
/// disables the button while a report is in flight.
class AddProgressButton extends StatelessWidget {
  final bool isLoggingProgress;
  final VoidCallback onTap;

  const AddProgressButton({
    super.key,
    required this.isLoggingProgress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ElevatedButton(
      onPressed: isLoggingProgress ? null : onTap,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: AppTheme.display(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.4),
      ),
      child: isLoggingProgress
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            )
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CutoutPlusIcon(size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text('ADD PROGRESS'),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────
// Add-progress popup — numeric input, quick-add chips, hold-to-submit
// ─────────────────────────────────────────────

const List<int> _quickAddAmounts = [1, 5, 25];

/// Shows the add-progress popup, prefilled with [initialAmount] and showing
/// [holdStatement] in the gap above the submit button while the hold runs.
/// Returns the submitted amount once the user completes the hold-to-submit
/// gesture, or null if they cancelled.
/// [maxAmount] caps the amount at what's left to reach the goal (null for
/// modes with no finish line); anything above it is refused with a message.
Future<int?> showAddProgressDialog(
  BuildContext context, {
  required int initialAmount,
  required String holdStatement,
  int? maxAmount,
  String unit = '',
}) {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => _AddProgressDialog(
      initialAmount: initialAmount,
      holdStatement: holdStatement,
      maxAmount: maxAmount,
      unit: unit,
    ),
  );
}

class _AddProgressDialog extends StatefulWidget {
  final int initialAmount;
  final String holdStatement;
  final int? maxAmount;
  final String unit;

  const _AddProgressDialog({
    required this.initialAmount,
    required this.holdStatement,
    required this.maxAmount,
    required this.unit,
  });

  @override
  State<_AddProgressDialog> createState() => _AddProgressDialogState();
}

class _AddProgressDialogState extends State<_AddProgressDialog> {
  // Owned by this State (not by the showDialog<int> Future) so it's disposed
  // only once this widget is actually unmounted — the dialog route's exit
  // transition keeps this TextField alive and reacting (losing focus,
  // animating its label) for a bit after Navigator.pop() resolves that
  // Future, so disposing on the Future's completion tore the controller down
  // while the field could still touch it, crashing mid-frame.
  //
  // The prefill starts fully selected, so typing a new amount replaces the
  // last one instead of appending to it ("5" + "10" → "10", not "510");
  // autofocus keeps a valid selection rather than collapsing it.
  late final TextEditingController _controller = TextEditingController.fromValue(
    TextEditingValue(
      text: '${widget.initialAmount}',
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: '${widget.initialAmount}'.length,
      ),
    ),
  );

  bool _isHolding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _currentAmount() => int.tryParse(_controller.text.trim()) ?? 0;

  bool get _isOverGoal {
    final max = widget.maxAmount;
    return max != null && _currentAmount() > max;
  }

  String get _overGoalMessage {
    final max = widget.maxAmount ?? 0;
    final unitSuffix = widget.unit.isNotEmpty ? ' ${widget.unit}' : '';
    return "That's too much — only $max$unitSuffix left to hit the goal";
  }

  void _applyQuickAdd(int delta) {
    HapticFeedback.selectionClick();
    final next = _currentAmount() + delta;
    _controller.text = '$next';
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final green = colorScheme.tertiary;

    return AlertDialog(
      title: const Text('Add progress'),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              autofocus: true,
              style: AppTheme.mono(fontSize: 34, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                errorText: _isOverGoal ? _overGoalMessage : null,
                errorMaxLines: 2,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _quickAddAmounts
                  .map(
                    (amount) => OutlinedButton(
                      onPressed: () => _applyQuickAdd(amount),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: green,
                        side: BorderSide(color: green),
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('+$amount'),
                    ),
                  )
                  .toList(),
            ),
            // Deliberate breathing room between the quick-add chips and
            // the submit button: the hold's encouragement lives here, and
            // reserving the space unconditionally keeps the button from
            // jumping under a finger that's already pressing it.
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: AnimatedOpacity(
                opacity: _isHolding ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Center(
                  child: Text(
                    widget.holdStatement,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: AppTheme.display(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: green,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _HoldToSubmitButton(
              enabled: _currentAmount() > 0 && !_isOverGoal,
              color: green,
              onHoldChanged: (holding) {
                if (_isHolding != holding) {
                  setState(() => _isHolding = holding);
                }
              },
              onConfirmed: () => Navigator.of(context).pop(_currentAmount()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// A button that only fires [onConfirmed] after being pressed and held for
/// the full [_holdDuration] — releasing early cancels the hold instead of
/// submitting, giving a deliberate confirmation gesture for a write that
/// (unlike the old +1 tap) can move progress by a large, hard-to-undo
/// amount. Short enough to feel like a firm press rather than a wait, long
/// enough that a stray tap never submits. Fires at most once per dialog.
class _HoldToSubmitButton extends StatefulWidget {
  final bool enabled;
  final Color color;

  /// Fired with true the moment a hold starts and false once it's released
  /// or confirmed, so the dialog can reveal its encouragement above the
  /// button for exactly as long as the finger is down.
  final ValueChanged<bool> onHoldChanged;
  final VoidCallback onConfirmed;

  const _HoldToSubmitButton({
    required this.enabled,
    required this.color,
    required this.onHoldChanged,
    required this.onConfirmed,
  });

  @override
  State<_HoldToSubmitButton> createState() => _HoldToSubmitButtonState();
}

class _HoldToSubmitButtonState extends State<_HoldToSubmitButton>
    with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 800);

  late final AnimationController _controller;

  /// Latched on the first completed hold: the dialog's exit transition keeps
  /// this button alive and pressable briefly, and a second completion would
  /// pop the screen underneath (and report twice).
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _holdDuration)
      ..addStatusListener(_onStatusChanged);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onStatusChanged(AnimationStatus status) {
    // Only a hold that runs the animation all the way to 1.0 counts as a
    // confirmation — a release partway through animates back to 0 instead
    // of completing, so this only ever fires for a genuine full-length hold.
    if (status == AnimationStatus.completed && !_confirmed) {
      _confirmed = true;
      // The "click" that tells the thumb it landed — no-op on web.
      HapticFeedback.heavyImpact();
      widget.onHoldChanged(false);
      widget.onConfirmed();
    }
  }

  void _startHold() {
    if (!mounted || !widget.enabled || _confirmed) return;
    widget.onHoldChanged(true);
    _controller.forward(from: 0);
  }

  void _cancelHold() {
    // The dialog closes as soon as a hold completes (see _onStatusChanged),
    // which can leave a pointer-up still in flight for the pointer that
    // completed it — guard against acting on a disposed controller.
    if (!mounted || _confirmed) return;
    // Reported before the value guard below: a tap released within the same
    // frame it started never moves the controller off 0, and skipping the
    // report there would leave the statement showing with no hold running.
    widget.onHoldChanged(false);
    if (_controller.value == 0) return;
    _controller.animateBack(0, duration: const Duration(milliseconds: 200));
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.enabled ? 1 : 0.4,
      child: GestureDetector(
        // Without this, a tap only registers where a descendant actually
        // paints (the small centered label, or the fill once it's already
        // grown) — most of the button's surface would be dead space for
        // hit-testing and the hold would never start.
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _startHold(),
        onTapUp: (_) => _cancelHold(),
        onTapCancel: _cancelHold,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _controller.value;

            return Container(
              height: 52,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: widget.color, width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(color: widget.color),
                  ),
                  Text(
                    // A seconds countdown would read "1s" the whole way at
                    // this length, so the fill alone shows how long is left.
                    progress > 0 ? 'HOLD…' : 'HOLD TO SUBMIT',
                    style: AppTheme.display(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: progress > 0.5 ? Colors.white : widget.color,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// A filled circle with a plus-shaped hole punched through the middle, so
// whatever sits behind it (the button's background color) shows through the
// plus instead of the plus being drawn on top in a solid color.
class _CutoutPlusIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _CutoutPlusIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CutoutPlusPainter(color: color),
    );
  }
}

class _CutoutPlusPainter extends CustomPainter {
  final Color color;

  _CutoutPlusPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final barLength = size.width * 0.6;
    final barThickness = size.width * 0.22;

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawCircle(center, size.width / 2, Paint()..color = color);

    final cutout = Paint()..blendMode = BlendMode.clear;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: barLength, height: barThickness),
        Radius.circular(barThickness / 2),
      ),
      cutout,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: barThickness, height: barLength),
        Radius.circular(barThickness / 2),
      ),
      cutout,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CutoutPlusPainter oldDelegate) =>
      oldDelegate.color != color;
}
