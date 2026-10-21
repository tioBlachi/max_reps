import 'dart:async';

import 'package:flutter/material.dart';
import 'package:max_reps_frontend/models/exercise.dart';
import 'package:max_reps_frontend/models/lift_record.dart';
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/exercise_service.dart';
import 'package:max_reps_frontend/services/lift_record_service.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';
import 'package:max_reps_frontend/widgets/exercise_autocomplete.dart';

class AddLiftPage extends StatefulWidget {
  final AuthState authState;
  final ExerciseService exerciseService;
  final LiftRecordService liftRecordService;
  final String initialUnit;
  final ValueChanged<LiftRecord> onSaved;
  const AddLiftPage({
    super.key,
    required this.authState,
    required this.exerciseService,
    required this.liftRecordService,
    required this.onSaved,
    this.initialUnit = 'lb',
  });

  @override
  State<AddLiftPage> createState() => _AddLiftPageState();
}

class _AddLiftPageState extends State<AddLiftPage> {
  final _form = GlobalKey<FormState>();
  final _reps = TextEditingController();
  final _weight = TextEditingController();
  late Future<List<Exercise>> _catalog;
  late String _unit;
  Exercise? _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _unit = widget.initialUnit;
    _catalog = widget.exerciseService.getExercises();
  }

  Future<void> _save() async {
    if (_saving || _form.currentState?.validate() != true) return;
    final token = widget.authState.accessToken;
    if (token == null) {
      await widget.authState.logout();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final record = await widget.liftRecordService.createLiftRecord(
        accessToken: token,
        exerciseId: _selected!.id,
        reps: int.parse(_reps.text.trim()),
        weight: double.parse(_weight.text.trim()),
        unit: _unit,
      );
      if (mounted) widget.onSaved(record);
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        await widget.authState.logout();
        return;
      }
      setState(() {
        _error = error is TimeoutException
            ? 'The request timed out. The lift may have been saved. Check Training Zone before adding it again.'
            : error is ApiException
            ? error.message
            : 'Could not save the lift. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to Training Zone',
          onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Add New Lift'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.fitness_center_rounded,
                        color: AppColors.aqua,
                        size: 32,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Log your next lift.',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Choose any exercise and we’ll calculate your estimated one-rep max.',
                      ),
                      const SizedBox(height: 28),
                      FutureBuilder<List<Exercise>>(
                        future: _catalog,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError) {
                            return Column(
                              children: [
                                const Text('Could not load exercises.'),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _catalog = widget.exerciseService
                                        .getExercises();
                                  }),
                                  child: const Text('Retry exercises'),
                                ),
                              ],
                            );
                          }
                          final exercises = snapshot.data ?? [];
                          if (exercises.isEmpty) {
                            return const Text(
                              'No exercises are available yet.',
                            );
                          }
                          return Form(
                            key: _form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ExerciseAutocomplete(
                                  exercises: exercises,
                                  selected: _selected,
                                  enabled: !_saving,
                                  onSelected: (exercise) => setState(() {
                                    _selected = exercise;
                                  }),
                                  onCleared: () => setState(() {
                                    _selected = null;
                                  }),
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _reps,
                                  enabled: !_saving,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Repetitions',
                                    hintText: 'e.g. 5',
                                  ),
                                  validator: (value) {
                                    final reps = int.tryParse(
                                      value?.trim() ?? '',
                                    );
                                    return reps == null || reps <= 0
                                        ? 'Enter a whole number greater than zero.'
                                        : null;
                                  },
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _weight,
                                  enabled: !_saving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: 'Weight',
                                    hintText: 'e.g. 135',
                                  ),
                                  onFieldSubmitted: (_) => _save(),
                                  validator: (value) {
                                    final weight = double.tryParse(
                                      value?.trim() ?? '',
                                    );
                                    return weight == null ||
                                            !weight.isFinite ||
                                            weight <= 0
                                        ? 'Enter a positive weight.'
                                        : null;
                                  },
                                ),
                                const SizedBox(height: 20),
                                DropdownButtonFormField<String>(
                                  initialValue: _unit,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Unit',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'lb',
                                      child: Text('Pounds (lb)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'kg',
                                      child: Text('Kilograms (kg)'),
                                    ),
                                  ],
                                  onChanged: _saving
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            setState(() {
                                              _unit = value;
                                            });
                                          }
                                        },
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 18),
                                  Text(
                                    _error!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 28),
                                FilledButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: const Icon(Icons.add_rounded),
                                  label: Text(
                                    _saving ? 'Saving...' : 'Save lift',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => Navigator.of(context).pop(),
                                  child: const Text('Cancel'),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Estimates use the Epley formula. Weights and percentages are shown to two decimal places.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _reps.dispose();
    _weight.dispose();
    super.dispose();
  }
}
