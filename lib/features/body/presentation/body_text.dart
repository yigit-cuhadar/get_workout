import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/body_entry.dart';
import '../domain/body_validation.dart';

extension BodyText on AppLocalizations {
  String _number(double value) => (NumberFormat.decimalPattern(
    localeName,
  )..maximumFractionDigits = 1).format(value);

  String bodyWeightUnit(WeightUnit unit) => switch (unit) {
    WeightUnit.kg => unitKg,
    WeightUnit.lb => unitLb,
  };

  String bodyLengthUnit(LengthUnit unit) => switch (unit) {
    LengthUnit.cm => unitCm,
    LengthUnit.inch => unitIn,
  };

  String bodyWeight(double kg, WeightUnit unit) =>
      bodyQuantity(_number(unit.fromKg(kg)), bodyWeightUnit(unit));

  String bodyLength(double cm, LengthUnit unit) =>
      bodyQuantity(_number(unit.fromCm(cm)), bodyLengthUnit(unit));

  /// Signed; "0" for no change.
  String bodyWeightChange(double kg, WeightUnit unit) =>
      _signed(unit.fromKg(kg), bodyWeightUnit(unit));

  String bodyLengthChange(double cm, LengthUnit unit) =>
      _signed(unit.fromCm(cm), bodyLengthUnit(unit));

  String _signed(double value, String unit) {
    final text = bodyQuantity(_number(value.abs()), unit);
    // Anything that rounds to zero shows no sign.
    if (_number(value.abs()) == _number(0)) return text;
    return value > 0 ? bodyIncrease(text) : bodyDecrease(text);
  }

  String measurementName(BodyMeasurement measurement) => switch (measurement) {
    BodyMeasurement.neck => bodyNeck,
    BodyMeasurement.shoulders => bodyShoulders,
    BodyMeasurement.chest => bodyChest,
    BodyMeasurement.waist => bodyWaist,
    BodyMeasurement.abdomen => bodyAbdomen,
    BodyMeasurement.hips => bodyHips,
    BodyMeasurement.leftUpperArm => bodyLeftUpperArm,
    BodyMeasurement.rightUpperArm => bodyRightUpperArm,
    BodyMeasurement.leftForearm => bodyLeftForearm,
    BodyMeasurement.rightForearm => bodyRightForearm,
    BodyMeasurement.leftThigh => bodyLeftThigh,
    BodyMeasurement.rightThigh => bodyRightThigh,
    BodyMeasurement.leftCalf => bodyLeftCalf,
    BodyMeasurement.rightCalf => bodyRightCalf,
  };

  String poseName(PhotoPose pose) => switch (pose) {
    PhotoPose.front => bodyPoseFront,
    PhotoPose.right => bodyPoseRight,
    PhotoPose.left => bodyPoseLeft,
    PhotoPose.back => bodyPoseBack,
  };

  /// What the entry holds besides its weight, e.g. "5 measurements · 4
  /// photos"; null for a quick weight log.
  String? entryContents(BodyEntry entry) {
    final parts = [
      if (entry.measurements.isNotEmpty)
        bodyMeasurementCount(entry.measurements.length),
      if (entry.photos.isNotEmpty) bodyPhotoCount(entry.photos.length),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String bodyWeightRange(WeightUnit unit) => bodyErrorWeight(
    bodyWeight(BodyLimits.minWeightKg, unit),
    bodyWeight(BodyLimits.maxWeightKg, unit),
  );

  String bodyMeasurementRange(LengthUnit unit) => bodyErrorMeasurement(
    bodyLength(BodyLimits.minMeasurementCm, unit),
    bodyLength(BodyLimits.maxMeasurementCm, unit),
  );
}
