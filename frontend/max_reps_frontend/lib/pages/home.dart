import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:max_reps_frontend/models/exercise.dart';
import 'package:max_reps_frontend/models/lift_record.dart';
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/exercise_service.dart';
import 'package:max_reps_frontend/services/lift_record_service.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';
import 'package:max_reps_frontend/widgets/app_scaffold.dart';
import 'package:max_reps_frontend/widgets/lift_estimate_card.dart';

class HomePage extends StatefulWidget {
  final AuthState authState;
  final ExerciseService exerciseService;
  final LiftRecordService liftRecordService;

  const HomePage({
    super.key,
    required this.authState,
    required this.exerciseService,
    required this.liftRecordService,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _formKey = GlobalKey<FormState>();
  final _repsController = TextEditingController();
  final _weightController = TextEditingController();

  late Future<List<Exercise>> _exercisesFuture;

  int? _selectedExerciseId;
  String _unit = 'lb';
  bool _isSubmitting = false;
  String? _errorMessage;

  LiftRecord? _savedRecord;
  bool _isLoadingSavedRecord = false;
  String? _savedRecordError;
  int _savedRecordRequest = 0;

  // Results submitted during this visit, newest first.
  final List<LiftRecord> _results = [];

  @override
  void initState() {
    super.initState();
    _exercisesFuture = widget.exerciseService.getExercises();
  }

  void _retryExercises() {
    setState(() {
      _selectedExerciseId = null;
      _clearSavedRecord();
      _exercisesFuture = widget.exerciseService.getExercises();
    });
  }

  // Call inside setState when the selected exercise is cleared.
  void _clearSavedRecord() {
    // Invalidate pending lookups so an old response cannot replace newer data.
    _savedRecordRequest++;
    _savedRecord = null;
    _savedRecordError = null;
    _isLoadingSavedRecord = false;
  }

  Future<void> _loadSavedRecord() async {
    final exerciseId = _selectedExerciseId;
    if (exerciseId == null) return;

    final token = widget.authState.accessToken;
    if (token == null) {
      _sessionExpired();
      return;
    }

    final request = ++_savedRecordRequest;
    final unit = _unit;
    setState(() {
      _savedRecord = null;
      _savedRecordError = null;
      _isLoadingSavedRecord = true;
    });

    try {
      // The API filters by the authenticated user and sorts newest attempts first.
      // Request only one record, converted by the backend to the selected unit.
      final records = await widget.liftRecordService.getLiftRecords(
        accessToken: token,
        exerciseId: exerciseId,
        unit: unit,
        limit: 1,
      );

      if (!mounted || request != _savedRecordRequest) return;
      setState(() {
        _savedRecord = records.isEmpty ? null : records.first;
      });
    } catch (error) {
      if (!mounted || request != _savedRecordRequest) return;
      if (error is ApiException && error.statusCode == 401) {
        _sessionExpired();
        return;
      }

      setState(() {
        _savedRecordError = error is ApiException && error.statusCode == 429
            ? 'Too many requests. Please wait before trying again.'
            : 'Could not load your saved estimate. Please try again.';
      });
    } finally {
      if (mounted && request == _savedRecordRequest) {
        setState(() {
          _isLoadingSavedRecord = false;
        });
      }
    }
  }

  void _sessionExpired() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your session expired. Please sign in again.'),
      ),
    );

    // app.dart will replace this page with LoginPage.
    widget.authState.logout();
  }

  Future<void> _submitLift() async {
    if (_isSubmitting || widget.authState.isLoading) return;
    if (_formKey.currentState?.validate() != true) return;

    final token = widget.authState.accessToken;

    if (token == null) {
      _sessionExpired();
      return;
    }

    // Validation has established that these values are valid.
    // Capture them before starting the asynchronous request.
    final exerciseId = _selectedExerciseId!;
    final reps = int.parse(_repsController.text.trim());
    final weight = double.parse(_weightController.text.trim());
    final unit = _unit;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final record = await widget.liftRecordService.createLiftRecord(
        accessToken: token,
        exerciseId: exerciseId,
        reps: reps,
        weight: weight,
        unit: unit,
      );

      if (!mounted) return;

      setState(() {
        // Display the backend's returned record, including its estimate.
        _results.insert(0, record);
      });

      // Refresh the saved estimate now that the database contains this attempt.
      unawaited(_loadSavedRecord());
    } catch (error) {
      if (!mounted) return;

      if (error is ApiException && error.statusCode == 401) {
        _sessionExpired();
        return;
      }

      setState(() {
        if (error is ApiException) {
          _errorMessage = error.statusCode == 429
              ? 'Too many requests. Please wait before trying again.'
              : error.message;
        } else if (error is TimeoutException) {
          _errorMessage =
              'The request timed out. The lift may already have been saved.';
        } else if (error is http.ClientException) {
          _errorMessage =
              'Could not complete the request. Check your connection.';
        } else {
          _errorMessage = 'Unable to complete the calculation.';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildExerciseField(List<Exercise> exercises) {
    return Autocomplete<Exercise>(
      displayStringForOption: (exercise) => exercise.name,
      optionsMaxHeight: 300,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();

        if (_isSubmitting || query.isEmpty) {
          return const Iterable<Exercise>.empty();
        }

        return exercises
            .where((exercise) {
              return exercise.name.toLowerCase().contains(query);
            })
            .take(10);
      },
      onSelected: (exercise) {
        setState(() {
          _selectedExerciseId = exercise.id;
        });
        unawaited(_loadSavedRecord());
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: !_isSubmitting,
          decoration: const InputDecoration(
            labelText: 'Exercise',
            hintText: 'Start typing an exercise name',
            helperText: 'Choose an exercise from the suggestions.',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onFieldSubmitted: (_) => onFieldSubmitted(),
          onChanged: (_) {
            if (_selectedExerciseId != null) {
              setState(() {
                _selectedExerciseId = null;
                _clearSavedRecord();
              });
            }
          },
          validator: (_) {
            if (_selectedExerciseId == null) {
              return 'Select an exercise from the suggestions.';
            }

            return null;
          },
        );
      },
    );
  }

  Widget _buildSavedEstimate(String exerciseName) {
    final record = _savedRecord;
    if (!_isLoadingSavedRecord && _savedRecordError == null && record != null) {
      return LiftEstimateCard(
        record: record,
        exerciseName: exerciseName,
        saved: true,
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Latest saved 1RM',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_isLoadingSavedRecord)
              const Text('Loading your saved estimate...')
            else if (_savedRecordError != null) ...[
              Text(
                _savedRecordError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _isSubmitting ? null : _loadSavedRecord,
                child: const Text('Retry saved estimate'),
              ),
            ] else
              Text('No saved estimate for $exerciseName yet.'),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(List<Exercise> exercises) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.add_circle_outline_rounded,
                  color: AppColors.deepAqua,
                ),
                const SizedBox(width: 10),
                Text(
                  'Log a lift',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('A few details. A clearer picture of your strength.'),
            const SizedBox(height: 24),
            _buildExerciseField(exercises),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _repsController,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Repetitions',
                      hintText: 'e.g. 5',
                    ),
                    validator: (value) {
                      final reps = int.tryParse(value?.trim() ?? '');
                      return reps == null || reps <= 0
                          ? 'Enter a whole number greater than zero.'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _weightController,
                    enabled: !_isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submitLift(),
                    decoration: const InputDecoration(
                      labelText: 'Weight',
                      hintText: 'e.g. 100',
                    ),
                    validator: (value) {
                      final weight = double.tryParse(value?.trim() ?? '');
                      return weight == null || !weight.isFinite || weight <= 0
                          ? 'Enter a positive weight.'
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _unit,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Unit',
                prefixIcon: Icon(Icons.scale_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'lb', child: Text('Pounds (lb)')),
                DropdownMenuItem(value: 'kg', child: Text('Kilograms (kg)')),
              ],
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      if (value == null || value == _unit) return;
                      setState(() {
                        _unit = value;
                      });
                      unawaited(_loadSavedRecord());
                    },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitLift,
              icon: const Icon(Icons.bolt_rounded),
              label: Text(_isSubmitting ? 'Calculating...' : 'Calculate 1RM'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Calculated using the Epley formula. Your result is an estimate, not a tested maximum.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildResults(List<Exercise> exercises) {
    final exerciseNames = {
      for (final exercise in exercises) exercise.id: exercise.name,
    };
    // The selected exercise's latest saved record already has a full result
    // card. Avoid repeating it in the session list after a successful save.
    final sessionRecords = _results
        .where((record) => record.id != _savedRecord?.id)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedExerciseId != null)
          _buildSavedEstimate(exerciseNames[_selectedExerciseId] ?? 'Exercise')
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE6F5F4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.insights_rounded,
                      size: 40,
                      color: AppColors.deepAqua,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Your next best starts here.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Select an exercise to see your latest saved estimate, or log a lift to calculate a new one.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        if (sessionRecords.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('This session', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final record in sessionRecords)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: LiftEstimateCard(
                record: record,
                exerciseName: exerciseNames[record.exerciseId] ?? 'Exercise',
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildTrainingContent(List<Exercise> exercises) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 860) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildForm(exercises),
            const SizedBox(height: 24),
            _buildResults(exercises),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: _buildForm(exercises)),
          const SizedBox(width: 28),
          Expanded(flex: 5, child: _buildResults(exercises)),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => AppScaffold(
    authState: widget.authState,
    busy: _isSubmitting,
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.deepAqua,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MAKE EVERY REP COUNT',
                      style: TextStyle(
                        color: Color(0xFFFFC086),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Every rep. A stronger you.',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Estimate your one-rep max. Find your training weights. Build from here.',
                      style: TextStyle(
                        color: Color(0xFFD7EFED),
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              FutureBuilder<List<Exercise>>(
                future: _exercisesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Text('Could not load exercises.'),
                            TextButton(
                              onPressed: _retryExercises,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final exercises = snapshot.data ?? const <Exercise>[];
                  if (exercises.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No exercises are available yet.'),
                      ),
                    );
                  }
                  return _buildTrainingContent(exercises);
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _repsController.dispose();
    _weightController.dispose();
    super.dispose();
  }
}
