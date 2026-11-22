import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/grouping.dart' as grouping;
import '../../analytics/domain/analytics.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_editing.dart';
import '../../programs/domain/program_usecases.dart';
import '../../programs/domain/program_validation.dart';
import '../../programs/domain/program_volume.dart';
import '../domain/generated_program.dart';
import '../domain/generator_answers.dart';
import '../domain/generator_repository.dart';
import '../domain/generator_usecases.dart';

enum PreviewStatus {
  /// The server is making the program, or will be asked again shortly.
  building,
  ready,

  /// No connection; nothing was made.
  offline,

  /// The server still refuses Premium after a few tries.
  notPremium,

  /// No program fits the answers.
  noProgram,

  /// Nothing is published on the server yet.
  unavailable,
  failure,
}

enum SaveStatus { idle, saving, saved, failed }

/// An item being changed in the targets sheet that is not valid yet: it
/// stays out of the program until it is.
typedef ItemDraft = ({int day, int index, ProgramItem item});

class GeneratorPreviewState extends Equatable {
  const GeneratorPreviewState({
    this.status = PreviewStatus.building,
    this.program,
    this.seed = 0,
    this.kept = const {},
    this.uncovered = const {},
    this.draft,
    this.regenerateFailure,
    this.libraryFailed = false,
    this.saveStatus = SaveStatus.idle,
    this.savedId,
    this.saveFailure,
  });

  final PreviewStatus status;

  /// Only when [status] is ready.
  final GeneratedProgram? program;

  /// What [program] was, or is being, made with; Regenerate takes the next.
  final int seed;

  /// The items Regenerate keeps: day index and exercise id (an exercise is
  /// on a day once).
  final Set<(int, String)> kept;

  /// The muscles the banner names: the server's uncovered ones, after an
  /// edit the targeted ones no exercise of the week works as a main muscle.
  final Set<Muscle> uncovered;
  final ItemDraft? draft;

  /// Why the last Regenerate made no program; [program] is the one before.
  final Failure? regenerateFailure;

  /// The exercise library could not be loaded: rows cannot be named.
  final bool libraryFailed;
  final SaveStatus saveStatus;

  /// The stored program, once saved.
  final String? savedId;

  /// Why the last save failed: an [AuthFailure] while nobody is signed
  /// in, a [NotFoundFailure] while the library reloads, or the store's.
  final Failure? saveFailure;

  bool isKept(int day, ProgramItem item) =>
      kept.contains((day, item.exerciseId));

  /// The item at [index] of [day] as the targets sheet shows it.
  ProgramItem? itemAt(int day, int index) => switch (draft) {
    (day: final d, index: final i, :final item) when d == day && i == index =>
      item,
    _ => program?.days.elementAtOrNull(day)?.items.elementAtOrNull(index),
  };

  GeneratorPreviewState copyWith({
    GeneratedProgram? program,
    Set<(int, String)>? kept,
    Set<Muscle>? uncovered,
    ItemDraft? Function()? draft,
    Failure? Function()? regenerateFailure,
    bool? libraryFailed,
    SaveStatus? saveStatus,
    String? savedId,
    Failure? Function()? saveFailure,
  }) => GeneratorPreviewState(
    status: status,
    program: program ?? this.program,
    seed: seed,
    kept: kept ?? this.kept,
    uncovered: uncovered ?? this.uncovered,
    draft: draft != null ? draft() : this.draft,
    regenerateFailure: regenerateFailure != null
        ? regenerateFailure()
        : this.regenerateFailure,
    libraryFailed: libraryFailed ?? this.libraryFailed,
    saveStatus: saveStatus ?? this.saveStatus,
    savedId: savedId ?? this.savedId,
    saveFailure: saveFailure != null ? saveFailure() : this.saveFailure,
  );

  @override
  List<Object?> get props => [
    status,
    program,
    seed,
    kept,
    uncovered,
    draft,
    regenerateFailure,
    libraryFailed,
    saveStatus,
    savedId,
    saveFailure,
  ];
}

/// The program the server generates from [answers], asked again on
/// Regenerate with the next seed and the kept items, edited item by item,
/// and stored as one of the user's programs. A server that does not see
/// Premium yet is asked again after [retryDelay], twice and four times as
/// long, before the page says so. A Regenerate that fails leaves the
/// program before it on screen.
class GeneratorPreviewCubit extends Cubit<GeneratorPreviewState> {
  GeneratorPreviewCubit(
    this.answers, {
    required this.language,
    required this._catalogue,
    required this._generateProgram,
    required this._saveProgram,
    required this._getCurrentUser,
    required this._analytics,
    this.retryDelay = const Duration(seconds: 2),
  }) : super(const GeneratorPreviewState()) {
    _subscription = _catalogue.stream.listen((_) => _onLibrary());
    unawaited(_generate(0, const {}));
  }

  static const _autoRetries = 3;

  final GeneratorAnswers answers;

  /// The language the program's names come in.
  final String language;
  final Duration retryDelay;
  final ExerciseCatalogueCubit _catalogue;
  final GenerateProgram _generateProgram;
  final SaveProgram _saveProgram;
  final GetCurrentUser _getCurrentUser;
  final Analytics _analytics;
  late final StreamSubscription<ExerciseCatalogueState> _subscription;

  /// The program as the server made it; one that differs was edited.
  GeneratedProgram? _served;
  int _retries = 0;
  Timer? _retryTimer;

  /// Makes another program from the same answers around the kept items.
  Future<void> regenerate() async {
    if (state.status != PreviewStatus.ready ||
        state.saveStatus != SaveStatus.idle) {
      return;
    }
    _retries = 0;
    await _generate(
      state.seed + 1,
      state.kept,
      before: state.copyWith(draft: () => null, regenerateFailure: () => null),
    );
  }

  /// Asks again after the first program failed.
  Future<void> retry() async {
    if (state.status == PreviewStatus.building ||
        state.status == PreviewStatus.ready) {
      return;
    }
    _retries = 0;
    await _generate(state.seed, const {});
  }

  /// The page has shown the failed Regenerate.
  void regenerateFailureShown() =>
      emit(state.copyWith(regenerateFailure: () => null));

  /// Loads the exercise library again after it failed.
  Future<void> retryLibrary() => _catalogue.retry();

  /// [before] is the state a Regenerate started from, shown again when it
  /// fails.
  Future<void> _generate(
    int seed,
    Set<(int, String)> kept, {
    GeneratorPreviewState? before,
  }) async {
    _retryTimer?.cancel();
    _retryTimer = null;
    final keptItems = [
      for (final (i, day)
          in (before?.program?.days ?? const <ProgramDay>[]).indexed)
        [
          for (final item in day.items)
            if (kept.contains((i, item.exerciseId))) item,
        ],
    ];
    emit(
      GeneratorPreviewState(
        seed: seed,
        kept: kept,
        libraryFailed: _libraryFailed,
      ),
    );
    final result = await _generateProgram((
      answers: answers,
      seed: seed,
      kept: keptItems,
      language: language,
    ));
    if (isClosed) return;
    switch (result) {
      case Ok(value: final made):
        unawaited(
          _analytics.programGenerate(
            goal: answers.goal,
            days: answers.daysPerWeek,
          ),
        );
        final program = _withTargets(made, keptItems);
        _served = program;
        emit(
          GeneratorPreviewState(
            status: PreviewStatus.ready,
            program: program,
            seed: seed,
            kept: {
              for (final (i, day) in program.days.indexed)
                for (final item in day.items)
                  if (kept.contains((i, item.exerciseId))) (i, item.exerciseId),
            },
            uncovered: program.uncovered,
            libraryFailed: _libraryFailed,
          ),
        );
      case Err(:final failure):
        if (failure
            case GenerationRefused(refusal: GenerationRefusal.notPremium)
            when _retries < _autoRetries) {
          // The entitlement may not have reached the server yet.
          _retryTimer = Timer(retryDelay * (1 << _retries), () {
            _retryTimer = null;
            _retries++;
            unawaited(_generate(seed, kept, before: before));
          });
          return;
        }
        if (before != null) {
          return emit(
            before.copyWith(
              regenerateFailure: () => failure,
              libraryFailed: _libraryFailed,
            ),
          );
        }
        emit(
          GeneratorPreviewState(
            status: switch (failure) {
              NetworkFailure() => PreviewStatus.offline,
              GenerationRefused(:final refusal) => switch (refusal) {
                GenerationRefusal.notPremium => PreviewStatus.notPremium,
                GenerationRefusal.noTemplate ||
                GenerationRefusal.noExercises => PreviewStatus.noProgram,
                GenerationRefusal.noRules => PreviewStatus.unavailable,
                GenerationRefusal.invalidInput => PreviewStatus.failure,
              },
              _ => PreviewStatus.failure,
            },
            seed: seed,
            libraryFailed: _libraryFailed,
          ),
        );
    }
  }

  /// [program] with each [kept] item's target weight back on the item of
  /// the same exercise on its day; the server takes no targets.
  static GeneratedProgram _withTargets(
    GeneratedProgram program,
    List<List<ProgramItem>> kept,
  ) => program.withDays([
    for (final (i, day) in program.days.indexed)
      day.copyWith(
        items: [
          for (final item in day.items)
            switch (kept
                .elementAtOrNull(i)
                ?.where((k) => k.exerciseId == item.exerciseId)
                .firstOrNull
                ?.targetKg) {
              final kg? => item.copyWith(targetKg: () => kg),
              null => item,
            },
        ],
      ),
  ]);

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

  /// [exerciseId] in place of the item at [index] of [day], with its sets,
  /// rest and group, the targets as far as they fit; a kept item stays
  /// kept. An exercise already on the day is not added twice.
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

  /// [change] applied to the item at [index] of [day], as the targets
  /// sheet shows it. Only a valid item enters the program; one that is not
  /// valid yet is kept as the [GeneratorPreviewState.draft].
  void editItem(
    int day,
    int index,
    ProgramItem Function(ProgramItem item) change,
  ) {
    final item = state.itemAt(day, index);
    if (item == null || !_editable) return;
    final changed = change(item);
    if (validateItem(changed, loggingTypeOf(changed.exerciseId)).isNotEmpty) {
      return emit(
        state.copyWith(draft: () => (day: day, index: index, item: changed)),
      );
    }
    _changeItems(day, [
      for (final (i, other) in state.program!.days[day].items.indexed)
        i == index ? changed : other,
    ]);
  }

  /// The targets sheet closed: a change not valid yet is dropped.
  void discardDraft() => emit(state.copyWith(draft: () => null));

  /// Takes the item at [index] off [day]; the last one of a day stays. A
  /// group left with one item dissolves.
  void removeItem(int day, int index) {
    final item = _itemAt(day, index);
    if (item == null || !_editable) return;
    final items = state.program!.days[day].items;
    if (items.length < 2) return;
    _changeItems(
      day,
      grouping.removeItem(items, index),
      kept: {...state.kept}..remove((day, item.exerciseId)),
    );
  }

  /// The logging type of [exerciseId] in the library, if it is there.
  LoggingType? loggingTypeOf(String exerciseId) =>
      _exercises[exerciseId]?.loggingType;

  /// The week on screen's sets per muscle, counted from the library.
  ProgramVolume? get volume => switch (state.program) {
    final program? => programVolume(program.toProgram(name: ''), _exercises),
    null => null,
  };

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

  bool get _libraryFailed => _catalogue.state is CatalogueFailed;

  /// The banner's muscles for [program]: the server's until it is edited.
  Set<Muscle> _uncoveredOf(GeneratedProgram program) =>
      program == _served ? program.uncovered : program.untrained(_exercises);

  void _changeItems(
    int day,
    List<ProgramItem> items, {
    Set<(int, String)>? kept,
  }) {
    final program = state.program!;
    final changed = program.withDays([
      for (final (i, other) in program.days.indexed)
        i == day ? other.copyWith(items: items) : other,
    ]);
    emit(
      state.copyWith(
        program: changed,
        kept: kept,
        draft: () => null,
        uncovered: _uncoveredOf(changed),
      ),
    );
  }

  /// The library changed: whether it failed, and the uncovered muscles.
  void _onLibrary() {
    final program = state.program;
    emit(
      state.copyWith(
        libraryFailed: _libraryFailed,
        uncovered: program == null ? null : _uncoveredOf(program),
      ),
    );
  }

  /// Stores the program on screen named [name].
  Future<void> save({required String name}) async {
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
      program: program.toProgram(name: name),
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

  @override
  Future<void> close() async {
    _retryTimer?.cancel();
    await _subscription.cancel();
    return super.close();
  }
}
