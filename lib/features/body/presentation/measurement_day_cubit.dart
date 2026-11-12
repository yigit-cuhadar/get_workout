import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import '../domain/body_entry.dart';
import '../domain/body_stats.dart';
import '../domain/body_usecases.dart';
import '../domain/body_validation.dart';
import 'body_input.dart';

/// One step of a measurement day.
sealed class MeasureStep extends Equatable {
  const MeasureStep();

  /// The measurements asked for on this step.
  List<BodyMeasurement> get measurements => const [];
}

class WeightStep extends MeasureStep {
  const WeightStep();

  @override
  List<Object?> get props => [];
}

class MeasurementStep extends MeasureStep {
  const MeasurementStep(this.measurement);
  final BodyMeasurement measurement;

  @override
  List<BodyMeasurement> get measurements => [measurement];

  @override
  List<Object?> get props => [measurement];
}

/// Both sides of a pair, such as the left and right thigh, on one step.
class PairStep extends MeasureStep {
  const PairStep(this.left, this.right);
  final BodyMeasurement left;
  final BodyMeasurement right;

  @override
  List<BodyMeasurement> get measurements => [left, right];

  @override
  List<Object?> get props => [left, right];
}

class PhotoStep extends MeasureStep {
  const PhotoStep(this.pose);
  final PhotoPose pose;

  @override
  List<Object?> get props => [pose];
}

enum MeasurementDayStatus {
  editing,
  saving,
  saved,
  saveFailed,

  /// Every step was skipped; there is nothing to save.
  empty,

  /// The signed-in user changed; the flow must close.
  closed,
}

class MeasurementDayState extends Equatable {
  const MeasurementDayState({
    required this.steps,
    this.index = 0,
    this.weight = '',
    this.measurements = const {},
    this.newPhotos = const {},
    this.keptPhotos = const {},
    this.keptFiles = const {},
    this.ghosts = const {},
    this.invalid = false,
    this.invalidMeasurements = const {},
    this.status = MeasurementDayStatus.editing,
    this.failure,
  });

  final List<MeasureStep> steps;
  final int index;

  /// In the user's weight unit, as typed.
  final String weight;

  /// In the user's length unit, as typed.
  final Map<BodyMeasurement, String> measurements;

  /// Pictures taken in this flow, as files.
  final Map<PhotoPose, String> newPhotos;

  /// The stored photos of the entry being edited, by storage path; a new
  /// picture replaces one.
  final Map<PhotoPose, String> keptPhotos;

  /// The files of [keptPhotos] on this device.
  final Map<PhotoPose, String> keptFiles;

  /// The file of the previous photo of each pose, to line a new one up with.
  final Map<PhotoPose, String> ghosts;

  /// A value of the current step is out of range.
  final bool invalid;

  /// Those of the current step's measurements whose value is out of
  /// range, while [invalid].
  final Set<BodyMeasurement> invalidMeasurements;
  final MeasurementDayStatus status;
  final Failure? failure;

  MeasureStep get step => steps[index];
  bool get isLast => index == steps.length - 1;

  /// The picture shown for [pose]: a new one, else the kept one.
  String? photoFile(PhotoPose pose) => newPhotos[pose] ?? keptFiles[pose];

  MeasurementDayState copyWith({
    List<MeasureStep>? steps,
    int? index,
    String? weight,
    Map<BodyMeasurement, String>? measurements,
    Map<PhotoPose, String>? newPhotos,
    Map<PhotoPose, String>? keptFiles,
    Map<PhotoPose, String>? ghosts,
    bool? invalid,
    Set<BodyMeasurement>? invalidMeasurements,
    MeasurementDayStatus? status,
    Failure? failure,
  }) => MeasurementDayState(
    steps: steps ?? this.steps,
    index: index ?? this.index,
    weight: weight ?? this.weight,
    measurements: measurements ?? this.measurements,
    newPhotos: newPhotos ?? this.newPhotos,
    keptPhotos: keptPhotos,
    keptFiles: keptFiles ?? this.keptFiles,
    ghosts: ghosts ?? this.ghosts,
    invalid: invalid ?? this.invalid,
    // Cleared with [invalid].
    invalidMeasurements: invalid == false
        ? const {}
        : invalidMeasurements ?? this.invalidMeasurements,
    status: status ?? this.status,
    failure: failure,
  );

  @override
  List<Object?> get props => [
    steps,
    index,
    weight,
    measurements,
    newPhotos,
    keptPhotos,
    keptFiles,
    ghosts,
    invalid,
    invalidMeasurements,
    status,
    failure,
  ];
}

/// What a measurement day starts from: the entry being edited (null for a
/// new day), what the user tracks and their units.
typedef MeasurementDaySetup = ({
  BodyEntry? initial,
  Set<BodyMeasurement> tracked,
  WeightUnit weightUnit,
  LengthUnit lengthUnit,
});

/// A measurement day, step by step: the weight, each tracked measurement
/// (both sides of a pair on one step), then a photo of each pose. Every step can be skipped; the last one
/// saves. Edits [MeasurementDaySetup.initial] when given; skipping a step
/// then keeps its stored value, and only an emptied field clears one. The
/// previous photos are loaded here, so the flow also works when opened
/// first, e.g. from a reminder. Pictures taken and not kept are removed.
/// Closes when the signed-in user changes.
class MeasurementDayCubit extends Cubit<MeasurementDayState> {
  MeasurementDayCubit({
    required MeasurementDaySetup setup,
    required this._saveEntry,
    required this._newEntryId,
    required this._discardCapture,
    required WatchBodyEntries watchEntries,
    required RestoreBodyPhoto restorePhoto,
    required GetCurrentUser getCurrentUser,
    required WatchAuthUser watchAuthUser,
    DateTime Function()? clock,
  }) : _initial = setup.initial,
       _weightUnit = setup.weightUnit,
       _lengthUnit = setup.lengthUnit,
       _getCurrentUser = getCurrentUser,
       _uid = getCurrentUser()?.id,
       _clock = clock ?? DateTime.now,
       super(_initialState(setup)) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          if (uid != _uid) _close();
        });
    unawaited(_findPhotos(watchEntries, restorePhoto));
  }

  final SaveBodyEntry _saveEntry;
  final NewBodyEntryId _newEntryId;
  final DiscardCapture _discardCapture;
  final BodyEntry? _initial;
  final WeightUnit _weightUnit;
  final LengthUnit _lengthUnit;
  final GetCurrentUser _getCurrentUser;
  final DateTime Function() _clock;
  final String? _uid;
  late final StreamSubscription<String?> _userSubscription;

  /// Fixed at the first save, so a retry saves the same entry.
  String? _entryId;
  DateTime? _date;

  bool get isEditing => _initial != null;

  /// Something was entered that leaving the flow would lose; nothing once
  /// it saved or closed.
  bool get hasChanges => switch (state.status) {
    MeasurementDayStatus.saved || MeasurementDayStatus.closed => false,
    _ =>
      state.weight.isNotEmpty ||
          state.measurements.values.any((text) => text.isNotEmpty) ||
          state.newPhotos.isNotEmpty,
  };

  /// The id of the new entry once saved, for its summary; null before, and
  /// when editing.
  String? get savedNewId =>
      state.status == MeasurementDayStatus.saved && !isEditing
      ? _entryId
      : null;

  static MeasurementDayState _initialState(MeasurementDaySetup setup) {
    final initial = setup.initial;
    return MeasurementDayState(
      steps: _steps(setup.tracked, initial),
      weight: metricText(initial?.weightKg, setup.weightUnit.fromKg),
      measurements: {
        for (final MapEntry(:key, :value)
            in (initial?.measurements ?? const {}).entries)
          key: metricText(value, setup.lengthUnit.fromCm),
      },
      keptPhotos: initial?.photos ?? const {},
    );
  }

  /// The tracked measurements, plus those the edited entry already has, in
  /// their usual order; both sides of a pair share a step.
  static List<MeasureStep> _steps(
    Set<BodyMeasurement> tracked,
    BodyEntry? initial,
  ) => [
    const WeightStep(),
    for (final group in pairedMeasurements({
      ...tracked,
      ...?initial?.measurements.keys,
    }))
      switch (group) {
        [final left, final right] => PairStep(left, right),
        _ => MeasurementStep(group.single),
      },
    for (final pose in PhotoPose.values) PhotoStep(pose),
  ];

  /// The ghosts and the edited entry's photos, fetched from the backup
  /// when not on this device.
  Future<void> _findPhotos(
    WatchBodyEntries watchEntries,
    RestoreBodyPhoto restorePhoto,
  ) async {
    final uid = _uid;
    if (uid == null) return;
    final initial = _initial;
    final List<BodyEntry> entries;
    try {
      entries = await watchEntries(uid).first;
    } on Object catch (error, stack) {
      Log.e('body', 'no ghosts: entries not loaded', error, stack);
      return;
    }
    final previous = previousPhotos(
      entries,
      date: initial?.date ?? _clock(),
      excludeId: initial?.id,
    );
    final kept = initial?.photos ?? const {};
    final paths = {...previous.values, ...kept.values}.toList();
    final found = await Future.wait(paths.map(restorePhoto.call));
    final files = {for (final (i, path) in paths.indexed) path: ?found[i]};
    if (isClosed) return;
    Map<PhotoPose, String> present(Map<PhotoPose, String> paths) => {
      for (final MapEntry(:key, :value) in paths.entries) key: ?files[value],
    };
    emit(state.copyWith(ghosts: present(previous), keptFiles: present(kept)));
  }

  /// Follows a change of the tracked measurements, staying on the current
  /// step when it is still there, or on one with a measurement of it (a
  /// pair that lost or gained a side).
  void setTracked(Set<BodyMeasurement> tracked) {
    if (state.status != MeasurementDayStatus.editing) return;
    final steps = _steps(tracked, _initial);
    final current = state.step;
    var index = steps.indexOf(current);
    if (index < 0 && current.measurements.isNotEmpty) {
      index = steps.indexWhere(
        (step) => step.measurements.any(current.measurements.contains),
      );
    }
    emit(
      state.copyWith(
        steps: steps,
        index: index < 0 ? state.index.clamp(0, steps.length - 1) : index,
        invalid: false,
      ),
    );
  }

  void setWeight(String text) =>
      _edit(state.copyWith(weight: text, invalid: false));

  /// The value of [measurement], one of the current step's.
  void setMeasurement(BodyMeasurement measurement, String text) {
    if (state.step.measurements.contains(measurement)) {
      _edit(
        state.copyWith(
          measurements: {...state.measurements, measurement: text},
          invalid: false,
        ),
      );
    }
  }

  /// [file] is the picture just taken for the current step, a photo; one
  /// taken before for it is removed.
  void photoTaken(String file) {
    if (state.status
        case MeasurementDayStatus.saving || MeasurementDayStatus.closed) {
      unawaited(_discardCapture(file));
      return;
    }
    if (state.step case PhotoStep(:final pose)) {
      if (state.newPhotos[pose] case final earlier?) {
        unawaited(_discardCapture(earlier));
      }
      _edit(state.copyWith(newPhotos: {...state.newPhotos, pose: file}));
    }
  }

  void _edit(MeasurementDayState next) {
    if (state.status
        case MeasurementDayStatus.saving || MeasurementDayStatus.closed) {
      return;
    }
    emit(next.copyWith(status: MeasurementDayStatus.editing));
  }

  /// Moves on once the current values are in range; the last step saves.
  Future<void> next() async {
    if (!_canMove) return;
    if (!_valid(state.step)) {
      emit(
        state.copyWith(
          invalid: true,
          invalidMeasurements: _invalidMeasurements(state.step),
        ),
      );
      return;
    }
    await _advance();
  }

  /// Moves on without changing the current step: what the edited entry
  /// stores stays (a value typed here is dropped, on both fields of a
  /// pair), as does a stored photo.
  Future<void> skip() async {
    if (!_canMove) return;
    final initial = _initial;
    final cleared = switch (state.step) {
      WeightStep() => state.copyWith(
        weight: metricText(initial?.weightKg, _weightUnit.fromKg),
      ),
      MeasurementStep() || PairStep() => state.copyWith(
        measurements: {
          ...state.measurements,
          for (final measurement in state.step.measurements)
            measurement: metricText(
              initial?.measurements[measurement],
              _lengthUnit.fromCm,
            ),
        },
      ),
      PhotoStep(:final pose) => () {
        if (state.newPhotos[pose] case final taken?) {
          unawaited(_discardCapture(taken));
        }
        return state.copyWith(newPhotos: {...state.newPhotos}..remove(pose));
      }(),
    };
    emit(
      cleared.copyWith(invalid: false, status: MeasurementDayStatus.editing),
    );
    await _advance();
  }

  /// False on the first step, where going back leaves the flow.
  bool back() {
    if (!_canMove || state.index == 0) return false;
    emit(
      state.copyWith(
        index: state.index - 1,
        invalid: false,
        status: MeasurementDayStatus.editing,
      ),
    );
    return true;
  }

  bool get _canMove => switch (state.status) {
    MeasurementDayStatus.saving ||
    MeasurementDayStatus.saved ||
    MeasurementDayStatus.closed => false,
    _ => true,
  };

  Future<void> _advance() async {
    if (state.isLast) return _save();
    emit(state.copyWith(index: state.index + 1));
  }

  bool _valid(MeasureStep step) => switch (step) {
    WeightStep() => switch (_weightKg) {
      null => true,
      final kg => BodyLimits.weightKg(kg),
    },
    MeasurementStep() || PairStep() => _invalidMeasurements(step).isEmpty,
    PhotoStep() => true,
  };

  Set<BodyMeasurement> _invalidMeasurements(MeasureStep step) => {
    for (final measurement in step.measurements)
      if (_cm(measurement) case final cm? when !BodyLimits.measurementCm(cm))
        measurement,
  };

  double? get _weightKg => readMetric(
    state.weight,
    stored: _initial?.weightKg,
    fromMetric: _weightUnit.fromKg,
    toMetric: _weightUnit.toKg,
  );

  double? _cm(BodyMeasurement measurement) => readMetric(
    state.measurements[measurement] ?? '',
    stored: _initial?.measurements[measurement],
    fromMetric: _lengthUnit.fromCm,
    toMetric: _lengthUnit.toCm,
  );

  void _close() {
    if (state.status != MeasurementDayStatus.closed && !isClosed) {
      emit(state.copyWith(status: MeasurementDayStatus.closed));
    }
  }

  /// Measurements no longer among the steps are left out, as are invalid
  /// values of steps passed by going back and editing; those send the user
  /// to their step.
  Future<void> _save() async {
    final uid = _getCurrentUser()?.id;
    if (uid == null || uid != _uid) return _close();
    final invalidAt = state.steps.indexWhere((step) => !_valid(step));
    if (invalidAt >= 0) {
      emit(
        state.copyWith(
          index: invalidAt,
          invalid: true,
          invalidMeasurements: _invalidMeasurements(state.steps[invalidAt]),
        ),
      );
      return;
    }
    final initial = _initial;
    final entry = BodyEntry(
      id: _entryId ??= initial?.id ?? _newEntryId(uid),
      date: _date ??= initial?.date ?? _clock(),
      weightKg: _weightKg,
      measurements: {
        for (final step in state.steps)
          for (final measurement in step.measurements)
            measurement: ?_cm(measurement),
      },
      photos: state.keptPhotos,
    );
    if (entry.isEmpty && state.newPhotos.isEmpty) {
      emit(state.copyWith(status: MeasurementDayStatus.empty));
      return;
    }
    emit(state.copyWith(status: MeasurementDayStatus.saving));
    final failure = (await _saveEntry((
      uid: uid,
      entry: entry,
      newPhotos: state.newPhotos,
      isNew: initial == null,
    ))).failureOrNull;
    if (isClosed || state.status == MeasurementDayStatus.closed) return;
    emit(
      failure == null
          ? state.copyWith(status: MeasurementDayStatus.saved)
          : state.copyWith(
              status: MeasurementDayStatus.saveFailed,
              failure: failure,
            ),
    );
  }

  /// The pictures taken are no longer needed: after a save they were
  /// stored (and already removed), otherwise the flow was left.
  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    for (final file in state.newPhotos.values) {
      await _discardCapture(file);
    }
    return super.close();
  }
}
