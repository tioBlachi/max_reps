import 'package:flutter/material.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.aqua,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Icon(
          Icons.fitness_center_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
      const SizedBox(width: 12),
      const Text(
        'MAXREPS',
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.3,
        ),
      ),
    ],
  );
}
