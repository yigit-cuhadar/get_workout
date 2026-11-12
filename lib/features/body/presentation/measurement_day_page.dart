import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/ghost_camera.dart';
import '../../../core/unsaved_changes.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/body_entry.dart';
import '../domain/entry_body_fat.dart';
import 'body_entry_page.dart';
import 'body_input.dart';
import 'body_text.dart';
import 'measurement_day_cubit.dart';

/// A new measurement day.
class MeasurementDayNewPage extends StatelessWidget {
  const MeasurementDayNewPage({super.key});

  @override
  Widget build(BuildContext context) => const _MeasurementDay(entry: null);
}

/// A stored entry, gone through again step by step.
class MeasurementDayEditPage extends StatelessWidget {
  const MeasurementDayEditPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => StoredEntry(
    id: id,
    title: AppLocalizations.of(context).bodyMeasurementDay,
    builder: (entry) => _MeasurementDay(entry: entry),
  );
}

class _MeasurementDay extends StatelessWidget {
  const _MeasurementDay({required this.entry});

  final BodyEntry? entry;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsCubit>().state.settings;
    final MeasurementDaySetup setup = (
      initial: entry,
      tracked: _tracked(context),
      weightUnit: settings.weightUnit,
      lengthUnit: settings.lengthUnit,
    );
    return BlocProvider(
      create: (_) => sl<MeasurementDayCubit>(param1: setup),
      child: _MeasurementDayView(settings),
    );
  }
}

/// What the user tracks: their own choice, else the default for their sex.
Set<BodyMeasurement> _tracked(BuildContext context) => trackedMeasurements(
  context.read<SettingsCubit>().state.settings.customTrackedMeasurements,
  context.read<ProfileCubit>().state.profile.sex,
);

class _MeasurementDayView extends StatefulWidget {
  const _MeasurementDayView(this.settings);

  /// As the flow opened; units do not change midway.
  final UserSettings settings;

  @override
  State<_MeasurementDayView> createState() => _MeasurementDayViewState();
}

class _MeasurementDayViewState extends State<_MeasurementDayView> {
  late final MeasurementDayCubit _cubit = context.read<MeasurementDayCubit>();

  /// The current photo step shows the camera again over its picture.
  bool _retaking = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MultiBlocListener(
      listeners: [
        BlocListener<SettingsCubit, SettingsState>(
          listenWhen: (previous, current) =>
              previous.settings.customTrackedMeasurements !=
              current.settings.customTrackedMeasurements,
          listener: (context, _) => _cubit.setTracked(_tracked(context)),
        ),
        // The default follows the sex.
        BlocListener<ProfileCubit, ProfileState>(
          listenWhen: (previous, current) =>
              previous.profile.sex != current.profile.sex,
          listener: (context, _) => _cubit.setTracked(_tracked(context)),
        ),
        BlocListener<MeasurementDayCubit, MeasurementDayState>(
          listenWhen: (previous, current) =>
              previous.status != current.status ||
              previous.index != current.index,
          listener: _onChange,
        ),
      ],
      child: UnsavedChangesGuard(
        hasChanges: () => _cubit.hasChanges,
        confirmDiscard: _confirmDiscard,
        child: BlocBuilder<MeasurementDayCubit, MeasurementDayState>(
          builder: (context, state) {
            final busy = state.status == MeasurementDayStatus.saving;
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) unawaited(_back(context));
              },
              child: Scaffold(
                appBar: AppBar(
                  title: Text(
                    l10n.bodyStepOf(state.index + 1, state.steps.length),
                  ),
                  actions: [
                    IconButton(
                      tooltip: l10n.bodyTrackedTitle,
                      icon: const Icon(Icons.tune),
                      onPressed: busy ? null : _editTracked,
                    ),
                  ],
                ),
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _step(context, state)),
                        const SizedBox(height: Gap.md),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: busy ? null : _cubit.skip,
                                child: Text(l10n.bodySkip),
                              ),
                            ),
                            const SizedBox(width: Gap.sm),
                            Expanded(
                              child: ForgeButton(
                                label: state.isLast
                                    ? l10n.bodySave
                                    : l10n.bodyNext,
                                loading: busy,
                                onPressed: _cubit.next,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _onChange(BuildContext context, MeasurementDayState state) {
    final l10n = AppLocalizations.of(context);
    void tell(String text) =>
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text)));
    setState(() => _retaking = false);
    switch (state.status) {
      // A new day goes on to its summary, in place of the flow.
      case MeasurementDayStatus.saved when _cubit.savedNewId != null:
        context.go(Routes.bodySummary(_cubit.savedNewId!));
      case MeasurementDayStatus.saved || MeasurementDayStatus.closed:
        context.pop();
      case MeasurementDayStatus.empty:
        tell(l10n.bodyNothingToSave);
      case MeasurementDayStatus.saveFailed:
        tell(
          state.failure is NetworkFailure
              ? l10n.errorNetwork
              : l10n.bodySaveFailed,
        );
      default:
    }
  }

  /// One step back; from the first step, out of the flow, after asking when
  /// something changed. [context] is below the [UnsavedChangesGuard].
  Future<void> _back(BuildContext context) async {
    if (_cubit.back()) return;
    if (_cubit.hasChanges && !await UnsavedChangesGuard.ask(context)) return;
    if (context.mounted) context.pop();
  }

  Future<bool> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.bodyDiscardTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.bodyDiscard),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _editTracked() async {
    final settings = context.read<SettingsCubit>();
    final tracked = _tracked(context);
    final chosen = await showDialog<Set<BodyMeasurement>>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<ProfileCubit>(),
        child: _TrackedDialog(tracked),
      ),
    );
    // An unchanged set keeps following the default.
    if (chosen == null || setEquals(chosen, tracked)) return;
    await settings.update(
      settings.state.settings.copyWith(customTrackedMeasurements: chosen),
    );
  }

  Widget _step(BuildContext context, MeasurementDayState state) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final weightUnit = widget.settings.weightUnit;
    final lengthUnit = widget.settings.lengthUnit;
    Widget field({
      required Object key,
      required String unit,
      required String value,
      required String? error,
      required ValueChanged<String> onChanged,
      String? label,
      bool first = true,
      bool last = true,
    }) => TextFormField(
      // A fresh field per step.
      key: ValueKey(key),
      initialValue: value,
      autofocus: first,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: decimalInput,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        errorText: error,
        errorMaxLines: 2,
      ),
      onChanged: onChanged,
      onFieldSubmitted: last ? (_) => _cubit.next() : null,
    );
    Widget page(String title, Widget fields, {String? hint}) => ListView(
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: Gap.md),
        fields,
        if (hint != null) ...[
          const SizedBox(height: Gap.sm),
          Text(hint, style: theme.textTheme.bodySmall),
        ],
      ],
    );
    Widget side(
      BodyMeasurement measurement,
      String label, {
      required bool first,
    }) => field(
      key: (state.step, measurement),
      label: label,
      unit: l10n.bodyLengthUnit(lengthUnit),
      value: state.measurements[measurement] ?? '',
      error: state.invalidMeasurements.contains(measurement)
          ? l10n.bodyMeasurementRange(lengthUnit)
          : null,
      onChanged: (text) => _cubit.setMeasurement(measurement, text),
      first: first,
      last: !first,
    );

    return switch (state.step) {
      WeightStep() => page(
        l10n.bodyWeightTitle,
        field(
          key: state.step,
          unit: l10n.bodyWeightUnit(weightUnit),
          value: state.weight,
          error: state.invalid ? l10n.bodyWeightRange(weightUnit) : null,
          onChanged: _cubit.setWeight,
        ),
      ),
      MeasurementStep(:final measurement) => page(
        l10n.measurementName(measurement),
        field(
          key: state.step,
          unit: l10n.bodyLengthUnit(lengthUnit),
          value: state.measurements[measurement] ?? '',
          error: state.invalid ? l10n.bodyMeasurementRange(lengthUnit) : null,
          onChanged: (text) => _cubit.setMeasurement(measurement, text),
        ),
        hint: l10n.measurementHint(measurement),
      ),
      PairStep(:final left, :final right) => page(
        l10n.measurementPairName(left),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: side(left, l10n.bodyLeft, first: true)),
            const SizedBox(width: Gap.md),
            Expanded(child: side(right, l10n.bodyRight, first: false)),
          ],
        ),
        hint: l10n.measurementHint(left),
      ),
      PhotoStep(:final pose) => _photo(context, state, pose),
    };
  }

  Widget _photo(
    BuildContext context,
    MeasurementDayState state,
    PhotoPose pose,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final file = state.photoFile(pose);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.poseName(pose), style: theme.textTheme.headlineSmall),
        const SizedBox(height: Gap.sm),
        Expanded(
          child: file == null || _retaking
              ? GhostCamera(
                  key: ValueKey(pose),
                  ghostFile: state.ghosts[pose],
                  captureLabel: l10n.bodyTakePhoto,
                  switchLabel: l10n.bodySwitchCamera,
                  unavailableText: l10n.bodyCameraUnavailable,
                  onCaptured: (file) {
                    setState(() => _retaking = false);
                    _cubit.photoTaken(file);
                  },
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: Image.file(File(file))),
                    TextButton.icon(
                      onPressed: () => setState(() => _retaking = true),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.bodyRetake),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// The measurements a measurement day asks for; pops with the new set.
/// "Body fat" stands for the measurements its estimate needs: ticking it
/// ticks them, and it is ticked exactly while all of them are. Unticking
/// it unticks those not in the standard set; when all are standard, it is
/// stopped by unticking one of them. Without the sex or height in the
/// profile it links to the profile instead.
class _TrackedDialog extends StatefulWidget {
  const _TrackedDialog(this.tracked);
  final Set<BodyMeasurement> tracked;

  @override
  State<_TrackedDialog> createState() => _TrackedDialogState();
}

class _TrackedDialogState extends State<_TrackedDialog> {
  late final Set<BodyMeasurement> _chosen = {...widget.tracked};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = context.select((ProfileCubit cubit) => cubit.state.profile);
    final sex = profile.sex;
    final needed = sex == null
        ? const <BodyMeasurement>{}
        : bodyFatMeasurements(sex);
    return AlertDialog(
      title: Text(l10n.bodyTrackedTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bodyFat(l10n, profile, needed),
            const Divider(),
            for (final measurement in BodyMeasurement.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _chosen.contains(measurement),
                title: Text(l10n.measurementName(measurement)),
                subtitle: needed.contains(measurement)
                    ? Text(l10n.bodyFatPart)
                    : null,
                onChanged: (on) => setState(
                  () => on == true
                      ? _chosen.add(measurement)
                      : _chosen.remove(measurement),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _chosen),
          child: Text(l10n.bodyDone),
        ),
      ],
    );
  }

  Widget _bodyFat(
    AppLocalizations l10n,
    UserProfile profile,
    Set<BodyMeasurement> needed,
  ) {
    final sex = profile.sex;
    if (sex == null || profile.heightCm == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.bodyFatTitle),
        subtitle: Text(l10n.bodyFatNeedsProfile),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          final router = GoRouter.of(context);
          Navigator.pop(context);
          router.go(Routes.profileDetails);
        },
      );
    }
    final on = tracksBodyFat(_chosen, sex: sex, heightCm: profile.heightCm);
    final off = withoutBodyFat(_chosen, sex);
    final stuck = on && setEquals(off, _chosen);
    final names = [
      for (final measurement in BodyMeasurement.values)
        if (needed.contains(measurement)) l10n.measurementName(measurement),
    ].join(', ');
    void choose(Set<BodyMeasurement> chosen) => setState(
      () => _chosen
        ..clear()
        ..addAll(chosen),
    );
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: on,
      title: Text(l10n.bodyFatTitle),
      // Stuck when all its measurements are standard ones: it is then
      // stopped through one of them.
      subtitle: Text(
        stuck ? l10n.bodyFatNeeds(names) : l10n.bodyFatNeedsList(names),
      ),
      onChanged: stuck
          ? null
          : (_) => choose(on ? off : withBodyFat(_chosen, sex)),
    );
  }
}
