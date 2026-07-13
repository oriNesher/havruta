import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';
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

class HomeEventsSection extends StatefulWidget {
  final String uid;
  const HomeEventsSection({super.key, required this.uid});

  @override
  State<HomeEventsSection> createState() => _HomeEventsSectionState();
}

class _HomeEventsSectionState extends State<HomeEventsSection> {
  late final FirestoreService _firestoreService;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _firestoreService = FirestoreService();
    _stream = _firestoreService.getHomeEvents(widget.uid);
  }

  String _formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return '';
    final date = (timestamp as Timestamp).toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _pickHeroEvent(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) return null;
    for (final doc in docs) {
      if (doc.data()['type'] == 'overtook') return doc;
    }
    return docs.first;
  }

  EventUIModel _mapEventToUI(Map<String, dynamic> data) {
    final type = data['type'];
    final actorUsername = data['actorUsername'] ?? 'Someone';
    final competitionTitle = data['competitionTitle'] ?? 'Competition';
    final timestamp = data['lastUpdatedAt'] ?? data['createdAt'];
    final timeText = _formatTimeAgo(timestamp);

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

  Widget _buildHeroCard(BuildContext context, EventUIModel ui) {
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
            style: AppTheme.display(
              fontSize: 23,
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
                  style: AppTheme.display(
                    fontSize: 15,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                ui.ctaLabel,
                style: AppTheme.display(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, EventUIModel ui) {
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
            style: AppTheme.display(
              fontSize: 19,
              fontWeight: FontWeight.w700,
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
                  style: AppTheme.display(
                    fontSize: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                ui.timeText,
                style: AppTheme.mono(
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

  Widget _buildDismissibleHero(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final ui = _mapEventToUI(doc.data());
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
        child: const Icon(Icons.close, color: Colors.white),
      ),
      onDismissed: (_) {
        _firestoreService.dismissEventsForUser([doc.id], widget.uid);
      },
      child: _buildHeroCard(context, ui),
    );
  }

  Widget _buildDismissibleEvent(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final ui = _mapEventToUI(doc.data());
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
        child: const Icon(Icons.close, color: Colors.white),
      ),
      onDismissed: (_) {
        _firestoreService.dismissEventsForUser([doc.id], widget.uid);
      },
      child: _buildEventCard(context, ui),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Matches hero card shape exactly so no layout shift when real data arrives
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
          _SkeletonBlock(width: 180, height: 20, radius: 10),
          const SizedBox(height: 10),
          _SkeletonBlock(width: double.infinity, height: 12, radius: 6),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SkeletonBlock(width: 120, height: 12, radius: 6),
              _SkeletonBlock(width: 80, height: 14, radius: 7),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton(context);
        }

        if (snapshot.hasError) {
          return Text('Error loading events: ${snapshot.error}');
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Text('No new events');
        }

        final heroDoc = _pickHeroEvent(docs);
        final feedDocs = docs.where((doc) => doc.id != heroDoc?.id).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (heroDoc != null) _buildDismissibleHero(context, heroDoc),
            ...feedDocs.map((doc) => _buildDismissibleEvent(context, doc)),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Shared skeleton primitive
// ─────────────────────────────────────────────

class _SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBlock({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF282840),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
