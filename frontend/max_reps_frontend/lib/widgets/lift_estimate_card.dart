import 'package:flutter/material.dart';
import 'package:max_reps_frontend/models/lift_record.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';
import 'package:max_reps_frontend/utils/date_format.dart';

class LiftEstimateCard extends StatelessWidget {
  final LiftRecord record;
  final String exerciseName;
  final bool saved;

  const LiftEstimateCard({
    super.key,
    required this.record,
    required this.exerciseName,
    this.saved = false,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.aqua.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: AppColors.deepAqua,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  saved ? 'Latest saved 1RM' : 'New estimate',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.aqua,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(exerciseName, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '${record.reps} reps at ${record.weight.toStringAsFixed(2)} ${record.unit}',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.aqua.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Estimated 1RM: ${record.oneRepMaxEst.toStringAsFixed(2)} ${record.unit}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: AppColors.deepAqua),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Attempted at: ${formatUsUtc(record.attemptedAt)}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 20),
          Text(
            'Percentages of estimated 1RM',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text('Your numbers for the next session.'),
          const SizedBox(height: 16),
          // Descending intensity: red for 90%, through orange and aqua, to blue
          // for 50%. Labels and values convey the same information without color.
          for (final level in const [
            (90, Color(0xFFC73D42)),
            (80, Color(0xFFBA5A16)),
            (70, Color(0xFF917200)),
            (60, Color(0xFF007B84)),
            (50, Color(0xFF275DB3)),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: level.$2.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${level.$1}%',
                      style: TextStyle(
                        color: level.$2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: level.$1 / 100,
                        minHeight: 6,
                        color: level.$2,
                        backgroundColor: AppColors.background,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Text(
                      '${(record.oneRepMaxEst * level.$1 / 100).toStringAsFixed(2)} ${record.unit}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
