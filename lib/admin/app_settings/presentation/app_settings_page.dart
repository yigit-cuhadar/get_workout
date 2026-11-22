import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../shell/admin_form.dart';
import '../../shell/admin_text.dart';
import '../../shell/publishing.dart';
import '../domain/app_settings.dart';
import 'app_settings_cubit.dart';

/// The widths of a key's input and its "Changed" column on the C1 board.
const _inputWidth = 240.0;
const _changedWidth = 170.0;

/// The publish confirm's width on the C2 board.
const _dialogWidth = 620.0;

/// How long a published version may take to reach apps: their release
/// builds fetch at most every 12 hours (`bootstrap`).
const _reachHours = 12;

/// The app's Remote Config keys edited in place (C1), published after a
/// confirm (C2), with the version history and restore beside them (C3).
class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<AppSettingsCubit>()..load(),
    child: const _AppSettingsView(),
  );
}

/// What each key does, under its name.
const _descriptions = {
  'paywall_layout':
      'Paywall layout for new sessions: a list, b cards, c one plan. A '
      'running A/B test sets it for its own users.',
  'maintenance': 'Shows the maintenance page on iOS and Android.',
  'maintenance_message':
      'Text on the maintenance page. Empty uses the app’s own text.',
  'min_version_ios': 'Below this version the iOS app must update.',
  'min_version_android': 'Below this version the Android app must update.',
  'recommended_version_ios':
      'Below this version the iOS app offers an update once.',
  'recommended_version_android':
      'Below this version the Android app offers an update once.',
};

/// A warning on its own line under a key's description (owner's pick:
/// the paywall layout stays editable while its A/B test runs).
const _warnings = {
  'paywall_layout': 'A change also reaches users outside its A/B test.',
};

const _choiceLabels = {'a': 'list', 'b': 'cards', 'c': 'one plan'};

String _groupTitle(SettingGroup group) => switch (group) {
  SettingGroup.paywall => 'Paywall',
  SettingGroup.updates => 'Update and maintenance',
};

String _plain(SettingSpec spec, String value) => switch (spec.kind) {
  SettingKind.choice => '$value · ${_choiceLabels[value] ?? value}',
  SettingKind.toggle => value == 'true' ? 'on' : 'off',
  _ when value.isEmpty => '(empty)',
  _ => value,
};

/// [value] as the page shows it in a "was", Now or After column.
String _label(SettingSpec spec, SettingValue value) => switch (value) {
  SetValue(:final value) => _plain(spec, value),
  AppDefault() => 'app default (${_plain(spec, spec.appDefault)})',
  ConsoleValue(kind: 'experiment', :final id) => 'A/B test $id',
  ConsoleValue(:final kind, :final id) => '$kind $id',
};

final _date = DateFormat('MMM d, y');
final _dateTime = DateFormat('MMM d, y, HH:mm');

String _who(ConfigVersion version) => switch (version) {
  ConfigVersion(origin: PublishOrigin.console) => 'Firebase console',
  ConfigVersion(:final by?) => by,
  _ => 'unknown',
};

String _changesTitle(int count) =>
    'Publish $count ${count == 1 ? 'change' : 'changes'}?';

String _loadFailureMessage(Failure failure) => switch (failure) {
  AppSettingsUnavailableFailure() =>
    'The app settings functions are not deployed to this project.',
  _ => failureMessage(failure),
};

/// What the page says about a failed publish.
String _publishFailureMessage(Failure failure, {required bool refreshed}) =>
    switch (failure) {
      PermissionFailure() when refreshed =>
        'Refused, but this account still has admin access and its token is '
            'now refreshed. Publish again.',
      PermissionFailure() =>
        'Refused: this account has no current admin claim.',
      AppSettingsStaleFailure() =>
        'Not published: Remote Config changed since this page loaded (in '
            'the console or by another admin). Reload, check the values '
            'and publish again; your changes are kept.',
      SettingLockedFailure(:final message) => 'Not published: $message',
      AppSettingsUnavailableFailure() =>
        'Not published: the app settings functions are not deployed to '
            'this project.',
      ValidationFailure(:final message) => 'Refused: $message',
      NetworkFailure() =>
        'No connection to Firebase; it may or may not have been published. '
            'Reload to see.',
      _ => '${failureMessage(failure)} Reload to see whether it was published.',
    };

/// Confirms [changes] (C2), then publishes them.
Future<void> _confirmPublish(
  BuildContext context,
  List<SettingChange> changes, {
  int? restoring,
}) async {
  final cubit = context.read<AppSettingsCubit>();
  final version = cubit.state.settings?.version.number;
  if (version == null) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_changesTitle(changes.length)),
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChangeTable(changes),
            const SizedBox(height: Gap.md),
            Text(
              'This becomes version ${version + 1}. Apps pick it up at '
              'their next fetch, within $_reachHours hours. Version '
              '$version stays in History and can be restored.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Publish'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) await cubit.publish(changes, restoring: restoring);
}

class _AppSettingsView extends StatelessWidget {
  const _AppSettingsView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AppSettingsCubit>();
    final historyOpen = context.select(
      (AppSettingsCubit cubit) => cubit.state.historyOpen,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('App settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Gap.md),
            child: OutlinedButton(
              onPressed: historyOpen ? cubit.closeHistory : cubit.openHistory,
              child: const Text('History'),
            ),
          ),
        ],
      ),
      body: BlocListener<AppSettingsCubit, AppSettingsState>(
        listenWhen: (previous, state) =>
            previous.publishStatus != state.publishStatus,
        listener: (context, state) {
          final messenger = ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar();
          switch (state) {
            case AppSettingsState(
              publishStatus: PublishStatus.published,
              published: final version?,
            ):
              messenger.showSnackBar(
                SnackBar(content: Text('Published version ${version.number}.')),
              );
            case AppSettingsState(publishFailure: final failure?):
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    _publishFailureMessage(
                      failure,
                      refreshed: state.accessRefreshed,
                    ),
                  ),
                  action: switch (failure) {
                    PermissionFailure() || ValidationFailure() => null,
                    _ => SnackBarAction(label: 'Reload', onPressed: cubit.load),
                  },
                ),
              );
            default:
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(child: _Settings()),
            if (historyOpen) ...[
              const VerticalDivider(width: 1),
              const SizedBox(width: historyWidth, child: _History()),
            ],
          ],
        ),
      ),
    );
  }
}

class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AppSettingsCubit>();
    final state = context.watch<AppSettingsCubit>().state;
    final settings = state.settings;
    if (settings == null) {
      return switch (state.loadFailure) {
        final failure? => ErrorView(
          title: 'App settings did not load',
          message: _loadFailureMessage(failure),
          onRetry: cubit.load,
          retryLabel: 'Retry',
        ),
        null => const LoadingView(),
      };
    }
    final version = settings.version;
    final changes = state.changes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxFormWidth),
              child: ListView(
                padding: const EdgeInsets.all(Gap.md),
                children: [
                  Text(
                    'Remote Config · version ${version.number}, published '
                    '${version.updatedAt == null ? '' : '${_date.format(version.updatedAt!.toLocal())} '}'
                    'by ${_who(version)} · apps fetch within $_reachHours '
                    'hours',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (state.loadFailure case final failure?)
                    ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(_loadFailureMessage(failure)),
                      trailing: TextButton(
                        onPressed: cubit.load,
                        child: const Text('Retry'),
                      ),
                    ),
                  for (final group in SettingGroup.values) ...[
                    const SizedBox(height: Gap.md),
                    FormSection(
                      title: _groupTitle(group),
                      children: [
                        for (final spec in settingSpecs)
                          if (spec.group == group) _SettingRow(spec),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (changes.isNotEmpty)
          PublishBar(
            count: changes.length,
            publishing: state.publishing,
            onDiscard: cubit.discard,
            onReview: state.canPublish
                ? () => _confirmPublish(context, changes)
                : null,
          ),
      ],
    );
  }
}

/// A key: its name and what it does with its conditional values, its
/// input, and its old value once changed.
class _SettingRow extends StatelessWidget {
  const _SettingRow(this.spec);

  final SettingSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final state = context.watch<AppSettingsCubit>().state;
    final setting = state.settings!.settingOf(spec.key);
    final changed = state.edits.containsKey(spec.key);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(spec.key, style: theme.textTheme.titleSmall),
              Text(_descriptions[spec.key] ?? '', style: muted),
              if (_warnings[spec.key] case final warning?)
                Text(warning, style: muted),
              if (setting.conditional.isNotEmpty) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  'Under conditions (kept as they are; edit them in the '
                  'Firebase console):',
                  style: muted,
                ),
                for (final conditional in setting.conditional)
                  Text(
                    '${conditional.condition}: '
                    '${_label(spec, conditional.value)}',
                    style: muted,
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(width: Gap.md),
        SizedBox(width: _inputWidth, child: _Input(spec, setting.value)),
        const SizedBox(width: Gap.md),
        SizedBox(
          width: _changedWidth,
          child: changed
              ? Wrap(
                  spacing: Gap.xs,
                  runSpacing: Gap.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const ForgeTag('Changed', kind: ForgeTagKind.category),
                    Text('was ${_label(spec, setting.value)}', style: muted),
                  ],
                )
              : null,
        ),
      ],
    );
  }
}

class _Input extends StatelessWidget {
  const _Input(this.spec, this.current);

  final SettingSpec spec;
  final SettingValue current;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AppSettingsCubit>();
    final state = context.watch<AppSettingsCubit>().state;
    if (current is ConsoleValue) {
      return Text(
        'Set by ${_label(spec, current)} in the Firebase console',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final value = state.valueOf(spec.key) ?? '';
    final enabled = !state.publishing;
    void edit(String value) => cubit.edit(spec.key, value);
    // Keyed by the form version, so a load or a discard shows afresh.
    final key = ValueKey((spec.key, state.formVersion));
    return switch (spec.kind) {
      SettingKind.choice => DropdownButtonFormField<String>(
        key: key,
        initialValue: spec.choices.contains(value) ? value : null,
        items: [
          for (final choice in spec.choices)
            DropdownMenuItem(value: choice, child: Text(_plain(spec, choice))),
        ],
        onChanged: enabled
            ? (choice) {
                if (choice != null) edit(choice);
              }
            : null,
      ),
      SettingKind.toggle => Align(
        alignment: Alignment.centerLeft,
        child: Switch(
          value: value == 'true',
          onChanged: enabled ? (on) => edit('$on') : null,
        ),
      ),
      SettingKind.text || SettingKind.version => TextFormField(
        key: key,
        initialValue: value,
        enabled: enabled,
        decoration: InputDecoration(
          hintText: '(empty)',
          errorText: state.problemOf(spec.key),
          errorMaxLines: 2,
        ),
        onChanged: edit,
      ),
    };
  }
}

/// Key / Now / After publishing.
class _ChangeTable extends StatelessWidget {
  const _ChangeTable(this.changes);

  final List<SettingChange> changes;

  @override
  Widget build(BuildContext context) => ChangeTable(whereLabel: 'Key', [
    for (final change in changes)
      if (specOf(change.key) case final spec)
        (change.key, _label(spec, change.before), _label(spec, change.after)),
  ]);
}

/// The versions, newest first; an opened one shows what restoring it
/// changes, and Restore leads to the publish confirm.
class _History extends StatelessWidget {
  const _History();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AppSettingsCubit>();
    final state = context.watch<AppSettingsCubit>().state;
    final history = state.history;
    return HistoryPane(
      onClose: cubit.closeHistory,
      onRetry: cubit.retryHistory,
      loaded: history != null,
      failure: switch (state.historyFailure) {
        final failure? => _loadFailureMessage(failure),
        null => null,
      },
      children: [
        for (final (i, entry) in (history ?? const []).indexed)
          _VersionCard(entry, current: i == 0),
      ],
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard(this.entry, {required this.current});

  final VersionEntry entry;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final cubit = context.read<AppSettingsCubit>();
    final state = context.watch<AppSettingsCubit>().state;
    final version = entry.version;
    final opened = !current && state.openedVersion == version.number;
    final changed = [
      ...entry.changed,
      if (entry.conditionsChanged) 'conditions',
    ];
    final restore = switch (state.settings) {
      final settings? when opened => restoreChanges(settings, entry),
      _ => const <SettingChange>[],
    };
    return Card(
      color: opened ? theme.colorScheme.surfaceContainerHigh : null,
      child: InkWell(
        onTap: current
            ? null
            : () => cubit.openVersion(opened ? null : version.number),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Version ${version.number}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (current)
                    const ForgeTag('Current', kind: ForgeTagKind.record),
                ],
              ),
              Text(
                '${version.updatedAt == null ? '' : '${_dateTime.format(version.updatedAt!.toLocal())} · '}'
                '${_who(version)}',
                style: muted,
              ),
              Text(
                changed.isEmpty
                    ? 'No changes'
                    : 'Changed ${changed.join(', ')}',
                style: muted,
              ),
              if (opened) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  'Restoring it changes:',
                  style: theme.textTheme.bodyMedium,
                ),
                if (restore.isEmpty)
                  Text('Nothing in these settings.', style: muted)
                else
                  _ChangeTable(restore),
                Text(
                  'Only default values are restored; conditional values '
                  'and other parameters stay as they are.',
                  style: muted,
                ),
                const SizedBox(height: Gap.sm),
                FilledButton(
                  onPressed: restore.isEmpty || state.publishing
                      ? null
                      : () => _confirmPublish(
                          context,
                          restore,
                          restoring: version.number,
                        ),
                  child: Text('Restore version ${version.number}'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
