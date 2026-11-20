import '../domain/dashboard.dart';

/// Reads the dashboard documents and the callables' answers as the
/// functions write them (`functions/src/dashboard`). Every field is read
/// defensively: one missing or of another type is null, never an error.
abstract final class DashboardMaps {
  static Report report(Map<Object?, Object?> data) {
    final tiles = _map(data['tiles']);
    final funnel = _map(data['funnel']);
    final usage = _map(data['usage']);
    final top = _map(usage['topProgram']);
    final quality = _map(data['quality']);
    final from = day(data['from']);
    final to = day(data['to']);
    return Report(
      range: from == null || to == null ? null : DayRange(from, to),
      tiles: {
        for (final tile in DashboardTile.values)
          tile: TileValue(
            value: _double(_map(tiles[tile.name])['value']),
            previous: _double(_map(tiles[tile.name])['previous']),
          ),
      },
      growth: [
        for (final row in _list(data['growth']).map(_map))
          if (day(row['day']) case final day?)
            DayCount(
              day: day,
              active: _int(row['active']),
              newUsers: _int(row['new']),
            ),
      ],
      funnel: Funnel(
        installed: _int(funnel['installed']),
        onboardingComplete: _int(funnel['onboardingComplete']),
        firstWorkout: _int(funnel['firstWorkout']),
        paywallSeen: _int(funnel['paywallSeen']),
        trialStarted: _int(funnel['trialStarted']),
        paid: _int(funnel['paid']),
      ),
      usage: Usage(
        programStarts: _int(usage['programStarts']),
        workoutsPerActiveUser: _double(usage['workoutsPerActiveUser']),
        customExercisesCreated: _int(usage['customExercisesCreated']),
        weightsLogged: _int(usage['weightsLogged']),
        notificationsOpened: _int(usage['notificationsOpened']),
        topProgramId: _string(top['id']),
        topProgramStarts: _int(top['starts']),
      ),
      quality: Quality(
        crashFreeUsers: _double(quality['crashFreeUsers']),
        handledErrors: _int(quality['handledErrors']),
        topIssues: quality['topIssues'] is List
            ? [
                for (final issue in _list(quality['topIssues']).map(_map))
                  Issue(
                    title: _string(issue['title']) ?? '',
                    users: _int(issue['users']),
                  ),
              ]
            : null,
      ),
    );
  }

  static List<Cohort> retention(Map<Object?, Object?> data) => [
    for (final row in _list(data['cohorts']).map(_map))
      if (day(row['week']) case final week?)
        Cohort(
          week: week,
          users: _int(row['users']),
          d1: _double(row['d1']),
          d7: _double(row['d7']),
          d30: _double(row['d30']),
        ),
  ];

  static RevenueSnapshot revenue(Map<Object?, Object?> data) => RevenueSnapshot(
    mrr: _double(data['mrr']),
    revenue28d: _double(data['revenue28d']),
    activeSubscriptions: _int(data['activeSubscriptions']),
    activeTrials: _int(data['activeTrials']),
    currency: _string(data['currency']),
  );

  static DashboardStatus status(Map<Object?, Object?> data) => DashboardStatus(
    state: switch (data['state']) {
      'ok' => RefreshState.ok,
      'no-data' => RefreshState.noData,
      'error' => RefreshState.error,
      _ => RefreshState.unknown,
    },
    lastDay: day(data['lastDay']),
    updatedAt: switch (data['updatedAtMillis']) {
      final num millis => DateTime.fromMillisecondsSinceEpoch(millis.toInt()),
      _ => null,
    },
    message: _string(data['message']),
  );

  static final _day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// A real calendar day as `YYYY-MM-DD`, at UTC midnight; else null.
  static DateTime? day(Object? value) {
    if (value is! String) return null;
    final match = _day.firstMatch(value);
    if (match == null) return null;
    final [year, month, dayOfMonth] = [
      for (var i = 1; i <= 3; i++) int.parse(match.group(i)!),
    ];
    final parsed = DateTime.utc(year, month, dayOfMonth);
    return parsed.month == month && parsed.day == dayOfMonth ? parsed : null;
  }

  /// [value] as `YYYY-MM-DD`.
  static String dayString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static Map<Object?, Object?> _map(Object? value) =>
      value is Map ? value : const {};

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static double? _double(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;

  static int? _int(Object? value) =>
      value is num && value.isFinite ? value.round() : null;

  static String? _string(Object? value) => value is String ? value : null;
}
