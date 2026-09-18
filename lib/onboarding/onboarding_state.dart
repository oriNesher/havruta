import 'package:flutter/foundation.dart';

/// The user's answer to the Welcome prompt. Absent (null) until they answer.
enum OnboardingWelcomeChoice {
  /// "Yes, show me" — the guided narrative runs module by module.
  accepted,

  /// "Skip" — the guided narrative doesn't run, but nothing is dismissed:
  /// every module stays available to start individually later, from the
  /// Home onboarding checklist.
  deferred,
}

/// Where the initial guided narrative (the one "Yes, show me" starts) is.
/// Absent (null) while it hasn't finished — including for users who skipped
/// it. Deliberately separate from module statuses: finishing the narrative
/// never suppresses modules added or updated later.
enum OnboardingNarrativeStatus {
  /// Every narrative module was genuinely completed as part of the guided
  /// narrative; the final "You're ready." message is still owed.
  completed,

  /// The user tapped "Let's go" on that message. Terminal.
  acknowledged,
}

/// Every onboarding module. The guided order lives in
/// OnboardingController.narrative; per-module metadata (version, checklist
/// copy, eligibility) lives in OnboardingModuleRegistry.
enum OnboardingModuleId {
  acceptInvites,
  reportProgress,
  celebrationTrashTalk,
  eventsRespect,
  createChallenge,
  invitePeople,
}

enum OnboardingModuleStatus {
  notStarted,
  active,

  /// "Not now": left before finishing. Stays available in the checklist.
  deferred,
  completed,

  /// "I don't want to see this": hidden from the checklist, and never
  /// started automatically again, for the version it was dismissed at.
  dismissed,
}

/// One module's persisted lifecycle, versioned.
///
/// [status] is the latest transition, recorded against module [version].
/// [completedVersion]/[dismissedVersion] are the highest versions ever
/// completed/dismissed — history that a later version never erases, so a
/// module completed at v1 resurfaces for v2 without losing that v1 record.
@immutable
class OnboardingModuleProgress {
  /// The version every module implicitly had before versioning existed —
  /// what un-versioned (pre-Part 6) records are read as.
  static const legacyVersion = 1;

  final OnboardingModuleStatus status;
  final int version;
  final int? completedVersion;
  final int? dismissedVersion;

  const OnboardingModuleProgress({
    this.status = OnboardingModuleStatus.notStarted,
    this.version = 0,
    this.completedVersion,
    this.dismissedVersion,
  });

  static const none = OnboardingModuleProgress();

  bool get isEmpty => this == none;

  /// Completed at some version — how prerequisites and the initial
  /// narrative count a module as done, so a new version of an earlier
  /// module can't lock later ones or rewind the narrative.
  bool get everCompleted => completedVersion != null;

  /// The status as it applies to the module's [currentVersion]: a
  /// completion/dismissal of an older version (or an old run left active or
  /// deferred) reads as not started, which is how a new version resurfaces.
  /// [dismissAllVersions] makes a dismissal of any version stick.
  OnboardingModuleStatus effectiveStatus(
    int currentVersion, {
    bool dismissAllVersions = false,
  }) {
    final completed = completedVersion;
    final dismissed = dismissedVersion;
    if (completed != null && completed >= currentVersion) {
      return OnboardingModuleStatus.completed;
    }
    if (dismissed != null &&
        (dismissAllVersions || dismissed >= currentVersion)) {
      return OnboardingModuleStatus.dismissed;
    }
    if (version < currentVersion ||
        status == OnboardingModuleStatus.completed ||
        status == OnboardingModuleStatus.dismissed) {
      return OnboardingModuleStatus.notStarted;
    }
    return status;
  }

  /// Records [next] against [atVersion], keeping the history fields.
  OnboardingModuleProgress transition(
    OnboardingModuleStatus next,
    int atVersion,
  ) {
    int? raise(int? current) =>
        current == null || current < atVersion ? atVersion : current;
    return OnboardingModuleProgress(
      status: next,
      version: atVersion,
      completedVersion: next == OnboardingModuleStatus.completed
          ? raise(completedVersion)
          : completedVersion,
      dismissedVersion: next == OnboardingModuleStatus.dismissed
          ? raise(dismissedVersion)
          : dismissedVersion,
    );
  }

  /// Unknown statuses (e.g. written by a newer app version) yield null.
  /// Pre-versioning records carry only `status`: they're read as
  /// [legacyVersion], and a legacy `completed` as completed at that version.
  static OnboardingModuleProgress? fromMap(Map<dynamic, dynamic> map) {
    final status = _byName(OnboardingModuleStatus.values, map['status']);
    if (status == null) return null;
    final version = (map['version'] as num?)?.toInt() ?? legacyVersion;
    var completed = (map['completedVersion'] as num?)?.toInt();
    var dismissed = (map['dismissedVersion'] as num?)?.toInt();
    if (status == OnboardingModuleStatus.completed) completed ??= version;
    if (status == OnboardingModuleStatus.dismissed) dismissed ??= version;
    return OnboardingModuleProgress(
      status: status,
      version: version,
      completedVersion: completed,
      dismissedVersion: dismissed,
    );
  }

  /// Every field is always written (nulls included) so a merged save can
  /// also clear a history field, e.g. when a module is reset.
  Map<String, Object?> toMap() => {
    'status': status.name,
    'version': version,
    'completedVersion': completedVersion,
    'dismissedVersion': dismissedVersion,
  };

  @override
  bool operator ==(Object other) =>
      other is OnboardingModuleProgress &&
      other.status == status &&
      other.version == version &&
      other.completedVersion == completedVersion &&
      other.dismissedVersion == dismissedVersion;

  @override
  int get hashCode =>
      Object.hash(status, version, completedVersion, dismissedVersion);

  @override
  String toString() => toMap().toString();
}

/// The user's persisted tutorial progress, stored as the
/// `users/{uid}.onboardingTutorial` map.
///
/// This is cosmetic, client-written state (like the streak): it only
/// decides which tutorial guidance to show. The real onboarding challenges
/// and invites are server-created (startOnboarding), and what a module
/// considers "done" is always re-derived from those real records.
@immutable
class OnboardingTutorialState {
  static const firestoreField = 'onboardingTutorial';

  /// 2: per-module versions/history, deferred/dismissed, `narrative`.
  /// Version 1 records parse unchanged (see OnboardingModuleProgress).
  static const schemaVersion = 2;

  final OnboardingWelcomeChoice? welcome;

  /// The initial narrative's own completion — never a global "onboarding
  /// done" flag; modules keep their own state regardless.
  final OnboardingNarrativeStatus? narrative;

  /// The module currently being guided, if any. Null between modules and
  /// when nothing is running.
  final OnboardingModuleId? activeModule;

  final Map<OnboardingModuleId, OnboardingModuleProgress> modules;

  /// Small, module-owned durable facts (e.g. which real Challenge a module
  /// is tracking), stored as `modules.<id>.data`. Only modules that need to
  /// survive a relaunch mid-step keep anything here.
  final Map<OnboardingModuleId, Map<String, Object?>> moduleData;

  const OnboardingTutorialState({
    this.welcome,
    this.narrative,
    this.activeModule,
    this.modules = const {},
    this.moduleData = const {},
  });

  static const empty = OnboardingTutorialState();

  OnboardingModuleProgress progressOf(OnboardingModuleId id) =>
      modules[id] ?? OnboardingModuleProgress.none;

  Map<String, Object?> dataOf(OnboardingModuleId id) =>
      moduleData[id] ?? const {};

  OnboardingTutorialState copyWith({
    OnboardingWelcomeChoice? welcome,
    OnboardingNarrativeStatus? narrative,
    bool clearNarrative = false,
    OnboardingModuleId? activeModule,
    bool clearActiveModule = false,
  }) {
    return OnboardingTutorialState(
      welcome: welcome ?? this.welcome,
      narrative: clearNarrative ? null : (narrative ?? this.narrative),
      activeModule: clearActiveModule
          ? null
          : (activeModule ?? this.activeModule),
      modules: modules,
      moduleData: moduleData,
    );
  }

  OnboardingTutorialState withModuleProgress(
    OnboardingModuleId id,
    OnboardingModuleProgress progress,
  ) {
    return OnboardingTutorialState(
      welcome: welcome,
      narrative: narrative,
      activeModule: activeModule,
      modules: {...modules, id: progress},
      moduleData: moduleData,
    );
  }

  /// Records [status] for [id] at module version [version].
  OnboardingTutorialState withModuleStatus(
    OnboardingModuleId id,
    OnboardingModuleStatus status, {
    required int version,
  }) => withModuleProgress(id, progressOf(id).transition(status, version));

  /// Merges [data] into [id]'s module data. Add-only by design: saves
  /// merge, so a key can't be removed this way (see [withoutModuleData]).
  OnboardingTutorialState withModuleData(
    OnboardingModuleId id,
    Map<String, Object?> data,
  ) {
    final merged = {...dataOf(id), ...data};
    return OnboardingTutorialState(
      welcome: welcome,
      narrative: narrative,
      activeModule: activeModule,
      modules: modules,
      moduleData: {...moduleData, id: merged},
    );
  }

  OnboardingTutorialState withoutModuleData(Iterable<OnboardingModuleId> ids) {
    return OnboardingTutorialState(
      welcome: welcome,
      narrative: narrative,
      activeModule: activeModule,
      modules: modules,
      moduleData: {...moduleData}..removeWhere((id, _) => ids.contains(id)),
    );
  }

  /// Unknown values (e.g. a module id or status written by a newer app
  /// version) are dropped here rather than failing; since saves merge, they
  /// also survive untouched in Firestore.
  factory OnboardingTutorialState.fromMap(Map<String, dynamic>? map) {
    if (map == null) return empty;

    final modules = <OnboardingModuleId, OnboardingModuleProgress>{};
    final moduleData = <OnboardingModuleId, Map<String, Object?>>{};
    final rawModules = map['modules'];
    if (rawModules is Map) {
      for (final entry in rawModules.entries) {
        final id = _byName(OnboardingModuleId.values, entry.key);
        final raw = entry.value;
        if (id == null || raw is! Map) continue;
        final progress = OnboardingModuleProgress.fromMap(raw);
        if (progress != null) modules[id] = progress;
        final rawData = raw['data'];
        if (rawData is Map && rawData.isNotEmpty) {
          moduleData[id] = Map<String, Object?>.from(rawData);
        }
      }
    }

    return OnboardingTutorialState(
      welcome: _byName(OnboardingWelcomeChoice.values, map['welcome']),
      narrative: _byName(OnboardingNarrativeStatus.values, map['narrative']),
      activeModule: _byName(OnboardingModuleId.values, map['activeModule']),
      modules: modules,
      moduleData: moduleData,
    );
  }

  /// Saved with a merge, so module data keys absent here are left as they
  /// are in Firestore (removing them takes an explicit delete — see
  /// OnboardingRepository.clearModuleData).
  Map<String, Object?> toMap() => {
    'welcome': welcome?.name,
    'narrative': narrative?.name,
    'activeModule': activeModule?.name,
    'modules': {
      for (final id in {...modules.keys, ...moduleData.keys})
        id.name: {
          if (modules[id] != null) ...modules[id]!.toMap(),
          if (moduleData[id] != null) 'data': moduleData[id],
        },
    },
  };

  @override
  String toString() => toMap().toString();
}

T? _byName<T extends Enum>(List<T> values, Object? raw) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}
