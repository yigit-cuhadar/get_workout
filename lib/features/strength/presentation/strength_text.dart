import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../workout/domain/exercise_stats.dart';
import '../../workout/domain/set_logging.dart';
import '../../workout/presentation/workout_text.dart';
import '../domain/strength.dart';

extension StrengthText on AppLocalizations {
  String recordName(RecordKind kind) => switch (kind) {
    RecordKind.heaviestWeight => strengthHeaviestWeight,
    RecordKind.bestE1rm => strengthBestE1rm,
    RecordKind.mostReps => strengthMostReps,
    RecordKind.bestSetVolume => strengthBestSetVolume,
    RecordKind.longestDuration => strengthLongestDuration,
  };

  /// A record's value: the e1RM or set volume alone, the other records as
  /// the set that made them ("82.5 kg × 8", "70 kg × 12", "1:45"). Stats
  /// stored before records kept their set show the value alone.
  String recordValue(RecordEntry entry, LoggingType type, WeightUnit unit) {
    final (:kind, :record) = entry;
    final value = record.value;
    if (record.set case final set?
        when kind != RecordKind.bestE1rm && kind != RecordKind.bestSetVolume) {
      return liftText(set, type, unit, unitOnLoad: true);
    }
    return switch (kind) {
      RecordKind.heaviestWeight => liftedWeightText(value, unit),
      RecordKind.bestE1rm => estimatedWeightText(value, unit),
      RecordKind.bestSetVolume => weightText(value, unit),
      RecordKind.mostReps => strengthReps(value.round()),
      RecordKind.longestDuration => elapsedText(
        Duration(seconds: value.round()),
      ),
    };
  }

  /// A set as the strength page writes it: "82.5 × 8" (with [unitOnLoad]
  /// "82.5 kg × 8"), "12 reps", "+10 kg × 8", "20 kg assist × 8", "1:45",
  /// "20 kg · 1:30".
  String liftText(
    SetValues set,
    LoggingType type,
    WeightUnit unit, {
    required bool unitOnLoad,
  }) {
    final kg = set.weightKg ?? 0;
    final reps = set.reps ?? 0;
    final time = elapsedText(Duration(seconds: set.durationS ?? 0));
    final weight = liftedWeightText(kg, unit);
    return switch (type) {
      _ when type.isDurationBased && kg <= 0 => time,
      LoggingType.duration => time,
      LoggingType.weightDuration => strengthSetTimed(weight, time),
      _ when kg <= 0 => strengthReps(reps),
      LoggingType.weightReps => strengthSetWeight(
        unitOnLoad ? weight : weightField(kg, unit),
        reps,
      ),
      LoggingType.weightedBodyweight => strengthSetAdded(weight, reps),
      LoggingType.assistedBodyweight => strengthSetAssisted(weight, reps),
      LoggingType.reps => strengthReps(reps),
    };
  }

  /// A session's line: its best set, and its e1RM where it has one
  /// ("82.5 × 8 · e1RM 104").
  String sessionText(HistoryPoint point, LoggingType type, WeightUnit unit) {
    final kg = point.bestE1rmKg;
    final e1rm = kg == null ? null : numberField(unit.estimatedFromKg(kg));
    final set = point.bestSet;
    if (set == null) {
      // Stored before sessions kept their best set; rebuilt soon.
      return kg == null ? '—' : estimatedWeightText(kg, unit);
    }
    final text = liftText(set, type, unit, unitOnLoad: false);
    return e1rm == null ? text : strengthSessionE1rm(text, e1rm);
  }

  /// "Fri, Nov 13 · Push".
  String sessionDetail(HistoryPoint point) {
    final date = dayDate(point.date);
    final name = point.workoutName;
    return name == null ? date : strengthSessionDetail(date, name);
  }

  String rangeName(StrengthRange range) => switch (range) {
    StrengthRange.weeks2 => strengthRange2Weeks,
    StrengthRange.months6 => strengthRange6Months,
    StrengthRange.year1 => strengthRange1Year,
    StrengthRange.all => strengthRangeAll,
  };

  /// "Nov 13", with the year only when it is not this one.
  String shortDate(DateTime date) => _yearAware(
    date,
    DateFormat.MMMd(localeName),
    DateFormat.yMMMd(localeName),
  );

  /// "Fri, Nov 13", with the year only when it is not this one.
  String dayDate(DateTime date) => _yearAware(
    date,
    DateFormat.MMMEd(localeName),
    DateFormat.yMMMEd(localeName),
  );

  String _yearAware(DateTime date, DateFormat thisYear, DateFormat other) {
    final local = date.toLocal();
    return (local.year == DateTime.now().year ? thisYear : other).format(local);
  }
}
