import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../analytics/domain/analytics.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/body_entry.dart';
import '../domain/body_usecases.dart';
import 'body_input.dart';

enum WeightFormStatus {
  editing,
  saving,
  saved,
  saveFailed,

  /// The signed-in user changed; the form must close.
  closed,
}

/// The weight on the ruler, in the user's unit, and when it was weighed.
class WeightFormState extends Equatable {
  const WeightFormState({
    required this.date,
    required this.weight,
    this.status = WeightFormStatus.editing,
    this.failure,
  });

  final DateTime date;
  final double weight;
  final WeightFormStatus status;
  final Failure? failure;

  WeightFormState copyWith({
    DateTime? date,
    double? weight,
    WeightFormStatus? status,
    Failure? failure,
  }) => WeightFormState(
    date: date ?? this.date,
    weight: weight ?? this.weight,
    status: status ?? this.status,
    failure: failure,
  );

  @override
  List<Object?> get props => [date, weight, status, failure];
}

/// What the weight sheet starts from: the entry edited (null for a new
/// log) and, for a new log, the weight its ruler starts at.
typedef WeightFormSetup = ({BodyEntry? initial, double startKg});

/// Logs a weight, or edits the weight and date of [WeightFormSetup.initial];
/// anything else it holds is kept. The ruler and the day picker only offer
/// values that can be saved. Closes when the signed-in user changes.
class WeightFormCubit extends Cubit<WeightFormState> {
  WeightFormCubit({
    required WeightFormSetup setup,
    required this._saveEntry,
    required this._newEntryId,
    required GetCurrentUser getCurrentUser,
    required WatchAuthUser watchAuthUser,
    required this._unit,
    required this._analytics,
    DateTime Function()? clock,
  }) : _initial = setup.initial,
       _getCurrentUser = getCurrentUser,
       _uid = getCurrentUser()?.id,
       _clock = clock ?? DateTime.now,
       super(
         WeightFormState(
           date: setup.initial?.date ?? (clock ?? DateTime.now)(),
           weight: rulerWeight(setup.initial?.weightKg ?? setup.startKg, _unit),
         ),
       ) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          if (uid != _uid && state.status != WeightFormStatus.closed) {
            emit(state.copyWith(status: WeightFormStatus.closed));
          }
        });
  }

  final SaveBodyEntry _saveEntry;
  final NewBodyEntryId _newEntryId;
  final GetCurrentUser _getCurrentUser;
  final WeightUnit _unit;
  final BodyEntry? _initial;
  final DateTime Function() _clock;
  final String? _uid;
  late final StreamSubscription<String?> _userSubscription;

  /// Fixed at the first save, so a retry saves the same entry.
  String? _entryId;
  final Analytics _analytics;

  bool get isEditing => _initial != null;

  /// [value] in the user's unit.
  void setWeight(double value) => _change(state.copyWith(weight: value));

  /// Today keeps the time of now; another day is logged at noon. The day
  /// already set keeps its time.
  void setDay(DateTime day) {
    bool same(DateTime other) =>
        day.year == other.year &&
        day.month == other.month &&
        day.day == other.day;
    if (same(state.date)) return;
    final now = _clock();
    final today = same(now);
    _change(
      state.copyWith(
        date: today ? now : DateTime(day.year, day.month, day.day, 12),
      ),
    );
  }

  void _change(WeightFormState next) {
    if (state.status case WeightFormStatus.saving || WeightFormStatus.closed) {
      return;
    }
    emit(next.copyWith(status: WeightFormStatus.editing));
  }

  Future<void> save() async {
    if (state.status case WeightFormStatus.saving || WeightFormStatus.closed) {
      return;
    }
    final uid = _getCurrentUser()?.id;
    if (uid == null || uid != _uid) {
      emit(state.copyWith(status: WeightFormStatus.closed));
      return;
    }
    final initial = _initial;
    final entry = BodyEntry(
      id: _entryId ??= initial?.id ?? _newEntryId(uid),
      date: state.date,
      weightKg: rulerWeightKg(state.weight, _unit, stored: initial?.weightKg),
      measurements: initial?.measurements ?? const {},
      photos: initial?.photos ?? const {},
    );
    emit(state.copyWith(status: WeightFormStatus.saving));
    final failure = (await _saveEntry((
      uid: uid,
      entry: entry,
      newPhotos: const {},
      isNew: initial == null,
    ))).failureOrNull;
    if (failure == null && initial == null) {
      unawaited(_analytics.weightLog());
    }
    if (isClosed || state.status == WeightFormStatus.closed) return;
    emit(
      failure == null
          ? state.copyWith(status: WeightFormStatus.saved)
          : state.copyWith(
              status: WeightFormStatus.saveFailed,
              failure: failure,
            ),
    );
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    return super.close();
  }
}
