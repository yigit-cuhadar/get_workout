import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../../features/generator/domain/generator_answers.dart';
import '../../exercises/domain/exercise_admin_usecases.dart';
import '../../exercises/domain/exercise_draft.dart';
import '../domain/generator_rules.dart';
import '../domain/generator_rules_usecases.dart';
import '../domain/simulation.dart';

/// Which rules the simulator runs: the published ones, or the admin's
/// unpublished changes.
enum RulesSource { published, draft }

enum SimulationStatus { idle, running, done, failed }

/// A finished run: what was asked, with which rules, and what came back.
class SimulationRun extends Equatable {
  const SimulationRun({
    required this.request,
    required this.rules,
    required this.simulation,
  });

  final SimulationRequest request;

  /// The rules the program was made with.
  final GeneratorRules rules;
  final Simulation simulation;

  @override
  List<Object?> get props => [request, rules, simulation];
}

/// The simulator's answers, the rules it may run and its last run. The
/// answers are the tab's own: never part of the rules draft.
class GeneratorSimulatorState extends Equatable {
  const GeneratorSimulatorState({
    this.published,
    this.draft,
    this.source = RulesSource.published,
    this.goal = Goal.buildMuscle,
    this.level = Level.intermediate,
    this.daysPerWeek = 4,
    this.sessionMinutes = defaultSessionMinutes,
    this.equipment = EquipmentProfile.fullGym,
    this.equipmentStyle = EquipmentStyle.any,
    this.focus = const {},
    this.skip = const {},
    this.sensitive = const {},
    this.split,
    this.seed = 0,
    this.status = SimulationStatus.idle,
    this.run,
    this.failure,
    this.day = 0,
    this.openRow,
    this.names = const {},
  });

  /// The session length picked while the rules offer it.
  static const defaultSessionMinutes = 60;
  static const minDays = 2;
  static const maxDays = 6;

  /// The loaded version, when it has rules.
  final StoredRules? published;

  /// The unpublished changes, while they may be run: they differ from the
  /// loaded rules and the server found no problem in them.
  final GeneratorRules? draft;

  final RulesSource source;
  final Goal goal;
  final Level level;
  final int daysPerWeek;
  final int sessionMinutes;
  final EquipmentProfile equipment;
  final EquipmentStyle equipmentStyle;
  final Set<FocusArea> focus;

  /// Never holds an area of [focus].
  final Set<FocusArea> skip;
  final Set<SensitiveArea> sensitive;

  /// A split id of [rules]; null lets the rules choose.
  final String? split;
  final int seed;

  final SimulationStatus status;

  /// The last successful run; null after a failed one.
  final SimulationRun? run;
  final Failure? failure;

  /// The day open in the result, and the row of it opened to its score.
  final int day;
  final int? openRow;

  /// English exercise names by id, once loaded.
  final Map<String, String> names;

  /// The rules a run uses now.
  GeneratorRules? get rules => switch (source) {
    RulesSource.published => published?.rules,
    RulesSource.draft => draft,
  };

  /// The sources there are to choose from, in the order shown.
  List<RulesSource> get sources => [
    if (published?.rules != null) RulesSource.published,
    if (draft != null) RulesSource.draft,
  ];

  List<int> get sessionOptions => _sessionOptions(rules);

  /// The splits of [rules].
  List<JsonMap> get splits => rules?.splits ?? const [];

  int get maxFocus => _whole(rules?.at(['focus', 'max']));
  int get maxSkip => _whole(rules?.at(['skip', 'max']));

  bool get running => status == SimulationStatus.running;

  bool get canGenerate => rules != null && !running;

  GeneratorAnswers get answers => GeneratorAnswers(
    goal: goal,
    level: level,
    daysPerWeek: daysPerWeek,
    sessionMinutes: sessionMinutes,
    equipment: equipment.equipment,
    focus: focus,
    skip: skip,
    sensitive: sensitive,
    equipmentStyle: equipmentStyle,
    splitId: split,
  );

  GeneratorSimulatorState copyWith({
    StoredRules? Function()? published,
    GeneratorRules? Function()? draft,
    RulesSource? source,
    Goal? goal,
    Level? level,
    int? daysPerWeek,
    int? sessionMinutes,
    EquipmentProfile? equipment,
    EquipmentStyle? equipmentStyle,
    Set<FocusArea>? focus,
    Set<FocusArea>? skip,
    Set<SensitiveArea>? sensitive,
    String? Function()? split,
    int? seed,
    SimulationStatus? status,
    SimulationRun? Function()? run,
    Failure? Function()? failure,
    int? day,
    int? Function()? openRow,
    Map<String, String>? names,
  }) => GeneratorSimulatorState(
    published: published != null ? published() : this.published,
    draft: draft != null ? draft() : this.draft,
    source: source ?? this.source,
    goal: goal ?? this.goal,
    level: level ?? this.level,
    daysPerWeek: daysPerWeek ?? this.daysPerWeek,
    sessionMinutes: sessionMinutes ?? this.sessionMinutes,
    equipment: equipment ?? this.equipment,
    equipmentStyle: equipmentStyle ?? this.equipmentStyle,
    focus: focus ?? this.focus,
    skip: skip ?? this.skip,
    sensitive: sensitive ?? this.sensitive,
    split: split != null ? split() : this.split,
    seed: seed ?? this.seed,
    status: status ?? this.status,
    run: run != null ? run() : this.run,
    failure: failure != null ? failure() : this.failure,
    day: day ?? this.day,
    openRow: openRow != null ? openRow() : this.openRow,
    names: names ?? this.names,
  );

  @override
  List<Object?> get props => [
    published,
    draft,
    source,
    goal,
    level,
    daysPerWeek,
    sessionMinutes,
    equipment,
    equipmentStyle,
    focus,
    skip,
    sensitive,
    split,
    seed,
    status,
    run,
    failure,
    day,
    openRow,
    names,
  ];
}

int _whole(Object? value) => value is num ? value.toInt() : 0;

List<int> _sessionOptions(GeneratorRules? rules) => [
  for (final minutes
      in rules?.at(['time', 'sessionMinutes']) as List? ?? const [])
    if (minutes is num) minutes.toInt(),
];

/// The generator simulator (AG4): answers in, a program out with why each
/// exercise was picked, from the published rules or the unpublished ones.
class GeneratorSimulatorCubit extends Cubit<GeneratorSimulatorState> {
  GeneratorSimulatorCubit({
    required this._simulateGenerator,
    required this._watchExerciseRecords,
  }) : super(const GeneratorSimulatorState());

  final SimulateGenerator _simulateGenerator;
  final WatchExerciseRecords _watchExerciseRecords;
  StreamSubscription<List<ExerciseRecord>>? _exercises;

  /// Counts the runs: only the latest one's answer counts.
  int _turn = 0;

  @override
  Future<void> close() async {
    await _exercises?.cancel();
    return super.close();
  }

  /// The rules there are to run: [published] (the loaded version) and the
  /// [draft] while it may be run. The answers follow the chosen rules.
  void setRules({StoredRules? published, GeneratorRules? draft}) {
    final next = state.copyWith(
      published: () => published?.rules == null ? null : published,
      draft: () => draft,
    );
    final sources = next.sources;
    _emitFitted(
      next.copyWith(
        source: sources.contains(state.source)
            ? state.source
            : sources.firstOrNull,
      ),
    );
  }

  void selectSource(RulesSource source) {
    if (!state.sources.contains(source)) return;
    _emitFitted(state.copyWith(source: source));
  }

  void setGoal(Goal goal) => emit(state.copyWith(goal: goal));

  void setLevel(Level level) => emit(state.copyWith(level: level));

  void setDays(int days) => emit(
    state.copyWith(
      daysPerWeek: days.clamp(
        GeneratorSimulatorState.minDays,
        GeneratorSimulatorState.maxDays,
      ),
    ),
  );

  void setSessionMinutes(int minutes) {
    if (state.sessionOptions.contains(minutes)) {
      emit(state.copyWith(sessionMinutes: minutes));
    }
  }

  void setEquipment(EquipmentProfile equipment) =>
      emit(state.copyWith(equipment: equipment));

  void setEquipmentStyle(EquipmentStyle style) =>
      emit(state.copyWith(equipmentStyle: style));

  /// Adds or removes a focus area; one more than the rules allow is not
  /// added, and a focus area is no longer left out.
  void toggleFocus(FocusArea area) {
    if (state.focus.contains(area)) {
      emit(state.copyWith(focus: {...state.focus}..remove(area)));
    } else if (state.focus.length < state.maxFocus) {
      emit(
        state.copyWith(
          focus: {...state.focus, area},
          skip: {...state.skip}..remove(area),
        ),
      );
    }
  }

  /// Adds or removes an area to leave out; never one in focus, nor more
  /// than the rules allow.
  void toggleSkip(FocusArea area) {
    if (state.skip.contains(area)) {
      emit(state.copyWith(skip: {...state.skip}..remove(area)));
    } else if (!state.focus.contains(area) &&
        state.skip.length < state.maxSkip) {
      emit(state.copyWith(skip: {...state.skip, area}));
    }
  }

  void toggleSensitive(SensitiveArea area) => emit(
    state.copyWith(
      sensitive: state.sensitive.contains(area)
          ? ({...state.sensitive}..remove(area))
          : {...state.sensitive, area},
    ),
  );

  /// A split of the chosen rules, or null to let them choose.
  void setSplit(String? split) {
    if (split == null || state.splits.any((s) => s['id'] == split)) {
      emit(state.copyWith(split: () => split));
    }
  }

  void setSeed(int seed) => emit(state.copyWith(seed: seed));

  void selectDay(int day) =>
      emit(state.copyWith(day: day, openRow: () => null));

  /// Opens [row] of the open day to its score, or closes it when open.
  void toggleRow(int row) =>
      emit(state.copyWith(openRow: () => state.openRow == row ? null : row));

  /// Runs the answers through the chosen rules; the result replaces the
  /// last one.
  Future<void> generate() async {
    final rules = state.rules;
    if (rules == null || state.running) return;
    _watchNames();
    final request = SimulationRequest(
      answers: state.answers,
      seed: state.seed,
      rules: state.source == RulesSource.draft ? rules : null,
    );
    final turn = ++_turn;
    emit(state.copyWith(status: SimulationStatus.running, failure: () => null));
    final result = await _simulateGenerator(request);
    if (isClosed || turn != _turn) return;
    switch (result) {
      case Ok(value: final simulation):
        emit(
          state.copyWith(
            status: SimulationStatus.done,
            run: () => SimulationRun(
              request: request,
              rules: rules,
              simulation: simulation,
            ),
            day: 0,
            openRow: () => null,
          ),
        );
      case Err(:final failure):
        emit(
          state.copyWith(
            status: SimulationStatus.failed,
            run: () => null,
            failure: () => failure,
          ),
        );
    }
  }

  /// The exercise names, from the first run on; a failed load leaves the
  /// ids.
  void _watchNames() {
    _exercises ??= _watchExerciseRecords().listen(
      (records) => emit(
        state.copyWith(
          names: {for (final record in records) record.id: record.draft.name},
        ),
      ),
      onError: (Object _) {},
    );
  }

  /// [next] with its answers fitted to its rules: a session length and a
  /// split they offer, and no more focus or left-out areas than they allow.
  void _emitFitted(GeneratorSimulatorState next) {
    if (next.rules == null) return emit(next);
    final sessions = next.sessionOptions;
    final split = next.split;
    emit(
      next.copyWith(
        sessionMinutes:
            sessions.isEmpty || sessions.contains(next.sessionMinutes)
            ? next.sessionMinutes
            : sessions.contains(GeneratorSimulatorState.defaultSessionMinutes)
            ? GeneratorSimulatorState.defaultSessionMinutes
            : sessions[sessions.length ~/ 2],
        split: () => split != null && next.splits.any((s) => s['id'] == split)
            ? split
            : null,
        focus: next.focus.take(next.maxFocus).toSet(),
        skip: next.skip.take(next.maxSkip).toSet(),
      ),
    );
  }
}
