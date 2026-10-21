import 'package:flutter/material.dart';
import 'package:max_reps_frontend/models/lift_record.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';
import 'package:max_reps_frontend/utils/date_format.dart';

class LiftHistoryCard extends StatelessWidget {
  final LiftRecord record;
  final bool initiallyExpanded;
  const LiftHistoryCard({
    super.key,
    required this.record,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: PageStorageKey('${record.id}-${record.unit}'),
      initiallyExpanded: initiallyExpanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      childrenPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        '${record.oneRepMaxEst.toStringAsFixed(2)} ${record.unit}',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(color: AppColors.deepAqua),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${record.reps} reps × ${record.weight.toStringAsFixed(2)} ${record.unit}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              formatUsLocal(record.attemptedAt),
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
      children: [
        const Divider(height: 1),
        const SizedBox(height: 18),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Training splits',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
        ),
        const SizedBox(height: 12),
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
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: level.$2.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${level.$1}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: level.$2,
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
                Text(
                  '${(record.oneRepMaxEst * level.$1 / 100).toStringAsFixed(2)} ${record.unit}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
