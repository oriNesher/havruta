import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../app_theme.dart';
import 'feature_tip.dart';
import 'feature_tip_anchor.dart';
import 'feature_tips_controller.dart';

const Color _accent = Color(0xFF8B5CF6);
const Color _surface = Color(0xFF181824);
const double _ringPadding = 6;
const double _ringRadius = 14;

/// How long a tip's anchor must sit still on screen before the tip shows,
/// so it never lands on a screen's first paint or flickers past during a
/// transition or scroll.
const Duration _dwell = Duration(milliseconds: 800);

/// Mounted once, above the Navigator (see MaterialApp.builder), so a tip can
/// be drawn over whatever real screen the user is on.
///
/// Tips never block anything: there is no scrim, and every tap goes through
/// to the app. The first tap anywhere while a tip is up both does what it
/// normally would and dismisses the tip for good. At most one tip shows per
/// screen visit (see PageVisitObserver); others wait for the next visit.
class FeatureTipLayer extends StatefulWidget {
  final Widget child;

  const FeatureTipLayer({super.key, required this.child});

  @override
  State<FeatureTipLayer> createState() => _FeatureTipLayerState();
}

class _FeatureTipLayerState extends State<FeatureTipLayer>
    with SingleTickerProviderStateMixin {
  final FeatureTipsController _controller = FeatureTipsController.instance;
  final GlobalKey _layerKey = GlobalKey();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  _ShownTip? _shown;

  /// The tip whose anchor is visible and is waiting out [_dwell].
  FeatureTip? _candidate;
  DateTime? _candidateSince;
  Timer? _dwellTimer;

  /// The page visit a tip was last dismissed on: no other tip shows until
  /// the user moves to a different page.
  int? _quietVisit;

  /// Pointers that went down while the current tip was showing.
  final Set<int> _pointersDown = {};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_scheduleFrame);
    _controller.pageVisits.addListener(_scheduleFrame);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    // Persistent (not repeating): runs after layout on frames that already
    // happen — scrolls, route transitions, anchors mounting — instead of
    // driving frames of its own.
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _controller.pageVisits.removeListener(_scheduleFrame);
    _controller.removeListener(_scheduleFrame);
    _dwellTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _scheduleFrame() {
    if (mounted) SchedulerBinding.instance.scheduleFrame();
  }

  void _onPointer(PointerEvent event) {
    final shown = _shown;
    if (shown == null) {
      _pointersDown.clear();
      return;
    }
    if (event is PointerDownEvent) {
      _pointersDown.add(event.pointer);
    } else if (event is PointerCancelEvent) {
      _pointersDown.remove(event.pointer);
    } else if (event is PointerUpEvent && _pointersDown.remove(event.pointer)) {
      // Only a tap that started while the tip was up — never the tail end
      // of a touch that began before it appeared.
      _dismiss(shown.tip);
    }
  }

  void _dismiss(FeatureTip tip) {
    if (_shown?.tip != tip) return;
    _controller.markSeen(tip);
    _quietVisit = _controller.pageVisits.visit;
    _clearCandidate();
    _pointersDown.clear();
    _pulse.stop();
    setState(() => _shown = null);
  }

  void _clearCandidate() {
    _candidate = null;
    _candidateSince = null;
    _dwellTimer?.cancel();
    _dwellTimer = null;
  }

  void _onFrame(Duration _) {
    if (!mounted) return;
    final next = _resolve();
    if (next != _shown) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _apply(next));
    }
  }

  void _apply(_ShownTip? next) {
    if (!mounted || next == _shown) return;
    setState(() => _shown = next);
    if (next == null) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  _ShownTip? _resolve() {
    final pending = _controller.pending;
    if (pending.isEmpty) {
      _clearCandidate();
      return null;
    }
    final layerBox = _layerKey.currentContext?.findRenderObject();
    if (layerBox is! RenderBox || !layerBox.hasSize) return null;
    Rect toLocal(Rect global) => Rect.fromPoints(
      layerBox.globalToLocal(global.topLeft),
      layerBox.globalToLocal(global.bottomRight),
    );
    final registry = FeatureTipAnchorRegistry.instance;

    // A tip that's up follows its anchor around. If the anchor goes away
    // without the user dismissing it (a celebration pushed over it, the
    // system back button), the tip simply hides and stays owed.
    final current = _shown;
    if (current != null && pending.contains(current.tip)) {
      final rect = registry.visibleRect(current.tip);
      if (rect != null) return _ShownTip(current.tip, toLocal(rect));
    }

    if (_quietVisit == _controller.pageVisits.visit) {
      _clearCandidate();
      return null;
    }

    for (final tip in pending) {
      final rect = registry.visibleRect(tip);
      if (rect == null) continue;
      if (_candidate != tip) {
        _clearCandidate();
        _candidate = tip;
        _candidateSince = DateTime.now();
        _dwellTimer = Timer(_dwell, _scheduleFrame);
        return null;
      }
      if (DateTime.now().difference(_candidateSince!) < _dwell) return null;
      return _ShownTip(tip, toLocal(rect));
    }
    _clearCandidate();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Stack(
      key: _layerKey,
      fit: StackFit.expand,
      children: [
        widget.child,
        if (shown != null)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(shown.tip),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              builder: (context, value, child) =>
                  Opacity(opacity: value, child: child),
              child: _TipView(
                shown: shown,
                pulse: _pulse,
                onDismiss: () => _dismiss(shown.tip),
              ),
            ),
          ),
      ],
    );
  }
}

@immutable
class _ShownTip {
  final FeatureTip tip;

  /// The anchor's rect in the layer's coordinates.
  final Rect target;

  const _ShownTip(this.tip, this.target);

  @override
  bool operator ==(Object other) =>
      other is _ShownTip && other.tip == tip && other.target == target;

  @override
  int get hashCode => Object.hash(tip, target);
}

class _TipView extends StatelessWidget {
  final _ShownTip shown;
  final Animation<double> pulse;
  final VoidCallback onDismiss;

  const _TipView({
    required this.shown,
    required this.pulse,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: pulse,
              builder: (context, _) => CustomPaint(
                painter: _RingPainter(target: shown.target, pulse: pulse.value),
              ),
            ),
          ),
        ),
        // Only the bubble itself takes taps; everywhere else passes
        // through to the app (CustomSingleChildLayout hit-tests its child
        // only).
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _BubbleLayout(
              target: shown.target.inflate(_ringPadding),
              safeTop: padding.top + 8,
              safeBottom: keyboard > 0 ? keyboard + 8 : padding.bottom + 8,
            ),
            child: _TipBubble(tip: shown.tip, onDismiss: onDismiss),
          ),
        ),
      ],
    );
  }
}

/// Puts the bubble on whichever side of the target has more room
/// (excluding the keyboard), then clamps it on-screen.
class _BubbleLayout extends SingleChildLayoutDelegate {
  static const double _gap = 12;
  static const double _sideMargin = 16;
  static const double _maxWidth = 420;

  final Rect target;
  final double safeTop;
  final double safeBottom;

  const _BubbleLayout({
    required this.target,
    required this.safeTop,
    required this.safeBottom,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = (constraints.maxWidth - _sideMargin * 2).clamp(
      0.0,
      _maxWidth,
    );
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bottomLimit = size.height - safeBottom;
    final roomBelow = bottomLimit - target.bottom;
    final roomAbove = target.top - safeTop;
    final preferred = roomBelow >= roomAbove
        ? target.bottom + _gap
        : target.top - _gap - childSize.height;
    final maxTop = bottomLimit - childSize.height;
    final top = maxTop < safeTop
        ? safeTop
        : preferred.clamp(safeTop, maxTop).toDouble();
    final left = ((size.width - childSize.width) / 2)
        .clamp(_sideMargin, size.width)
        .toDouble();
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_BubbleLayout oldDelegate) =>
      oldDelegate.target != target ||
      oldDelegate.safeTop != safeTop ||
      oldDelegate.safeBottom != safeBottom;
}

class _TipBubble extends StatelessWidget {
  final FeatureTip tip;
  final VoidCallback onDismiss;

  const _TipBubble({required this.tip, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: _surface,
        elevation: 8,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _accent.withValues(alpha: 0.55)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: PhosphorIcon(
                        PhosphorIconsFill.sparkle,
                        size: 18,
                        color: _accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tip.title,
                            style: AppTheme.display(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tip.message,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  height: 1.35,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(foregroundColor: _accent),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pulsing ring around the target. Draws only — never takes taps.
class _RingPainter extends CustomPainter {
  final Rect target;
  final double pulse;

  const _RingPainter({required this.target, required this.pulse});

  RRect _ring(double extra) => RRect.fromRectAndRadius(
    target.inflate(_ringPadding + extra),
    Radius.circular(_ringRadius + extra),
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      _ring(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _accent,
    );
    canvas.drawRRect(
      _ring(1 + 10 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _accent.withValues(alpha: (1 - pulse) * 0.5),
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.pulse != pulse || oldDelegate.target != target;
}
