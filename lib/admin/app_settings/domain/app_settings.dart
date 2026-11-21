import 'package:forge_core/forge_core.dart';

import '../../../features/subscription/domain/paywall_layout.dart';

enum SettingGroup { paywall, updates }

enum SettingKind { choice, toggle, text, version }

/// The longest maintenance message, as `functions/src/app_settings`
/// allows it.
const maxSettingText = 300;

final _version = RegExp(r'^\d{1,6}(\.\d{1,6}){0,3}$');

/// A Remote Config key the panel edits, with the app's own default as
/// Remote Config sends values: text (`'a'`, `'false'`, `''`).
class SettingSpec {
  const SettingSpec(
    this.key, {
    required this.group,
    required this.kind,
    required this.appDefault,
    this.choices = const [],
  });

  final String key;
  final SettingGroup group;
  final SettingKind kind;
  final String appDefault;

  /// The values of a [SettingKind.choice].
  final List<String> choices;

  /// Why [value] cannot be published, or null. The function checks the
  /// same rules.
  String? problem(String value) => switch (kind) {
    SettingKind.choice when !choices.contains(value) =>
      'Pick one of ${choices.join(', ')}.',
    SettingKind.toggle when value != 'true' && value != 'false' =>
      'Must be on or off.',
    SettingKind.text when value.length > maxSettingText =>
      'At most $maxSettingText characters.',
    SettingKind.version when value.isNotEmpty && !_version.hasMatch(value) =>
      'A version such as 1.2.0, or empty for none.',
    _ => null,
  };

  /// What apps get from [value]; null when the console owns it.
  String? effective(SettingValue value) => switch (value) {
    SetValue(:final value) => value,
    AppDefault() => appDefault,
    ConsoleValue() => null,
  };
}

/// Every key the panel edits, in page order: the app's Remote Config
/// defaults (`SubscriptionModule.remoteConfigDefaults` and
/// `AppGateModule.remoteConfigDefaults`, kept in step by a test).
final settingSpecs = [
  SettingSpec(
    paywallLayoutKey,
    group: SettingGroup.paywall,
    kind: SettingKind.choice,
    appDefault: paywallLayoutDefault,
    choices: [for (final layout in PaywallLayout.values) layout.code],
  ),
  const SettingSpec(
    'maintenance',
    group: SettingGroup.updates,
    kind: SettingKind.toggle,
    appDefault: 'false',
  ),
  const SettingSpec(
    'maintenance_message',
    group: SettingGroup.updates,
    kind: SettingKind.text,
    appDefault: '',
  ),
  for (final rule in ['min', 'recommended'])
    for (final platform in ['ios', 'android'])
      SettingSpec(
        '${rule}_version_$platform',
        group: SettingGroup.updates,
        kind: SettingKind.version,
        appDefault: '',
      ),
];

SettingSpec specOf(String key) =>
    settingSpecs.singleWhere((spec) => spec.key == key);

/// A Remote Config value as the template holds it.
sealed class SettingValue extends Equatable {
  const SettingValue();
}

final class SetValue extends SettingValue {
  const SetValue(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

/// "Use in-app default", or no parameter at all: apps use their own.
final class AppDefault extends SettingValue {
  const AppDefault();

  @override
  List<Object?> get props => [];
}

/// Set by an A/B experiment, a rollout or a personalization: changed only
/// in the Firebase console.
final class ConsoleValue extends SettingValue {
  const ConsoleValue(this.kind, this.id);

  /// `experiment`, `rollout` or `personalization`.
  final String kind;
  final String id;

  @override
  List<Object?> get props => [kind, id];
}

/// A value apps get when [condition] holds; the panel leaves these alone.
class ConditionalValue extends Equatable {
  const ConditionalValue(this.condition, this.value);

  final String condition;
  final SettingValue value;

  @override
  List<Object?> get props => [condition, value];
}

class RemoteSetting extends Equatable {
  const RemoteSetting({required this.value, this.conditional = const []});

  /// The default value: what apps get outside every condition.
  final SettingValue value;
  final List<ConditionalValue> conditional;

  @override
  List<Object?> get props => [value, conditional];
}

enum PublishOrigin { panel, console, other }

class ConfigVersion extends Equatable {
  const ConfigVersion({
    required this.number,
    this.updatedAt,
    this.by,
    this.origin = PublishOrigin.other,
    this.restoredFrom,
  });

  final int number;
  final DateTime? updatedAt;

  /// The admin's email for a panel publish, else the publisher's.
  final String? by;
  final PublishOrigin origin;

  /// The version this one restored.
  final int? restoredFrom;

  @override
  List<Object?> get props => [number, updatedAt, by, origin, restoredFrom];
}

/// The template's current version: its [etag], which a publish must
/// match, and the value of every key of [settingSpecs].
class AppSettings extends Equatable {
  const AppSettings({
    required this.etag,
    required this.version,
    required this.settings,
  });

  final String etag;
  final ConfigVersion version;
  final Map<String, RemoteSetting> settings;

  RemoteSetting settingOf(String key) =>
      settings[key] ?? const RemoteSetting(value: AppDefault());

  @override
  List<Object?> get props => [etag, version, settings];
}

/// A version of the history, with what changed since the one before it.
class VersionEntry extends Equatable {
  const VersionEntry({
    required this.version,
    required this.changed,
    required this.conditionsChanged,
    required this.values,
  });

  final ConfigVersion version;

  /// Every parameter whose values changed, the panel's or not.
  final List<String> changed;
  final bool conditionsChanged;

  /// Its default values of [settingSpecs]' keys.
  final Map<String, SettingValue> values;

  @override
  List<Object?> get props => [version, changed, conditionsChanged, values];
}

/// One key's default going from [before] to [after].
class SettingChange extends Equatable {
  const SettingChange(this.key, {required this.before, required this.after});

  final String key;
  final SettingValue before;

  /// A [SetValue] or [AppDefault]; never a [ConsoleValue].
  final SettingValue after;

  @override
  List<Object?> get props => [key, before, after];
}

/// What restoring [entry] changes in [current]: the keys whose default
/// differs, in page order. A default the console owns, then or now, is
/// left out, as are conditional values: a restore writes defaults only.
List<SettingChange> restoreChanges(AppSettings current, VersionEntry entry) => [
  for (final spec in settingSpecs)
    if ((
          current.settingOf(spec.key).value,
          entry.values[spec.key] ?? const AppDefault(),
        )
        case (final before, final after)
        when before != after &&
            before is! ConsoleValue &&
            after is! ConsoleValue)
      SettingChange(spec.key, before: before, after: after),
];

/// A publish of [changes] onto the template at [etag]; [restoring] names
/// the version a restore brings back.
class SettingsPublish extends Equatable {
  const SettingsPublish({
    required this.etag,
    required this.changes,
    this.restoring,
  });

  final String etag;
  final List<SettingChange> changes;
  final int? restoring;

  @override
  List<Object?> get props => [etag, changes, restoring];
}

/// The template changed since the page loaded it (in the console, or
/// another admin's publish); nothing was published.
final class AppSettingsStaleFailure extends Failure {
  const AppSettingsStaleFailure([
    super.message = 'Remote Config changed since this page loaded',
    Object? cause,
  ]) : super(cause: cause);
}

/// A key's default is set by an experiment, a rollout or a
/// personalization; nothing was published.
final class SettingLockedFailure extends Failure {
  const SettingLockedFailure(super.message, [Object? cause])
    : super(cause: cause);
}

/// The app settings functions cannot be called: not deployed to this
/// project, or without permission to call them.
final class AppSettingsUnavailableFailure extends Failure {
  const AppSettingsUnavailableFailure([
    super.message = 'the app settings functions cannot be called',
    Object? cause,
  ]) : super(cause: cause);
}
