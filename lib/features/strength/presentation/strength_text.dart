import '../../../l10n/app_localizations.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../workout/domain/exercise_stats.dart';
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

  /// A record's [value] as stored (kg, reps or seconds), weights in [unit].
  String recordValue(RecordKind kind, double value, WeightUnit unit) =>
      switch (kind) {
        RecordKind.heaviestWeight ||
        RecordKind.bestE1rm ||
        RecordKind.bestSetVolume => weightText(value, unit),
        RecordKind.mostReps => strengthReps(value.round()),
        RecordKind.longestDuration => elapsedText(
          Duration(seconds: value.round()),
        ),
      };

  String rangeName(StrengthRange range) => switch (range) {
    StrengthRange.weeks12 => strengthRange12Weeks,
    StrengthRange.months6 => strengthRange6Months,
    StrengthRange.year1 => strengthRange1Year,
    StrengthRange.all => strengthRangeAll,
  };
}
