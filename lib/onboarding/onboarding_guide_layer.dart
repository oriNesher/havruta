import 'package:flutter/foundation.dart' show kDebugMode, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'modules/onboarding_module.dart';
import 'onboarding_anchor.dart';
import 'onboarding_controller.dart';
import 'onboarding_ids.dart';

const double _holePadding = 6;
const double _holeRadius = 14;
const Color _accent = Color(0xFF8B5CF6);

/// Mounted once, above the Navigator (see MaterialApp.builder), so onboarding
/// guidance can be drawn over whatever real screen the user is on without any
/// screen hosting an overlay of its own — which is also why repeated
/// navigation can't stack duplicate overlays.
///
/// Every frame while the controller is guiding, this resolves the highest
/// priority guidance whose anchors are actually usable right now and
/// spotlights them. If the target screen isn't up yet, an anchor hasn't been
/// laid out, or a dialog is covering it, nothing is drawn — so the spotlight
/// naturally waits for screens and anchors to mount.
class OnboardingGuideLayer extends StatefulWidget {
  final Widget child;

  const OnboardingGuideLayer({super.key, required this.child});

  @override
  State<OnboardingGuideLayer> createState() => _OnboardingGuideLayerState();
}

class _OnboardingGuideLayerState extends State<OnboardingGuideLayer>
    with SingleTickerProviderStateMixin {
  final OnboardingController _controller = OnboardingController.instance;
  final GlobalKey _layerKey = GlobalKey();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  _Spotlight? _spotlight;
  String? _scrolledFor;
  DateTime? _lastRevealAt;

  /// waitForUserTouch guidance: the signature that is showable but still
  /// held back this frame, and the ones the user has since touched for.
  String? _heldForTouch;
  final Set<String> _touchedFor = {};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    // Persistent (not repeating) callbacks: this runs after layout on
    // frames that already happen — scrolls, route transitions, anchors
    // mounting — instead of driving frames of its own. For users not in
    // onboarding it costs one boolean check per frame.
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _controller.removeListener(_onControllerChanged);
    _pulse.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // Re-resolve on the next frame: anchors may still need one to mount.
    if (mounted) SchedulerBinding.instance.scheduleFrame();
  }

  /// A pointer-up (the end of the user's own tap/scroll, which the screen
  /// has already handled) releases guidance held for a first touch.
  void _onPointer(PointerEvent event) {
    final held = _heldForTouch;
    if (event is! PointerUpEvent || held == null || !mounted) return;
    _touchedFor.add(held);
    SchedulerBinding.instance.scheduleFrame();
  }

  void _onFrame(Duration _) {
    if (!mounted) return;

    final guidance = _controller.guidance;
    if (guidance.isEmpty) {
      _heldForTouch = null;
      _touchedFor.clear();
    }
    final next = guidance.isEmpty ? null : _resolve(guidance);
    if (next != _spotlight) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _apply(next));
    }
    if (next == null && guidance.isNotEmpty) _maybeReveal(guidance);

    // Welcome or the final completion message, once Home is settled.
    if (_controller.wantsPrompt &&
        OnboardingAnchorRegistry.instance.settled(
              OnboardingAnchorIds.homeScreen,
            ) !=
            null) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => _controller.presentPrompt(),
      );
    }
  }

  _Spotlight? _resolve(List<OnboardingGuidance> guidance) {
    _heldForTouch = null;
    final layerBox = _layerKey.currentContext?.findRenderObject();
    if (layerBox is! RenderBox || !layerBox.hasSize) return null;

    Rect toLocal(Rect global) => Rect.fromPoints(
      layerBox.globalToLocal(global.topLeft),
      layerBox.globalToLocal(global.bottomRight),
    );

    _Spotlight? found;
    for (final entry in guidance) {
      final anchors = <OnboardingAnchorState>[];
      final holes = <Rect>[];
      for (final id in entry.anchorIds) {
        final settled = OnboardingAnchorRegistry.instance.settled(id);
        if (settled == null) continue;
        anchors.add(settled.anchor);
        holes.add(toLocal(settled.rect));
      }
      if (anchors.isEmpty) continue;

      if (entry.waitForUserTouch && !_touchedFor.contains(entry.signature)) {
        _heldForTouch = entry.signature;
        break;
      }

      // TEMPORARY: keep the debug harness reachable, since the scrim
      // otherwise blocks every control but the one being pointed at.
      // Remove with the debug entry point in home_screen.dart.
      final passThroughIds = [
        ...entry.passThroughAnchorIds,
        if (kDebugMode) OnboardingAnchorIds.debugHarnessButton,
      ];
      found = _Spotlight(
        guidance: entry,
        holes: holes,
        passThroughHoles: [
          for (final id in passThroughIds)
            if (OnboardingAnchorRegistry.instance.settled(id) case final hit?)
              toLocal(hit.rect),
        ],
        anchors: anchors,
      );
      break;
    }

    // A held-back step re-arms once it stops being showable (the user left
    // the screen), so coming back to it waits for a fresh first touch.
    _touchedFor.removeWhere((signature) => found?.signature != signature);
    return found;
  }

  /// Nothing is usable, possibly because the target sits on an item a lazy
  /// container hasn't built (an off-screen carousel page): ask containers
  /// to bring the highest-priority unmounted anchor into view. Throttled,
  /// and it retries, since the container may itself still be loading — or
  /// may have moved on (e.g. a newer item arrived) after an earlier reveal.
  void _maybeReveal(List<OnboardingGuidance> guidance) {
    final now = DateTime.now();
    final last = _lastRevealAt;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastRevealAt = now;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final registry = OnboardingAnchorRegistry.instance;
      for (final entry in guidance) {
        for (final id in entry.anchorIds) {
          if (!registry.isMounted(id) && registry.reveal(id)) return;
        }
      }
    });
  }

  void _apply(_Spotlight? next) {
    if (!mounted || next == _spotlight) return;
    setState(() => _spotlight = next);

    if (next == null) {
      _pulse.stop();
      _scrolledFor = null;
      return;
    }
    if (!_pulse.isAnimating) _pulse.repeat();
    _controller.noteGuidanceShown(next.guidance, next.anchors.first.route);

    // Bring a target that's scrolled out of view into it — once per
    // distinct piece of guidance, so this can't fight the user's own
    // scrolling afterwards. Never for non-modal guidance, which is shown
    // while the user is working on the screen themselves.
    if (!next.guidance.modal || _scrolledFor == next.signature) return;
    _scrolledFor = next.signature;
    final layerBox = _layerKey.currentContext?.findRenderObject();
    if (layerBox is! RenderBox || !layerBox.hasSize) return;
    final padding = MediaQuery.paddingOf(context);
    final safe = Rect.fromLTRB(
      0,
      padding.top + 56,
      layerBox.size.width,
      layerBox.size.height - padding.bottom - 24,
    );
    final target = next.holes.first;
    if (!safe.contains(target.topLeft) || !safe.contains(target.bottomRight)) {
      next.anchors.first.ensureVisible();
    }
  }

  @override
  Widget build(BuildContext context) {
    final spotlight = _spotlight;
    return Stack(
      key: _layerKey,
      fit: StackFit.expand,
      children: [
        widget.child,
        if (spotlight != null)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(spotlight.signature),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              builder: (context, value, child) =>
                  Opacity(opacity: value, child: child),
              child: _SpotlightView(spotlight: spotlight, pulse: _pulse),
            ),
          ),
      ],
    );
  }
}

@immutable
class _Spotlight {
  final OnboardingGuidance guidance;

  /// The controls the guidance points at: ringed, and tappable.
  final List<Rect> holes;

  /// Left tappable but not highlighted (debug harness escape hatch).
  final List<Rect> passThroughHoles;

  final List<OnboardingAnchorState> anchors;

  const _Spotlight({
    required this.guidance,
    required this.holes,
    this.passThroughHoles = const [],
    required this.anchors,
  });

  String get signature => guidance.signature;

  @override
  bool operator ==(Object other) =>
      other is _Spotlight &&
      other.signature == signature &&
      listEquals(other.holes, holes) &&
      listEquals(other.passThroughHoles, passThroughHoles);

  @override
  int get hashCode => Object.hash(
    signature,
    Object.hashAll(holes),
    Object.hashAll(passThroughHoles),
  );
}

class _SpotlightView extends StatelessWidget {
  final _Spotlight spotlight;
  final Animation<double> pulse;

  const _SpotlightView({required this.spotlight, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final union = spotlight.holes
            .reduce((a, b) => a.expandToInclude(b))
            .inflate(_holePadding);
        final padding = MediaQuery.paddingOf(context);
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;

        return Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: pulse,
                builder: (context, _) => CustomPaint(
                  painter: _SpotlightPainter(
                    holes: spotlight.holes,
                    passThroughHoles: spotlight.passThroughHoles,
                    pulse: pulse.value,
                    modal: spotlight.guidance.modal,
                  ),
                ),
              ),
            ),
            if (spotlight.guidance.message.isNotEmpty)
              Positioned.fill(
                child: CustomSingleChildLayout(
                  delegate: _BubbleLayout(
                    target: union,
                    safeTop: padding.top + 8,
                    safeBottom: keyboard > 0
                        ? keyboard + 8
                        : padding.bottom + 8,
                  ),
                  child: _GuideBubble(guidance: spotlight.guidance),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Puts the bubble on whichever side of the highlighted controls has more
/// room (excluding the keyboard), then clamps it on-screen — so a tall
/// target, or a dialog pushed up by the keyboard, can't push the message
/// off the edge; at worst it overlaps the dimmed area around the target.
class _BubbleLayout extends SingleChildLayoutDelegate {
  static const double _gap = 14;
  static const double _sideMargin = 16;

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
    final width = constraints.maxWidth - _sideMargin * 2;
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
    return Offset(_sideMargin, top);
  }

  @override
  bool shouldRelayout(_BubbleLayout oldDelegate) =>
      oldDelegate.target != target ||
      oldDelegate.safeTop != safeTop ||
      oldDelegate.safeBottom != safeBottom;
}

class _GuideBubble extends StatelessWidget {
  final OnboardingGuidance guidance;

  const _GuideBubble({required this.guidance});

  @override
  Widget build(BuildContext context) {
    final actions = guidance.actions;
    return Material(
      color: const Color(0xFF181824),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _accent.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, actions.isEmpty ? 16 : 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PhosphorIcon(
                  PhosphorIconsFill.sparkle,
                  size: 18,
                  color: _accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    guidance.message,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final action in actions)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: action.primary
                          ? FilledButton(
                              onPressed: action.onPressed,
                              style: FilledButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(action.label),
                            )
                          : TextButton(
                              onPressed: action.onPressed,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white70,
                              ),
                              child: Text(action.label),
                            ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Modal: dims everything except the highlighted controls, and — via
/// [hitTest] — absorbs taps outside them, so the only thing the user can
/// press is the real control the guide is pointing at. Non-modal: only
/// rings the controls; nothing is dimmed and every tap goes through.
class _SpotlightPainter extends CustomPainter {
  final List<Rect> holes;
  final List<Rect> passThroughHoles;
  final double pulse;
  final bool modal;

  const _SpotlightPainter({
    required this.holes,
    required this.pulse,
    this.passThroughHoles = const [],
    this.modal = true,
  });

  Iterable<Rect> get _allHoles => [...holes, ...passThroughHoles];

  RRect _hole(Rect rect, [double extra = 0]) => RRect.fromRectAndRadius(
    rect.inflate(_holePadding + extra),
    Radius.circular(_holeRadius + extra),
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (modal) {
      final scrim = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size);
      for (final hole in _allHoles) {
        scrim.addRRect(_hole(hole));
      }
      canvas.drawPath(scrim, Paint()..color = const Color(0xC7050509));
    }

    for (final hole in holes) {
      canvas.drawRRect(
        _hole(hole, 1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _accent,
      );
      canvas.drawRRect(
        _hole(hole, 1 + 10 * pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _accent.withValues(alpha: (1 - pulse) * 0.5),
      );
    }
  }

  @override
  bool hitTest(Offset position) =>
      modal && !_allHoles.any((hole) => _hole(hole).contains(position));

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.pulse != pulse ||
      oldDelegate.modal != modal ||
      !listEquals(oldDelegate.holes, holes) ||
      !listEquals(oldDelegate.passThroughHoles, passThroughHoles);
}
