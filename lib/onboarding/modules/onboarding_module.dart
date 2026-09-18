import 'package:flutter/foundation.dart';

import '../onboarding_repository.dart';
import '../onboarding_state.dart';

/// A button shown in the guide bubble itself, for steps that explain rather
/// than point at a control to press (e.g. "Next", "Not now").
@immutable
class OnboardingGuidanceAction {
  final String label;
  final VoidCallback onPressed;

  /// The step's main way forward (filled) rather than an opt-out (text).
  final bool primary;

  const OnboardingGuidanceAction({
    required this.label,
    required this.onPressed,
    this.primary = true,
  });
}

/// One piece of guidance: highlight every currently-usable anchor in
/// [anchorIds] and show [message] next to them, plus any bubble [actions].
@immutable
class OnboardingGuidance {
  final List<String> anchorIds;

  /// Empty shows the highlight ring with no bubble.
  final String message;
  final List<OnboardingGuidanceAction> actions;

  /// Modal guidance dims the screen and only lets the highlighted controls
  /// be pressed. Non-modal guidance only rings them and shows the bubble —
  /// the rest of the screen stays fully usable and is never auto-scrolled,
  /// for steps that point something out while the user works freely.
  final bool modal;

  /// Kept pressable through a modal scrim without being highlighted — for
  /// alternatives the step shouldn't block, only not point at.
  final List<String> passThroughAnchorIds;

  /// Held back until the user has touched the screen at least once while
  /// it could be shown, so a screen the user just opened isn't covered
  /// before they've had a look at it. Re-armed whenever it stops being
  /// showable (e.g. the user leaves the screen).
  final bool waitForUserTouch;

  const OnboardingGuidance({
    required this.anchorIds,
    required this.message,
    this.actions = const [],
    this.modal = true,
    this.passThroughAnchorIds = const [],
    this.waitForUserTouch = false,
  });

  /// Stable identity for "the same guidance", used by the guide layer to
  /// avoid re-running one-shot effects (like scrolling into view) and by
  /// modules to recognize which of their guidance was shown.
  String get signature =>
      '${anchorIds.join(',')}|$message|${actions.map((a) => a.label).join(',')}'
      '|$modal|${passThroughAnchorIds.join(',')}';
}

/// What the controller does with the screen the guide led the user onto
/// once a module completes.
enum OnboardingUnwind {
  /// Leave the navigation stack alone.
  none,

  /// Pop back to Home (the first route).
  toHome,

  /// Pop only the route the guide last highlighted something on, once it's
  /// the current route again and the app is in the foreground, letting the
  /// product flow underneath unwind itself the way it normally would.
  guidedRoute,
}

/// What the controller exposes to the module it is running.
abstract interface class OnboardingModuleHost {
  String get uid;
  OnboardingRepository get repository;

  /// [id]'s durable module data (see OnboardingTutorialState.moduleData).
  Map<String, Object?> moduleData(OnboardingModuleId id);

  /// Merges [data] into [id]'s durable module data and persists it.
  void saveModuleData(OnboardingModuleId id, Map<String, Object?> data);

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

  /// What to do with the screen the guide led the user onto once this
  /// module completes.
  OnboardingUnwind get unwindOnComplete => OnboardingUnwind.none;

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

  /// The guide layer is now showing [shown] (one of this module's
  /// [guidance] entries, matched by signature) on a settled screen. Called
  /// again whenever it's re-shown.
  void guidanceShown(OnboardingGuidance shown) {}

  Map<String, Object?> debugDescribe() => const {};
}
