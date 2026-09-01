import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../app_theme.dart';
import '../competitions/create_competition_screen.dart';
import '../invites/pending_invites_screen.dart';
import '../services/firestore_service.dart';
import '../services/progress_snapshot_cache.dart';
import '../services/respect_service.dart';
import '../services/respect_store.dart';
import 'home_competitions_section.dart';

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
              return Container(
                height: 36,
                width: 36,
                margin: const EdgeInsets.only(right: 6),
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
              );
            },
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
      body: SingleChildScrollView(
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
            _CreateChallengeButton(uid: user.uid),
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
      setState(() {
        _hasLoaded = true;
        _createdAt = (data?['createdAt'] as Timestamp?)?.toDate();
        _lastCompetitionCreatedAt =
            (data?['lastCompetitionCreatedAt'] as Timestamp?)?.toDate();
      });
    });
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
// Respect summary — plain typography, no card/border/icon: total Respect
// received (prominent), how much is left to give today, and a countdown to
// the next local midnight (when a new day's grant becomes available on next
// app open). Balance is fed into RespectStore so every Give Respect button
// on the page shares the same live number.
// ─────────────────────────────────────────────

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
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _userDocSub.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  String _formatCountdown(Duration d) {
    final hh = d.inHours.toString().padLeft(2, '0');
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final remaining = nextMidnight.difference(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_totalReceived',
          style: AppTheme.mono(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Text('Respect received', style: textTheme.labelSmall),
        const SizedBox(height: 10),
        ListenableBuilder(
          listenable: RespectStore.instance,
          builder: (context, _) => Text(
            'You have ${RespectStore.instance.displayBalance} Respect to give',
            style: textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Next Respect in ${_formatCountdown(remaining)}',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}
