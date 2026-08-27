import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../competitions/competition_event.dart';
import 'celebration_types.dart';
import 'celebration_visuals.dart';
import 'shareable_card.dart';
import 'trash_talk_copy.dart';

/// Shown after the actor confirms a celebration (possibly for several
/// events fired by the same progress update at once — see
/// CelebrationScreen). Lets them tweak the suggested brag before sharing it
/// as an image via the native share sheet.
class TrashTalkScreen extends StatefulWidget {
  final List<CompetitionEvent> events;

  const TrashTalkScreen({super.key, required this.events});

  @override
  State<TrashTalkScreen> createState() => _TrashTalkScreenState();
}

class _TrashTalkScreenState extends State<TrashTalkScreen> {
  final GlobalKey _cardKey = GlobalKey();
  late final TextEditingController _messageController;
  bool _isSharing = false;

  late final List<CompetitionEvent> _sortedEvents = [...widget.events]
    ..sort(
      (a, b) => celebrationPriorityRank(a.type).compareTo(celebrationPriorityRank(b.type)),
    );

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(
      text: buildSuggestedTrashTalk(widget.events),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSharing) return;

    setState(() => _isSharing = true);
    try {
      await captureAndShareCard(boundaryKey: _cardKey, shareText: message);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not share: $e')));
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.secondary;
    final screenColor = screenTintColor(accentColor);

    return Scaffold(
      backgroundColor: screenColor,
      appBar: AppBar(
        backgroundColor: screenColor,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Dismiss',
        ),
        title: Text('Trash Talk', style: AppTheme.display(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                            AnimatedBuilder(
                              animation: _messageController,
                              builder: (context, _) => Text(
                                _messageController.text.isEmpty
                                    ? ' '
                                    : _messageController.text,
                                style: AppTheme.display(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            for (final event in _sortedEvents) CelebrationEventRow(event: event),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _messageController,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(labelText: 'Your message'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isSharing ? null : _share,
                style: ElevatedButton.styleFrom(backgroundColor: accentColor),
                child: _isSharing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.ios_share, size: 18),
                          SizedBox(width: 8),
                          Text('SHARE'),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
