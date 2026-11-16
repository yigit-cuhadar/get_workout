import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/unsaved_changes.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../../profile/presentation/profile_questions.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/body_entry.dart';
import '../domain/body_stats.dart';
import '../domain/body_validation.dart';
import '../domain/entry_body_fat.dart';
import 'body_entry_page.dart';
import 'body_list_cubit.dart';
import 'body_text.dart';
import 'measurement_day_cubit.dart';
import 'widgets/pose_camera.dart';

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
    final previous = previousWeighIn(
      sl<BodyListCubit>().state.entries,
      edited: entry,
    );
    final MeasurementDaySetup setup = (
      initial: entry,
      tracked: _tracked(context),
      weightUnit: settings.weightUnit,
      lengthUnit: settings.lengthUnit,
      startKg: startWeightKg(
        previous: previous,
        profileKg: context.read<ProfileCubit>().state.profile.weightKg,
      ),
    );
    return BlocProvider(
      create: (_) => sl<MeasurementDayCubit>(param1: setup),
      child: _MeasurementDayView(settings, entry: entry, previous: previous),
    );
  }
}

/// What the user tracks: their own choice, else the default for their sex.
Set<BodyMeasurement> _tracked(BuildContext context) => trackedMeasurements(
  context.read<SettingsCubit>().state.settings.customTrackedMeasurements,
  context.read<ProfileCubit>().state.profile.sex,
);

/// Stores [chosen] as what the user tracks; an unchanged set keeps
/// following the default.
Future<void> _setTracked(
  BuildContext context,
  Set<BodyMeasurement> chosen,
) async {
  final settings = context.read<SettingsCubit>();
  if (setEquals(chosen, _tracked(context))) return;
  await settings.update(
    settings.state.settings.copyWith(customTrackedMeasurements: chosen),
  );
}

class _MeasurementDayView extends StatefulWidget {
  const _MeasurementDayView(
    this.settings, {
    required this.entry,
    required this.previous,
  });

  /// As the flow opened; units do not change midway.
  final UserSettings settings;
  final BodyEntry? entry;

  /// The weigh-in before this day, named under the ruler.
  final BodyEntry? previous;

  @override
  State<_MeasurementDayView> createState() => _MeasurementDayViewState();
}

class _MeasurementDayViewState extends State<_MeasurementDayView> {
  late final MeasurementDayCubit _cubit = context.read<MeasurementDayCubit>();
  final _fields = <BodyMeasurement, TextEditingController>{};

  /// The ruler's steps, in the user's unit.
  static const _weightStep = 0.1;

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  TextEditingController _field(BodyMeasurement measurement) =>
      _fields[measurement] ??= TextEditingController(
        text: _cubit.state.measurements[measurement] ?? '',
      );

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
          listenWhen: (previous, current) => previous.status != current.status,
          listener: _onStatus,
        ),
      ],
      child: UnsavedChangesGuard(
        hasChanges: () => _cubit.hasChanges,
        confirmDiscard: _confirmDiscard,
        child: BlocBuilder<MeasurementDayCubit, MeasurementDayState>(
          builder: (context, state) {
            final busy = state.status == MeasurementDayStatus.saving;
            final camera = state.camera;
            final caption = l10n.bodyStepCaption(
              state.step.index + 1,
              MeasureStep.values.length,
              _stepName(l10n, state.step),
            );
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) unawaited(_back(context));
              },
              child: Scaffold(
                appBar: ForgeAppBar(
                  title: l10n.bodyMeasurementDay,
                  actions: [
                    // MD12: only where the measurements are.
                    if (state.step == MeasureStep.measurements)
                      ForgeAppBarAction.icon(
                        icon: ForgeIcons.tune,
                        label: l10n.bodyTrackedTitle,
                        onPressed: busy ? null : _editTracked,
                      ),
                  ],
                ),
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Gap.md,
                        Gap.sm,
                        Gap.md,
                        Gap.md,
                      ),
                      child: StepProgress(
                        count: MeasureStep.values.length,
                        current: state.step.index + 1,
                        caption: switch (widget.entry) {
                          final entry? => l10n.bodyStepCaptionDated(
                            l10n.bodyShortDayDate(entry.date),
                            caption,
                          ),
                          null => caption,
                        },
                      ),
                    ),
                    Expanded(
                      child: camera != null
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(
                                Gap.md,
                                0,
                                Gap.md,
                                Gap.md,
                              ),
                              child: PoseCamera(
                                key: ValueKey(camera),
                                pose: l10n.poseName(camera),
                                step: camera.index + 1,
                                total: PhotoPose.values.length,
                                ghostFile: state.ghosts[camera],
                                onCaptured: _cubit.photoTaken,
                                onSkip: _cubit.closeCamera,
                              ),
                            )
                          : state.step == MeasureStep.weight
                          ? _weightPage(context, state)
                          : ListView(
                              padding: _contentPadding,
                              children: [
                                Text(
                                  _stepName(l10n, state.step),
                                  style: _heading(context),
                                ),
                                const SizedBox(height: Gap.md),
                                ...switch (state.step) {
                                  MeasureStep.measurements => _measurements(
                                    context,
                                    state,
                                  ),
                                  _ => _photos(context, state),
                                },
                              ],
                            ),
                    ),
                  ],
                ),
                bottomNavigationBar: _actions(l10n, state, busy),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The step's 20px heading, as the board draws it.
  static TextStyle _heading(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!
          .copyWith(fontSize: 20, height: 26 / 20);

  static String _stepName(AppLocalizations l10n, MeasureStep step) =>
      switch (step) {
        MeasureStep.weight => l10n.bodyWeightTitle,
        MeasureStep.measurements => l10n.bodyStepMeasurements,
        MeasureStep.photos => l10n.bodyStepPhotos,
      };

  Widget _actions(AppLocalizations l10n, MeasurementDayState state, bool busy) {
    if (state.camera != null) {
      return ForgeBottomActionBar(
        primary: ForgeButton(
          label: l10n.bodySkipThisPhoto,
          variant: ForgeButtonVariant.secondary,
          size: ForgeButtonSize.large,
          onPressed: _cubit.closeCamera,
        ),
      );
    }
    final back = ForgeButton(
      label: l10n.bodyBack,
      variant: ForgeButtonVariant.secondary,
      size: ForgeButtonSize.large,
      onPressed: busy ? null : _cubit.back,
    );
    return switch (state.step) {
      MeasureStep.weight => ForgeBottomActionBar(
        primary: ForgeButton(
          label: l10n.bodyNextMeasurements,
          size: ForgeButtonSize.large,
          onPressed: _cubit.next,
        ),
      ),
      MeasureStep.measurements => ForgeBottomActionBar.sideBySide(
        secondary: back,
        primary: ForgeButton(
          label: l10n.bodyNextPhotos,
          size: ForgeButtonSize.large,
          onPressed: _cubit.next,
        ),
      ),
      MeasureStep.photos => ForgeBottomActionBar.sideBySide(
        secondary: back,
        primary: ForgeButton(
          label: l10n.bodySave,
          size: ForgeButtonSize.large,
          loading: busy,
          onPressed: busy ? null : _cubit.next,
        ),
      ),
    };
  }

  static const _contentPadding = EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.lg);

  /// The heading at the top and the ruler at the bottom, near the thumb,
  /// with the room between them (P5).
  Widget _weightPage(BuildContext context, MeasurementDayState state) {
    final l10n = AppLocalizations.of(context);
    final unit = widget.settings.weightUnit;
    final range = rulerRange(
      BodyLimits.minWeightKg,
      BodyLimits.maxWeightKg,
      unit.fromKg,
      _weightStep,
    );
    final previous = widget.previous;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: _contentPadding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - _contentPadding.vertical,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.bodyWeightTitle, style: _heading(context)),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Gap.lg),
                  NumberPicker.ruler(
                    label: l10n.bodyWeightTitle,
                    unit: l10n.bodyWeightUnit(unit),
                    min: range.min,
                    max: range.max,
                    step: _weightStep,
                    value: state.weight,
                    onChanged: _cubit.setWeight,
                  ),
                  if (previous?.weightKg case final kg?) ...[
                    const SizedBox(height: Gap.sm),
                    Text(
                      l10n.bodyLastWeighIn(
                        l10n.bodyWeight(kg, unit),
                        l10n.bodyShortDayDate(previous!.date),
                      ),
                      textAlign: TextAlign.center,
                      style: _muted(context),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static TextStyle _muted(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!
          .copyWith(color: ForgeStyle.of(context).colors.inkMuted);

  List<Widget> _measurements(BuildContext context, MeasurementDayState state) {
    final l10n = AppLocalizations.of(context);
    final unit = l10n.bodyLengthUnit(widget.settings.lengthUnit);
    final range = l10n.bodyMeasurementRange(widget.settings.lengthUnit);
    Widget field(BodyMeasurement measurement, String label, {String? side}) =>
        ForgeNumberField(
          key: ValueKey(measurement),
          label: label,
          unit: unit,
          side: side,
          controller: _field(measurement),
          onChanged: (text) => _cubit.setMeasurement(measurement, text),
        );
    return [
      ListRowCard(
        children: [
          for (final group in state.groups)
            () {
              final name = group.length == 1
                  ? l10n.measurementName(group.single)
                  : l10n.measurementPairName(group.first);
              return ListRow(
                title: name,
                onInfo: () => _showHint(name, group.first),
                infoLabel: l10n.bodyAboutMeasurement,
                error: group.any(state.invalidMeasurements.contains)
                    ? range
                    : null,
                trailing: switch (group) {
                  [final left, final right] => Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Gap.sm,
                    children: [
                      field(left, name, side: l10n.bodyLeft),
                      field(right, name, side: l10n.bodyRight),
                    ],
                  ),
                  _ => field(group.single, name),
                },
              );
            }(),
        ],
      ),
      const SizedBox(height: Gap.md),
      ListRowCard(children: [_bodyFatRow(context)]),
    ];
  }

  /// Estimate body fat: the Body fat box of "Measurements to track"
  /// (MD10), with the estimate of the values typed so far.
  Widget _bodyFatRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = context.select((ProfileCubit cubit) => cubit.state.profile);
    final sex = profile.sex;
    if (sex == null || profile.heightCm == null) {
      return ListRow(
        title: l10n.bodyEstimateBodyFat,
        detail: l10n.bodyFatNeedsProfile,
        end: ListRowEnd.chevron,
        onTap: () => context.go(Routes.profileDetails),
      );
    }
    final tracked = context.select(
      (SettingsCubit cubit) => trackedMeasurements(
        cubit.state.settings.customTrackedMeasurements,
        sex,
      ),
    );
    final on = tracksBodyFat(tracked, sex: sex, heightCm: profile.heightCm);
    final from = switch (sex) {
      Sex.male => l10n.bodyFatFromMale,
      Sex.female => l10n.bodyFatFromFemale,
    };
    final percent = _cubit
        .bodyFat(sex: sex, heightCm: profile.heightCm)
        .percent;
    return ListRow(
      title: l10n.bodyEstimateBodyFat,
      detail: on && percent != null
          ? l10n.bodyFatFromValue(from, l10n.bodyFat(percent))
          : from,
      checked: on,
      onTap: () => _setTracked(
        context,
        on ? withoutBodyFat(tracked, sex) : withBodyFat(tracked, sex),
      ),
    );
  }

  Future<void> _showHint(String name, BodyMeasurement measurement) {
    final l10n = AppLocalizations.of(context);
    return showForgeBottomSheet<void>(
      context: context,
      builder: (context) => ForgeBottomSheet(
        title: name,
        child: Text(
          l10n.measurementHint(measurement),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  List<Widget> _photos(BuildContext context, MeasurementDayState state) {
    final l10n = AppLocalizations.of(context);
    Widget tile(PhotoPose pose) {
      final label = l10n.poseName(pose);
      void open() => _cubit.openCamera(pose);
      if (state.photoFile(pose) case final file?) {
        return PhotoTile(
          image: FileImage(File(file)),
          semanticLabel: l10n.bodyPhotoLabel(label),
          label: label,
          onTap: open,
        );
      }
      if (state.keptPhotos.containsKey(pose)) {
        return PhotoTile.loading(label: label);
      }
      return PhotoTile.empty(
        message: l10n.bodyAddPhoto,
        label: label,
        onTap: open,
      );
    }

    return [
      Text(
        widget.entry == null ? l10n.bodyPhotosHint : l10n.bodyPhotosKeptHint,
        style: _muted(context),
      ),
      const SizedBox(height: Gap.md),
      for (var i = 0; i < PhotoPose.values.length; i += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.sm),
          child: Row(
            spacing: Gap.sm,
            children: [
              Expanded(child: tile(PhotoPose.values[i])),
              Expanded(child: tile(PhotoPose.values[i + 1])),
            ],
          ),
        ),
    ];
  }

  void _onStatus(BuildContext context, MeasurementDayState state) {
    final l10n = AppLocalizations.of(context);
    switch (state.status) {
      // A new day goes on to its summary, in place of the flow.
      case MeasurementDayStatus.saved when _cubit.savedNewId != null:
        context.go(Routes.bodySummary(_cubit.savedNewId!));
      case MeasurementDayStatus.saved || MeasurementDayStatus.closed:
        context.pop();
      case MeasurementDayStatus.saveFailed:
        showForgeSnackbar(
          context,
          message: state.failure is NetworkFailure
              ? l10n.errorNetwork
              : l10n.bodySaveFailed,
          error: true,
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
    final discard = await showForgeDialog<bool>(
      context: context,
      builder: (dialog) => ForgeDialog(
        title: l10n.bodyDiscardTitle,
        action: ForgeButton(
          label: l10n.bodyDiscard,
          variant: ForgeButtonVariant.danger,
          onPressed: () => Navigator.pop(dialog, true),
        ),
        cancel: ForgeButton(
          label: l10n.cancel,
          variant: ForgeButtonVariant.secondary,
          onPressed: () => Navigator.pop(dialog, false),
        ),
      ),
    );
    return discard ?? false;
  }

  Future<void> _editTracked() async {
    final chosen = await showForgeDialog<Set<BodyMeasurement>>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<ProfileCubit>(),
        child: _TrackedDialog(_tracked(context)),
      ),
    );
    if (chosen != null && mounted) await _setTracked(context, chosen);
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
    return ForgeDialog.list(
      title: l10n.bodyTrackedTitle,
      list: [
        _bodyFat(l10n, profile, needed),
        for (final measurement in BodyMeasurement.values)
          ListRow(
            title: l10n.measurementName(measurement),
            detail: needed.contains(measurement) ? l10n.bodyFatPart : null,
            checked: _chosen.contains(measurement),
            onTap: () => setState(
              () => _chosen.contains(measurement)
                  ? _chosen.remove(measurement)
                  : _chosen.add(measurement),
            ),
          ),
      ],
      action: ForgeButton(
        label: l10n.bodyDone,
        onPressed: () => Navigator.pop(context, _chosen),
      ),
      cancel: ForgeButton(
        label: l10n.cancel,
        variant: ForgeButtonVariant.secondary,
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _bodyFat(
    AppLocalizations l10n,
    UserProfile profile,
    Set<BodyMeasurement> needed,
  ) {
    final sex = profile.sex;
    if (sex == null || profile.heightCm == null) {
      return ListRow(
        title: l10n.bodyFatTitle,
        detail: l10n.bodyFatNeedsProfile,
        end: ListRowEnd.chevron,
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
    return ListRow(
      title: l10n.bodyFatTitle,
      // Stuck when all its measurements are standard ones: it is then
      // stopped through one of them.
      detail: stuck ? l10n.bodyFatNeeds(names) : l10n.bodyFatNeedsList(names),
      checked: on,
      disabled: stuck,
      onTap: stuck
          ? null
          : () => setState(() {
              final chosen = on ? off : withBodyFat(_chosen, sex);
              _chosen
                ..clear()
                ..addAll(chosen);
            }),
    );
  }
}
