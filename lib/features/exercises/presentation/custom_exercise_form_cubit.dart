import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/custom_exercise.dart';
import '../domain/exercise_usecases.dart';
import '../domain/vocabulary.dart';

enum CustomExerciseFormStatus {
  editing,
  saving,

  /// Final, like [closed]: the form closes and writes nothing more.
  saved,
  saveFailed,

  /// The signed-in user changed; the form must close.
  closed,
}

class CustomExerciseFormState extends Equatable {
  const CustomExerciseFormState({
    this.name = '',
    this.loggingType = LoggingType.weightReps,
    this.mainMuscles = const {},
    this.secondaryMuscles = const {},
    this.equipment = const {},
    this.note = '',
    this.issues = const {},
    this.status = CustomExerciseFormStatus.editing,
    this.failure,
  });

  /// As typed.
  final String name;
  final LoggingType loggingType;

  /// Never sharing a muscle with [secondaryMuscles].
  final Set<Muscle> mainMuscles;
  final Set<Muscle> secondaryMuscles;

  /// Bodyweight is only ever chosen alone.
  final Set<Equipment> equipment;
  final String note;

  /// Shown once a save was attempted, then kept up to date.
  final Set<CustomExerciseIssue> issues;
  final CustomExerciseFormStatus status;
  final Failure? failure;

  bool get isSaving => status == CustomExerciseFormStatus.saving;

  /// Saved or closed: nothing changes any more.
  bool get isDone =>
      status == CustomExerciseFormStatus.saved ||
      status == CustomExerciseFormStatus.closed;

  CustomExerciseFormState copyWith({
    String? name,
    LoggingType? loggingType,
    Set<Muscle>? mainMuscles,
    Set<Muscle>? secondaryMuscles,
    Set<Equipment>? equipment,
    String? note,
    Set<CustomExerciseIssue>? issues,
    CustomExerciseFormStatus? status,
    Failure? failure,
  }) => CustomExerciseFormState(
    name: name ?? this.name,
    loggingType: loggingType ?? this.loggingType,
    mainMuscles: mainMuscles ?? this.mainMuscles,
    secondaryMuscles: secondaryMuscles ?? this.secondaryMuscles,
    equipment: equipment ?? this.equipment,
    note: note ?? this.note,
    issues: issues ?? this.issues,
    status: status ?? this.status,
    failure: failure,
  );

  @override
  List<Object?> get props => [
    name,
    loggingType,
    mainMuscles,
    secondaryMuscles,
    equipment,
    note,
    issues,
    status,
    failure,
  ];
}

/// Creates a custom exercise, or edits [initial]. Closes when the signed-in
/// user changes, so it never shows or writes another user's exercise.
class CustomExerciseFormCubit extends Cubit<CustomExerciseFormState> {
  CustomExerciseFormCubit({
    required this._saveExercise,
    required GetCurrentUser getCurrentUser,
    required WatchAuthUser watchAuthUser,
    this._initial,
  }) : _getCurrentUser = getCurrentUser,
       _uid = getCurrentUser()?.id,
       super(_initialState(_initial)) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          if (uid != _uid && !state.isDone) {
            emit(state.copyWith(status: CustomExerciseFormStatus.closed));
          }
        });
  }

  final SaveCustomExercise _saveExercise;
  final GetCurrentUser _getCurrentUser;
  final CustomExercise? _initial;

  /// The user the form was opened for.
  final String? _uid;
  late final StreamSubscription<String?> _userSubscription;
  bool _submitted = false;

  bool get isEditing => _initial?.id != null;

  /// Inputs a navigation away would lose; none once saved or closed.
  bool get hasChanges =>
      !state.isDone &&
      state.copyWith(
            issues: const {},
            status: CustomExerciseFormStatus.editing,
          ) !=
          _initialState(_initial);

  static CustomExerciseFormState _initialState(CustomExercise? exercise) =>
      exercise == null
      ? const CustomExerciseFormState()
      : CustomExerciseFormState(
          name: exercise.name,
          loggingType: exercise.loggingType,
          mainMuscles: exercise.mainMuscles.toSet(),
          secondaryMuscles: exercise.secondaryMuscles.toSet(),
          equipment: exercise.equipment.toSet(),
          note: exercise.note ?? '',
        );

  void setName(String name) => _change(state.copyWith(name: name));

  void setLoggingType(LoggingType type) =>
      _change(state.copyWith(loggingType: type));

  /// Choosing a main muscle takes it off the secondary ones.
  void toggleMainMuscle(Muscle muscle) => _change(
    state.copyWith(
      mainMuscles: _toggle(state.mainMuscles, muscle),
      secondaryMuscles: {...state.secondaryMuscles}..remove(muscle),
    ),
  );

  /// Choosing a secondary muscle takes it off the main ones.
  void toggleSecondaryMuscle(Muscle muscle) => _change(
    state.copyWith(
      secondaryMuscles: _toggle(state.secondaryMuscles, muscle),
      mainMuscles: {...state.mainMuscles}..remove(muscle),
    ),
  );

  /// Bodyweight means no equipment, so choosing it clears the rest and
  /// choosing anything else clears it.
  void toggleEquipment(Equipment item) {
    final selected = _toggle(state.equipment, item);
    if (selected.contains(item)) {
      if (item == Equipment.bodyweight) {
        selected.retainWhere((other) => other == item);
      } else {
        selected.remove(Equipment.bodyweight);
      }
    }
    _change(state.copyWith(equipment: selected));
  }

  void setNote(String note) => _change(state.copyWith(note: note));

  void _change(CustomExerciseFormState next) {
    if (state.isDone) return;
    final editing = next.copyWith(status: CustomExerciseFormStatus.editing);
    emit(
      _submitted
          ? editing.copyWith(issues: validateCustomExercise(_exercise(editing)))
          : editing,
    );
  }

  Future<void> save() async {
    if (state.isSaving || state.isDone) return;
    _submitted = true;
    final exercise = _exercise(state);
    final issues = validateCustomExercise(exercise);
    if (issues.isNotEmpty) {
      emit(
        state.copyWith(
          issues: issues,
          status: CustomExerciseFormStatus.editing,
        ),
      );
      return;
    }
    final uid = _getCurrentUser()?.id;
    if (uid == null || uid != _uid) {
      emit(state.copyWith(status: CustomExerciseFormStatus.closed));
      return;
    }
    emit(
      state.copyWith(status: CustomExerciseFormStatus.saving, issues: const {}),
    );
    final failure = (await _saveExercise((uid: uid, exercise: exercise)))
        .failureOrNull;
    if (isClosed || state.isDone) return;
    emit(
      failure == null
          ? state.copyWith(status: CustomExerciseFormStatus.saved)
          : state.copyWith(
              status: CustomExerciseFormStatus.saveFailed,
              failure: failure,
            ),
    );
  }

  /// The exercise the inputs describe, in the vocabulary's order; the use
  /// case trims the name and note.
  CustomExercise _exercise(CustomExerciseFormState input) => CustomExercise(
    id: _initial?.id,
    name: input.name,
    loggingType: input.loggingType,
    mainMuscles: _ordered(Muscle.values, input.mainMuscles),
    secondaryMuscles: _ordered(Muscle.values, input.secondaryMuscles),
    equipment: _ordered(Equipment.values, input.equipment),
    note: input.note,
  );

  static List<T> _ordered<T>(List<T> values, Set<T> selected) => [
    for (final value in values)
      if (selected.contains(value)) value,
  ];

  static Set<T> _toggle<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    return super.close();
  }
}
