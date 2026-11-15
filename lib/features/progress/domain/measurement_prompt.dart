import 'package:forge_core/forge_core.dart';

import '../../body/domain/body_entry.dart';
import '../../programs/domain/calendar_date.dart';
import '../../settings/domain/user_settings.dart';

/// The Progress tab's reminder of the next measurement day [date]: the
/// newest progress photos ([lastPhotos], their poses in order), else the
/// newest entry's date ([lastMeasured]).
class MeasurementPrompt extends Equatable {
  const MeasurementPrompt({
    required this.date,
    required this.today,
    this.lastPhotos,
    this.lastMeasured,
  });

  final CalendarDate date;

  /// [date] is today.
  final bool today;
  final ({DateTime date, List<PhotoPose> poses})? lastPhotos;
  final DateTime? lastMeasured;

  @override
  List<Object?> get props => [
    date,
    today,
    lastPhotos?.date,
    lastPhotos?.poses,
    lastMeasured,
  ];
}

/// Days before a measurement day its prompt shows.
const measurementPromptDays = 2;

/// The [MeasurementPrompt] of [entries] (newest first) on [today], while
/// the measurement reminder of [settings] is on: from
/// [measurementPromptDays] before its next date through that day, unless
/// a measurement day was saved in that time or the prompt for that date
/// was [dismissed].
MeasurementPrompt? measurementPrompt(
  MeasurementReminderSettings settings,
  List<BodyEntry> entries, {
  required CalendarDate today,
  CalendarDate? dismissed,
}) {
  final from = settings.from;
  if (!settings.enabled || from == null) return null;
  final period = DateTime.daysPerWeek * settings.everyWeeks;
  final elapsed = today.daysSince(from);
  // The first date of the series on or after today.
  final date = from.addDays(
    elapsed <= 0 ? 0 : (elapsed + period - 1) ~/ period * period,
  );
  final opens = date.addDays(-measurementPromptDays);
  if (today.isBefore(opens) || date == dismissed) return null;
  final measured = entries.any((entry) {
    final day = CalendarDate.of(entry.date.toLocal());
    return !entry.isWeightOnly && !day.isBefore(opens) && !day.isAfter(date);
  });
  if (measured) return null;
  final photographed = entries
      .where((entry) => entry.photos.isNotEmpty)
      .firstOrNull;
  return MeasurementPrompt(
    date: date,
    today: date == today,
    lastPhotos: photographed == null
        ? null
        : (
            date: photographed.date,
            poses: [
              for (final pose in PhotoPose.values)
                if (photographed.photos.containsKey(pose)) pose,
            ],
          ),
    lastMeasured: photographed == null
        ? entries.where((entry) => !entry.isEmpty).firstOrNull?.date
        : null,
  );
}

/// Where the dismissed prompt's date is kept, on this device.
abstract interface class MeasurementPromptStore {
  /// The date whose prompt user [uid] dismissed last; null if none.
  Future<Result<CalendarDate?>> loadDismissed(String uid);

  Future<Result<void>> saveDismissed(String uid, CalendarDate date);
}

class LoadDismissedPrompt implements UseCase<CalendarDate?, String> {
  const LoadDismissedPrompt(this._store);
  final MeasurementPromptStore _store;

  @override
  Future<Result<CalendarDate?>> call(String uid) => _store.loadDismissed(uid);
}

typedef PromptDismissal = ({String uid, CalendarDate date});

class DismissPrompt implements UseCase<void, PromptDismissal> {
  const DismissPrompt(this._store);
  final MeasurementPromptStore _store;

  @override
  Future<Result<void>> call(PromptDismissal params) =>
      _store.saveDismissed(params.uid, params.date);
}
