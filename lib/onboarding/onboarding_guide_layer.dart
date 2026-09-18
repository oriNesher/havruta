import 'package:flutter/foundation.dart' show kDebugMode, listEquals;
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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    // Persistent (not repeating) callbacks: this runs after layout on
    // frames that already happen — scrolls, route transitions, anchors
    // mounting — instead of driving frames of its own. For users not in
    // onboarding it costs one boolean check per frame.
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _pulse.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // Re-resolve on the next frame: anchors may still need one to mount.
    if (mounted) SchedulerBinding.instance.scheduleFrame();
  }

  void _onFrame(Duration _) {
    if (!mounted) return;

    final guidance = _controller.guidance;
    final next = guidance.isEmpty ? null : _resolve(guidance);
    if (next != _spotlight) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _apply(next));
    }

    if (_controller.wantsWelcome &&
        OnboardingAnchorRegistry.instance.settled(
              OnboardingAnchorIds.homeScreen,
            ) !=
            null) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => _controller.presentWelcome(),
      );
    }
  }

  _Spotlight? _resolve(List<OnboardingGuidance> guidance) {
    final layerBox = _layerKey.currentContext?.findRenderObject();
    if (layerBox is! RenderBox || !layerBox.hasSize) return null;

    for (final entry in guidance) {
      final anchors = <OnboardingAnchorState>[];
      final holes = <Rect>[];
      for (final id in entry.anchorIds) {
        final found = OnboardingAnchorRegistry.instance.settled(id);
        if (found == null) continue;
        anchors.add(found.anchor);
        holes.add(
          Rect.fromPoints(
            layerBox.globalToLocal(found.rect.topLeft),
            layerBox.globalToLocal(found.rect.bottomRight),
          ),
        );
      }
      if (anchors.isNotEmpty) {
        // TEMPORARY: keep the debug harness reachable, since the scrim
        // otherwise blocks every control but the one being pointed at.
        // Remove with the debug entry point in home_screen.dart.
        final debugHole = kDebugMode
            ? OnboardingAnchorRegistry.instance.settled(
                OnboardingAnchorIds.debugHarnessButton,
              )
            : null;
        return _Spotlight(
          signature: entry.signature,
          message: entry.message,
          holes: holes,
          passThroughHoles: [
            if (debugHole != null)
              Rect.fromPoints(
                layerBox.globalToLocal(debugHole.rect.topLeft),
                layerBox.globalToLocal(debugHole.rect.bottomRight),
              ),
          ],
          anchors: anchors,
        );
      }
    }
    return null;
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
    _controller.noteGuidedRoute(next.anchors.first.route);

    // Bring a target that's scrolled out of view into it — once per
    // distinct piece of guidance, so this can't fight the user's own
    // scrolling afterwards.
    if (_scrolledFor == next.signature) return;
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
  final String signature;
  final String message;

  /// The controls the guidance points at: ringed, and tappable.
  final List<Rect> holes;

  /// Left tappable but not highlighted (debug harness escape hatch).
  final List<Rect> passThroughHoles;

  final List<OnboardingAnchorState> anchors;

  const _Spotlight({
    required this.signature,
    required this.message,
    required this.holes,
    this.passThroughHoles = const [],
    required this.anchors,
  });

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
        final size = constraints.biggest;
        final union = spotlight.holes
            .reduce((a, b) => a.expandToInclude(b))
            .inflate(_holePadding);
        final below = (size.height - union.bottom) >= union.top;

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
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: below ? union.bottom + 14 : null,
              bottom: below ? null : size.height - union.top + 14,
              child: _GuideBubble(message: spotlight.message),
            ),
          ],
        );
      },
    );
  }
}

class _GuideBubble extends StatelessWidget {
  final String message;

  const _GuideBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF181824),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _accent.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhosphorIcon(PhosphorIconsFill.sparkle, size: 18, color: _accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims everything except the highlighted controls, and — via [hitTest] —
/// absorbs taps outside them, so the only thing the user can press is the
/// real control the guide is pointing at.
class _SpotlightPainter extends CustomPainter {
  final List<Rect> holes;
  final List<Rect> passThroughHoles;
  final double pulse;

  const _SpotlightPainter({
    required this.holes,
    required this.pulse,
    this.passThroughHoles = const [],
  });

  Iterable<Rect> get _allHoles => [...holes, ...passThroughHoles];

  RRect _hole(Rect rect, [double extra = 0]) => RRect.fromRectAndRadius(
    rect.inflate(_holePadding + extra),
    Radius.circular(_holeRadius + extra),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    for (final hole in _allHoles) {
      scrim.addRRect(_hole(hole));
    }
    canvas.drawPath(scrim, Paint()..color = const Color(0xC7050509));

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
      !_allHoles.any((hole) => _hole(hole).contains(position));

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.pulse != pulse ||
      !listEquals(oldDelegate.holes, holes) ||
      !listEquals(oldDelegate.passThroughHoles, passThroughHoles);
}
