import 'dart:async';

import 'package:flutter/material.dart';
import 'package:max_reps_frontend/models/exercise.dart';
import 'package:max_reps_frontend/models/lift_record.dart';
import 'package:max_reps_frontend/services/api_client.dart';
import 'package:max_reps_frontend/services/lift_record_service.dart';
import 'package:max_reps_frontend/state/auth_state.dart';
import 'package:max_reps_frontend/theme/app_theme.dart';
import 'package:max_reps_frontend/widgets/exercise_autocomplete.dart';
import 'package:max_reps_frontend/widgets/lift_history_card.dart';

class TrainingZonePage extends StatefulWidget {
  final AuthState authState;
  final LiftRecordService liftRecordService;
  final VoidCallback onAddLift;
  const TrainingZonePage({
    super.key,
    required this.authState,
    required this.liftRecordService,
    required this.onAddLift,
  });

  @override
  State<TrainingZonePage> createState() => TrainingZonePageState();
}

class TrainingZonePageState extends State<TrainingZonePage> {
  List<Exercise> _exercises = [];
  List<LiftRecord> _records = [];
  Exercise? _selected;
  String _unit = 'lb';
  String get unit => _unit;
  bool _loadingExercises = true;
  bool _loadingHistory = false;
  String? _exerciseError;
  String? _historyError;
  int _exerciseRequest = 0;
  int _historyRequest = 0;
  int _searchRevision = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  Future<void> reload({int? selectExerciseId, String? unit}) async {
    final token = widget.authState.accessToken;
    if (token == null) return;
    final request = ++_exerciseRequest;
    _historyRequest++;
    final preferredId = selectExerciseId ?? _selected?.id;
    setState(() {
      _loadingExercises = true;
      _loadingHistory = false;
      _exerciseError = null;
      _historyError = null;
      if (unit != null) _unit = unit;
    });
    try {
      final exercises = await widget.liftRecordService.getLoggedExercises(
        accessToken: token,
      );
      if (!mounted || request != _exerciseRequest) return;
      Exercise? selected;
      for (final exercise in exercises) {
        if (exercise.id == preferredId) selected = exercise;
      }
      selected ??= exercises.isEmpty ? null : exercises.first;
      setState(() {
        _exercises = exercises;
        _selected = selected;
        _records = [];
        _loadingExercises = false;
        _searchRevision++;
      });
      if (selected != null) await _loadHistory();
    } catch (error) {
      if (!mounted || request != _exerciseRequest) return;
      if (await _expireSession(error)) return;
      if (mounted) {
        setState(() {
          _loadingExercises = false;
          _exerciseError =
              'Could not load your logged exercises. Please try again.';
        });
      }
    }
  }

  Future<bool> _expireSession(Object error) async {
    if (error is ApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      await widget.authState.logout();
      return true;
    }
    return false;
  }

  Future<void> _loadHistory() async {
    final selected = _selected;
    final token = widget.authState.accessToken;
    if (selected == null || token == null) return;
    final request = ++_historyRequest;
    final unit = _unit;
    setState(() {
      _loadingHistory = true;
      _historyError = null;
      _records = [];
    });
    try {
      final records = await widget.liftRecordService.getLiftRecords(
        accessToken: token,
        exerciseId: selected.id,
        unit: unit,
        limit: 5,
      );
      if (!mounted || request != _historyRequest) return;
      setState(() {
        _records = records;
      });
    } catch (error) {
      if (!mounted || request != _historyRequest) return;
      if (await _expireSession(error)) return;
      if (mounted) {
        setState(() {
          _historyError = error is ApiException && error.statusCode == 429
              ? 'Too many requests. Please wait before trying again.'
              : 'Could not load your lift records. Please try again.';
        });
      }
    } finally {
      if (mounted && request == _historyRequest) {
        setState(() {
          _loadingHistory = false;
        });
      }
    }
  }

  void _clearSelection() {
    _historyRequest++; // Ignore an older response if the user edits the search.
    setState(() {
      _selected = null;
      _records = [];
      _historyError = null;
      _loadingHistory = false;
    });
  }

  Widget _empty() => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFE5F4F3),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fitness_center_rounded,
              color: AppColors.deepAqua,
              size: 36,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Nothing Logged.',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: widget.onAddLift,
            icon: const Icon(Icons.add_rounded),
            label: const Text('To Add A Lift'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 120),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'YOUR TRAINING',
              style: TextStyle(
                color: AppColors.deepAqua,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Training Zone',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 10),
            const Text('Your last five lifts. Your next session.'),
            const SizedBox(height: 28),
            if (_loadingExercises)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_exerciseError != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(_exerciseError!),
                      TextButton(
                        onPressed: reload,
                        child: const Text('Retry logged exercises'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_exercises.isEmpty)
              _empty()
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final search = ExerciseAutocomplete(
                        key: ValueKey(_searchRevision),
                        exercises: _exercises,
                        selected: _selected,
                        label: 'Search your logged exercises',
                        requiredSelection: false,
                        onSelected: (exercise) {
                          setState(() {
                            _selected = exercise;
                          });
                          unawaited(_loadHistory());
                        },
                        onCleared: _clearSelection,
                      );
                      final units = DropdownButtonFormField<String>(
                        initialValue: _unit,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Unit'),
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
                        onChanged: (value) {
                          if (value == null || value == _unit) return;
                          setState(() {
                            _unit = value;
                          });
                          unawaited(_loadHistory());
                        },
                      );
                      if (constraints.maxWidth < 600) {
                        return Column(
                          children: [search, const SizedBox(height: 16), units],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: search),
                          const SizedBox(width: 18),
                          SizedBox(width: 180, child: units),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 28),
              if (_selected == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'Choose one of your logged exercises from the suggestions.',
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selected!.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh records',
                      onPressed: _loadingHistory ? null : _loadHistory,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Estimated 1RM · newest first · expand a record for training splits',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                if (_loadingHistory)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_historyError != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(_historyError!),
                          TextButton(
                            onPressed: _loadHistory,
                            child: const Text('Retry records'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_records.isEmpty)
                  _empty()
                else
                  for (var index = 0; index < _records.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: LiftHistoryCard(
                        key: ValueKey('${_records[index].id}-$_unit'),
                        record: _records[index],
                        initiallyExpanded: index == 0,
                      ),
                    ),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}
