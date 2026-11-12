import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../steps/domain/steps.dart';
import '../../steps/domain/steps_usecases.dart';

enum TodayStepsStatus {
  loading,

  /// Steps cannot be read yet: not asked here, refused, or Health Connect
  /// missing. The Steps page sets it up; Today never asks the system.
  setUp,

  /// No health store on this device: no card.
  unavailable,
  ready,
  failure,
}

class TodayStepsState extends Equatable {
  const TodayStepsState({
    this.status = TodayStepsStatus.loading,
    this.progress,
    this.failure,
  });

  final TodayStepsStatus status;

  /// Set once ready.
  final StepGoalProgress? progress;
  final Failure? failure;

  @override
  List<Object?> get props => [status, progress, failure];
}

/// Today's steps against the daily goal, for the Today card. Reads only:
/// access is checked, never requested. [load] again when the app comes
/// back or the goal changes; a newer load wins over one still running.
class TodayStepsCubit extends Cubit<TodayStepsState> {
  TodayStepsCubit({required this._getAccess, required this._getTodaySteps})
    : super(const TodayStepsState());

  final GetStepsAccess _getAccess;
  final GetTodaySteps _getTodaySteps;
  int _generation = 0;

  /// Reads today's steps against [goal]; what was shown stays meanwhile.
  Future<void> load(int goal) async {
    final generation = ++_generation;
    bool stale() => isClosed || generation != _generation;
    final access = await _getAccess();
    if (stale()) return;
    switch (access) {
      case Err(:final failure):
        return _fail(failure);
      case Ok(value: StepsAccess.unsupported):
        return emit(
          const TodayStepsState(status: TodayStepsStatus.unavailable),
        );
      case Ok(value: final access) when !access.readable:
        return emit(const TodayStepsState(status: TodayStepsStatus.setUp));
      case Ok():
    }
    final steps = await _getTodaySteps(goal);
    if (stale()) return;
    switch (steps) {
      // Android: access was taken back since it was checked.
      case Err(failure: PermissionFailure()):
        emit(const TodayStepsState(status: TodayStepsStatus.setUp));
      case Err(:final failure):
        _fail(failure);
      case Ok(value: final progress):
        emit(
          TodayStepsState(status: TodayStepsStatus.ready, progress: progress),
        );
    }
  }

  void _fail(Failure failure) =>
      emit(TodayStepsState(status: TodayStepsStatus.failure, failure: failure));
}
