import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

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

  /// The user already has a copy, [CatalogueDetailState.copyId]; the page
  /// offers it, or [CatalogueDetailCubit.copy] for another.
  alreadyCopied,

  /// [CatalogueDetailState.copyId] is the new copy.
  copied,
  failed,
}

class CatalogueDetailState extends Equatable {
  const CatalogueDetailState({
    this.status = CatalogueDetailStatus.loading,
    this.program,
    this.days = const [],
    this.useStatus = UseStatus.waiting,
    this.copyStatus = CopyStatus.idle,
    this.copyId,
    this.copyFailure,
  });

  final CatalogueDetailStatus status;

  /// The card, once known; also while the days load or are locked.
  final CatalogueProgram? program;

  /// Only when [status] is ready.
  final List<ProgramDay> days;

  /// Only meaningful when [status] is ready.
  final UseStatus useStatus;
  final CopyStatus copyStatus;
  final String? copyId;
  final Failure? copyFailure;

  CatalogueDetailState copyWith({
    CopyStatus? copyStatus,
    String? Function()? copyId,
    Failure? Function()? copyFailure,
  }) => CatalogueDetailState(
    status: status,
    program: program,
    days: days,
    useStatus: useStatus,
    copyStatus: copyStatus ?? this.copyStatus,
    copyId: copyId != null ? copyId() : this.copyId,
    copyFailure: copyFailure != null ? copyFailure() : this.copyFailure,
  );

  @override
  List<Object?> get props => [
    status,
    program,
    days,
    useStatus,
    copyStatus,
    copyId,
    copyFailure,
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
    required this._getCurrentUser,
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
  final GetCurrentUser _getCurrentUser;
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

  /// The primary action: copies the program, unless the user already has a
  /// copy of it, which is offered instead.
  Future<void> use() async {
    if (state.useStatus != UseStatus.ready ||
        state.copyStatus == CopyStatus.copying) {
      return;
    }
    final existing = _list.state.programs
        .where(
          (program) =>
              program.origin == ProgramOrigin.catalog &&
              program.sourceId == programId,
        )
        .firstOrNull;
    if (existing != null) {
      emit(
        state.copyWith(
          copyStatus: CopyStatus.alreadyCopied,
          copyId: () => existing.id,
        ),
      );
      return;
    }
    return copy();
  }

  /// Stores a copy of the program as one of the user's, through the
  /// builder's validation.
  Future<void> copy() async {
    final program = _program;
    final uid = _getCurrentUser()?.id;
    final exercises = _exercises.state;
    if (state.status != CatalogueDetailStatus.ready ||
        state.useStatus != UseStatus.ready ||
        state.copyStatus == CopyStatus.copying ||
        program == null ||
        uid == null ||
        exercises is! CatalogueReady) {
      return;
    }
    emit(
      state.copyWith(
        copyStatus: CopyStatus.copying,
        copyId: () => null,
        copyFailure: () => null,
      ),
    );
    final result = await _saveProgram((
      uid: uid,
      program: program.copy(state.days, language),
      loggingTypes: {
        for (final exercise in exercises.exercises)
          exercise.id: exercise.loggingType,
      },
    ));
    if (isClosed) return;
    emit(
      result.fold(
        (id) => state.copyWith(copyStatus: CopyStatus.copied, copyId: () => id),
        (failure) => state.copyWith(
          copyStatus: CopyStatus.failed,
          copyFailure: () => failure,
        ),
      ),
    );
  }

  /// The page has acted on the copy status.
  void copyHandled() => emit(
    state.copyWith(
      copyStatus: CopyStatus.idle,
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
        copyId: state.copyId,
        copyFailure: state.copyFailure,
      ),
    );
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
