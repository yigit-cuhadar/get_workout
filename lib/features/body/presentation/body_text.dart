import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/body_chart.dart';
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

  /// Signed, without the unit; "0" for no change.
  String bodyWeightChangeNumber(double kg, WeightUnit unit) {
    final value = unit.fromKg(kg);
    final text = _number(value.abs());
    if (text == _number(0)) return text;
    return value > 0 ? bodyIncrease(text) : bodyDecrease(text);
  }

  /// [kg] in [unit], without the unit.
  String bodyWeightNumber(double kg, WeightUnit unit) =>
      _number(unit.fromKg(kg));

  /// [cm] in [unit], without the unit.
  String bodyLengthNumber(double cm, LengthUnit unit) =>
      _number(unit.fromCm(cm));

  /// Signed, without the unit; "0" for no change.
  String bodyLengthChangeNumber(double cm, LengthUnit unit) =>
      _signedNumber(_number(unit.fromCm(cm).abs()), unit.fromCm(cm));

  /// A body fat percentage without the sign, one decimal.
  String bodyFatNumber(double percent) => _oneDecimal(percent);

  /// Signed body fat points, one decimal, without the unit.
  String bodyFatChangeNumber(double points) =>
      _signedNumber(_oneDecimal(points.abs()), points);

  String _signedNumber(String text, double value) {
    if (text == _number(0) || text == _oneDecimal(0)) return text;
    return value > 0 ? bodyIncrease(text) : bodyDecrease(text);
  }

  /// "Nov 1"; the year only when it is not this one.
  String bodyShortDate(DateTime date) =>
      _dated(date, DateFormat.MMMd, DateFormat.yMMMd);

  /// "Fri, Nov 13"; the year only when it is not this one.
  String bodyShortDayDate(DateTime date) =>
      _dated(date, DateFormat.MMMEd, DateFormat.yMMMEd);

  /// "Oct 18, 2026".
  String bodyFullDate(DateTime date) =>
      DateFormat.yMMMd(localeName).format(date.toLocal());

  /// "Sun, Aug 30, 2026".
  String bodyFullDayDate(DateTime date) =>
      DateFormat.yMMMEd(localeName).format(date.toLocal());

  /// "Oct 18 → Nov 1, 2026": the year once, unless the days' years differ.
  String bodyDateSpan(DateTime from, DateTime to) => bodyFromTo(
    from.toLocal().year == to.toLocal().year
        ? DateFormat.MMMd(localeName).format(from.toLocal())
        : bodyFullDate(from),
    bodyFullDate(to),
  );

  String _dated(
    DateTime date,
    DateFormat Function([String?]) thisYear,
    DateFormat Function([String?]) otherYear,
  ) {
    final local = date.toLocal();
    final format = local.year == DateTime.now().year ? thisYear : otherYear;
    return format(localeName).format(local);
  }

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

  /// Where to put the tape for [measurement]; both sides of a pair share
  /// one.
  String measurementHint(BodyMeasurement measurement) => switch (measurement) {
    BodyMeasurement.neck => bodyHintNeck,
    BodyMeasurement.shoulders => bodyHintShoulders,
    BodyMeasurement.chest => bodyHintChest,
    BodyMeasurement.waist => bodyHintWaist,
    BodyMeasurement.abdomen => bodyHintAbdomen,
    BodyMeasurement.hips => bodyHintHips,
    BodyMeasurement.leftUpperArm ||
    BodyMeasurement.rightUpperArm => bodyHintUpperArm,
    BodyMeasurement.leftForearm ||
    BodyMeasurement.rightForearm => bodyHintForearm,
    BodyMeasurement.leftThigh || BodyMeasurement.rightThigh => bodyHintThigh,
    BodyMeasurement.leftCalf || BodyMeasurement.rightCalf => bodyHintCalf,
  };

  /// The name of the pair whose left side is [left], e.g. "Thigh".
  String measurementPairName(BodyMeasurement left) => switch (left) {
    BodyMeasurement.leftUpperArm => bodyUpperArm,
    BodyMeasurement.leftForearm => bodyForearm,
    BodyMeasurement.leftThigh => bodyThigh,
    BodyMeasurement.leftCalf => bodyCalf,
    _ => measurementName(left),
  };

  /// The name of a group of [pairedMeasurements]: one measurement, or both
  /// sides of a pair, e.g. "Thigh (L / R)".
  String measurementGroupName(List<BodyMeasurement> group) => group.length == 1
      ? measurementName(group.single)
      : bodyPairName(measurementPairName(group.first));

  /// A series of the Body chart; a pair of measurements as [measurementGroupName].
  String seriesName(BodySeries series) => switch (series) {
    BodySeries.weight => bodyWeightTitle,
    BodySeries.bodyFat => bodyFatTitle,
    BodySeries.fatMass => bodyFatMass,
    BodySeries.leanMass => bodyLeanMass,
    BodySeries.weeklySets => bodyWeeklySets,
    BodySeries.dailySteps => bodyDailySteps,
    _ => measurementGroupName(series.measurements),
  };

  String seriesGroupName(BodySeriesGroup group) => switch (group) {
    BodySeriesGroup.body => bodyChartGroupBody,
    BodySeriesGroup.measurements => bodyChartGroupMeasurements,
    BodySeriesGroup.training => bodyChartGroupTraining,
  };

  /// A body fat percentage, always with one decimal.
  String bodyFat(double percent) => bodyFatValue(_oneDecimal(percent));

  String _oneDecimal(double value) =>
      (NumberFormat.decimalPattern(localeName)
            ..minimumFractionDigits = 1
            ..maximumFractionDigits = 1)
          .format(value);

  String poseName(PhotoPose pose) => switch (pose) {
    PhotoPose.front => bodyPoseFront,
    PhotoPose.right => bodyPoseRight,
    PhotoPose.left => bodyPoseLeft,
    PhotoPose.back => bodyPoseBack,
  };

  /// The pose as the photo card's chips name it: "Right", not "Right side".
  String poseShortName(PhotoPose pose) => switch (pose) {
    PhotoPose.right => bodyPoseShortRight,
    PhotoPose.left => bodyPoseShortLeft,
    _ => poseName(pose),
  };

  String bodyWeightRange(WeightUnit unit) => bodyErrorWeight(
    bodyWeight(BodyLimits.minWeightKg, unit),
    bodyWeight(BodyLimits.maxWeightKg, unit),
  );

  String bodyMeasurementRange(LengthUnit unit) => bodyErrorMeasurement(
    bodyLength(BodyLimits.minMeasurementCm, unit),
    bodyLength(BodyLimits.maxMeasurementCm, unit),
  );
}
