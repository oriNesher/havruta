import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import 'feature_tip.dart';

/// Marks a real product widget as where [tip] belongs.
///
/// Placing one has no visible effect and no tip logic: the screen only
/// declares "this control lives here". The one thing it reports is a tap on
/// the control, which FeatureTipLayer treats like "Got it" when this tip is
/// up — using the feature means the tip has done its job. A drag that
/// starts on it (a scroll, a carousel swipe) doesn't count. FeatureTipsController decides
/// whether the tip is still owed, and FeatureTipLayer only uses an anchor
/// that is fully on screen, on the settled top-most route. Several anchors
/// may share a tip (e.g. every Home card's Add Progress button); the first
/// fully visible one is used.
class FeatureTipAnchor extends StatefulWidget {
  final FeatureTip tip;
  final Widget child;

  const FeatureTipAnchor({super.key, required this.tip, required this.child});

  @override
  State<FeatureTipAnchor> createState() => _FeatureTipAnchorState();
}

class _FeatureTipAnchorState extends State<FeatureTipAnchor> {
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    FeatureTipAnchorRegistry.instance._register(widget.tip, this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(FeatureTipAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tip != widget.tip) {
      FeatureTipAnchorRegistry.instance._unregister(oldWidget.tip, this);
      FeatureTipAnchorRegistry.instance._register(widget.tip, this);
    }
  }

  @override
  void dispose() {
    FeatureTipAnchorRegistry.instance._unregister(widget.tip, this);
    super.dispose();
  }

  /// This anchor's global rect, or null unless it's laid out on the
  /// top-most route (not covered by a dialog or sheet), that route has
  /// finished animating in with nothing transitioning above it, and it
  /// sits entirely inside every scrollable viewport around it — so a tip
  /// is never pointed at something scrolled away or on a hidden page.
  Rect? get visibleGlobalRect {
    if (!mounted) return null;
    final route = _route;
    if (route != null) {
      if (!route.isCurrent) return null;
      final status = route.animation?.status;
      if (status != null && status != AnimationStatus.completed) return null;
      final above = route.secondaryAnimation?.status;
      if (above != null && above != AnimationStatus.dismissed) return null;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = box.localToGlobal(Offset.zero) & box.size;

    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      final viewportBox = scrollable.context.findRenderObject();
      if (viewportBox is RenderBox && viewportBox.hasSize) {
        final viewport =
            viewportBox.localToGlobal(Offset.zero) & viewportBox.size;
        if (!_within(viewport, rect)) return null;
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    return rect;
  }

  static bool _within(Rect outer, Rect inner) =>
      inner.left >= outer.left - 1 &&
      inner.top >= outer.top - 1 &&
      inner.right <= outer.right + 1 &&
      inner.bottom <= outer.bottom + 1;

  int? _downPointer;
  Offset? _downPosition;

  void _onPointerDown(PointerDownEvent event) {
    _downPointer = event.pointer;
    _downPosition = event.position;
  }

  void _onPointerUp(PointerUpEvent event) {
    final start = _downPosition;
    final isTap = event.pointer == _downPointer &&
        start != null &&
        (event.position - start).distance < kTouchSlop;
    _downPointer = null;
    _downPosition = null;
    if (isTap) FeatureTipAnchorRegistry.instance._reportUsed(widget.tip);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _downPointer = null;
    _downPosition = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onPointerDown,
    onPointerUp: _onPointerUp,
    onPointerCancel: _onPointerCancel,
    child: widget.child,
  );
}

/// Every mounted [FeatureTipAnchor], by tip.
class FeatureTipAnchorRegistry {
  FeatureTipAnchorRegistry._();
  static final FeatureTipAnchorRegistry instance = FeatureTipAnchorRegistry._();

  final Map<FeatureTip, List<_FeatureTipAnchorState>> _byTip = {};

  /// Set by FeatureTipLayer: told whenever an anchored control is tapped.
  ValueChanged<FeatureTip>? onAnchorUsed;

  void _reportUsed(FeatureTip tip) => onAnchorUsed?.call(tip);

  void _register(FeatureTip tip, _FeatureTipAnchorState anchor) {
    _byTip.putIfAbsent(tip, () => []).add(anchor);
  }

  void _unregister(FeatureTip tip, _FeatureTipAnchorState anchor) {
    final list = _byTip[tip];
    if (list == null) return;
    list.remove(anchor);
    if (list.isEmpty) _byTip.remove(tip);
  }

  /// The global rect of the first fully visible anchor for [tip], if any.
  Rect? visibleRect(FeatureTip tip) {
    for (final anchor in _byTip[tip] ?? const <_FeatureTipAnchorState>[]) {
      final rect = anchor.visibleGlobalRect;
      if (rect != null) return rect;
    }
    return null;
  }
}
