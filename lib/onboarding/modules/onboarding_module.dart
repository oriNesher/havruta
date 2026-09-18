import 'package:flutter/foundation.dart';

import '../onboarding_repository.dart';
import '../onboarding_state.dart';

/// One piece of guidance: highlight every currently-usable anchor in
/// [anchorIds] and show [message] next to them.
@immutable
class OnboardingGuidance {
  final List<String> anchorIds;
  final String message;

  const OnboardingGuidance({required this.anchorIds, required this.message});

  /// Stable identity for "the same guidance", used by the guide layer to
  /// avoid re-running one-shot effects (like scrolling into view).
  String get signature => '${anchorIds.join(',')}|$message';
}

/// What the controller exposes to the module it is running.
abstract interface class OnboardingModuleHost {
  String get uid;
  OnboardingRepository get repository;

  /// The module's [OnboardingModule.guidance] may have changed.
  void guidanceChanged();

  /// The module has observed, from real product data, that the user did
  /// what it teaches. Called at most once per started module.
  void moduleCompleted(OnboardingModule module);
}

/// A self-contained tutorial step. A module observes normal product data
/// (Firestore records, not screen state) to decide what to point at next
/// and when it's done, and describes that as [guidance] against anchor ids
/// — it never touches screens directly and screens never check which
/// module is running.
abstract class OnboardingModule {
  OnboardingModuleId get id;

  /// Whether finishing this module should unwind the screen the guide led
  /// the user onto, back to Home.
  bool get returnsHomeOnComplete => false;

  /// Creates/verifies the real product data this module teaches with,
  /// before it's marked active. Throws if that isn't possible right now.
  Future<void> prepare(OnboardingModuleHost host) async {}

  /// Begin observing product data. Guidance may be empty until the first
  /// data arrives.
  void start(OnboardingModuleHost host);

  void stop();

  /// Ordered by priority: the guide layer shows the first entry that has
  /// at least one usable anchor on the current screen.
  List<OnboardingGuidance> get guidance;

  Map<String, Object?> debugDescribe() => const {};
}
