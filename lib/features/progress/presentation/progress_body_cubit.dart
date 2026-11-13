import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../body/presentation/body_list_cubit.dart';
import '../domain/body_snapshot.dart';

class ProgressBodyState extends Equatable {
  const ProgressBodyState({
    this.status = BodyListStatus.loading,
    this.empty = true,
    this.snapshot = const BodySnapshot(),
  });

  /// As the body list's.
  final BodyListStatus status;

  /// Nothing is logged.
  final bool empty;
  final BodySnapshot snapshot;

  @override
  List<Object?> get props => [status, empty, snapshot];
}

/// The [bodySnapshot] of the app's body list, for the Progress tab. Its
/// 12 weeks end today: [refreshNow] moves them on, e.g. after the app
/// slept over midnight.
class ProgressBodyCubit extends Cubit<ProgressBodyState> {
  ProgressBodyCubit({
    required BodyListCubit bodyList,
    DateTime Function()? clock,
  }) : _bodyList = bodyList,
       _clock = clock ?? DateTime.now,
       super(const ProgressBodyState()) {
    _publish(bodyList.state);
    _subscription = bodyList.stream.listen(_publish);
  }

  final BodyListCubit _bodyList;
  final DateTime Function() _clock;
  late final StreamSubscription<BodyListState> _subscription;

  void refreshNow() => _publish(_bodyList.state);

  void retry() => _bodyList.retry();

  void _publish(BodyListState list) => emit(
    ProgressBodyState(
      status: list.status,
      empty: list.entries.isEmpty,
      snapshot: bodySnapshot(list.entries, list.bodyFat, now: _clock()),
    ),
  );

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
