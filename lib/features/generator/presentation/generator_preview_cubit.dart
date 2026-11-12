import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../programs/domain/program_usecases.dart';
import '../domain/generator_answers.dart';
import '../domain/generator_usecases.dart';
import '../domain/program_generator.dart';

enum PreviewStatus {
  /// The exercise library or the program is on its way.
  loading,
  ready,

  /// No program can be made from the answers; see
  /// [GeneratorPreviewState.issue].
  impossible,

  /// The exercise library could not be loaded.
  libraryFailed,
}

enum SaveStatus { idle, saving, saved, failed }

class GeneratorPreviewState extends Equatable {
  const GeneratorPreviewState({
    this.status = PreviewStatus.loading,
    this.program,
    this.issue,
    this.seed = 0,
    this.saveStatus = SaveStatus.idle,
    this.savedId,
    this.saveFailure,
  });

  final PreviewStatus status;

  /// Only when [status] is ready.
  final GeneratedProgram? program;

  /// Only when [status] is impossible.
  final GenerationIssue? issue;

  /// What [program] was made with; Regenerate takes the next.
  final int seed;
  final SaveStatus saveStatus;

  /// The stored program, once saved.
  final String? savedId;

  /// Why the last save failed: an [AuthFailure] while nobody is signed
  /// in, a [NotFoundFailure] while the library reloads, or the store's.
  final Failure? saveFailure;

  GeneratorPreviewState copyWith({
    SaveStatus? saveStatus,
    String? savedId,
    Failure? Function()? saveFailure,
  }) => GeneratorPreviewState(
    status: status,
    program: program,
    issue: issue,
    seed: seed,
    saveStatus: saveStatus ?? this.saveStatus,
    savedId: savedId ?? this.savedId,
    saveFailure: saveFailure != null ? saveFailure() : this.saveFailure,
  );

  @override
  List<Object?> get props => [
    status,
    program,
    issue,
    seed,
    saveStatus,
    savedId,
    saveFailure,
  ];
}

/// The program generated from [answers], made again on Regenerate with the
/// next seed, and storing it as one of the user's programs. Waits for the
/// exercise library; later library changes leave the program on screen,
/// and saving validates it against the library as it is then.
class GeneratorPreviewCubit extends Cubit<GeneratorPreviewState> {
  GeneratorPreviewCubit(
    this.answers, {
    required this._catalogue,
    required this._generateProgram,
    required this._saveProgram,
    required this._getCurrentUser,
  }) : super(const GeneratorPreviewState()) {
    _subscription = _catalogue.stream.listen(_onCatalogue);
    _onCatalogue(_catalogue.state);
  }

  final GeneratorAnswers answers;
  final ExerciseCatalogueCubit _catalogue;
  final GenerateProgram _generateProgram;
  final SaveProgram _saveProgram;
  final GetCurrentUser _getCurrentUser;
  late final StreamSubscription<ExerciseCatalogueState> _subscription;
  bool _generating = false;

  /// Makes another program from the same answers.
  Future<void> regenerate() async {
    if (state.status != PreviewStatus.ready ||
        state.saveStatus == SaveStatus.saving) {
      return;
    }
    await _generate(state.seed + 1);
  }

  /// Tries the exercise library again after it failed to load.
  Future<void> retry() => _catalogue.retry();

  /// Stores the program on screen named [name], its days by [dayName].
  Future<void> save({
    required String name,
    required String Function(GeneratedDay day) dayName,
  }) async {
    final program = state.program;
    final uid = _getCurrentUser()?.id;
    final library = _catalogue.state;
    if (program == null ||
        state.saveStatus == SaveStatus.saving ||
        state.saveStatus == SaveStatus.saved) {
      return;
    }
    // Both pass quickly: the user changes, or the library reloads.
    if (uid == null || library is! CatalogueReady) {
      emit(
        state.copyWith(
          saveStatus: SaveStatus.failed,
          saveFailure: () => uid == null
              ? const AuthFailure('nobody is signed in')
              : const NotFoundFailure('the exercise library is loading'),
        ),
      );
      return;
    }
    emit(
      state.copyWith(saveStatus: SaveStatus.saving, saveFailure: () => null),
    );
    final result = await _saveProgram((
      uid: uid,
      program: program.toProgram(name: name, dayName: dayName),
      loggingTypes: {
        for (final exercise in library.exercises)
          exercise.id: exercise.loggingType,
      },
    ));
    if (isClosed) return;
    emit(
      result.fold(
        (id) => state.copyWith(saveStatus: SaveStatus.saved, savedId: id),
        (failure) => state.copyWith(
          saveStatus: SaveStatus.failed,
          saveFailure: () => failure,
        ),
      ),
    );
  }

  /// The page has shown the failure.
  void saveFailureShown() => emit(
    state.copyWith(saveStatus: SaveStatus.idle, saveFailure: () => null),
  );

  void _onCatalogue(ExerciseCatalogueState library) {
    // Answers that give no program give none with a newer library either.
    if (state.program != null || state.status == PreviewStatus.impossible) {
      return;
    }
    switch (library) {
      case CatalogueReady():
        unawaited(_generate(state.seed));
      case CatalogueFailed():
        emit(const GeneratorPreviewState(status: PreviewStatus.libraryFailed));
      case CatalogueLoading():
        if (state.status != PreviewStatus.loading) {
          emit(const GeneratorPreviewState());
        }
    }
  }

  Future<void> _generate(int seed) async {
    final library = _catalogue.state;
    if (library is! CatalogueReady || _generating) return;
    _generating = true;
    final result = await _generateProgram((
      answers: answers,
      exercises: library.exercises,
      seed: seed,
    ));
    _generating = false;
    if (isClosed) return;
    emit(
      result.fold(
        (program) => GeneratorPreviewState(
          status: PreviewStatus.ready,
          program: program,
          seed: seed,
        ),
        (failure) => GeneratorPreviewState(
          status: PreviewStatus.impossible,
          // The use case fails with nothing else.
          issue: (failure as GenerationFailure).issue,
          seed: seed,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
