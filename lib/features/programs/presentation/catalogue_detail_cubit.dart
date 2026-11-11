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

  /// Offline, and the card or the days were never loaded on this device.
  offline,

  /// The program, or its days, no longer exist.
  notFound,
  failure,
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
    this.copyStatus = CopyStatus.idle,
    this.copyId,
    this.copyFailure,
  });

  final CatalogueDetailStatus status;

  /// The card, once known; also while the days load or are locked.
  final CatalogueProgram? program;

  /// Only when [status] is ready.
  final List<ProgramDay> days;
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
    copyStatus: copyStatus ?? this.copyStatus,
    copyId: copyId != null ? copyId() : this.copyId,
    copyFailure: copyFailure != null ? copyFailure() : this.copyFailure,
  );

  @override
  List<Object?> get props => [
    status,
    program,
    days,
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
/// days when the user has no premium. The server has the last word: days
/// it refuses are locked too.
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
  }) : _catalogue = catalogue,
       super(const CatalogueDetailState()) {
    _catalogueSubscription = catalogue.stream.listen(_onCatalogue);
    _onCatalogue(catalogue.state);
  }

  final String programId;

  /// The language the copy is named in.
  final String language;
  final ProgramCatalogueCubit _catalogue;
  final ProgramListCubit _list;
  final ExerciseCatalogueCubit _exercises;
  final GetCatalogueDays _getDays;
  final SaveProgram _saveProgram;
  final GetCurrentUser _getCurrentUser;
  late final StreamSubscription<ProgramCatalogueState> _catalogueSubscription;

  CatalogueProgram? _program;
  bool? _premium;
  List<ProgramDay>? _days;
  Failure? _daysFailure;
  bool _fetching = false;

  /// Tries again after the card or the days failed to load.
  void retry() {
    _daysFailure = null;
    if (_program == null) {
      _catalogue.retry();
    } else {
      _update();
    }
  }

  /// The primary action: copies the program, unless the user already has a
  /// copy of it, which is offered instead.
  Future<void> use() async {
    final existing = _list.state.programs
        .where(
          (program) =>
              program.origin == ProgramOrigin.catalog &&
              program.sourceId == programId,
        )
        .firstOrNull;
    if (existing != null) {
      if (state.copyStatus == CopyStatus.copying) return;
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
    if (state.status != CatalogueDetailStatus.ready ||
        state.copyStatus == CopyStatus.copying ||
        program == null ||
        uid == null) {
      return;
    }
    final exercises = _exercises.state;
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
        if (exercises is CatalogueReady)
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
      // A refusal said nothing about the new status.
      if (_daysFailure is PermissionFailure) _daysFailure = null;
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
      return _emit(switch (failure) {
        PermissionFailure() when program.premium =>
          CatalogueDetailStatus.locked,
        NetworkFailure() => CatalogueDetailStatus.offline,
        NotFoundFailure() => CatalogueDetailStatus.notFound,
        _ => CatalogueDetailStatus.failure,
      });
    }
    _emit(CatalogueDetailStatus.loading);
    if (!_fetching) unawaited(_fetchDays());
  }

  Future<void> _fetchDays() async {
    _fetching = true;
    final result = await _getDays(programId);
    _fetching = false;
    if (isClosed) return;
    result.fold((days) => _days = days, (failure) => _daysFailure = failure);
    if (_program != null) _update();
  }

  void _emit(CatalogueDetailStatus status) {
    final ready = status == CatalogueDetailStatus.ready;
    emit(
      CatalogueDetailState(
        status: status,
        program: _program,
        days: ready ? _days! : const [],
        copyStatus: state.copyStatus,
        copyId: state.copyId,
        copyFailure: state.copyFailure,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _catalogueSubscription.cancel();
    return super.close();
  }
}
