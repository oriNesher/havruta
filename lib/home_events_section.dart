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

  QueryDocumentSnapshot<Map<String, dynamic>>? pickHeroEvent(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) return null;

    // Prefer overtook events
    for (final doc in docs) {
      final data = doc.data();
      if (data['type'] == 'overtook') {
        return doc;
      }
    }

    return docs.first;
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
        ctaLabel: 'Give a minute',
      );
    }

    if (type == 'overtook') {
      return EventUIModel(
        title: '$actorUsername overtook you',
        subtitle: 'You are no longer ahead in this competition',
        competitionTitle: competitionTitle,
        timeText: timeText,
        ctaLabel: 'Give a minute',
      );
    }

    return EventUIModel(
      title: 'New activity',
      subtitle: 'Something changed in this competition',
      competitionTitle: competitionTitle,
      timeText: timeText,
      ctaLabel: 'Give a minute',
    );
  }

  Widget buildHeroCard(EventUIModel ui) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE7FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ui.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            ui.subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  ui.competitionTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black45,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                ui.ctaLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildEventCard(EventUIModel ui) {
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
              Text(
                ui.timeText,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black38,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildDismissibleHero({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required FirestoreService firestoreService,
  }) {
    final ui = mapEventToUI(doc.data());

    return Dismissible(
      key: ValueKey('hero_${doc.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          Icons.close,
          color: Colors.white,
        ),
      ),
      onDismissed: (_) {
        firestoreService.dismissEventsForUser([doc.id], uid);
      },
      child: buildHeroCard(ui),
    );
  }

  Widget buildDismissibleEvent({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required FirestoreService firestoreService,
  }) {
    final ui = mapEventToUI(doc.data());

    return Dismissible(
      key: ValueKey(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.close,
          color: Colors.white,
        ),
      ),
      onDismissed: (_) {
        firestoreService.dismissEventsForUser([doc.id], uid);
      },
      child: buildEventCard(ui),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestoreService.getHomeEvents(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Text(
            'Error loading events: ${snapshot.error}',
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Text('No new events');
        }

        final heroDoc = pickHeroEvent(docs);
        final feedDocs = docs
            .where((doc) => doc.id != heroDoc?.id)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (heroDoc != null)
              buildDismissibleHero(
                doc: heroDoc,
                firestoreService: firestoreService,
              ),

            ...feedDocs.map(
              (doc) => buildDismissibleEvent(
                doc: doc,
                firestoreService: firestoreService,
              ),
            ),
          ],
        );
      },
    );
  }
}