import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'services/firestore_service.dart';

class EventUIModel {
  final String title;
  final String subtitle;
  final String competitionTitle;
  final String timeText;
  final String ctaLabel;

  EventUIModel({
    required this.title,
    required this.subtitle,
    required this.competitionTitle,
    required this.timeText,
    required this.ctaLabel,
  });
}

class HomeEventsSection extends StatelessWidget {
  final String uid;

  const HomeEventsSection({super.key, required this.uid});

  String formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return '';

    final date = (timestamp as Timestamp).toDate();
    final diff = DateTime.now().difference(date);

    if (diff.inSeconds < 60) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  EventUIModel mapEventToUI(Map<String, dynamic> data) {
    final type = data['type'];
    final actorUsername = data['actorUsername'] ?? 'Someone';
    final competitionTitle = data['competitionTitle'] ?? 'Competition';

    final timestamp = data['lastUpdatedAt'] ?? data['createdAt'];
    final timeText = formatTimeAgo(timestamp);

    if (type == 'progress') {
      final metadata = data['metadata'] as Map<String, dynamic>?;
      final delta = metadata?['progressDelta'];

      return EventUIModel(
        title: '$actorUsername made progress',
        subtitle: delta != null
            ? 'Advanced by $delta since your last visit'
            : 'Moved forward in this competition',
        competitionTitle: competitionTitle,
        timeText: timeText,
        ctaLabel: 'Open',
      );
    }

    if (type == 'overtook') {
      return EventUIModel(
        title: '$actorUsername overtook you',
        subtitle: 'You are no longer ahead in this competition',
        competitionTitle: competitionTitle,
        timeText: timeText,
        ctaLabel: 'Open',
      );
    }

    return EventUIModel(
      title: 'New activity',
      subtitle: 'Something changed in this competition',
      competitionTitle: competitionTitle,
      timeText: timeText,
      ctaLabel: 'Open',
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestoreService.getHomeEvents(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Text('Error loading events: ${snapshot.error}');
        }

        final docs = snapshot.data?.docs ?? [];

        /* mark the loaded events as seen
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (docs.isEmpty) return;

          final eventIds = docs.map((doc) => doc.id).toList();
          firestoreService.markEventsAsSeen(eventIds, uid);
        });
        */

        if (docs.isEmpty) {
          return const Text('No new events');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: docs.map((doc) {
            final data = doc.data();
            final ui = mapEventToUI(data);

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F3F3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ui.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ui.subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          ui.competitionTitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        children: [
                          Text(
                            ui.timeText,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black38,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            ui.ctaLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}