import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../analytics/domain/analytics.dart';
import '../../profile/domain/user_profile.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/body_entry.dart';
import '../domain/body_stats.dart';
import '../domain/body_usecases.dart';
import '../domain/body_validation.dart';
import '../domain/entry_body_fat.dart';
import 'body_input.dart';

/// The three steps of a measurement day, in order.
enum MeasureStep { weight, measurements, photos }

enum MeasurementDayStatus {
  editing,
  saving,
  saved,
  saveFailed,

  /// The signed-in user changed; the flow must close.
  closed,
}

class MeasurementDayState extends Equatable {
  const MeasurementDayState({
    required this.weight,
    required this.groups,
    this.step = MeasureStep.weight,
    this.measurements = const {},
    this.invalidMeasurements = const {},
    this.newPhotos = const {},
    this.keptPhotos = const {},
    this.keptFiles = const {},
    this.ghosts = const {},
    this.camera,
    this.status = MeasurementDayStatus.editing,
    this.failure,
  });

  final MeasureStep step;

  /// On the ruler, in the user's weight unit.
  final double weight;

  /// The measurement rows: a measurement alone, or both sides of a pair.
  final List<List<BodyMeasurement>> groups;

  /// In the user's length unit, as typed.
  final Map<BodyMeasurement, String> measurements;

  /// The measurements whose value is out of range, once Next was tapped
  /// on them; then kept up to date.
  final Set<BodyMeasurement> invalidMeasurements;

  /// Pictures taken in this flow, as files.
  final Map<PhotoPose, String> newPhotos;

  /// The stored photos of the entry being edited, by storage path; a new
  /// picture replaces one.
  final Map<PhotoPose, String> keptPhotos;

  /// The files of [keptPhotos] on this device.
  final Map<PhotoPose, String> keptFiles;

  /// The file of the previous photo of each pose, to line a new one up with.
  final Map<PhotoPose, String> ghosts;

  /// The pose the camera is open for, on the photos step.
  final PhotoPose? camera;
  final MeasurementDayStatus status;
  final Failure? failure;

  /// The picture shown for [pose]: a new one, else the kept one.
  String? photoFile(PhotoPose pose) => newPhotos[pose] ?? keptFiles[pose];

  MeasurementDayState copyWith({
    MeasureStep? step,
    double? weight,
    List<List<BodyMeasurement>>? groups,
    Map<BodyMeasurement, String>? measurements,
    Set<BodyMeasurement>? invalidMeasurements,
    Map<PhotoPose, String>? newPhotos,
    Map<PhotoPose, String>? keptFiles,
    Map<PhotoPose, String>? ghosts,
    PhotoPose? Function()? camera,
    MeasurementDayStatus? status,
    Failure? failure,
  }) => MeasurementDayState(
    step: step ?? this.step,
    weight: weight ?? this.weight,
    groups: groups ?? this.groups,
    measurements: measurements ?? this.measurements,
    invalidMeasurements: invalidMeasurements ?? this.invalidMeasurements,
    newPhotos: newPhotos ?? this.newPhotos,
    keptPhotos: keptPhotos,
    keptFiles: keptFiles ?? this.keptFiles,
    ghosts: ghosts ?? this.ghosts,
    camera: camera == null ? this.camera : camera(),
    status: status ?? this.status,
    failure: failure,
  );

  @override
  List<Object?> get props => [
    step,
    weight,
    groups,
    measurements,
    invalidMeasurements,
    newPhotos,
    keptPhotos,
    keptFiles,
    ghosts,
    camera,
    status,
    failure,
  ];
}

/// What a measurement day starts from: the entry being edited (null for a
/// new day), what the user tracks, their units, and where the weight ruler
/// starts when the entry has no weight.
typedef MeasurementDaySetup = ({
  BodyEntry? initial,
  Set<BodyMeasurement> tracked,
  WeightUnit weightUnit,
  LengthUnit lengthUnit,
  double startKg,
});

/// A measurement day in three steps: the weight on a ruler, which cannot
/// be skipped (MD11); each tracked measurement, both sides of a pair on
/// one row, any left empty; and a photo of each pose, any left out. The
/// last step saves. Edits [MeasurementDaySetup.initial] when given: an
/// emptied measurement clears it, a photo not retaken stays. The previous
/// photos are loaded here, so the flow also works when opened first, e.g.
/// from a reminder. Pictures taken and not kept are removed. Closes when
/// the signed-in user changes.
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
    required this._analytics,
    DateTime Function()? clock,
  }) : _initial = setup.initial,
       _weightUnit = setup.weightUnit,
       _lengthUnit = setup.lengthUnit,
       _getCurrentUser = getCurrentUser,
       _uid = getCurrentUser()?.id,
       _clock = clock ?? DateTime.now,
       super(_initialState(setup)) {
    _start = state;
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          if (uid != _uid) _close();
        });
    unawaited(_findPhotos(watchEntries, restorePhoto));
  }

  final SaveBodyEntry _saveEntry;
  final Analytics _analytics;
  final NewBodyEntryId _newEntryId;
  final DiscardCapture _discardCapture;
  final BodyEntry? _initial;
  final WeightUnit _weightUnit;
  final LengthUnit _lengthUnit;
  final GetCurrentUser _getCurrentUser;
  final DateTime Function() _clock;
  final String? _uid;
  late final StreamSubscription<String?> _userSubscription;

  /// What [hasChanges] compares against.
  late final MeasurementDayState _start;

  /// Set once Next was tapped on the measurements.
  bool _checked = false;

  /// Fixed at the first save, so a retry saves the same entry.
  String? _entryId;
  DateTime? _date;

  bool get isEditing => _initial != null;

  /// The weight or a value differs from those the flow opened with (none
  /// for a new day), or a picture was taken; nothing once it saved or
  /// closed.
  bool get hasChanges => switch (state.status) {
    MeasurementDayStatus.saved || MeasurementDayStatus.closed => false,
    _ =>
      state.weight != _start.weight ||
          state.newPhotos.isNotEmpty ||
          !_sameEntered(state.measurements, _start.measurements),
  };

  /// Whether [a] and [b] hold the same non-empty texts; an emptied field of
  /// a new day is nothing entered.
  static bool _sameEntered(
    Map<BodyMeasurement, String> a,
    Map<BodyMeasurement, String> b,
  ) {
    Map<BodyMeasurement, String> entered(Map<BodyMeasurement, String> map) =>
        {...map}..removeWhere((_, text) => text.isEmpty);
    final left = entered(a);
    final right = entered(b);
    return left.length == right.length &&
        left.entries.every((entry) => right[entry.key] == entry.value);
  }

  /// The id of the new entry once saved, for its summary; null before, and
  /// when editing.
  String? get savedNewId =>
      state.status == MeasurementDayStatus.saved && !isEditing
      ? _entryId
      : null;

  static MeasurementDayState _initialState(MeasurementDaySetup setup) {
    final initial = setup.initial;
    return MeasurementDayState(
      weight: rulerWeight(initial?.weightKg ?? setup.startKg, setup.weightUnit),
      groups: _groups(setup.tracked, initial),
      measurements: {
        for (final MapEntry(:key, :value)
            in (initial?.measurements ?? const {}).entries)
          key: metricText(value, setup.lengthUnit.fromCm),
      },
      keptPhotos: initial?.photos ?? const {},
    );
  }

  /// The tracked measurements, plus those the edited entry already has, in
  /// their usual order; both sides of a pair share a row.
  static List<List<BodyMeasurement>> _groups(
    Set<BodyMeasurement> tracked,
    BodyEntry? initial,
  ) => pairedMeasurements({...tracked, ...?initial?.measurements.keys});

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

  /// Follows a change of the tracked measurements.
  void setTracked(Set<BodyMeasurement> tracked) {
    if (state.status != MeasurementDayStatus.editing) return;
    final groups = _groups(tracked, _initial);
    emit(
      state.copyWith(
        groups: groups,
        invalidMeasurements: _checked ? _invalid(groups) : const {},
      ),
    );
  }

  /// [value] in the user's weight unit.
  void setWeight(double value) => _edit(state.copyWith(weight: value));

  void setMeasurement(BodyMeasurement measurement, String text) {
    final next = state.copyWith(
      measurements: {...state.measurements, measurement: text},
    );
    _edit(
      _checked
          ? next.copyWith(invalidMeasurements: _invalid(next.groups, next))
          : next,
    );
  }

  /// Opens the camera for [pose] on the photos step, over its picture if it
  /// has one.
  void openCamera(PhotoPose pose) {
    if (state.step == MeasureStep.photos) {
      _edit(state.copyWith(camera: () => pose));
    }
  }

  /// Back to the photos without a new picture ("Skip this photo").
  void closeCamera() => _edit(state.copyWith(camera: () => null));

  /// [file] is the picture just taken with the camera open; one taken
  /// before for its pose is removed.
  void photoTaken(String file) {
    final pose = state.camera;
    if (pose == null || !_canMove) {
      unawaited(_discardCapture(file));
      return;
    }
    if (state.newPhotos[pose] case final earlier?) {
      unawaited(_discardCapture(earlier));
    }
    _edit(
      state.copyWith(
        newPhotos: {...state.newPhotos, pose: file},
        camera: () => null,
      ),
    );
  }

  void _edit(MeasurementDayState next) {
    if (!_canMove) return;
    emit(next.copyWith(status: MeasurementDayStatus.editing));
  }

  /// Moves on; the measurements only once every value is in range; the
  /// photos save.
  Future<void> next() async {
    if (!_canMove) return;
    switch (state.step) {
      case MeasureStep.weight:
        _edit(state.copyWith(step: MeasureStep.measurements));
      case MeasureStep.measurements:
        _checked = true;
        final invalid = _invalid(state.groups);
        if (invalid.isNotEmpty) {
          emit(state.copyWith(invalidMeasurements: invalid));
          return;
        }
        _edit(
          state.copyWith(
            step: MeasureStep.photos,
            invalidMeasurements: const {},
          ),
        );
      case MeasureStep.photos:
        await _save();
    }
  }

  /// One step back, or out of the open camera; false on the first step,
  /// where going back leaves the flow.
  bool back() {
    if (!_canMove) return false;
    if (state.camera != null) {
      closeCamera();
      return true;
    }
    if (state.step == MeasureStep.weight) return false;
    _edit(state.copyWith(step: MeasureStep.values[state.step.index - 1]));
    return true;
  }

  bool get _canMove => switch (state.status) {
    MeasurementDayStatus.saving ||
    MeasurementDayStatus.saved ||
    MeasurementDayStatus.closed => false,
    _ => true,
  };

  Set<BodyMeasurement> _invalid(
    List<List<BodyMeasurement>> groups, [
    MeasurementDayState? input,
  ]) => {
    for (final group in groups)
      for (final measurement in group)
        if (_cm(measurement, input ?? state) case final cm?
            when !BodyLimits.measurementCm(cm))
          measurement,
  };

  double? _cm(BodyMeasurement measurement, MeasurementDayState input) =>
      readMetric(
        input.measurements[measurement] ?? '',
        stored: _initial?.measurements[measurement],
        fromMetric: _lengthUnit.fromCm,
        toMetric: _lengthUnit.toCm,
      );

  /// The typed measurements in range, in cm.
  Map<BodyMeasurement, double> get _validCm => {
    for (final group in state.groups)
      for (final measurement in group)
        if (_cm(measurement, state) case final cm?
            when BodyLimits.measurementCm(cm))
          measurement: cm,
  };

  /// The body fat the typed measurements give a person of [sex] and
  /// [heightCm], live as they are typed (MD10).
  EntryBodyFat bodyFat({required Sex? sex, required double? heightCm}) =>
      entryBodyFat(_validCm, sex: sex, heightCm: heightCm);

  void _close() {
    if (state.status != MeasurementDayStatus.closed && !isClosed) {
      emit(state.copyWith(status: MeasurementDayStatus.closed));
    }
  }

  /// Measurements no longer among the rows are left out; an invalid value
  /// sends the user back to the measurements.
  Future<void> _save() async {
    final uid = _getCurrentUser()?.id;
    if (uid == null || uid != _uid) return _close();
    final invalid = _invalid(state.groups);
    if (invalid.isNotEmpty) {
      _checked = true;
      emit(
        state.copyWith(
          step: MeasureStep.measurements,
          invalidMeasurements: invalid,
        ),
      );
      return;
    }
    final initial = _initial;
    final entry = BodyEntry(
      id: _entryId ??= initial?.id ?? _newEntryId(uid),
      date: _date ??= initial?.date ?? _clock(),
      weightKg: rulerWeightKg(
        state.weight,
        _weightUnit,
        stored: initial?.weightKg,
      ),
      measurements: _validCm,
      photos: state.keptPhotos,
    );
    emit(state.copyWith(status: MeasurementDayStatus.saving));
    final photos = state.keptPhotos.length + state.newPhotos.length;
    final failure = (await _saveEntry((
      uid: uid,
      entry: entry,
      newPhotos: state.newPhotos,
      isNew: initial == null,
    ))).failureOrNull;
    if (failure == null && initial == null) {
      unawaited(_analytics.measurementDaySave(photos: photos));
    }
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
