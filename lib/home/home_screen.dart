import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../app_theme.dart';
// TEMPORARY — remove with the debug entry point below once the onboarding
// flow is fully verified.
import '../debug/onboarding_debug_screen.dart';
import '../competitions/create_competition_screen.dart';
import '../invites/pending_invites_screen.dart';
import '../onboarding/onboarding_anchor.dart';
import '../onboarding/onboarding_controller.dart';
import '../onboarding/onboarding_ids.dart';
import '../services/firestore_service.dart';
import '../services/progress_snapshot_cache.dart';
import '../services/respect_service.dart';
import '../services/respect_store.dart';
import 'home_competitions_section.dart';
import 'home_onboarding_checklist.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  final RespectService _respectService = RespectService();
  int _streak = 0;
  Future<String?>? _usernameFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _usernameFuture = _firestoreService.getMyUsername(uid);
    _updateStreak();
    _grantDailyRespect();
    // Entering the real Home experience is what onboarding hangs off; the
    // controller decides from persisted state whether anything happens.
    if (uid != null) OnboardingController.instance.attachUser(uid);
  }

  Future<void> _updateStreak() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final streak = await _firestoreService.checkAndUpdateStreak(user.uid);
    if (mounted) setState(() => _streak = streak);
  }

  // Fire-and-forget, same "did they open the app today" trigger point as
  // _updateStreak — grantDailyRespect itself is idempotent per server day.
  Future<void> _grantDailyRespect() async {
    try {
      final balance = await _respectService.grantDailyRespect();
      RespectStore.instance.updateServerBalance(balance);
    } catch (e) {
      debugPrint('Daily Respect grant error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ProgressSnapshotCache.instance.persist(_firestoreService);
    }
  }

  Future<void> _signOut() async {
    await ProgressSnapshotCache.instance.persistAndClear(_firestoreService);
    RespectStore.instance.reset();
    OnboardingController.instance.reset();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('No logged in user')));
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.75),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'Havruta',
              style: AppTheme.display(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          if (_streak > 0)
            Container(
              height: 36,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFFF5C7A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFFF5C7A).withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(
                    PhosphorIconsFill.flame,
                    size: 14,
                    color: const Color(0xFFFF5C7A),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_streak',
                    style: AppTheme.mono(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFF5C7A),
                    ),
                  ),
                ],
              ),
            ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestoreService.getPendingInvites(user.uid),
            builder: (context, snapshot) {
              final count = snapshot.data?.docs.length ?? 0;
              // The margin stays outside the anchor so onboarding
              // highlights the button itself, not its spacing.
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: OnboardingAnchor(
                  id: OnboardingAnchorIds.homeNotificationsButton,
                  child: Container(
                    height: 36,
                    width: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF181824),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2A2A42), width: 1),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: Badge(
                        isLabelVisible: count > 0,
                        label: Text('$count'),
                        child: PhosphorIcon(
                          PhosphorIconsFill.bell,
                          size: 18,
                          color: const Color(0xFF8888A0),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PendingInvitesScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          // TEMPORARY (debug builds only): entry point for the onboarding
          // test harness (backend + tutorial session). Delete this block
          // together with lib/debug/onboarding_debug_screen.dart once the
          // whole onboarding flow is signed off.
          if (kDebugMode)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: OnboardingAnchor(
                id: OnboardingAnchorIds.debugHarnessButton,
                child: Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF181824),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFB69CFB), width: 1),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: const Icon(
                      Icons.bug_report_outlined,
                      size: 18,
                      color: Color(0xFFB69CFB),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OnboardingDebugScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          Container(
            height: 36,
            width: 36,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF181824),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A42), width: 1),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: PhosphorIcon(
                PhosphorIconsFill.signOut,
                size: 18,
                color: const Color(0xFF8888A0),
              ),
              onPressed: _signOut,
            ),
          ),
        ],
      ),
      // Marks "the real Home experience is on screen and settled" for
      // onboarding (the Welcome prompt waits for it); never highlighted.
      body: OnboardingAnchor(
        id: OnboardingAnchorIds.homeScreen,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<String?>(
                future: _usernameFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text(
                      'Hello...',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                    );
                  }
                  final username = snapshot.data;
                  return Text(
                    'Hello ${username ?? user.email ?? ""}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                  );
                },
              ),
              const SizedBox(height: 10),
              _RespectSummary(uid: user.uid, firestoreService: _firestoreService),
              const SizedBox(height: 20),
              OnboardingAnchor(
                id: OnboardingAnchorIds.homeCreateChallengeButton,
                child: _CreateChallengeButton(uid: user.uid),
              ),
              const HomeOnboardingChecklist(),
              const SizedBox(height: 24),
              Text(
                'MY COMPETITIONS',
                style: AppTheme.display(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.0),
              ),
              const SizedBox(height: 12),
              HomeCompetitionsSection(uid: user.uid),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Create-challenge button with scarcity cooldown:
// 3 minutes after account creation before the first challenge, then 3 days
// after each creation before the next one is allowed. Client-side gating
// only — mirrors the rest of this screen's validation, no server enforcement.
// ─────────────────────────────────────────────

class _CreateChallengeButton extends StatefulWidget {
  final String uid;
  const _CreateChallengeButton({required this.uid});

  @override
  State<_CreateChallengeButton> createState() =>
      _CreateChallengeButtonState();
}

class _CreateChallengeButtonState extends State<_CreateChallengeButton> {
  // TEMP: cooldown disabled — flip back to true to re-enable the scarcity gating.
  static const _cooldownEnabled = false;
  static const _firstWait = Duration(minutes: 3);
  static const _cooldown = Duration(days: 3);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  Timer? _ticker;
  bool _hasLoaded = false;
  DateTime? _createdAt;
  DateTime? _lastCompetitionCreatedAt;

  @override
  void initState() {
    super.initState();
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      if (!mounted) return;
      setState(() {
        _hasLoaded = true;
        _createdAt = (data?['createdAt'] as Timestamp?)?.toDate();
        _lastCompetitionCreatedAt =
            (data?['lastCompetitionCreatedAt'] as Timestamp?)?.toDate();
      });
    }, onError: (Object e) => debugPrint('User doc stream error: $e'));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  DateTime? get _eligibleAt {
    if (!_cooldownEnabled) return null;
    if (_lastCompetitionCreatedAt != null) {
      return _lastCompetitionCreatedAt!.add(_cooldown);
    }
    if (_createdAt != null) return _createdAt!.add(_firstWait);
    return null;
  }

  String _formatRemaining(Duration d) {
    if (d.inDays > 0) {
      final hours = d.inHours % 24;
      final minutes = d.inMinutes % 60;
      final seconds = d.inSeconds % 60;
      final hh = hours.toString().padLeft(2, '0');
      final mm = minutes.toString().padLeft(2, '0');
      final ss = seconds.toString().padLeft(2, '0');
      return '${d.inDays}d $hh:$mm:$ss';
    }
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final eligibleAt = _eligibleAt;
    final remaining = eligibleAt == null
        ? Duration.zero
        : eligibleAt.difference(DateTime.now());
    final isWaiting = !_hasLoaded || remaining > Duration.zero;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isWaiting
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateCompetitionScreen(),
                  ),
                );
              },
        child: remaining > Duration.zero
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Create Challenge'),
                  const SizedBox(height: 2),
                  Text(
                    _formatRemaining(remaining),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : const Text('Create Challenge'),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Respect card: Respect received (left), the wallet of Respect to give
// (right, RespectStore.walletCapacity slots), and — only while the wallet
// has room — a countdown to the next server (UTC) day, when the daily grant
// unlocks. Balance is fed into RespectStore so every Give Respect button on
// the page shares the same live number.
// ─────────────────────────────────────────────

const _respectPurple = Color(0xFFB69CFB);
const _respectTeal = Color(0xFF2DD4BF);
const _respectMuted = Color(0xFF8888A0);
const _respectLine = Color(0xFF2A2A42);

class _RespectSummary extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _RespectSummary({required this.uid, required this.firestoreService});

  @override
  State<_RespectSummary> createState() => _RespectSummaryState();
}

class _RespectSummaryState extends State<_RespectSummary> {
  late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
  _userDocSub;
  Timer? _ticker;
  int _totalReceived = 0;
  late int _utcDay = DateTime.now().toUtc().day;

  @override
  void initState() {
    super.initState();
    _userDocSub = widget.firestoreService.getUserDoc(widget.uid).listen((
      doc,
    ) {
      final data = doc.data();
      final balance = (data?['respectBalance'] as num?)?.toInt() ?? 0;
      RespectStore.instance.updateServerBalance(balance);
      final received = (data?['totalRespectReceived'] as num?)?.toInt() ?? 0;
      if (mounted) setState(() => _totalReceived = received);
      // onError matters here: without it the permission-denied this
      // listener gets at sign-out reaches the zone as an uncaught
      // exception instead of failing quietly — see CelebrationGate.
    }, onError: (Object e) => debugPrint('Respect summary stream error: $e'));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final day = DateTime.now().toUtc().day;
      // The grant normally fires on app open; claim it here too so a
      // countdown reaching zero while Home is open actually delivers.
      if (day != _utcDay) {
        _utcDay = day;
        RespectService().grantDailyRespect().then(
          RespectStore.instance.updateServerBalance,
          onError: (e) => debugPrint('Daily Respect grant error: $e'),
        );
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _userDocSub.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RespectStore.instance,
      builder: (context, _) {
        final wallet = RespectStore.instance.displayBalance;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF181824),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _respectLine),
          ),
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _ReceivedPanel(total: _totalReceived)),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: _respectLine,
                    ),
                    Expanded(child: _WalletPanel(wallet: wallet)),
                  ],
                ),
              ),
              if (!RespectStore.instance.isWalletFull) const _NextRespectRow(),
            ],
          ),
        );
      },
    );
  }
}

class _RespectLabel extends StatelessWidget {
  final String text;
  const _RespectLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTheme.display(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: _respectMuted,
    ),
  );
}

class _ReceivedPanel extends StatelessWidget {
  final int total;
  const _ReceivedPanel({required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RespectLabel('RECEIVED'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$total',
                    style: AppTheme.mono(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      color: _respectPurple,
                    ).copyWith(
                      shadows: [
                        Shadow(
                          color: _respectPurple.withValues(alpha: 0.5),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PhosphorIcon(
                PhosphorIconsFill.pawPrint,
                size: 22,
                color: _respectPurple,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletPanel extends StatelessWidget {
  final int wallet;
  const _WalletPanel({required this.wallet});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RespectLabel('TO GIVE'),
          const SizedBox(height: 10),
          // Plain rows, not a GridView: the card's IntrinsicHeight needs
          // intrinsic sizes, which scrollable viewports can't report.
          for (var row = 0; row * 3 < RespectStore.walletCapacity; row++) ...[
            if (row > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (var col = 0; col < 3; col++) ...[
                  if (col > 0) const SizedBox(width: 8),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: row * 3 + col < RespectStore.walletCapacity
                          ? _WalletSlot(filled: row * 3 + col < wallet)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '$wallet/${RespectStore.walletCapacity}',
            style: AppTheme.mono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: wallet > 0 ? _respectTeal : _respectMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletSlot extends StatelessWidget {
  final bool filled;
  const _WalletSlot({required this.filled});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: filled
            ? _respectTeal.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: filled ? _respectTeal.withValues(alpha: 0.45) : _respectLine,
        ),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: _respectTeal.withValues(alpha: 0.18),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Center(
        child: PhosphorIcon(
          PhosphorIconsFill.pawPrint,
          size: 16,
          color: filled ? _respectTeal : _respectLine,
        ),
      ),
    );
  }
}

class _NextRespectRow extends StatelessWidget {
  const _NextRespectRow();

  String _format(Duration d) {
    final hh = d.inHours.toString().padLeft(2, '0');
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    // Must match the server's UTC-day grant (functions/src/respect/).
    final now = DateTime.now().toUtc();
    final remaining = DateTime.utc(
      now.year,
      now.month,
      now.day + 1,
    ).difference(now);
    final dayElapsed = 1 - remaining.inSeconds / Duration.secondsPerDay;

    return Container(
      decoration: BoxDecoration(
        color: _respectPurple.withValues(alpha: 0.05),
        border: const Border(top: BorderSide(color: _respectLine)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 20, 14),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: dayElapsed,
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    backgroundColor: _respectLine,
                    color: const Color(0xFF8B5CF6),
                  ),
                ),
                PhosphorIcon(
                  PhosphorIconsFill.pawPrint,
                  size: 18,
                  color: _respectPurple,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _format(remaining),
              style: AppTheme.mono(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          Text(
            '+1',
            style: AppTheme.mono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _respectMuted,
            ),
          ),
          const SizedBox(width: 4),
          PhosphorIcon(
            PhosphorIconsFill.pawPrint,
            size: 16,
            color: _respectMuted,
          ),
        ],
      ),
    );
  }
}
