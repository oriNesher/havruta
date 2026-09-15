// TEMPORARY — onboarding Part 1 test harness.
//
// This screen exists only to exercise and inspect the system-managed
// onboarding backend (functions/src/onboarding/) from a real device in
// debug. It is not part of the product: there is no tutorial UI yet, and
// this whole file (plus its entry point in home_screen.dart, which is
// wrapped in `if (kDebugMode)`) should be deleted once Part 1 is signed
// off and the real onboarding UI lands.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../app_theme.dart';

const String kSystemUserUid = 'havruta_system';

/// One line of test output, with a pass/fail/info state.
class _Line {
  final String text;
  final _LineKind kind;
  _Line(this.text, this.kind);
}

enum _LineKind { pass, fail, info, header }

class OnboardingDebugScreen extends StatefulWidget {
  const OnboardingDebugScreen({super.key});

  @override
  State<OnboardingDebugScreen> createState() => _OnboardingDebugScreenState();
}

class _OnboardingDebugScreenState extends State<OnboardingDebugScreen> {
  final _db = FirebaseFirestore.instance;
  final List<_Line> _lines = [];
  bool _busy = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  String _compId(String key) => 'onboarding_${_uid}_$key';
  String _inviteId(String key) => 'onboarding_invite_${_uid}_$key';

  void _log(String text, [_LineKind kind = _LineKind.info]) {
    setState(() => _lines.add(_Line(text, kind)));
  }

  void _pass(String text) => _log(text, _LineKind.pass);
  void _fail(String text) => _log(text, _LineKind.fail);
  void _header(String text) => _log(text, _LineKind.header);

  void _check(bool condition, String label, [String? detail]) {
    if (condition) {
      _pass(label);
    } else {
      _fail('$label${detail != null ? ' — $detail' : ''}');
    }
  }

  Future<void> _guard(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } catch (e) {
      _fail('UNEXPECTED ERROR: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Test 1: call startOnboarding ──────────────────────────────────────

  Future<Map<String, dynamic>?> _callStartOnboarding() async {
    final sw = Stopwatch()..start();
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('startOnboarding');
      final result = await callable.call<Map<dynamic, dynamic>>();
      sw.stop();
      final data = Map<String, dynamic>.from(result.data);
      _pass('startOnboarding returned in ${sw.elapsedMilliseconds}ms');
      _log('   $data');
      return data;
    } on FirebaseFunctionsException catch (e) {
      sw.stop();
      _fail('startOnboarding FAILED: [${e.code}] ${e.message}');
      if (e.details != null) _log('   details: ${e.details}');
      return null;
    }
  }

  Future<void> _runCreationTest() => _guard(() async {
        _header('TEST 1 — create onboarding data');
        _log('uid: $_uid');

        final data = await _callStartOnboarding();
        if (data == null) return;

        final challenges = Map<String, dynamic>.from(data['challenges'] as Map);
        for (final key in ['acceptInvites', 'challengeFriends']) {
          final entry = challenges[key];
          _check(entry != null, 'response contains "$key"');
          if (entry == null) continue;
          final e = Map<String, dynamic>.from(entry as Map);
          _check(e['competitionId'] == _compId(key),
              '$key competitionId is the deterministic id', '${e['competitionId']}');
          _check(e['inviteId'] == _inviteId(key),
              '$key inviteId is the deterministic id', '${e['inviteId']}');
        }

        await _inspectState();
      });

  // ── Test 2: inspect what's actually in Firestore ──────────────────────

  Future<void> _inspectState() async {
    _header('STATE — what is in Firestore now');

    for (final spec in [
      ('acceptInvites', 'Accept two invitations in Havruta', 2, 'invitations'),
      ('challengeFriends', 'Challenge two friends in Havruta', 2, 'friends'),
    ]) {
      final (key, expectedTitle, expectedTarget, expectedUnit) = spec;

      final comp = await _db.collection('competitions').doc(_compId(key)).get();
      _check(comp.exists, '[$key] competition doc exists');
      if (comp.exists) {
        final d = comp.data()!;
        _check(d['title'] == expectedTitle, '[$key] title is "$expectedTitle"',
            '${d['title']}');
        _check(d['createdBy'] == kSystemUserUid,
            '[$key] createdBy is the system user', '${d['createdBy']}');
        _check(d['status'] == 'active', '[$key] status is active');
        _check(d['type'] == 'personalGoalChallenge',
            '[$key] type is personalGoalChallenge');

        final meta = d['onboarding'] as Map<String, dynamic>?;
        _check(meta != null, '[$key] onboarding metadata block present');
        if (meta != null) {
          _check(meta['isOnboarding'] == true, '[$key] meta.isOnboarding true');
          _check(meta['onboardingChallengeKey'] == key,
              '[$key] meta.onboardingChallengeKey correct');
          _check(meta['onboardingUserId'] == _uid,
              '[$key] meta.onboardingUserId is my uid');
          _check(meta['onboardingVersion'] == 1,
              '[$key] meta.onboardingVersion set', '${meta['onboardingVersion']}');
        }

        final part = await _db
            .collection('competitions')
            .doc(_compId(key))
            .collection('participants')
            .doc(kSystemUserUid)
            .get();
        _check(part.exists, '[$key] system-user participant subdoc exists');
        if (part.exists) {
          final p = part.data()!;
          _check(p['targetValue'] == expectedTarget,
              '[$key] participant target is $expectedTarget', '${p['targetValue']}');
          _check(p['unit'] == expectedUnit,
              '[$key] participant unit is "$expectedUnit"', '${p['unit']}');
          _check(p['progress'] == 0, '[$key] participant progress is 0');
          _check(p['username'] == 'Havruta',
              '[$key] participant username is Havruta', '${p['username']}');
        }
      }

      final invite =
          await _db.collection('competition_invites').doc(_inviteId(key)).get();
      _check(invite.exists, '[$key] invite doc exists');
      if (invite.exists) {
        final i = invite.data()!;
        _check(i['fromUid'] == kSystemUserUid, '[$key] invite fromUid is system user');
        _check(i['toUid'] == _uid, '[$key] invite toUid is me');
        _log('   [$key] invite status: ${i['status']}, toUsername: ${i['toUsername']}');
        _check(i['creatorTargetValue'] == expectedTarget,
            '[$key] invite carries creatorTargetValue for the accept dialog');
        _check((i['onboarding'] as Map?)?['isOnboarding'] == true,
            '[$key] invite carries onboarding metadata');
      }
    }

    // Duplicate detection: how many onboarding docs exist for me in total.
    final comps = await _db
        .collection('competitions')
        .where('onboarding.onboardingUserId', isEqualTo: _uid)
        .get();
    final invites = await _db
        .collection('competition_invites')
        .where('onboarding.onboardingUserId', isEqualTo: _uid)
        .get();
    _check(comps.docs.length == 2,
        'exactly 2 onboarding competitions exist for me', 'found ${comps.docs.length}');
    _check(invites.docs.length == 2,
        'exactly 2 onboarding invites exist for me', 'found ${invites.docs.length}');

    // The system user profile the invite list reads for "Invited by: …".
    final sysUser = await _db.collection('users').doc(kSystemUserUid).get();
    _check(sysUser.exists, 'users/$kSystemUserUid profile doc exists');
    if (sysUser.exists) {
      _check(sysUser.data()!['username'] == 'Havruta',
          'system user username is "Havruta"');
    }

    // onboarding_state ledger — readable by me, per the new rule.
    try {
      final state = await _db.collection('onboarding_state').doc(_uid).get();
      _check(state.exists, 'onboarding_state ledger doc exists');
      if (state.exists) {
        _log('   ledger: ${state.data()}');
      }
    } catch (e) {
      _fail('could not read my own onboarding_state ledger: $e');
    }
  }

  Future<void> _runInspectOnly() => _guard(() async {
        await _inspectState();
      });

  // ── Test 3: idempotency ───────────────────────────────────────────────

  Future<void> _runIdempotencyTest() => _guard(() async {
        _header('TEST 2 — idempotency (call 3x, incl. 2 at once)');

        Future<Map<String, dynamic>?> snapshotTimes() async {
          final out = <String, dynamic>{};
          for (final key in ['acceptInvites', 'challengeFriends']) {
            final c = await _db.collection('competitions').doc(_compId(key)).get();
            final i =
                await _db.collection('competition_invites').doc(_inviteId(key)).get();
            out['c_$key'] = c.data()?['createdAt'];
            out['i_$key'] = i.data()?['createdAt'];
          }
          return out;
        }

        final before = await snapshotTimes();
        _log('   captured createdAt values before re-running');

        await _callStartOnboarding();

        // Two simultaneous calls, racing each other.
        final results = await Future.wait([
          FirebaseFunctions.instance
              .httpsCallable('startOnboarding')
              .call<Map<dynamic, dynamic>>(),
          FirebaseFunctions.instance
              .httpsCallable('startOnboarding')
              .call<Map<dynamic, dynamic>>(),
        ]);
        _pass('two concurrent calls both returned');
        final a = Map<String, dynamic>.from(results[0].data)['challenges'];
        final b = Map<String, dynamic>.from(results[1].data)['challenges'];
        _check(a.toString() == b.toString(),
            'both concurrent calls returned identical ids');

        final after = await snapshotTimes();
        var unchanged = true;
        for (final k in before!.keys) {
          if (before[k].toString() != after![k].toString()) {
            unchanged = false;
            _fail('$k createdAt CHANGED — document was rewritten');
          }
        }
        _check(unchanged,
            'no document was rewritten by the repeat calls (createdAt identical)');

        await _inspectState();
      });

  // ── Test 4: partial-failure recovery ──────────────────────────────────

  Future<void> _runPartialRecoveryTest() => _guard(() async {
        _header('TEST 3 — partial-failure recovery');

        const key = 'challengeFriends';
        final inviteRef = _db.collection('competition_invites').doc(_inviteId(key));

        final compBefore =
            await _db.collection('competitions').doc(_compId(key)).get();
        final compCreatedAtBefore = compBefore.data()?['createdAt'];

        _log('deleting [$key] invite to simulate a half-finished run…');
        await inviteRef.delete();
        final gone = await inviteRef.get();
        _check(!gone.exists, '[setup] invite is now missing');

        await _callStartOnboarding();

        final repaired = await inviteRef.get();
        _check(repaired.exists, 'missing invite was recreated by the retry');
        if (repaired.exists) {
          _check(repaired.data()!['fromUid'] == kSystemUserUid,
              'recreated invite has correct fromUid');
          _check(repaired.data()!['toUid'] == _uid,
              'recreated invite has correct toUid');
          _check(repaired.data()!['status'] == 'pending',
              'recreated invite is pending again');
        }

        final compAfter =
            await _db.collection('competitions').doc(_compId(key)).get();
        _check(
          compCreatedAtBefore.toString() ==
              compAfter.data()?['createdAt'].toString(),
          'the surviving competition was NOT recreated (createdAt unchanged)',
        );

        await _inspectState();
      });

  // ── Test 5: security ──────────────────────────────────────────────────

  Future<void> _runSecurityTest() => _guard(() async {
        _header('TEST 4 — security rules');

        Future<void> expectDenied(
            String label, Future<void> Function() action) async {
          try {
            await action();
            _fail('$label — WAS ALLOWED (expected denial)');
          } on FirebaseException catch (e) {
            _check(e.code == 'permission-denied', label, 'got ${e.code}');
          }
        }

        await expectDenied('cannot create a challenge as the system user',
            () async {
          await _db.collection('competitions').doc('debug_forged_$_uid').set({
            'title': 'Forged',
            'createdBy': kSystemUserUid,
            'participantUids': [kSystemUserUid],
            'status': 'active',
            'type': 'personalGoalChallenge',
          });
        });

        await expectDenied('cannot send an invite as the system user', () async {
          await _db
              .collection('competition_invites')
              .doc('debug_forged_invite_$_uid')
              .set({
            'competitionId': _compId('acceptInvites'),
            'fromUid': kSystemUserUid,
            'toUid': _uid,
            'status': 'pending',
          });
        });

        await expectDenied('cannot write my own onboarding_state ledger',
            () async {
          await _db
              .collection('onboarding_state')
              .doc(_uid)
              .set({'status': 'hacked'}, SetOptions(merge: true));
        });

        await expectDenied("cannot read another user's onboarding_state",
            () async {
          await _db
              .collection('onboarding_state')
              .doc('some-other-user-uid-that-is-not-me')
              .get();
        });

        await expectDenied('cannot delete a system-owned onboarding challenge',
            () async {
          await _db.collection('competitions').doc(_compId('acceptInvites')).delete();
        });

        _log('(reading my own ledger is covered in STATE above)');
      });

  // ── UI ────────────────────────────────────────────────────────────────

  Color _colorFor(_LineKind kind) {
    switch (kind) {
      case _LineKind.pass:
        return const Color(0xFF2DD4BF);
      case _LineKind.fail:
        return const Color(0xFFFF5C7A);
      case _LineKind.header:
        return const Color(0xFFB69CFB);
      case _LineKind.info:
        return Colors.white70;
    }
  }

  String _prefixFor(_LineKind kind) {
    switch (kind) {
      case _LineKind.pass:
        return 'PASS  ';
      case _LineKind.fail:
        return 'FAIL  ';
      case _LineKind.header:
        return '';
      case _LineKind.info:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final passCount = _lines.where((l) => l.kind == _LineKind.pass).length;
    final failCount = _lines.where((l) => l.kind == _LineKind.fail).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Onboarding Part 1 — debug'),
        actions: [
          IconButton(
            tooltip: 'Clear output',
            onPressed: () => setState(_lines.clear),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : _runCreationTest,
                  child: const Text('1. Create'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : _runIdempotencyTest,
                  child: const Text('2. Idempotency'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : _runPartialRecoveryTest,
                  child: const Text('3. Recovery'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : _runSecurityTest,
                  child: const Text('4. Security'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _runInspectOnly,
                  child: const Text('Inspect only'),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text('$passCount passed',
                      style: AppTheme.mono(
                          fontSize: 13, color: const Color(0xFF2DD4BF))),
                  const SizedBox(width: 12),
                  Text('$failCount failed',
                      style: AppTheme.mono(
                          fontSize: 13,
                          color: failCount == 0
                              ? Colors.white38
                              : const Color(0xFFFF5C7A))),
                ],
              ),
            ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final line = _lines[i];
                return Padding(
                  padding: EdgeInsets.only(
                      top: line.kind == _LineKind.header ? 14 : 2, bottom: 2),
                  child: SelectableText(
                    '${_prefixFor(line.kind)}${line.text}',
                    style: AppTheme.mono(
                      fontSize: 12,
                      color: _colorFor(line.kind),
                      fontWeight: line.kind == _LineKind.header
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
