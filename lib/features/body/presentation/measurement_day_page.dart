import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ghost_camera.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/body_entry.dart';
import 'body_entry_page.dart';
import 'body_input.dart';
import 'body_list_cubit.dart';
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
      entries: sl<BodyListCubit>().state.entries,
      tracked: settings.trackedMeasurements,
      weightUnit: settings.weightUnit,
      lengthUnit: settings.lengthUnit,
    );
    return BlocProvider(
      create: (_) => sl<MeasurementDayCubit>(param1: setup),
      child: _MeasurementDayView(settings),
    );
  }
}

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
              previous.settings.trackedMeasurements !=
              current.settings.trackedMeasurements,
          listener: (_, state) =>
              _cubit.setTracked(state.settings.trackedMeasurements),
        ),
        BlocListener<MeasurementDayCubit, MeasurementDayState>(
          listenWhen: (previous, current) =>
              previous.status != current.status ||
              previous.index != current.index,
          listener: _onChange,
        ),
      ],
      child: BlocBuilder<MeasurementDayCubit, MeasurementDayState>(
        builder: (context, state) {
          final busy = state.status == MeasurementDayStatus.saving;
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) unawaited(_back(state));
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
    );
  }

  void _onChange(BuildContext context, MeasurementDayState state) {
    final l10n = AppLocalizations.of(context);
    void tell(String text) =>
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text)));
    setState(() => _retaking = false);
    switch (state.status) {
      case MeasurementDayStatus.saved:
        // A retaken photo was written over its file; drop the old picture.
        for (final pose in state.newPhotos.keys) {
          if (state.keptFiles[pose] case final file?) {
            unawaited(FileImage(File(file)).evict());
          }
        }
        context.pop();
      case MeasurementDayStatus.closed:
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
  /// something was entered.
  Future<void> _back(MeasurementDayState state) async {
    if (_cubit.back()) return;
    final entered =
        state.weight.isNotEmpty ||
        state.measurements.values.any((text) => text.isNotEmpty) ||
        state.newPhotos.isNotEmpty;
    if (entered && !await _confirmDiscard()) return;
    if (mounted) context.pop();
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
    final chosen = await showDialog<Set<BodyMeasurement>>(
      context: context,
      builder: (_) =>
          _TrackedDialog(settings.state.settings.trackedMeasurements),
    );
    if (chosen == null) return;
    await settings.update(
      settings.state.settings.copyWith(trackedMeasurements: chosen),
    );
  }

  Widget _step(BuildContext context, MeasurementDayState state) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final weightUnit = widget.settings.weightUnit;
    final lengthUnit = widget.settings.lengthUnit;
    Widget field({
      required String title,
      required String unit,
      required String value,
      required String error,
      required ValueChanged<String> onChanged,
    }) => ListView(
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: Gap.md),
        TextFormField(
          // A fresh field per step.
          key: ValueKey(state.step),
          initialValue: value,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalInput,
          decoration: InputDecoration(
            suffixText: unit,
            errorText: state.invalid ? error : null,
          ),
          onChanged: onChanged,
          onFieldSubmitted: (_) => _cubit.next(),
        ),
      ],
    );

    return switch (state.step) {
      WeightStep() => field(
        title: l10n.bodyWeightTitle,
        unit: l10n.bodyWeightUnit(weightUnit),
        value: state.weight,
        error: l10n.bodyWeightRange(weightUnit),
        onChanged: _cubit.setWeight,
      ),
      MeasurementStep(:final measurement) => field(
        title: l10n.measurementName(measurement),
        unit: l10n.bodyLengthUnit(lengthUnit),
        value: state.measurements[measurement] ?? '',
        error: l10n.bodyMeasurementRange(lengthUnit),
        onChanged: _cubit.setMeasurement,
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
    return AlertDialog(
      title: Text(l10n.bodyTrackedTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final measurement in BodyMeasurement.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _chosen.contains(measurement),
                title: Text(l10n.measurementName(measurement)),
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
}
