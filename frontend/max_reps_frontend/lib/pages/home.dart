import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:max_reps_frontend/models/exercise.dart';
import 'package:max_reps_frontend/models/lift_record.dart';
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/exercise_service.dart';
import 'package:max_reps_frontend/services/lift_record_service.dart';
import 'package:max_reps_frontend/state/auth_state.dart';

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

        return exercises.where((exercise) {
          return exercise.name.toLowerCase().contains(query);
        }).take(10);
      },
      onSelected: (exercise) {
        setState(() {
          _selectedExerciseId = exercise.id;
        });
        unawaited(_loadSavedRecord());
      },
      fieldViewBuilder: (
        context,
        controller,
        focusNode,
        onFieldSubmitted,
      ) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: !_isSubmitting,
          decoration: const InputDecoration(
            labelText: 'Exercise',
            hintText: 'Start typing an exercise name',
            helperText: 'Choose an exercise from the suggestions.',
            border: OutlineInputBorder(),
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

  String _formatAttemptedAt(DateTime attemptedAt) {
    final utc = attemptedAt.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    final period = utc.hour < 12 ? 'AM' : 'PM';
    // In a 12-hour clock, midnight and noon both use 12 rather than 0.
    final hour = utc.hour % 12 == 0 ? 12 : utc.hour % 12;

    return '$month/$day/${utc.year} at $hour:$minute $period';
  }

  Widget _buildResultCard(
    LiftRecord record,
    String exerciseName, {
    bool saved = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (saved) ...[
              Text(
                'Latest saved 1RM',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('Attempted at: ${_formatAttemptedAt(record.attemptedAt)}'),
              const SizedBox(height: 8),
            ],
            Text(
              exerciseName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${record.reps} reps at '
              '${record.weight.toStringAsFixed(2)} ${record.unit}',
            ),
            const SizedBox(height: 8),
            Text(
              'Estimated 1RM: '
              '${record.oneRepMaxEst.toStringAsFixed(2)} ${record.unit}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPercentageCard(LiftRecord record) {
    const percentages = [50, 60, 70, 80, 90];

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Percentages of estimated 1RM',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            // Calculate each percentage using the estimate returned by the API.
            for (final percentage in percentages)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$percentage%'),
                    Text(
                      '${(record.oneRepMaxEst * percentage / 100).toStringAsFixed(2)} '
                      '${record.unit}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedEstimate(String exerciseName) {
    final record = _savedRecord;
    if (!_isLoadingSavedRecord && _savedRecordError == null && record != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildResultCard(record, exerciseName, saved: true),
          _buildPercentageCard(record),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Latest saved 1RM',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_isLoadingSavedRecord)
              const Text('Loading your saved estimate...')
            else if (_savedRecordError != null) ...[
              Text(_savedRecordError!),
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

  Widget _buildForm(List<Exercise> exercises) {
    // Look up an exercise's display name using a saved record's ID.
    final exerciseNames = <int, String>{
      for (final exercise in exercises) exercise.id: exercise.name,
    };

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Estimate your one-rep max',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          _buildExerciseField(exercises),
          const SizedBox(height: 16),
          TextFormField(
            controller: _repsController,
            enabled: !_isSubmitting,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Repetitions',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final reps = int.tryParse(value?.trim() ?? '');

              if (reps == null || reps <= 0) {
                return 'Enter a whole number greater than zero.';
              }

              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _weightController,
            enabled: !_isSubmitting,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitLift(),
            decoration: const InputDecoration(
              labelText: 'Weight',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final weight = double.tryParse(value?.trim() ?? '');

              if (weight == null || !weight.isFinite || weight <= 0) {
                return 'Enter a positive weight, such as 100.5.';
              }

              return null;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _unit,
            decoration: const InputDecoration(
              labelText: 'Unit',
              border: OutlineInputBorder(),
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
            onChanged: _isSubmitting
                ? null
                : (value) {
                    if (value == null) return;

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
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSubmitting ? null : _submitLift,
            child: Text(
              _isSubmitting ? 'Calculating...' : 'Calculate 1RM',
            ),
          ),
          if (_selectedExerciseId != null) ...[
            const SizedBox(height: 24),
            _buildSavedEstimate(
              exerciseNames[_selectedExerciseId] ?? 'Exercise',
            ),
          ],
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(
              'Your results',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ..._results.map((record) {
              // Keep each result and its percentages together.
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildResultCard(
                    record,
                    exerciseNames[record.exerciseId] ?? 'Exercise',
                  ),
                  _buildPercentageCard(record),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MaxReps'),
        actions: [
          TextButton(
            onPressed:
                _isSubmitting || widget.authState.isLoading
                    ? null
                    : widget.authState.logout,
            child: const Text('Log out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: FutureBuilder<List<Exercise>>(
                future: _exercisesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load exercises.'),
                        TextButton(
                          onPressed: _retryExercises,
                          child: const Text('Retry'),
                        ),
                      ],
                    );
                  }

                  final exercises = snapshot.data ?? const <Exercise>[];

                  if (exercises.isEmpty) {
                    return const Text('No exercises are available yet.');
                  }

                  return _buildForm(exercises);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _repsController.dispose();
    _weightController.dispose();
    super.dispose();
  }
}
