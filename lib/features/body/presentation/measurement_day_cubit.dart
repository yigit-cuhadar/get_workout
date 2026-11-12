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
  List<Object?> get props => [measurement];
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

  /// The value of the current step is out of range.
  final bool invalid;
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
    status,
    failure,
  ];
}

/// What a measurement day starts from: the entry being edited (null for a
/// new day), the user's entries (newest first, for the ghosts), what they
/// track and their units.
typedef MeasurementDaySetup = ({
  BodyEntry? initial,
  List<BodyEntry> entries,
  Set<BodyMeasurement> tracked,
  WeightUnit weightUnit,
  LengthUnit lengthUnit,
});

/// A measurement day, step by step: the weight, each tracked measurement,
/// then a photo of each pose. Every step can be skipped; the last one
/// saves. Edits [MeasurementDaySetup.initial] when given. Closes when the
/// signed-in user changes.
class MeasurementDayCubit extends Cubit<MeasurementDayState> {
  MeasurementDayCubit({
    required MeasurementDaySetup setup,
    required this._saveEntry,
    required this._newEntryId,
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
    unawaited(_findPhotos(setup, restorePhoto, clock ?? DateTime.now));
  }

  final SaveBodyEntry _saveEntry;
  final NewBodyEntryId _newEntryId;
  final BodyEntry? _initial;
  final WeightUnit _weightUnit;
  final LengthUnit _lengthUnit;
  final GetCurrentUser _getCurrentUser;
  final DateTime Function() _clock;
  final String? _uid;
  late final StreamSubscription<String?> _userSubscription;

  bool get isEditing => _initial != null;

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
  /// their usual order.
  static List<MeasureStep> _steps(
    Set<BodyMeasurement> tracked,
    BodyEntry? initial,
  ) => [
    const WeightStep(),
    for (final measurement in BodyMeasurement.values)
      if (tracked.contains(measurement) ||
          (initial?.measurements.containsKey(measurement) ?? false))
        MeasurementStep(measurement),
    for (final pose in PhotoPose.values) PhotoStep(pose),
  ];

  Future<void> _findPhotos(
    MeasurementDaySetup setup,
    RestoreBodyPhoto restorePhoto,
    DateTime Function() clock,
  ) async {
    final initial = setup.initial;
    final previous = previousPhotos(
      setup.entries,
      date: initial?.date ?? clock(),
      excludeId: initial?.id,
    );
    final kept = initial?.photos ?? const {};
    // Fetched from the backup when not on this device.
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
  /// step when it is still there.
  void setTracked(Set<BodyMeasurement> tracked) {
    if (state.status != MeasurementDayStatus.editing) return;
    final steps = _steps(tracked, _initial);
    final index = steps.indexOf(state.step);
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

  /// The value of the current step, a measurement.
  void setMeasurement(String text) {
    if (state.step case MeasurementStep(:final measurement)) {
      _edit(
        state.copyWith(
          measurements: {...state.measurements, measurement: text},
          invalid: false,
        ),
      );
    }
  }

  /// [file] is the picture just taken for the current step, a photo.
  void photoTaken(String file) {
    if (state.step case PhotoStep(:final pose)) {
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

  /// Moves on once the current value is in range; the last step saves.
  Future<void> next() async {
    if (!_canMove) return;
    if (!_valid(state.step)) {
      emit(state.copyWith(invalid: true));
      return;
    }
    await _advance();
  }

  /// Moves on without the current step's value. A stored photo stays.
  Future<void> skip() async {
    if (!_canMove) return;
    final cleared = switch (state.step) {
      WeightStep() => state.copyWith(weight: ''),
      MeasurementStep(:final measurement) => state.copyWith(
        measurements: {...state.measurements}..remove(measurement),
      ),
      PhotoStep(:final pose) => state.copyWith(
        newPhotos: {...state.newPhotos}..remove(pose),
      ),
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
    MeasurementStep(:final measurement) => switch (_cm(measurement)) {
      null => true,
      final cm => BodyLimits.measurementCm(cm),
    },
    PhotoStep() => true,
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
      emit(state.copyWith(index: invalidAt, invalid: true));
      return;
    }
    final initial = _initial;
    final entry = BodyEntry(
      id: initial?.id ?? _newEntryId(uid),
      date: initial?.date ?? _clock(),
      weightKg: _weightKg,
      measurements: {
        for (final step in state.steps)
          if (step case MeasurementStep(:final measurement))
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

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    return super.close();
  }
}
