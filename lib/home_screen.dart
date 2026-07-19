import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'app_theme.dart';
import 'create_competition_screen.dart';
import 'pending_invites_screen.dart';
import 'services/firestore_service.dart';
import 'services/progress_snapshot_cache.dart';
import 'home_competitions_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  int _streak = 0;
  Future<String?>? _usernameFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _usernameFuture = _firestoreService.getMyUsername(uid);
    _updateStreak();
  }

  Future<void> _updateStreak() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final streak = await _firestoreService.checkAndUpdateStreak(user.uid);
    if (mounted) setState(() => _streak = streak);
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateCompetitionScreen(),
                    ),
                  );
                },
                child: const Text('Create Challenge'),
              ),
            ),
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
