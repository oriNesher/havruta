import 'package:flutter/material.dart';

/// Marks a real product widget as a place onboarding guidance can point at.
///
/// Placing an anchor has no visible effect and no onboarding logic: the
/// screen just declares "this control lives here". OnboardingController
/// decides whether any anchor is currently highlighted, and the guide layer
/// only uses an anchor once its route is the settled top-most route (not
/// covered by a dialog, not mid-transition) and it has been laid out.
class OnboardingAnchor extends StatefulWidget {
  final String id;
  final Widget child;

  const OnboardingAnchor({super.key, required this.id, required this.child});

  @override
  State<OnboardingAnchor> createState() => OnboardingAnchorState();
}

class OnboardingAnchorState extends State<OnboardingAnchor> {
  ModalRoute<dynamic>? _route;

  ModalRoute<dynamic>? get route => _route;

  @override
  void initState() {
    super.initState();
    OnboardingAnchorRegistry.instance._register(widget.id, this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(OnboardingAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      OnboardingAnchorRegistry.instance._unregister(oldWidget.id, this);
      OnboardingAnchorRegistry.instance._register(widget.id, this);
    }
  }

  @override
  void dispose() {
    OnboardingAnchorRegistry.instance._unregister(widget.id, this);
    super.dispose();
  }

  /// This anchor's global rect, or null unless it's laid out on the
  /// top-most route and that route has finished animating in with nothing
  /// transitioning above it.
  Rect? get settledGlobalRect {
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
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> ensureVisible() {
    if (!mounted) return Future.value();
    return Scrollable.ensureVisible(
      context,
      alignment: 0.4,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Brings the item carrying anchor [id] into view, if this container holds
/// one, and returns whether it did. See [OnboardingAnchorRegistry.reveal].
typedef OnboardingAnchorRevealer = bool Function(String id);

/// Every mounted OnboardingAnchor, by id. More than one anchor can share an
/// id (e.g. the same control on two stacked routes); [settled] picks the
/// one that's actually usable right now.
class OnboardingAnchorRegistry {
  OnboardingAnchorRegistry._();
  static final OnboardingAnchorRegistry instance = OnboardingAnchorRegistry._();

  final Map<String, List<OnboardingAnchorState>> _byId = {};
  final List<OnboardingAnchorRevealer> _revealers = [];

  /// Registered by containers that build items lazily (e.g. a PageView that
  /// only builds its visible page), whose off-screen items' anchors
  /// therefore aren't mounted for Scrollable.ensureVisible to reach.
  void addRevealer(OnboardingAnchorRevealer revealer) =>
      _revealers.add(revealer);
  void removeRevealer(OnboardingAnchorRevealer revealer) =>
      _revealers.remove(revealer);

  /// Asks the registered containers to bring the item carrying anchor [id]
  /// on screen so it can mount. True if one of them did.
  bool reveal(String id) {
    for (final revealer in List.of(_revealers)) {
      if (revealer(id)) return true;
    }
    return false;
  }

  bool isMounted(String id) => _byId.containsKey(id);

  void _register(String id, OnboardingAnchorState anchor) {
    _byId.putIfAbsent(id, () => []).add(anchor);
  }

  void _unregister(String id, OnboardingAnchorState anchor) {
    final list = _byId[id];
    if (list == null) return;
    list.remove(anchor);
    if (list.isEmpty) _byId.remove(id);
  }

  ({OnboardingAnchorState anchor, Rect rect})? settled(String id) {
    for (final anchor in _byId[id] ?? const <OnboardingAnchorState>[]) {
      final rect = anchor.settledGlobalRect;
      if (rect != null) return (anchor: anchor, rect: rect);
    }
    return null;
  }

  Iterable<String> get mountedIds => _byId.keys;
}
