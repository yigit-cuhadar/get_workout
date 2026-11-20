import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../analytics/domain/analytics.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_editing.dart';
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
    this.kept = const {},
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

  /// The items Regenerate leaves in place: day index and exercise id (an
  /// exercise is on a day once).
  final Set<(int, String)> kept;
  final SaveStatus saveStatus;

  /// The stored program, once saved.
  final String? savedId;

  /// Why the last save failed: an [AuthFailure] while nobody is signed
  /// in, a [NotFoundFailure] while the library reloads, or the store's.
  final Failure? saveFailure;

  bool isKept(int day, ProgramItem item) =>
      kept.contains((day, item.exerciseId));

  GeneratorPreviewState copyWith({
    GeneratedProgram? program,
    Set<(int, String)>? kept,
    SaveStatus? saveStatus,
    String? savedId,
    Failure? Function()? saveFailure,
  }) => GeneratorPreviewState(
    status: status,
    program: program ?? this.program,
    issue: issue,
    seed: seed,
    kept: kept ?? this.kept,
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
    kept,
    saveStatus,
    savedId,
    saveFailure,
  ];
}

/// The program generated from [answers], made again on Regenerate with the
/// next seed around the kept items, edited item by item, and storing it as
/// one of the user's programs. Waits for the
/// exercise library; later library changes leave the program on screen,
/// and saving validates it against the library as it is then.
class GeneratorPreviewCubit extends Cubit<GeneratorPreviewState> {
  GeneratorPreviewCubit(
    this.answers, {
    required this._catalogue,
    required this._generateProgram,
    required this._saveProgram,
    required this._getCurrentUser,
    required this._analytics,
  }) : super(const GeneratorPreviewState()) {
    _subscription = _catalogue.stream.listen(_onCatalogue);
    _onCatalogue(_catalogue.state);
  }

  final GeneratorAnswers answers;
  final ExerciseCatalogueCubit _catalogue;
  final GenerateProgram _generateProgram;
  final SaveProgram _saveProgram;
  final GetCurrentUser _getCurrentUser;
  final Analytics _analytics;
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

  /// Keeps the item at [index] of [day] through Regenerate, or stops.
  void toggleKept(int day, int index) {
    final item = _itemAt(day, index);
    if (item == null || !_editable) return;
    final key = (day, item.exerciseId);
    emit(
      state.copyWith(
        kept: state.kept.contains(key)
            ? ({...state.kept}..remove(key))
            : {...state.kept, key},
      ),
    );
  }

  /// [exerciseId] in place of the item at [index] of [day], with its sets
  /// and rest, the targets as far as they fit; a kept item stays kept. An
  /// exercise already on the day is not added twice.
  void swapItem(int day, int index, String exerciseId) {
    final item = _itemAt(day, index);
    final exercise = _exercises[exerciseId];
    if (item == null || exercise == null || !_editable) return;
    final items = state.program!.days[day].items;
    if (items.any((other) => other.exerciseId == exerciseId)) return;
    final kept = state.isKept(day, item);
    _changeItems(
      day,
      [
        for (final (i, other) in items.indexed)
          i == index ? replaceExercise(other, exercise) : other,
      ],
      kept: {
        for (final key in state.kept)
          if (key != (day, item.exerciseId)) key,
        if (kept) (day, exerciseId),
      },
    );
  }

  /// [change] applied to the item at [index] of [day].
  void editItem(
    int day,
    int index,
    ProgramItem Function(ProgramItem item) change,
  ) {
    final item = _itemAt(day, index);
    if (item == null || !_editable) return;
    _changeItems(day, [
      for (final (i, other) in state.program!.days[day].items.indexed)
        i == index ? change(other) : other,
    ]);
  }

  /// Takes the item at [index] off [day]; the last one of a day stays.
  void removeItem(int day, int index) {
    final item = _itemAt(day, index);
    if (item == null || !_editable) return;
    final items = state.program!.days[day].items;
    if (items.length < 2) return;
    _changeItems(
      day,
      [...items]..removeAt(index),
      kept: {...state.kept}..remove((day, item.exerciseId)),
    );
  }

  /// The logging type of [exerciseId] in the library, if it is there.
  LoggingType? loggingTypeOf(String exerciseId) =>
      _exercises[exerciseId]?.loggingType;

  bool get _editable =>
      state.status == PreviewStatus.ready &&
      state.saveStatus != SaveStatus.saving &&
      state.saveStatus != SaveStatus.saved;

  ProgramItem? _itemAt(int day, int index) =>
      state.program?.days.elementAtOrNull(day)?.items.elementAtOrNull(index);

  Map<String, Exercise> get _exercises => switch (_catalogue.state) {
    CatalogueReady(:final exercises) => {for (final e in exercises) e.id: e},
    _ => const {},
  };

  void _changeItems(
    int day,
    List<ProgramItem> items, {
    Set<(int, String)>? kept,
  }) {
    final program = state.program!;
    emit(
      state.copyWith(
        program: program.withDays([
          for (final (i, other) in program.days.indexed)
            i == day
                ? GeneratedDay(
                    kind: other.kind,
                    variant: other.variant,
                    items: items,
                  )
                : other,
        ], _exercises),
        kept: kept,
      ),
    );
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
    final program = state.program;
    final kept = state.kept;
    final result = await _generateProgram((
      answers: answers,
      exercises: library.exercises,
      seed: seed,
      kept: [
        for (final (i, day)
            in (program?.days ?? const <GeneratedDay>[]).indexed)
          [
            for (final item in day.items)
              if (kept.contains((i, item.exerciseId))) item,
          ],
      ],
    ));
    _generating = false;
    if (isClosed) return;
    if (result.isOk) {
      unawaited(
        _analytics.programGenerate(
          goal: answers.goal,
          days: answers.daysPerWeek,
        ),
      );
    }
    emit(
      result.fold(
        (program) => GeneratorPreviewState(
          status: PreviewStatus.ready,
          program: program,
          seed: seed,
          kept: {
            for (final (i, day) in program.days.indexed)
              for (final item in day.items)
                if (kept.contains((i, item.exerciseId))) (i, item.exerciseId),
          },
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
