import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../body/presentation/body_list_cubit.dart';
import '../../programs/domain/program_usecases.dart';
import '../domain/body_snapshot.dart';
import '../domain/progress_usecases.dart';

class ProgressBodyState extends Equatable {
  const ProgressBodyState({
    this.status = BodyListStatus.loading,
    this.snapshot = const BodySnapshot(),
  });

  /// As the body list's.
  final BodyListStatus status;
  final BodySnapshot snapshot;

  @override
  List<Object?> get props => [status, snapshot];
}

/// The [bodySnapshot] of the app's body list over [cardWeeks] (again when
/// Premium comes or goes), for the Progress tab. Its weeks end today:
/// [refreshNow] moves them on, e.g. after the app slept over midnight.
class ProgressBodyCubit extends Cubit<ProgressBodyState> {
  ProgressBodyCubit({
    required BodyListCubit bodyList,
    required WatchPremium watchPremium,
    DateTime Function()? clock,
  }) : _bodyList = bodyList,
       _clock = clock ?? DateTime.now,
       super(const ProgressBodyState()) {
    _publish(bodyList.state);
    _subscription = bodyList.stream.listen(_publish);
    _premiumSubscription = watchPremium().listen((premium) {
      _premium = premium;
      refreshNow();
    });
  }

  final BodyListCubit _bodyList;
  final DateTime Function() _clock;
  late final StreamSubscription<BodyListState> _subscription;
  late final StreamSubscription<bool?> _premiumSubscription;
  bool? _premium;

  void refreshNow() => _publish(_bodyList.state);

  void retry() => _bodyList.retry();

  void _publish(BodyListState list) => emit(
    ProgressBodyState(
      status: list.status,
      snapshot: bodySnapshot(
        list.entries,
        list.bodyFat,
        now: _clock(),
        weeks: cardWeeks(_premium),
      ),
    ),
  );

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _premiumSubscription.cancel();
    return super.close();
  }
}
