import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/analytics/domain/analytics.dart';

/// A [Telemetry] that keeps what it is given, in order.
class RecordingTelemetry implements Telemetry {
  final events = <(String, Map<String, Object>)>[];
  final screens = <String>[];
  final properties = <String, String?>{};

  /// Every user followed and event logged, in order: `follow:<uid>`,
  /// `event:<name>`.
  final calls = <String>[];

  /// The names of [events].
  List<String> get names => [for (final (name, _) in events) name];

  /// [events] as `[name, parameters]` lists, which matchers compare deeply.
  List<List<Object>> get logged => [
    for (final (name, parameters) in events) [name, parameters],
  ];

  @override
  Future<Result<void>> follow(String? uid) async {
    calls.add('follow:$uid');
    return const Ok(null);
  }

  @override
  Future<Result<void>> apply(String uid, bool? consent) async => const Ok(null);

  @override
  Future<Result<void>> forget(String uid) async => const Ok(null);

  @override
  Future<void> logEvent(
    String name, [
    Map<String, Object> parameters = const {},
  ]) async {
    calls.add('event:$name');
    events.add((name, parameters));
  }

  @override
  Future<void> logScreen(String name) async => screens.add(name);

  @override
  Future<void> setUserProperty(String name, String? value) async =>
      properties[name] = value;
}

/// [Analytics] over a [RecordingTelemetry], for tests that need one.
Analytics fakeAnalytics([RecordingTelemetry? telemetry]) =>
    Analytics(telemetry ?? RecordingTelemetry());
