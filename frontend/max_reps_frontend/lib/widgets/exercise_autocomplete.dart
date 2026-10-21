import 'package:flutter/material.dart';
import 'package:max_reps_frontend/models/exercise.dart';

// Shared search behavior; callers choose whether options are the entire
// exercise catalog or only exercises belonging to the current user's history.
class ExerciseAutocomplete extends StatelessWidget {
  final List<Exercise> exercises;
  final Exercise? selected;
  final bool enabled;
  final ValueChanged<Exercise> onSelected;
  final VoidCallback onCleared;
  final bool requiredSelection;
  final String label;

  const ExerciseAutocomplete({
    super.key,
    required this.exercises,
    required this.selected,
    required this.onSelected,
    required this.onCleared,
    this.enabled = true,
    this.requiredSelection = true,
    this.label = 'Exercise',
  });

  @override
  Widget build(BuildContext context) => Autocomplete<Exercise>(
    initialValue: TextEditingValue(text: selected?.name ?? ''),
    displayStringForOption: (exercise) => exercise.name,
    optionsMaxHeight: 280,
    optionsBuilder: (value) {
      if (!enabled) return const Iterable<Exercise>.empty();
      final query = value.text.trim().toLowerCase();
      return exercises
          .where((exercise) => exercise.name.toLowerCase().contains(query))
          .take(10);
    },
    onSelected: onSelected,
    fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Start typing an exercise name',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear exercise',
                    onPressed: !enabled
                        ? null
                        : () {
                            controller.clear();
                            onCleared();
                            focusNode.requestFocus();
                          },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
          onChanged: (_) => onCleared(),
          onFieldSubmitted: (_) => onSubmitted(),
          validator: (_) => requiredSelection && selected == null
              ? 'Choose an exercise from the suggestions.'
              : null,
        ),
  );
}
