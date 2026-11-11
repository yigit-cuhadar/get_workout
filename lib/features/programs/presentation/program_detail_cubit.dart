import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/program.dart';
import '../domain/program_usecases.dart';
import 'program_list_cubit.dart';

enum ProgramDetailStatus {
  idle,
  working,
  failed,
  deleted,

  /// [ProgramDetailState.copyId] holds the new program's id.
  duplicated,

  /// The signed-in user changed; the page must close.
  closed,
}

class ProgramDetailState extends Equatable {
  const ProgramDetailState({
    this.status = ProgramDetailStatus.idle,
    this.failure,
    this.copyId,
  });

  final ProgramDetailStatus status;
  final Failure? failure;
  final String? copyId;

  bool get isBusy => status == ProgramDetailStatus.working;

  @override
  List<Object?> get props => [status, failure, copyId];
}

/// The actions of one program's page: start, change weekdays, stop,
/// duplicate and delete. The program and the active program come from the
/// app-wide [ProgramListCubit]; the results show up there.
class ProgramDetailCubit extends Cubit<ProgramDetailState> {
  ProgramDetailCubit(
    this.programId, {
    required this._list,
    required this._startProgram,
    required this._changeWeekdays,
    required this._stopProgram,
    required this._duplicateProgram,
    required this._deleteProgram,
    required GetCurrentUser getCurrentUser,
    required WatchAuthUser watchAuthUser,
  }) : _getCurrentUser = getCurrentUser,
       _uid = getCurrentUser()?.id,
       super(const ProgramDetailState()) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          if (uid != _uid) _close();
        });
  }

  final String programId;
  final ProgramListCubit _list;
  final StartProgram _startProgram;
  final ChangeWeekdays _changeWeekdays;
  final StopProgram _stopProgram;
  final DuplicateProgram _duplicateProgram;
  final DeleteProgram _deleteProgram;
  final GetCurrentUser _getCurrentUser;

  /// The user the page was opened for.
  final String? _uid;
  late final StreamSubscription<String?> _userSubscription;

  Program? get _program => _list.state.program(programId);

  Future<void> start(List<int> weekdays) => _withProgram(
    (uid, program) =>
        _startProgram((uid: uid, program: program, weekdays: weekdays)),
  );

  /// Only for the active program.
  Future<void> changeWeekdays(List<int> weekdays) {
    final active = _list.state.active;
    if (active == null || active.programId != programId) return Future.value();
    return _withProgram(
      (uid, program) => _changeWeekdays((
        uid: uid,
        active: active,
        dayCount: program.days.length,
        weekdays: weekdays,
      )),
    );
  }

  /// Only for the active program.
  Future<void> stop() {
    if (_list.state.active?.programId != programId) return Future.value();
    return _withProgram((uid, _) => _stopProgram(uid));
  }

  /// [nameOf] makes the copy's name from the original's.
  Future<void> duplicate(String Function(String name) nameOf) =>
      _withProgram((uid, program) async {
        final result = await _duplicateProgram((
          uid: uid,
          program: program,
          nameOf: nameOf,
        ));
        return result.map((id) {
          if (!isClosed && state.status != ProgramDetailStatus.closed) {
            emit(
              ProgramDetailState(
                status: ProgramDetailStatus.duplicated,
                copyId: id,
              ),
            );
          }
        });
      });

  Future<void> delete() => _withProgram((uid, _) async {
    final result = await _deleteProgram((
      uid: uid,
      id: programId,
      activeProgramId: _list.state.active?.programId,
    ));
    return result.map((_) {
      if (!isClosed && state.status != ProgramDetailStatus.closed) {
        emit(const ProgramDetailState(status: ProgramDetailStatus.deleted));
      }
    });
  });

  /// Runs [action] for the page's user and program. A success that did not
  /// emit a result of its own returns to idle.
  Future<void> _withProgram(
    Future<Result<void>> Function(String uid, Program program) action,
  ) async {
    if (state.isBusy || state.status == ProgramDetailStatus.closed) return;
    final uid = _getCurrentUser()?.id;
    if (uid == null || uid != _uid) return _close();
    final program = _program;
    if (program == null) return;
    emit(const ProgramDetailState(status: ProgramDetailStatus.working));
    final failure = (await action(uid, program)).failureOrNull;
    if (isClosed || state.status != ProgramDetailStatus.working) return;
    emit(
      failure == null
          ? const ProgramDetailState()
          : ProgramDetailState(
              status: ProgramDetailStatus.failed,
              failure: failure,
            ),
    );
  }

  void _close() {
    if (state.status != ProgramDetailStatus.closed) {
      emit(const ProgramDetailState(status: ProgramDetailStatus.closed));
    }
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    return super.close();
  }
}
