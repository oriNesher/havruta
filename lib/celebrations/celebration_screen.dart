import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../competitions/challenge.dart';
import '../competitions/competition_event.dart';
import '../services/firestore_service.dart';
import 'celebration_types.dart';
import 'celebration_visuals.dart';
import 'shareable_card.dart';
import 'swipe_up_to_dismiss.dart';
import 'trash_talk_screen.dart';

/// Full-screen celebration for every celebration-eligible event fired by
/// one progress update (see CelebrationGate, which groups events by
/// batchId before pushing this) — shown once, together, rather than one
/// screen per event.
class CelebrationScreen extends StatefulWidget {
  final List<CompetitionEvent> events;

  const CelebrationScreen({super.key, required this.events});

  @override
  State<CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<CelebrationScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _isSharing = false;

  /// Whether this challenge has Trash Talk on (organizers can turn it off;
  /// it defaults off in large and organizer-only challenges). Looked up as
  /// the screen opens; on a failed lookup the old behavior (on) stands.
  late final Future<bool> _trashTalk = _loadTrashTalk();

  Future<bool> _loadTrashTalk() async {
    final competitionId = widget.events.firstOrNull?.competitionId ?? '';
    if (competitionId.isEmpty) return true;
    try {
      final doc = await FirestoreService().getCompetition(competitionId);
      final data = doc.data();
      return data == null ||
          Challenge.fromDoc(competitionId, data).trashTalkEnabled;
    } catch (e) {
      debugPrint('Trash Talk setting unavailable: $e');
      return true;
    }
  }

  late final List<CompetitionEvent> _sortedEvents = [...widget.events]
    ..sort(
      (a, b) => celebrationPriorityRank(
        a.type,
      ).compareTo(celebrationPriorityRank(b.type)),
    );

  String get _headerTitle => _sortedEvents.length > 1
      ? '${_sortedEvents.length} things just happened!'
      : 'Nice one!';

  Future<void> _share() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final shareText = _sortedEvents.map(celebrationHeadline).join(' ');
      await captureAndShareCard(boundaryKey: _cardKey, shareText: shareText);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not share: $e')));
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _talkTrash() async {
    if (!await _trashTalk) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TrashTalkScreen(events: widget.events),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final competitionTitle = _sortedEvents.first.competitionTitle;
    final accentColor = Theme.of(context).colorScheme.tertiary;
    final screenColor = screenTintColor(accentColor);

    return SwipeUpToDismiss(
      backgroundColor: screenColor,
      child: Scaffold(
        backgroundColor: screenColor,
        appBar: AppBar(
          backgroundColor: screenColor,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.ios_share),
              onPressed: _isSharing ? null : _share,
              tooltip: 'Share',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Skip',
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: RepaintBoundary(
                        key: _cardKey,
                        child: ShareableCard(
                          accentColor: accentColor,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _headerTitle,
                                style: AppTheme.display(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              if (competitionTitle != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  competitionTitle,
                                  style: AppTheme.display(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              for (final event in _sortedEvents)
                                CelebrationEventRow(event: event),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _talkTrash,
                  style: ElevatedButton.styleFrom(backgroundColor: accentColor),
                  child: const Text('Nice!'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
