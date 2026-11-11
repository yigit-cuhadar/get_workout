import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../domain/program.dart';
import '../domain/program_usecases.dart';
import 'program_list_cubit.dart';

class AddToProgramState extends Equatable {
  const AddToProgramState({this.ready = false, this.programs = const []});

  /// The programs are known; until then none can be picked.
  final bool ready;

  /// The user's programs, by name.
  final List<Program> programs;

  @override
  List<Object?> get props => [ready, programs];
}

/// Adds an exercise to a day of one of the user's programs. The programs
/// come from the app-wide [ProgramListCubit].
class AddToProgramCubit extends Cubit<AddToProgramState> {
  AddToProgramCubit({
    required ProgramListCubit list,
    required this._addExercise,
    required this._catalogue,
    required this._getCurrentUser,
  }) : super(_of(list.state)) {
    _subscription = list.stream.listen((state) => emit(_of(state)));
  }

  final AddExerciseToProgram _addExercise;
  final ExerciseCatalogueCubit _catalogue;
  final GetCurrentUser _getCurrentUser;
  late final StreamSubscription<ProgramListState> _subscription;

  /// How long adding waits for the catalogue to know the program's
  /// exercises, custom ones included.
  static const catalogueWait = Duration(seconds: 10);

  static AddToProgramState _of(ProgramListState list) =>
      list.status == ProgramListStatus.ready
      ? AddToProgramState(ready: true, programs: list.programs)
      : const AddToProgramState();

  /// Appends [exercise] to day [dayIndex] of [program]; false when it could
  /// not be added.
  Future<bool> add(Program program, int dayIndex, Exercise exercise) async {
    final uid = _getCurrentUser()?.id;
    if (uid == null) return false;
    final ids = [
      for (final day in program.days)
        for (final item in day.items) item.exerciseId,
    ];
    bool knowsAll(ExerciseCatalogueState state) =>
        state is CatalogueReady && ids.every(state.knows);
    if (!knowsAll(_catalogue.state)) {
      try {
        await _catalogue.stream.firstWhere(knowsAll).timeout(catalogueWait);
      } on Object {
        return false;
      }
    }
    final catalogue = _catalogue.state as CatalogueReady;
    final result = await _addExercise((
      uid: uid,
      program: program,
      dayIndex: dayIndex,
      exercise: exercise,
      loggingTypes: {
        for (final e in catalogue.exercises) e.id: e.loggingType,
        exercise.id: exercise.loggingType,
      },
    ));
    if (result.failureOrNull case final failure?) {
      Log.e('programs', 'exercise not added: ${failure.message}');
    }
    return result.isOk;
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
