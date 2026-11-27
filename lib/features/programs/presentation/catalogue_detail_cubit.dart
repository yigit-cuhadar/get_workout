import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../analytics/domain/analytics.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../domain/catalogue_program.dart';
import '../domain/program.dart';
import '../domain/program_usecases.dart';
import 'program_catalogue_cubit.dart';
import 'program_list_cubit.dart';

enum CatalogueDetailStatus {
  /// The card, the premium status or the days are on their way.
  loading,

  /// The card and its days.
  ready,

  /// A premium program the user cannot open: the card only.
  locked,

  /// The user has premium but the server refused the days, e.g. while the
  /// entitlement reaches it: read again a few times, then on retry.
  unlocking,

  /// Offline, and the card or the days were never loaded on this device.
  offline,

  /// The program, or its days, no longer exist.
  notFound,
  failure,
}

/// Whether "Use this program" can copy the days on screen.
enum UseStatus {
  /// The exercise library or the user's programs are still loading.
  waiting,
  ready,

  /// A day uses an exercise that is no longer in the library; copying
  /// would never pass validation.
  exercisesMissing,

  /// The exercise library could not be loaded.
  exercisesFailed,
}

enum CopyStatus {
  idle,
  copying,

  /// [CatalogueDetailState.copyId] is the new copy.
  copied,

  /// The copy [CatalogueDetailState.copyId] was stored but could not be
  /// started; it stays among the user's programs, not started.
  startFailed,
  failed,
}

/// What a copy is made for: to start it on the training days picked, to edit it
/// in the builder, or only to keep it among the user's programs.
enum CopyIntent { start, edit, keep }

class CatalogueDetailState extends Equatable {
  const CatalogueDetailState({
    this.status = CatalogueDetailStatus.loading,
    this.program,
    this.days = const [],
    this.useStatus = UseStatus.waiting,
    this.copyStatus = CopyStatus.idle,
    this.copyIntent,
    this.copyId,
    this.copyFailure,
    this.queuedCopy,
  });

  final CatalogueDetailStatus status;

  /// The card, once known; also while the days load or are locked.
  final CatalogueProgram? program;

  /// Only when [status] is ready.
  final List<ProgramDay> days;

  /// Only meaningful when [status] is ready.
  final UseStatus useStatus;
  final CopyStatus copyStatus;

  /// What the copy being made, or just made, is for.
  final CopyIntent? copyIntent;
  final String? copyId;
  final Failure? copyFailure;

  /// A copy asked for before the days could be copied, e.g. right after
  /// Premium was bought: made once they are, or given up as failed.
  final CopyIntent? queuedCopy;

  CatalogueDetailState copyWith({
    CopyStatus? copyStatus,
    CopyIntent? Function()? copyIntent,
    String? Function()? copyId,
    Failure? Function()? copyFailure,
    CopyIntent? Function()? queuedCopy,
  }) => CatalogueDetailState(
    status: status,
    program: program,
    days: days,
    useStatus: useStatus,
    copyStatus: copyStatus ?? this.copyStatus,
    copyIntent: copyIntent != null ? copyIntent() : this.copyIntent,
    copyId: copyId != null ? copyId() : this.copyId,
    copyFailure: copyFailure != null ? copyFailure() : this.copyFailure,
    queuedCopy: queuedCopy != null ? queuedCopy() : this.queuedCopy,
  );

  @override
  List<Object?> get props => [
    status,
    program,
    days,
    useStatus,
    copyStatus,
    copyIntent,
    copyId,
    copyFailure,
    queuedCopy,
  ];
}

/// One ready-made program: its card from the app-wide
/// [ProgramCatalogueCubit], its days when the user may read them, and
/// copying it into the user's programs.
///
/// A premium program waits for a known premium status, so neither its days
/// nor a lock show before it is known, and is locked without reading its
/// days when the user has no premium. Days the server refuses to a user with
/// premium are read again after [retryDelay], twice and four times as long.
/// A result that arrives after the premium status changed is dropped.
class CatalogueDetailCubit extends Cubit<CatalogueDetailState> {
  CatalogueDetailCubit(
    this.programId, {
    required this.language,
    required ProgramCatalogueCubit catalogue,
    required this._list,
    required this._exercises,
    required this._getDays,
    required this._saveProgram,
    required this._startProgram,
    required this._getCurrentUser,
    required this._analytics,
    this.retryDelay = const Duration(seconds: 2),
  }) : _catalogue = catalogue,
       super(const CatalogueDetailState()) {
    _catalogueSubscription = catalogue.stream.listen(_onCatalogue);
    _listSubscription = _list.stream.listen((_) => _emit(state.status));
    _exercisesSubscription = _exercises.stream.listen(
      (_) => _emit(state.status),
    );
    _onCatalogue(catalogue.state);
  }

  static const _autoRetries = 3;

  final String programId;

  /// The language the copy is named in.
  final String language;
  final Duration retryDelay;
  final ProgramCatalogueCubit _catalogue;
  final ProgramListCubit _list;
  final ExerciseCatalogueCubit _exercises;
  final GetCatalogueDays _getDays;
  final SaveProgram _saveProgram;
  final StartProgram _startProgram;
  final GetCurrentUser _getCurrentUser;
  final Analytics _analytics;
  late final StreamSubscription<ProgramCatalogueState> _catalogueSubscription;
  late final StreamSubscription<ProgramListState> _listSubscription;
  late final StreamSubscription<ExerciseCatalogueState> _exercisesSubscription;

  CatalogueProgram? _program;
  bool? _premium;
  List<ProgramDay>? _days;
  Failure? _daysFailure;
  bool _fetching = false;

  /// Counts premium changes; a days result of an earlier one is stale.
  int _generation = 0;
  int _retries = 0;
  Timer? _retryTimer;

  /// Tries again after the card or the days failed to load.
  void retry() {
    _daysFailure = null;
    _retries = 0;
    _cancelRetry();
    if (_program == null) {
      _catalogue.retry();
    } else {
      _update();
    }
  }

  /// Tries the exercise library again after it failed to load.
  Future<void> retryExercises() => _exercises.retry();

  /// The name of the user's active program, which starting this one
  /// replaces.
  String? get activeProgramName => _list.state.activeProgram?.name;

  /// The user's copy of this program, if they have one, which the page
  /// offers before making another.
  String? get existingCopyId => _list.state.programs
      .where(
        (program) =>
            program.origin == ProgramOrigin.catalog &&
            program.sourceId == programId,
      )
      .firstOrNull
      ?.id;

  /// Stores a copy of the program as one of the user's, through the
  /// builder's validation, for [intent]: to start it at once on
  /// [schedule], replacing any active program, or to edit it.
  Future<void> copy(CopyIntent intent, {Map<int, int>? schedule}) async {
    final program = _program;
    final uid = _getCurrentUser()?.id;
    final exercises = _exercises.state;
    if (state.status != CatalogueDetailStatus.ready ||
        state.useStatus != UseStatus.ready ||
        state.copyStatus == CopyStatus.copying ||
        program == null ||
        uid == null ||
        exercises is! CatalogueReady ||
        (intent == CopyIntent.start && schedule == null)) {
      return;
    }
    emit(
      state.copyWith(
        copyStatus: CopyStatus.copying,
        copyIntent: () => intent,
        copyId: () => null,
        copyFailure: () => null,
      ),
    );
    final copy = program.copy(state.days, language);
    final saved = await _saveProgram((
      uid: uid,
      program: copy,
      loggingTypes: {
        for (final exercise in exercises.exercises)
          exercise.id: exercise.loggingType,
      },
    ));
    if (saved case Ok(value: final id) when intent == CopyIntent.start) {
      final stored = Program(
        id: id,
        name: copy.name,
        origin: copy.origin,
        sourceId: copy.sourceId,
        lengthWeeks: copy.lengthWeeks,
        days: copy.days,
        premium: copy.premium,
      );
      final started = await _startProgram((
        uid: uid,
        program: stored,
        schedule: schedule!,
      ));
      if (started.isOk) {
        unawaited(_analytics.programStart(stored, onboarding: false));
      }
      if (isClosed) return;
      if (started.failureOrNull case final failure?) {
        return emit(
          state.copyWith(
            copyStatus: CopyStatus.startFailed,
            copyId: () => id,
            copyFailure: () => failure,
          ),
        );
      }
    }
    if (isClosed) return;
    emit(
      saved.fold(
        (id) => state.copyWith(copyStatus: CopyStatus.copied, copyId: () => id),
        (failure) => state.copyWith(
          copyStatus: CopyStatus.failed,
          copyFailure: () => failure,
        ),
      ),
    );
  }

  /// Copies for [intent] as soon as the days can be copied: at once when
  /// they can, else once they unlock or load, reading them again if they
  /// stopped trying. Gives up as [CopyStatus.failed] when they cannot
  /// come: the unlock stopped retrying, offline, gone, or the exercises
  /// missing.
  void copyOnceReady(CopyIntent intent) {
    if (state.copyStatus != CopyStatus.idle) return;
    emit(state.copyWith(queuedCopy: () => intent));
    if (_stalled) return retry();
    _emit(state.status);
  }

  /// Whether the days stopped coming until [retry].
  bool get _stalled => switch (state.status) {
    CatalogueDetailStatus.unlocking => _retryTimer == null,
    CatalogueDetailStatus.offline || CatalogueDetailStatus.failure => true,
    _ => false,
  };

  void _runQueuedCopy() {
    final intent = state.queuedCopy;
    if (intent == null || isClosed) return;
    final status = state.status;
    final ready = status == CatalogueDetailStatus.ready;
    if (ready && state.useStatus == UseStatus.ready) {
      emit(state.copyWith(queuedCopy: () => null));
      unawaited(copy(intent));
    } else if (_stalled ||
        status == CatalogueDetailStatus.notFound ||
        (ready && state.useStatus != UseStatus.waiting)) {
      emit(
        state.copyWith(
          copyStatus: CopyStatus.failed,
          copyIntent: () => intent,
          copyFailure: () => status == CatalogueDetailStatus.offline
              ? const NetworkFailure()
              : _daysFailure ?? const UnknownFailure(),
          queuedCopy: () => null,
        ),
      );
    }
  }

  /// The page has acted on the copy status.
  void copyHandled() => emit(
    state.copyWith(
      copyStatus: CopyStatus.idle,
      copyIntent: () => null,
      copyId: () => null,
      copyFailure: () => null,
    ),
  );

  void _onCatalogue(ProgramCatalogueState catalogue) {
    final program = catalogue.program(programId);
    if (program == null) {
      _program = null;
      _emit(switch (catalogue.status) {
        ProgramCatalogueStatus.loading => CatalogueDetailStatus.loading,
        ProgramCatalogueStatus.ready => CatalogueDetailStatus.notFound,
        ProgramCatalogueStatus.offline => CatalogueDetailStatus.offline,
        ProgramCatalogueStatus.failure => CatalogueDetailStatus.failure,
      });
      return;
    }
    if (catalogue.premium != _premium) {
      // What was read or refused under the old status says nothing now.
      _generation++;
      _fetching = false;
      _daysFailure = null;
      _retries = 0;
      _cancelRetry();
      _premium = catalogue.premium;
    }
    _program = program;
    _update();
  }

  void _update() {
    final program = _program!;
    if (program.premium && _premium == null) {
      return _emit(CatalogueDetailStatus.loading);
    }
    if (program.premium && _premium == false) {
      return _emit(CatalogueDetailStatus.locked);
    }
    if (_days != null) return _emit(CatalogueDetailStatus.ready);
    if (_daysFailure case final failure?) {
      if (failure is PermissionFailure && program.premium) {
        _retryLater();
        return _emit(CatalogueDetailStatus.unlocking);
      }
      return _emit(switch (failure) {
        NetworkFailure() => CatalogueDetailStatus.offline,
        NotFoundFailure() => CatalogueDetailStatus.notFound,
        _ => CatalogueDetailStatus.failure,
      });
    }
    _emit(CatalogueDetailStatus.loading);
    if (!_fetching) unawaited(_fetchDays());
  }

  void _retryLater() {
    if (_retryTimer != null || _retries >= _autoRetries) return;
    _retryTimer = Timer(retryDelay * (1 << _retries), () {
      _retryTimer = null;
      _retries++;
      _daysFailure = null;
      if (_program != null) _update();
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> _fetchDays() async {
    final generation = _generation;
    _fetching = true;
    final result = await _getDays(programId);
    if (isClosed || generation != _generation) return;
    _fetching = false;
    result.fold((days) => _days = days, (failure) => _daysFailure = failure);
    if (_program != null) _update();
  }

  UseStatus _useStatus(List<ProgramDay> days) {
    final exercises = _exercises.state;
    if (exercises is CatalogueFailed) return UseStatus.exercisesFailed;
    if (exercises is! CatalogueReady ||
        _list.state.status != ProgramListStatus.ready) {
      return UseStatus.waiting;
    }
    final ids = {for (final day in days) ...day.items.map((i) => i.exerciseId)};
    if (!ids.every(exercises.knows)) return UseStatus.waiting;
    final known = {for (final exercise in exercises.exercises) exercise.id};
    return ids.every(known.contains)
        ? UseStatus.ready
        : UseStatus.exercisesMissing;
  }

  void _emit(CatalogueDetailStatus status) {
    if (isClosed) return;
    final days = status == CatalogueDetailStatus.ready
        ? _days!
        : const <ProgramDay>[];
    emit(
      CatalogueDetailState(
        status: status,
        program: _program,
        days: days,
        useStatus: _useStatus(days),
        copyStatus: state.copyStatus,
        copyIntent: state.copyIntent,
        copyId: state.copyId,
        copyFailure: state.copyFailure,
        queuedCopy: state.queuedCopy,
      ),
    );
    _runQueuedCopy();
  }

  @override
  Future<void> close() async {
    _cancelRetry();
    await _catalogueSubscription.cancel();
    await _listSubscription.cancel();
    await _exercisesSubscription.cancel();
    return super.close();
  }
}
