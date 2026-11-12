import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';

import '../domain/steps.dart';
import '../domain/steps_usecases.dart';

/// Where the page shows [StepsState.failure].
enum StepsFailureShown {
  none,

  /// Nothing to show yet: an error with a retry in place of the page.
  page,

  /// Beside the screen of the access that stands (the explanation, a
  /// refusal, ...), e.g. a failed "Continue" or "Ask again".
  inline,

  /// Briefly over the steps, which stay.
  snack,
}

class StepsState extends Equatable {
  const StepsState({
    this.access,
    this.history,
    this.failure,
    this.busy = false,
  });

  /// Null until first known.
  final StepsAccess? access;

  /// The last read, while [access] is readable.
  final StepsHistory? history;

  /// Set when the last load or request failed; what was known before
  /// stays.
  final Failure? failure;

  /// Asking for access or opening settings.
  final bool busy;

  /// Whether to say where access is allowed; see [showsAccessHint].
  bool get accessHint {
    final access = this.access;
    final history = this.history;
    return access != null &&
        history != null &&
        showsAccessHint(access, history);
  }

  StepsFailureShown get failureShown {
    if (failure == null) return StepsFailureShown.none;
    final access = this.access;
    if (access == null) return StepsFailureShown.page;
    if (!access.readable) return StepsFailureShown.inline;
    return history == null ? StepsFailureShown.page : StepsFailureShown.snack;
  }

  @override
  List<Object?> get props => [access, history, failure, busy];
}

/// Step access and the last 30 days. [load] again whenever the app comes
/// back: the user can change access in the system settings at any time,
/// and the day moves on. A newer load wins over one still running.
class StepsCubit extends Cubit<StepsState> {
  StepsCubit({
    required this._getAccess,
    required this._allowAccess,
    required this._getHistory,
    required this._openSettings,
  }) : super(const StepsState());

  final GetStepsAccess _getAccess;
  final AllowStepsAccess _allowAccess;
  final GetStepsHistory _getHistory;
  final OpenHealthSettings _openSettings;
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    bool stale() => isClosed || generation != _generation;
    final access = await _getAccess();
    if (stale()) return;
    switch (access) {
      case Err(:final failure):
        return _fail(failure);
      case Ok(value: final access) when !access.readable:
        return emit(StepsState(access: access, busy: state.busy));
      case Ok(value: final access):
        emit(
          StepsState(access: access, history: state.history, busy: state.busy),
        );
    }
    final history = await _getHistory();
    if (stale()) return;
    switch (history) {
      // Android: access was taken back since it was checked.
      case Err(failure: PermissionFailure()):
        emit(StepsState(access: StepsAccess.denied, busy: state.busy));
      case Err(:final failure):
        _fail(failure);
      case Ok(value: final history):
        emit(
          StepsState(access: state.access, history: history, busy: state.busy),
        );
    }
  }

  /// The user said yes to the explanation, or asks again after a refusal:
  /// shows the system prompt where it still can, then loads.
  Future<void> allow() async {
    if (state.busy) return;
    _setBusy(true);
    final result = await _allowAccess();
    if (isClosed) return;
    _setBusy(false);
    if (result.failureOrNull case final failure?) return _fail(failure);
    await load();
  }

  /// Health Connect's settings or its store page, or the app's iOS
  /// settings; whether they opened. Coming back reloads through [load].
  Future<bool> openSettings() async {
    if (state.busy) return false;
    _setBusy(true);
    final result = await _openSettings();
    if (!isClosed) _setBusy(false);
    if (result.failureOrNull case final failure?) {
      Log.e('steps', 'settings not opened: ${failure.message}');
      return false;
    }
    return true;
  }

  void _setBusy(bool busy) => emit(
    StepsState(
      access: state.access,
      history: state.history,
      failure: state.failure,
      busy: busy,
    ),
  );

  void _fail(Failure failure) {
    Log.e('steps', failure.message, failure.cause);
    emit(
      StepsState(
        access: state.access,
        history: state.history,
        failure: failure,
        busy: state.busy,
      ),
    );
  }
}
