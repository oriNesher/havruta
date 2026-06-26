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
  final _firestoreService = FirestoreService();

  HomeEventsSection({super.key, required this.uid});

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

  Widget buildHeroCard(BuildContext context, EventUIModel ui) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ui.title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            ui.subtitle,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  ui.competitionTitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                ui.ctaLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildEventCard(BuildContext context, EventUIModel ui) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ui.title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ui.subtitle,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  ui.competitionTitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                ui.timeText,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildDismissibleHero({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required FirestoreService firestoreService,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final ui = mapEventToUI(doc.data());

    return Dismissible(
      key: ValueKey('hero_${doc.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: colorScheme.secondary,
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
      child: buildHeroCard(context, ui),
    );
  }

  Widget buildDismissibleEvent({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required FirestoreService firestoreService,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final ui = mapEventToUI(doc.data());

    return Dismissible(
      key: ValueKey(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: colorScheme.secondary,
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
      child: buildEventCard(context, ui),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestoreService.getHomeEvents(uid),
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
                context: context,
                doc: heroDoc,
                firestoreService: _firestoreService,
              ),

            ...feedDocs.map(
              (doc) => buildDismissibleEvent(
                context: context,
                doc: doc,
                firestoreService: _firestoreService,
              ),
            ),
          ],
        );
      },
    );
  }
}
