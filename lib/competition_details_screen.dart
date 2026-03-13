import 'package:flutter/material.dart';

class CompetitionDetailsScreen extends StatelessWidget {
  final String competitionId;
  final String title;
  final String description;
  final int targetNumber;
  final String unit;
  final String status;
  final String createdBy;

  const CompetitionDetailsScreen({
    super.key,
    required this.competitionId,
    required this.title,
    required this.description,
    required this.targetNumber,
    required this.unit,
    required this.status,
    required this.createdBy,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Competition Details'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (description.isNotEmpty) ...[
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(description),
              const SizedBox(height: 20),
            ],
            const Text(
              'Target',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text('$targetNumber $unit'),
            const SizedBox(height: 20),
            const Text(
              'Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(status),
            const SizedBox(height: 20),
            const Text(
              'Created By',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(createdBy),
            const SizedBox(height: 20),
            const Text(
              'Competition ID',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(competitionId),
          ],
        ),
      ),
    );
  }
}