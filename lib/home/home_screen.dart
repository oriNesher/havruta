import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../app_theme.dart';
import '../auth/account_screen.dart';
import '../auth/auth_service.dart' as auth_service;
import '../competitions/create_competition_screen.dart';
import '../invites/pending_invites_screen.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/progress_snapshot_cache.dart';
import '../services/respect_service.dart';
import '../services/respect_store.dart';
import '../tips/feature_tips_controller.dart';
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  Timer? _grantTicker;
  int _utcDay = DateTime.now().toUtc().day;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _usernameFuture = _firestoreService.getMyUsername(uid);
    _updateStreak();
    _grantDailyRespect();
    if (uid != null) _listenToRespect(uid);
    // Loads which first-time feature tips this user has already seen.
    if (uid != null) FeatureTipsController.instance.attachUser(uid);
  }

  /// Keeps RespectStore live for the whole session: the wallet chip, the
  /// Respect sheet, the Notifications header and every Give Respect button
  /// read it. Also claims the daily grant the moment the UTC day turns
  /// while Home is open (it normally lands on app open).
  void _listenToRespect(String uid) {
    _userDocSub = _firestoreService.getUserDoc(uid).listen((doc) {
      final data = doc.data();
      RespectStore.instance.updateServerBalance(
        (data?['respectBalance'] as num?)?.toInt() ?? 0,
        totalReceived: (data?['totalRespectReceived'] as num?)?.toInt() ?? 0,
      );
      // onError matters here: without it the permission-denied this
      // listener gets at sign-out reaches the zone as an uncaught
      // exception instead of failing quietly — see CelebrationGate.
    }, onError: (Object e) => debugPrint('Respect user doc error: $e'));
    _grantTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final day = DateTime.now().toUtc().day;
      if (day == _utcDay) return;
      _utcDay = day;
      _grantDailyRespect();
    });
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
    _userDocSub?.cancel();
    _grantTicker?.cancel();
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
    FeatureTipsController.instance.reset();
    await auth_service.signOut();
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
        title: Text(
          'Havruta',
          style: AppTheme.display(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
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
          const _RespectWalletChip(),
          _NotificationsBell(
            uid: user.uid,
            firestoreService: _firestoreService,
          ),
          // Debug builds only: makes every first-time feature tip show
          // again, for checking them by hand.
          if (kDebugMode)
            Container(
              height: 36,
              width: 36,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF181824),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFB69CFB), width: 1),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Reset tips (debug)',
                icon: const Icon(
                  Icons.lightbulb_outline,
                  size: 18,
                  color: Color(0xFFB69CFB),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await FeatureTipsController.instance.debugResetAll();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Tips reset')),
                  );
                },
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
              tooltip: 'Account',
              icon: PhosphorIcon(
                PhosphorIconsFill.userCircle,
                size: 18,
                color: const Color(0xFF8888A0),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AccountScreen(onSignOut: _signOut),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      // The header, then the Challenge carousel filling everything below
      // "My Competitions". On a normal phone nothing but the carousel
      // scrolls; only a screen too short for _minChallengesHeight scrolls
      // as a whole.
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            sliver: SliverToBoxAdapter(child: _header(user)),
          ),
          SliverLayoutBuilder(
            builder: (context, constraints) {
              const bottomGap = 16.0;
              // Floored: a fraction of a pixel over would make the whole
              // page draggable.
              final remaining = (constraints.viewportMainAxisExtent -
                      constraints.precedingScrollExtent -
                      bottomGap)
                  .floorToDouble();
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, bottomGap),
                sliver: SliverToBoxAdapter(
                  child: SizedBox(
                    height: math.max(remaining, _minChallengesHeight),
                    child: HomeCompetitionsSection(uid: user.uid),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Below this the card is squeezed, so a short screen scrolls instead.
  static const double _minChallengesHeight = 480;

  Widget _header(User user) {
    return Column(
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
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        const _WebPushPrompt(),
        _CreateChallengeButton(uid: user.uid),
        const SizedBox(height: 22),
        Text(
          'MY COMPETITIONS',
          style: AppTheme.display(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Respect wallet chip — the Respect to give, in the app bar beside the
// streak. Tapping it opens the Respect sheet: what used to be the Home
// Respect card (received total, wallet slots, countdown to the next +1).
// ─────────────────────────────────────────────

class _RespectWalletChip extends StatelessWidget {
  const _RespectWalletChip();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RespectStore.instance,
      builder: (context, _) {
        final wallet = RespectStore.instance.displayBalance;
        final color = wallet > 0 ? _respectTeal : _respectMuted;
        return Container(
          height: 36,
          margin: const EdgeInsets.only(right: 8),
          child: Material(
            color: color.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: color.withValues(alpha: 0.35)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => const _RespectSheet(),
              ),
              child: Semantics(
                button: true,
                label: '$wallet Respect to give',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhosphorIcon(
                        PhosphorIconsFill.pawPrint,
                        size: 14,
                        color: color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$wallet',
                        style: AppTheme.mono(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bottom sheet with the full Respect picture. Ticks once a second for the
/// countdown; the numbers come live from RespectStore.
class _RespectSheet extends StatefulWidget {
  const _RespectSheet();

  @override
  State<_RespectSheet> createState() => _RespectSheetState();
}

class _RespectSheetState extends State<_RespectSheet> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // Must match the server's UTC-day grant (functions/src/respect/).
  Duration _untilNextGrant() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day + 1).difference(now);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: ListenableBuilder(
          listenable: RespectStore.instance,
          builder: (context, _) {
            final store = RespectStore.instance;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Respect',
                  style: AppTheme.display(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  store.isWalletFull
                      ? "Your wallet's full — give some from a Challenge's "
                            "activity so tomorrow's +1 isn't lost."
                      : 'Give it from a Challenge\'s activity to cheer someone '
                            'on. You get +1 a day, up to '
                            '${RespectStore.walletCapacity}.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: _respectMuted),
                ),
                const SizedBox(height: 16),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFF181824),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _respectLine),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ReceivedPanel(
                            total: store.totalReceived,
                            remaining: store.isWalletFull
                                ? null
                                : _untilNextGrant(),
                          ),
                        ),
                        const VerticalDivider(
                          width: 1,
                          thickness: 1,
                          indent: 16,
                          endIndent: 16,
                          color: _respectLine,
                        ),
                        _WalletPanel(wallet: store.displayBalance),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Notifications bell, plus an Instagram-style popup under it when Respect
// arrives: a purple bubble with how much Respect came in since the
// Notifications screen was last opened. It pops once per new arrival and
// fades after a few seconds; a purple dot stays on the bell (when there's
// no invite count to show) until that screen is opened, which marks it all
// seen (users/{uid}.respectSeenAt).
// ─────────────────────────────────────────────

const _respectPopupColor = Color(0xFF8B5CF6);

class _NotificationsBell extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _NotificationsBell({required this.uid, required this.firestoreService});

  @override
  State<_NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<_NotificationsBell>
    with SingleTickerProviderStateMixin {
  /// The newest Respect already popped this session, so coming back to
  /// Home doesn't replay it. A fresh app start pops whatever's still unseen.
  static String? _lastPoppedId;

  static const _showFor = Duration(seconds: 4);

  /// getRespectNotifications' page size: an unseen count this high reads
  /// as "30+".
  static const _respectPage = 30;

  final _link = LayerLink();
  final _portal = OverlayPortalController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _invites;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _respectSub;
  Timer? _hideTimer;

  Timestamp? _seenAt;
  bool _baselineRequested = false;
  bool _isCurrent = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _respect = const [];

  @override
  void initState() {
    super.initState();
    final service = widget.firestoreService;
    _invites = service.getPendingInvites(widget.uid);
    _userSub = service.getUserDoc(widget.uid).listen((doc) {
      if (!doc.exists) return;
      final seenAt = doc.data()?['respectSeenAt'] as Timestamp?;
      if (seenAt == null && !_baselineRequested) {
        // No marker yet (new account, or first run of this build): start
        // counting from now instead of popping every Respect ever received.
        _baselineRequested = true;
        service.markRespectSeen(widget.uid).catchError(
          (Object e) => debugPrint('Respect seen baseline failed: $e'),
        );
      }
      _seenAt = seenAt;
      _changed();
    }, onError: (Object e) => debugPrint('Bell user doc error: $e'));
    _respectSub = service.getRespectNotifications(widget.uid).listen((snap) {
      _respect = snap.docs;
      _changed();
    }, onError: (Object e) => debugPrint('Bell Respect stream error: $e'));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depending on the route means this re-runs when Home is back on top,
    // so Respect that arrived on another screen pops on the way back.
    _isCurrent = ModalRoute.isCurrentOf(context) ?? true;
    if (!_isCurrent) _hide();
    _maybePop();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _respectSub?.cancel();
    _hideTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  /// Respect newer than the seen marker, newest first. Nothing while the
  /// marker is unknown or mid-write (a pending server timestamp reads null).
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _unseen {
    final seenAt = _seenAt;
    if (seenAt == null) return const [];
    return _respect.where((doc) {
      final createdAt = doc.data()['createdAt'] as Timestamp?;
      return createdAt != null && createdAt.compareTo(seenAt) > 0;
    }).toList();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _maybePop();
  }

  void _maybePop() {
    final unseen = _unseen;
    if (unseen.isEmpty) {
      _hide();
      return;
    }
    final newest = unseen.first.id;
    if (newest == _lastPoppedId || !_isCurrent) return;
    _lastPoppedId = newest;
    _portal.show();
    // A second arrival while it's up re-pops it from part-way.
    _anim.forward(from: _anim.value > 0.6 ? 0.6 : _anim.value);
    _hideTimer?.cancel();
    _hideTimer = Timer(_showFor, _hide);
  }

  void _hide() {
    _hideTimer?.cancel();
    if (!_portal.isShowing) return;
    _anim.reverse().whenComplete(() {
      if (mounted && _anim.isDismissed) _portal.hide();
    });
  }

  void _open() {
    _hide();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PendingInvitesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unseen = _unseen.length;

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Align(
        alignment: Alignment.topLeft,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, 4),
          child: _RespectPopup(
            animation: _anim,
            count: unseen,
            capped: unseen >= _respectPage,
            onTap: _open,
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _invites,
          builder: (context, snapshot) {
            final invites = snapshot.data?.docs.length ?? 0;
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
                // The invite count wins the badge; unseen Respect alone
                // shows as a purple dot.
                icon: Badge(
                  isLabelVisible: invites > 0 || unseen > 0,
                  backgroundColor: invites > 0 ? null : _respectPopupColor,
                  label: invites > 0 ? Text('$invites') : null,
                  child: PhosphorIcon(
                    PhosphorIconsFill.bell,
                    size: 18,
                    color: const Color(0xFF8888A0),
                  ),
                ),
                onPressed: _open,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The bubble under the bell: a caret pointing up at it, then a paw and
/// the count. Pops from the caret and fades back into it.
class _RespectPopup extends StatelessWidget {
  final Animation<double> animation;
  final int count;
  final bool capped;
  final VoidCallback onTap;

  const _RespectPopup({
    required this.animation,
    required this.count,
    required this.capped,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = capped ? '$count+' : '$count';

    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: const Interval(0, 0.5))),
      child: ScaleTransition(
        alignment: Alignment.topCenter,
        scale: animation.drive(CurveTween(curve: Curves.easeOutBack)),
        // The overlay has no Material of its own; without one the text
        // picks up the debug "missing Material" underline.
        child: Material(
          type: MaterialType.transparency,
          child: Semantics(
            liveRegion: true,
            button: true,
            label: '$label new Respect',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CustomPaint(
                    size: Size(12, 6),
                    painter: _CaretPainter(_respectPopupColor),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _respectPopupColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PhosphorIcon(
                          PhosphorIconsFill.pawPrint,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: AppTheme.mono(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  final Color color;
  const _CaretPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CaretPainter oldDelegate) =>
      oldDelegate.color != color;
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
  State<_CreateChallengeButton> createState() => _CreateChallengeButtonState();
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
// The Respect sheet's panels (the former Home Respect card). Left: Respect
// received on one line, plus — only while the wallet has room — a
// countdown to the next server (UTC) day, when the daily grant unlocks.
// Right: the wallet of Respect to give (RespectStore.walletCapacity slots).
// ─────────────────────────────────────────────

const _respectPurple = Color(0xFFB69CFB);
const _respectTeal = Color(0xFF2DD4BF);
const _respectMuted = Color(0xFF8888A0);
const _respectLine = Color(0xFF2A2A42);

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

  /// Time until the next daily grant, or null while the wallet is full.
  final Duration? remaining;

  const _ReceivedPanel({required this.total, required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$total',
                    style:
                        AppTheme.mono(
                          fontSize: 34,
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
              const SizedBox(width: 6),
              PhosphorIcon(
                PhosphorIconsFill.pawPrint,
                size: 18,
                color: _respectPurple,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'received',
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.display(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: _respectMuted,
                  ),
                ),
              ),
            ],
          ),
          if (remaining != null) ...[
            const SizedBox(height: 10),
            _NextRespectBar(remaining: remaining!),
          ],
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
        mainAxisSize: MainAxisSize.min,
        children: [
          const _RespectLabel('TO GIVE'),
          const SizedBox(height: 10),
          // Fixed-size slots in plain rows: the panel sizes itself to the
          // slots instead of stretching them across half the card.
          for (var row = 0; row * 3 < RespectStore.walletCapacity; row++) ...[
            if (row > 0) const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var col = 0; col < 3; col++) ...[
                  if (col > 0) const SizedBox(width: 6),
                  _WalletSlot(filled: row * 3 + col < wallet),
                ],
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '$wallet/${RespectStore.walletCapacity}',
            style: AppTheme.mono(
              fontSize: 13,
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
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: filled
            ? _respectTeal.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
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
          size: 13,
          color: filled ? _respectTeal : _respectLine,
        ),
      ),
    );
  }
}

/// Countdown to the next daily grant, drawn as a bar whose teal fill grows
/// from the left as the day runs out — full right before the grant lands.
class _NextRespectBar extends StatelessWidget {
  final Duration remaining;
  const _NextRespectBar({required this.remaining});

  String _format(Duration d) {
    final hh = d.inHours.toString().padLeft(2, '0');
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = (1 - remaining.inSeconds / Duration.secondsPerDay).clamp(
      0.0,
      1.0,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: elapsed,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _respectTeal.withValues(alpha: 0.22),
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _respectTeal.withValues(alpha: 0.35)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _format(remaining),
                      style: AppTheme.mono(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '+1',
                  style: AppTheme.mono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _respectTeal,
                  ),
                ),
                const SizedBox(width: 3),
                PhosphorIcon(
                  PhosphorIconsFill.pawPrint,
                  size: 13,
                  color: _respectTeal,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Web only: offer browser notifications (announcements from organizers),
// here rather than at sign-in, and only while the browser hasn't been
// asked yet. Renders nothing on Android/iOS or until a VAPID key exists.
// ─────────────────────────────────────────────

class _WebPushPrompt extends StatefulWidget {
  const _WebPushPrompt();

  @override
  State<_WebPushPrompt> createState() => _WebPushPromptState();
}

class _WebPushPromptState extends State<_WebPushPrompt> {
  // Dismissed for the rest of this session (the browser itself remembers
  // the real answer once given).
  static bool _dismissed = false;

  final NotificationService _notifications = NotificationService();
  bool _offer = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_dismissed) return;
    _notifications.shouldOfferWebPush().then((offer) {
      if (mounted) setState(() => _offer = offer);
    });
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    final on = await _notifications.enableWebPush().catchError((Object e) {
      debugPrint('Enabling web push failed: $e');
      return false;
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _offer = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(on
          ? "Notifications on — you'll get announcements here."
          : 'Notifications stay off. You can allow them in your browser '
              'settings any time.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!_offer || _dismissed) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Icon(Icons.notifications_active_outlined,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Get notified',
                        style: AppTheme.display(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(
                      'Announcements from your organizers and Challenge '
                      'news, even when this tab is closed.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _enable,
                child: const Text('Turn on'),
              ),
              IconButton(
                tooltip: 'Not now',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
