import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/program.dart';
import '../../../core/grouping.dart' as editing;
import '../domain/program_editing.dart' as editing;
import '../domain/program_usecases.dart';
import '../domain/program_validation.dart';

enum ProgramBuilderStatus {
  loading,
  editing,
  saving,
  saved,
  saveFailed,

  /// The program to edit does not exist (any more).
  notFound,
  loadFailed,

  /// The signed-in user changed; the builder must close.
  closed,
}

class ProgramBuilderState extends Equatable {
  const ProgramBuilderState({
    this.status = ProgramBuilderStatus.loading,
    required this.program,
    this.selectedDay = 0,
    this.exercises = const {},
    this.catalogueReady = false,
    this.customExercisesReady = false,
    this.validation = const ProgramValidation(),
    this.dirty = false,
    this.failure,
    this.savedId,
    this.adjusted = const [],
  });

  final ProgramBuilderStatus status;

  /// The program as edited so far.
  final Program program;

  /// The day whose items are shown.
  final int selectedDay;

  /// The live catalogue by id; an item whose exercise is missing is
  /// unavailable.
  final Map<String, Exercise> exercises;

  /// Until the catalogue is known no item counts as unavailable.
  final bool catalogueReady;

  /// Until the user's custom exercises are known in [exercises] no item of
  /// a custom exercise counts as unavailable.
  final bool customExercisesReady;

  /// Shown once a save was attempted, then kept up to date.
  final ProgramValidation validation;

  /// The program differs from what was loaded (or from an empty one).
  final bool dirty;
  final Failure? failure;

  /// The stored program's id after [ProgramBuilderStatus.saved].
  final String? savedId;

  /// Exercises whose items were changed on load to fit their exercise's
  /// current logging type; tell the user, then call
  /// [ProgramBuilderCubit.adjustedShown].
  final List<String> adjusted;

  ProgramDay? get day => program.days.elementAtOrNull(selectedDay);

  int get freeSlots => ProgramLimits.maxItemsPerDay - (day?.items.length ?? 0);

  bool get canAddDay => program.days.length < ProgramLimits.maxDays;

  bool isUnavailable(ProgramItem item) =>
      _knows(item.exerciseId) && !exercises.containsKey(item.exerciseId);

  bool _knows(String exerciseId) =>
      catalogueReady &&
      (customExercisesReady || !Exercise.isCustomId(exerciseId));

  /// Whether every item's exercise is known to exist or not, so the program
  /// can be validated.
  bool get canResolve =>
      catalogueReady &&
      program.days.every(
        (day) => day.items.every((item) => _knows(item.exerciseId)),
      );

  /// What is wrong with item [index] of the selected day right now, for the
  /// item editor, whether or not a save was attempted.
  Set<ItemIssue> liveItemIssues(int index) {
    final item = day?.items.elementAtOrNull(index);
    if (item == null) return const {};
    return validateItem(item, exercises[item.exerciseId]?.loggingType);
  }

  bool get isBusy => status == ProgramBuilderStatus.saving;

  ProgramBuilderState copyWith({
    ProgramBuilderStatus? status,
    Program? program,
    int? selectedDay,
    Map<String, Exercise>? exercises,
    bool? catalogueReady,
    bool? customExercisesReady,
    ProgramValidation? validation,
    bool? dirty,
    Failure? failure,
    String? savedId,
    List<String>? adjusted,
  }) => ProgramBuilderState(
    status: status ?? this.status,
    program: program ?? this.program,
    selectedDay: selectedDay ?? this.selectedDay,
    exercises: exercises ?? this.exercises,
    catalogueReady: catalogueReady ?? this.catalogueReady,
    customExercisesReady: customExercisesReady ?? this.customExercisesReady,
    validation: validation ?? this.validation,
    dirty: dirty ?? this.dirty,
    failure: failure,
    savedId: savedId ?? this.savedId,
    adjusted: adjusted ?? this.adjusted,
  );

  @override
  List<Object?> get props => [
    status,
    program,
    selectedDay,
    exercises,
    catalogueReady,
    customExercisesReady,
    validation,
    dirty,
    failure,
    savedId,
    adjusted,
  ];
}

/// Creates a program, or edits program [programId]. Target weights are typed
/// in [weightUnit] and stored in kg. Closes when the signed-in user changes,
/// so it never shows or writes another user's program.
class ProgramBuilderCubit extends Cubit<ProgramBuilderState> {
  ProgramBuilderCubit({
    this.programId,
    required this._getProgram,
    required this._saveProgram,
    required GetCurrentUser getCurrentUser,
    required WatchAuthUser watchAuthUser,
    required ExerciseCatalogueCubit catalogue,
    required this.weightUnit,
  }) : _uid = getCurrentUser()?.id,
       _getCurrentUser = getCurrentUser,
       super(
         ProgramBuilderState(
           status: programId == null
               ? ProgramBuilderStatus.editing
               : ProgramBuilderStatus.loading,
           program: _empty,
         ),
       ) {
    _onCatalogue(catalogue.state);
    _catalogueSubscription = catalogue.stream.listen(_onCatalogue);
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          if (uid != _uid) _close();
        });
    if (programId != null) unawaited(load());
  }

  final String? programId;
  final WeightUnit weightUnit;
  final GetProgram _getProgram;
  final SaveProgram _saveProgram;
  final GetCurrentUser _getCurrentUser;

  /// The user the builder was opened for.
  final String? _uid;
  late final StreamSubscription<ExerciseCatalogueState> _catalogueSubscription;
  late final StreamSubscription<String?> _userSubscription;

  /// What [ProgramBuilderState.dirty] compares against.
  Program _initial = _empty;
  bool _submitted = false;
  bool _fittedCatalogue = false;
  bool _fittedCustom = false;

  static const _empty = Program(name: '', days: [ProgramDay()]);

  bool get isEditing => programId != null;

  bool get _closed => state.status == ProgramBuilderStatus.closed;

  /// Loads the program to edit; again after a failure.
  Future<void> load() async {
    final id = programId;
    final uid = _uid;
    if (id == null || _closed) return;
    if (uid == null) return _close();
    emit(state.copyWith(status: ProgramBuilderStatus.loading));
    final result = await _getProgram((uid: uid, id: id));
    if (isClosed || _closed) return;
    switch (result) {
      case Ok(:final value):
        _initial = value.days.isEmpty
            ? value.copyWith(days: const [ProgramDay()])
            : value;
        emit(
          state.copyWith(
            status: ProgramBuilderStatus.editing,
            program: _initial,
            selectedDay: 0,
            dirty: false,
          ),
        );
        _fitToExercises();
      case Err(failure: NotFoundFailure()):
        emit(state.copyWith(status: ProgramBuilderStatus.notFound));
      case Err(:final failure):
        emit(
          state.copyWith(
            status: ProgramBuilderStatus.loadFailed,
            failure: failure,
          ),
        );
    }
  }

  void _onCatalogue(ExerciseCatalogueState catalogue) {
    if (catalogue is! CatalogueReady || _closed) return;
    final exercises = {for (final e in catalogue.exercises) e.id: e};
    emit(
      state.copyWith(
        exercises: exercises,
        catalogueReady: true,
        customExercisesReady: catalogue.customLoaded,
        validation: _submitted ? _validate(state.program, exercises) : null,
      ),
    );
    _fitToExercises();
  }

  void adjustedShown() => emit(state.copyWith(adjusted: const []));

  /// Once a stored program and the catalogue are both known, fits every item
  /// to its exercise's logging type, which an admin (or the user, for a
  /// custom exercise) may have changed since the program was saved. Items
  /// of custom exercises are fitted once those arrive, which can be later.
  /// The program is then unsaved.
  void _fitToExercises() {
    if (!isEditing ||
        !state.catalogueReady ||
        state.status != ProgramBuilderStatus.editing) {
      return;
    }
    final fitCatalogue = !_fittedCatalogue;
    final fitCustom = !_fittedCustom && state.customExercisesReady;
    if (!fitCatalogue && !fitCustom) return;
    _fittedCatalogue = true;
    if (fitCustom) _fittedCustom = true;
    bool due(ProgramItem item) =>
        Exercise.isCustomId(item.exerciseId) ? fitCustom : fitCatalogue;
    final adjusted = <String>{};
    final days = [
      for (final day in state.program.days)
        day.copyWith(
          items: [
            for (final item in day.items)
              switch (due(item) ? state.exercises[item.exerciseId] : null) {
                null => item,
                final exercise => () {
                  final fitted = editing.fitToLoggingType(
                    item,
                    exercise.loggingType,
                  );
                  if (!identical(fitted, item)) adjusted.add(item.exerciseId);
                  return fitted;
                }(),
              },
          ],
        ),
    ];
    if (adjusted.isEmpty) return;
    _edit(state.program.copyWith(days: days));
    emit(state.copyWith(adjusted: {...state.adjusted, ...adjusted}.toList()));
  }

  void setName(String name) => _edit(state.program.copyWith(name: name));

  /// Empty for a program without a set length.
  void setLengthWeeks(String text) {
    final trimmed = text.trim();
    _edit(
      state.program.copyWith(
        lengthWeeks: () => trimmed.isEmpty ? null : int.tryParse(trimmed) ?? 0,
      ),
    );
  }

  void selectDay(int index) {
    if (index < 0 || index >= state.program.days.length) return;
    emit(state.copyWith(selectedDay: index));
  }

  /// Adds an empty day and selects it.
  void addDay() {
    if (!state.canAddDay) return;
    final days = [...state.program.days, const ProgramDay()];
    _edit(state.program.copyWith(days: days), selectedDay: days.length - 1);
  }

  void renameDay(int index, String name) =>
      _editDay(index, (day) => day.copyWith(name: name));

  /// The moved day stays selected.
  void moveDay(int from, int to) {
    final days = [...state.program.days];
    if (from < 0 || from >= days.length || to < 0 || to >= days.length) {
      return;
    }
    days.insert(to, days.removeAt(from));
    _edit(state.program.copyWith(days: days), selectedDay: to);
  }

  /// A program keeps at least one day.
  void deleteDay(int index) {
    final days = [...state.program.days];
    if (days.length <= 1 || index < 0 || index >= days.length) return;
    days.removeAt(index);
    final selected = state.selectedDay;
    _edit(
      state.program.copyWith(days: days),
      selectedDay: selected > index || selected == days.length
          ? selected - 1
          : selected,
    );
  }

  /// Adds [exercises] to the selected day with default targets, as many as
  /// fit.
  void addExercises(List<Exercise> exercises) => _editItems(
    (items) => [
      ...items,
      for (final exercise in exercises.take(state.freeSlots))
        editing.defaultItem(exercise),
    ],
  );

  void replaceExercise(int index, Exercise exercise) => _editItems(
    (items) => [
      for (final (i, item) in items.indexed)
        i == index ? editing.replaceExercise(item, exercise) : item,
    ],
  );

  void removeItem(int index) =>
      _editItems((items) => editing.removeItem(items, index));

  /// [to] is where the item lands; see [editing.moveItem].
  void moveItem(int from, int to) =>
      _editItems((items) => editing.moveItem(items, from, to));

  void linkWithNext(int index) => _editItems(
    (items) => editing.canLinkWithNext(items, index)
        ? editing.linkWithNext(items, index)
        : items,
  );

  void ungroup(int index) =>
      _editItems((items) => editing.ungroup(items, index));

  /// A blank or unreadable count reads as 0, which is invalid.
  void setSets(int index, String text) =>
      _editItem(index, (item) => item.copyWith(sets: _whole(text) ?? 0));

  void setRepMin(int index, String text) =>
      _editItem(index, (item) => item.copyWith(repMin: () => _whole(text)));

  void setRepMax(int index, String text) =>
      _editItem(index, (item) => item.copyWith(repMax: () => _whole(text)));

  /// In seconds.
  void setDuration(int index, String text) =>
      _editItem(index, (item) => item.copyWith(durationS: () => _whole(text)));

  /// In seconds; blank is no rest.
  void setRest(int index, String text) =>
      _editItem(index, (item) => item.copyWith(restS: _whole(text) ?? 0));

  /// In [weightUnit]; blank removes the target.
  void setTarget(int index, String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    _editItem(
      index,
      (item) => item.copyWith(
        targetKg: () =>
            value == null || !value.isFinite ? null : weightUnit.toKg(value),
      ),
    );
  }

  Future<void> save() async {
    if (!state.canResolve ||
        (state.status != ProgramBuilderStatus.editing &&
            state.status != ProgramBuilderStatus.saveFailed)) {
      return;
    }
    _submitted = true;
    final validation = _validate(state.program, state.exercises);
    if (!validation.isValid) {
      final firstBadDay = {
        ...validation.days.keys,
        for (final ref in validation.items.keys) ref.day,
      }.fold<int?>(null, (min, day) => min == null || day < min ? day : min);
      emit(
        state.copyWith(
          status: ProgramBuilderStatus.editing,
          validation: validation,
          selectedDay: validation.program.isEmpty ? firstBadDay : null,
        ),
      );
      return;
    }
    final uid = _getCurrentUser()?.id;
    if (uid == null || uid != _uid) return _close();
    emit(
      state.copyWith(
        status: ProgramBuilderStatus.saving,
        validation: validation,
      ),
    );
    final result = await _saveProgram((
      uid: uid,
      program: state.program,
      loggingTypes: _loggingTypes(state.exercises),
    ));
    if (isClosed || _closed) return;
    switch (result) {
      case Ok(:final value):
        emit(
          state.copyWith(
            status: ProgramBuilderStatus.saved,
            savedId: value,
            dirty: false,
          ),
        );
      case Err(:final failure):
        emit(
          state.copyWith(
            status: ProgramBuilderStatus.saveFailed,
            failure: failure,
          ),
        );
    }
  }

  void _editDay(int index, ProgramDay Function(ProgramDay day) change) {
    final days = state.program.days;
    if (index < 0 || index >= days.length) return;
    _edit(
      state.program.copyWith(
        days: [
          for (final (i, day) in days.indexed) i == index ? change(day) : day,
        ],
      ),
    );
  }

  void _editItems(List<ProgramItem> Function(List<ProgramItem> items) change) =>
      _editDay(
        state.selectedDay,
        (day) => day.copyWith(items: change(day.items)),
      );

  void _editItem(int index, ProgramItem Function(ProgramItem item) change) =>
      _editItems(
        (items) => [
          for (final (i, item) in items.indexed)
            i == index ? change(item) : item,
        ],
      );

  void _edit(Program program, {int? selectedDay}) {
    // Only a shown program can change.
    if (state.status != ProgramBuilderStatus.editing &&
        state.status != ProgramBuilderStatus.saveFailed) {
      return;
    }
    emit(
      state.copyWith(
        status: ProgramBuilderStatus.editing,
        program: program,
        selectedDay: selectedDay,
        dirty: program != _initial,
        validation: _submitted ? _validate(program, state.exercises) : null,
      ),
    );
  }

  ProgramValidation _validate(
    Program program,
    Map<String, Exercise> exercises,
  ) => validateProgram(program, _loggingTypes(exercises));

  static Map<String, LoggingType> _loggingTypes(
    Map<String, Exercise> exercises,
  ) => {
    for (final MapEntry(:key, :value) in exercises.entries)
      key: value.loggingType,
  };

  static int? _whole(String text) {
    final value = int.tryParse(text.trim());
    // Text fields cap the length; this guards pasted text.
    return value == null || value.abs() > 1000000 ? null : value;
  }

  void _close() {
    if (!_closed) emit(state.copyWith(status: ProgramBuilderStatus.closed));
  }

  @override
  Future<void> close() async {
    await _catalogueSubscription.cancel();
    await _userSubscription.cancel();
    return super.close();
  }
}
