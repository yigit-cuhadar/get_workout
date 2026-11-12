import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import '../domain/body_entry.dart';
import '../domain/body_usecases.dart';
import '../domain/body_validation.dart';
import 'body_input.dart';

enum WeightFormStatus {
  editing,
  saving,
  saved,
  saveFailed,

  /// The signed-in user changed; the form must close.
  closed,
}

/// The weight as typed, in the user's unit.
class WeightFormState extends Equatable {
  const WeightFormState({
    required this.date,
    this.weight = '',
    this.issues = const {},
    this.status = WeightFormStatus.editing,
    this.failure,
  });

  final DateTime date;
  final String weight;

  /// Shown once a save was attempted, then kept up to date.
  final Set<BodyIssue> issues;
  final WeightFormStatus status;
  final Failure? failure;

  WeightFormState copyWith({
    DateTime? date,
    String? weight,
    Set<BodyIssue>? issues,
    WeightFormStatus? status,
    Failure? failure,
  }) => WeightFormState(
    date: date ?? this.date,
    weight: weight ?? this.weight,
    issues: issues ?? this.issues,
    status: status ?? this.status,
    failure: failure,
  );

  @override
  List<Object?> get props => [date, weight, issues, status, failure];
}

/// Logs a weight, or edits the weight and date of [initial]; anything else
/// [initial] holds is kept. Closes when the signed-in user changes.
class WeightFormCubit extends Cubit<WeightFormState> {
  WeightFormCubit({
    required this._saveEntry,
    required this._newEntryId,
    required GetCurrentUser getCurrentUser,
    required WatchAuthUser watchAuthUser,
    required this._unit,
    this._initial,
    DateTime Function()? clock,
  }) : _getCurrentUser = getCurrentUser,
       _uid = getCurrentUser()?.id,
       _clock = clock ?? DateTime.now,
       super(
         WeightFormState(
           date: _initial?.date ?? (clock ?? DateTime.now)(),
           weight: metricText(_initial?.weightKg, _unit.fromKg),
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
  bool _submitted = false;

  bool get isEditing => _initial != null;

  void setWeight(String text) => _change(state.copyWith(weight: text));

  /// Today keeps the time of now; another day is logged at noon.
  void setDay(DateTime day) {
    final now = _clock();
    final today =
        day.year == now.year && day.month == now.month && day.day == now.day;
    _change(
      state.copyWith(
        date: today ? now : DateTime(day.year, day.month, day.day, 12),
      ),
    );
  }

  void _change(WeightFormState next) {
    if (state.status == WeightFormStatus.closed) return;
    final editing = next.copyWith(status: WeightFormStatus.editing);
    emit(_submitted ? editing.copyWith(issues: _check(editing).$2) : editing);
  }

  Future<void> save() async {
    if (state.status case WeightFormStatus.saving || WeightFormStatus.closed) {
      return;
    }
    _submitted = true;
    final uid = _getCurrentUser()?.id;
    if (uid == null || uid != _uid) {
      emit(state.copyWith(status: WeightFormStatus.closed));
      return;
    }
    final (entry, issues) = _check(state, id: _initial?.id ?? _newEntryId(uid));
    if (issues.isNotEmpty) {
      emit(state.copyWith(issues: issues, status: WeightFormStatus.editing));
      return;
    }
    emit(state.copyWith(status: WeightFormStatus.saving, issues: const {}));
    final failure = (await _saveEntry((
      uid: uid,
      entry: entry,
      newPhotos: const {},
      isNew: _initial == null,
    ))).failureOrNull;
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

  /// The entry the input describes, under [id], and what is wrong with it.
  /// A weight is required here, unlike on a measurement day.
  (BodyEntry, Set<BodyIssue>) _check(WeightFormState input, {String id = ''}) {
    final initial = _initial;
    final weight = readMetric(
      input.weight,
      stored: initial?.weightKg,
      fromMetric: _unit.fromKg,
      toMetric: _unit.toKg,
    );
    final entry = BodyEntry(
      id: id,
      date: input.date,
      weightKg: weight,
      measurements: initial?.measurements ?? const {},
      photos: initial?.photos ?? const {},
    );
    return (
      entry,
      {
        ...validateBodyEntry(entry, now: _clock()),
        if (weight == null) BodyIssue.weightOutOfRange,
      }..remove(BodyIssue.empty),
    );
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    return super.close();
  }
}
