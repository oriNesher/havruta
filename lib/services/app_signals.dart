import 'dart:async';

/// A notable moment in the product that leaves no Firestore trace of its
/// own, published so other parts of the app (e.g. onboarding) can react
/// without the screen that caused it knowing who is listening.
sealed class AppSignal {
  const AppSignal();
}

/// The native share sheet was presented for a Trash Talk card. Says nothing
/// about whether anything was actually sent — that isn't observable.
class TrashTalkShareSheetShown extends AppSignal {
  final String competitionId;
  final String? batchId;

  const TrashTalkShareSheetShown({
    required this.competitionId,
    required this.batchId,
  });
}

/// App-wide broadcast of [AppSignal]s. Emitting with no listeners is a
/// no-op, so product code can emit unconditionally.
class AppSignals {
  AppSignals._();
  static final AppSignals instance = AppSignals._();

  final _controller = StreamController<AppSignal>.broadcast();

  Stream<AppSignal> get stream => _controller.stream;

  void emit(AppSignal signal) => _controller.add(signal);
}
