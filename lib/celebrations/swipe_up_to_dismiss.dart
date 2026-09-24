import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Wraps a full-screen celebration-flow route (see CelebrationScreen and
/// TrashTalkScreen) so it can be flicked away upwards, and periodically
/// nudges itself up and back to teach that gesture.
///
/// The nudge is the same hint-by-motion idea as the home screen's event
/// carousel (`_performNudge`): move the thing a little in the direction it
/// can be moved, rather than adding an explanatory label. It stays out of
/// the way of a real drag, and never runs once a dismissal has started.
///
/// Dragging is only picked up where nothing else claims the vertical axis.
/// A [SingleChildScrollView] whose content fits installs no drag recognizer
/// at all, so the usual case (card fits on screen) reaches this widget —
/// but when the card does overflow, or the trash-talk message field is
/// scrolled, scrolling wins, which is what you want.
class SwipeUpToDismiss extends StatefulWidget {
  /// Painted full-bleed behind the moving content, so travelling upwards
  /// uncovers the screen's own tint rather than a black band — the route
  /// below is still fully covered until the pop actually happens.
  final Color backgroundColor;
  final Widget child;

  const SwipeUpToDismiss({
    super.key,
    required this.backgroundColor,
    required this.child,
  });

  @override
  State<SwipeUpToDismiss> createState() => _SwipeUpToDismissState();
}

class _SwipeUpToDismissState extends State<SwipeUpToDismiss>
    with TickerProviderStateMixin {
  // Matches the carousel's nudge distance so the two hints feel like one
  // vocabulary; the first one lands after the route's entry transition has
  // settled rather than fighting it.
  static const double _nudgeDistance = 22.0;
  static const Duration _firstNudgeDelay = Duration(seconds: 3);
  static const Duration _nudgeInterval = Duration(seconds: 7);

  // Past either of these, the release counts as "flick it away" rather than
  // "peek and let go".
  static const double _dismissDistance = 110.0;
  static const double _dismissVelocity = -700.0;

  late final AnimationController _nudgeController;
  late final Animation<double> _nudgeOffset;
  late final AnimationController _settleController;

  Animation<double>? _settleOffset;
  double _dragOffset = 0;
  bool _isDragging = false;
  bool _isDismissing = false;
  Timer? _nudgeTimer;

  @override
  void initState() {
    super.initState();

    _nudgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _nudgeOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: -_nudgeDistance,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -_nudgeDistance,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 55,
      ),
    ]).animate(_nudgeController);

    _settleController = AnimationController(vsync: this)
      ..addListener(_onSettleTick);

    _nudgeTimer = Timer(_firstNudgeDelay, () {
      _performNudge();
      _nudgeTimer = Timer.periodic(_nudgeInterval, (_) => _performNudge());
    });
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    _nudgeController.dispose();
    _settleController
      ..removeListener(_onSettleTick)
      ..dispose();
    super.dispose();
  }

  void _performNudge() {
    if (!mounted || _isDragging || _isDismissing) return;
    if (_dragOffset != 0 || _nudgeController.isAnimating) return;
    _nudgeController.forward(from: 0);
  }

  void _onSettleTick() {
    final offset = _settleOffset;
    if (offset == null) return;
    setState(() => _dragOffset = offset.value);
  }

  void _onDragStart(DragStartDetails _) {
    if (_isDismissing) return;
    _settleController.stop();
    _nudgeController.stop();
    _nudgeController.value = 0;
    _isDragging = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isDismissing) return;
    final delta = details.primaryDelta ?? 0;
    setState(() {
      // Downward movement is heavily damped: this route only leaves
      // upwards, so pulling the other way should feel like resistance
      // rather than a second, non-existent exit.
      _dragOffset = math.min(
        40.0,
        _dragOffset + (delta > 0 ? delta * 0.25 : delta),
      );
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isDismissing) return;
    _isDragging = false;

    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss =
        _dragOffset <= -_dismissDistance || velocity <= _dismissVelocity;

    if (shouldDismiss) {
      _dismiss();
    } else {
      _animateOffsetTo(0, const Duration(milliseconds: 220), Curves.easeOut);
    }
  }

  void _dismiss() {
    _isDismissing = true;
    _nudgeTimer?.cancel();
    final target = -(MediaQuery.sizeOf(context).height + _dismissDistance);
    _animateOffsetTo(
      target,
      const Duration(milliseconds: 180),
      Curves.easeIn,
    ).whenComplete(() {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  TickerFuture _animateOffsetTo(double target, Duration duration, Curve curve) {
    _settleOffset = Tween<double>(
      begin: _dragOffset,
      end: target,
    ).chain(CurveTween(curve: curve)).animate(_settleController);
    _settleController.duration = duration;
    return _settleController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: AnimatedBuilder(
        animation: _nudgeController,
        builder: (context, child) {
          final y = _dragOffset + _nudgeOffset.value;
          // Fades out as it travels so a dismissal reads as "leaving",
          // not as the card sliding under the status bar.
          final fade = (y.abs() / 320).clamp(0.0, 0.6);
          return ColoredBox(
            color: widget.backgroundColor,
            child: Transform.translate(
              offset: Offset(0, y),
              child: Opacity(opacity: 1 - fade, child: child),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}
