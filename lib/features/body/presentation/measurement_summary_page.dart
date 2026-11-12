import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/before_after_slider.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/body_entry.dart';
import '../domain/entry_body_fat.dart';
import '../domain/measurement_summary.dart';
import 'body_photo.dart';
import 'body_text.dart';
import 'measurement_summary_cubit.dart';

/// A measurement day next to an earlier one: the dates with the choice of
/// what to compare with, body fat and lean mass, the changes, the way to
/// the target weight and the photos on a slider. Titled "Compare" when
/// [compare], "Measurement summary" right after the day was saved.
class MeasurementSummaryPage extends StatelessWidget {
  const MeasurementSummaryPage({
    super.key,
    required this.id,
    required this.compare,
  });

  final String id;
  final bool compare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocProvider(
      create: (_) => sl<MeasurementSummaryCubit>(param1: id),
      child: BlocBuilder<MeasurementSummaryCubit, MeasurementSummaryState>(
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            title: Text(compare ? l10n.bodyCompare : l10n.bodySummaryTitle),
          ),
          body: switch (state.status) {
            MeasurementSummaryStatus.loading => const LoadingView(),
            MeasurementSummaryStatus.failure => ErrorView(
              message: l10n.bodyLoadFailed,
              retryLabel: l10n.retry,
              onRetry: context.read<MeasurementSummaryCubit>().retry,
            ),
            MeasurementSummaryStatus.notFound => EmptyView(
              message: l10n.bodyNotFound,
            ),
            MeasurementSummaryStatus.ready => _Summary(state),
          },
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary(this.state);
  final MeasurementSummaryState state;

  @override
  Widget build(BuildContext context) {
    final summary = state.summary!;
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        _Dates(state),
        _BodyFat(summary, settings.weightUnit),
        if (summary.weightKg != null || summary.measurements.isNotEmpty)
          _Changes(summary, settings),
        if (summary.target case final target?)
          _Target(target, settings.weightUnit),
        if (state.pose case final pose?) _Photos(state, pose),
      ],
    );
  }
}

/// A heading with space above it.
class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.lg, bottom: Gap.sm),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// The two dates, and what to compare with when there is a choice.
class _Dates extends StatelessWidget {
  const _Dates(this.state);
  final MeasurementSummaryState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    final cubit = context.read<MeasurementSummaryCubit>();
    final summary = state.summary!;
    final after = dates.formatMediumDate(summary.after.date);
    final before = summary.before;
    final baseline = state.baseline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          before == null
              ? after
              : l10n.bodySummaryDates(
                  dates.formatMediumDate(before.date),
                  after,
                ),
          style: theme.textTheme.titleLarge,
        ),
        if (before == null)
          Text(l10n.bodySummaryAlone, style: theme.textTheme.bodyMedium),
        if (state.candidates.length > 1) ...[
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              ChoiceChip(
                label: Text(l10n.bodyBaselinePrevious),
                selected: baseline is PreviousDay,
                onSelected: (_) => cubit.chooseBaseline(const PreviousDay()),
              ),
              ChoiceChip(
                label: Text(l10n.bodyBaselineFirst),
                selected: baseline is FirstDay,
                onSelected: (_) => cubit.chooseBaseline(const FirstDay()),
              ),
              ChoiceChip(
                label: Text(l10n.bodyBaselineOther),
                selected: baseline is ChosenDay,
                onSelected: (_) => _pick(context, before?.id),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _pick(BuildContext context, String? current) async {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final cubit = context.read<MeasurementSummaryCubit>();
    final id = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.bodyCompareWith),
        children: [
          for (final entry in state.candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.id),
              child: Row(
                children: [
                  Expanded(child: Text(dates.formatMediumDate(entry.date))),
                  if (entry.id == current) const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (id != null) cubit.chooseBaseline(ChosenDay(id));
  }
}

/// Body fat with fat and lean mass, or what it is missing.
class _BodyFat extends StatelessWidget {
  const _BodyFat(this.summary, this.unit);
  final MeasurementSummary summary;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final alone = summary.before == null;
    final composition = summary.composition;
    final children = <Widget>[_Heading(l10n.bodyFatTitle)];
    if (composition == null) {
      final needsProfile = switch (summary.bodyFat) {
        BodyFatNeedsSex() || BodyFatNeedsHeight() => true,
        _ => false,
      };
      children.addAll([
        Text(switch (summary.bodyFat) {
          BodyFatNeedsMeasurements(:final missing) =>
            l10n.bodySummaryNeedsMeasurements(
              [
                for (final measurement in BodyMeasurement.values)
                  if (missing.contains(measurement))
                    l10n.measurementName(measurement),
              ].join(', '),
            ),
          BodyFatOutOfRange() => l10n.bodySummaryCheckMeasurements,
          _ => l10n.bodySummaryNeedsProfile,
        }, style: theme.textTheme.bodyMedium),
        if (needsProfile)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => context.go(Routes.profileDetails),
              child: Text(l10n.profileDetails),
            ),
          ),
      ]);
    } else {
      String weight(double kg) => l10n.bodyWeight(kg, unit);
      String weightChange(double kg) => l10n.bodyWeightChange(kg, unit);
      children.addAll([
        _ValueRow(
          name: l10n.bodyFatTitle,
          values: [composition.percent],
          alone: alone,
          value: l10n.bodyFat,
          change: l10n.bodyFatChange,
        ),
        if (composition.fatKg case final fatKg?)
          _ValueRow(
            name: l10n.bodyFatMass,
            values: [fatKg],
            alone: alone,
            value: weight,
            change: weightChange,
          ),
        if (composition.leanKg case final leanKg?)
          _ValueRow(
            name: l10n.bodyLeanMass,
            values: [leanKg],
            alone: alone,
            value: weight,
            change: weightChange,
          ),
        if (composition.fatKg == null)
          Text(l10n.bodySummaryNeedsWeight, style: theme.textTheme.bodyMedium),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// The weight and every measurement, with the change when there is an
/// earlier day.
class _Changes extends StatelessWidget {
  const _Changes(this.summary, this.settings);
  final MeasurementSummary summary;
  final UserSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    final before = summary.before;
    final alone = before == null;
    final unit = settings.lengthUnit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(alone ? l10n.bodyValues : l10n.bodyChanges),
        if (before != null)
          DefaultTextStyle.merge(
            style: theme.textTheme.labelMedium,
            child: _Columns(
              name: const SizedBox.shrink(),
              before: Text(dates.formatShortMonthDay(before.date)),
              after: Text(dates.formatShortMonthDay(summary.after.date)),
              change: Text(l10n.bodyChange, textAlign: TextAlign.end),
            ),
          ),
        if (summary.weightKg case final weightKg?)
          _ValueRow(
            name: l10n.bodyWeightTitle,
            values: [weightKg],
            alone: alone,
            value: (kg) => l10n.bodyWeight(kg, settings.weightUnit),
            change: (kg) => l10n.bodyWeightChange(kg, settings.weightUnit),
          ),
        for (final row in summary.measurements)
          _ValueRow(
            name: l10n.measurementGroupName(row.measurements),
            values: row.values,
            alone: alone,
            value: (cm) => l10n.bodyLength(cm, unit),
            change: (cm) => l10n.bodyLengthChange(cm, unit),
          ),
      ],
    );
  }
}

/// A name, then the value before, after and the change; without
/// [before] and [change], only the value.
class _Columns extends StatelessWidget {
  const _Columns({
    required this.name,
    required this.after,
    this.before,
    this.change,
  });

  final Widget name;
  final Widget? before;
  final Widget after;
  final Widget? change;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Gap.xs),
    child: Row(
      children: [
        Expanded(flex: 2, child: name),
        if (before case final before?) Expanded(child: before),
        Expanded(child: after),
        if (change case final change?) Expanded(child: change),
      ],
    ),
  );
}

/// One value, or the left and right side of a pair joined, on both days
/// with the change; a missing side is a dash. Changes all look the same:
/// whether one is good depends on the user's goal.
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.name,
    required this.values,
    required this.alone,
    required this.value,
    required this.change,
  });

  final String name;

  /// One, or the left and the right side.
  final List<ValuePair> values;

  /// There is no earlier day: only the value shows.
  final bool alone;
  final String Function(double) value;
  final String Function(double) change;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String joined(List<String> texts) => switch (texts) {
      [final left, final right] => l10n.bodyPair(left, right),
      _ => texts.single,
    };
    String text(double? Function(ValuePair) side) => joined([
      for (final pair in values)
        if (side(pair) case final metric?) value(metric) else l10n.bodyNoValue,
    ]);
    final differences = [for (final pair in values) pair.change];
    return _Columns(
      name: Text(name),
      before: alone ? null : Text(text((pair) => pair.before)),
      after: Text(
        text((pair) => pair.after),
        textAlign: alone ? TextAlign.end : null,
      ),
      change: alone
          ? null
          : Text(
              differences.every((difference) => difference == null)
                  ? ''
                  : joined([
                      for (final difference in differences)
                        difference == null
                            ? l10n.bodyNoValue
                            : change(difference),
                    ]),
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
    );
  }
}

/// The distance to the target weight and, when there is one, when it is
/// reached at the current rate.
class _Target extends StatelessWidget {
  const _Target(this.target, this.unit);
  final TargetProgress target;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final weight = l10n.bodyWeight(target.targetKg, unit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(l10n.bodyTargetTitle),
        Text(
          target.reached
              ? l10n.bodyTargetReached(weight)
              : l10n.bodyTargetToGo(
                  weight,
                  l10n.bodyWeight(target.toGoKg.abs(), unit),
                ),
          style: theme.textTheme.bodyMedium,
        ),
        if (target.estimate case final estimate?)
          Text(
            l10n.bodyTargetEstimate(
              MaterialLocalizations.of(context).formatMediumDate(estimate),
            ),
            style: theme.textTheme.bodyMedium,
          ),
      ],
    );
  }
}

/// The photos of one pose: the earlier left of a bar and the later right
/// of it, or the later alone.
class _Photos extends StatelessWidget {
  const _Photos(this.state, this.pose);
  final MeasurementSummaryState state;
  final PhotoPose pose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    final summary = state.summary!;
    final before = summary.before;
    final poses = summary.poses;
    Widget side(BodyEntry entry, AlignmentGeometry alignment) => _Side(
      path: entry.photos[pose],
      files: state.photoFiles,
      alignment: alignment,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(l10n.bodyPhotos),
        if (poses.length > 1) ...[
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final option in poses)
                ChoiceChip(
                  label: Text(l10n.poseName(option)),
                  selected: option == pose,
                  onSelected: (_) => context
                      .read<MeasurementSummaryCubit>()
                      .selectPose(option),
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
        ],
        AspectRatio(
          aspectRatio: BodyPhoto.aspectRatio,
          child: before == null
              ? side(summary.after, Alignment.center)
              : BeforeAfterSlider(
                  // Starts in the middle again for another pair of photos.
                  key: ValueKey((before.id, summary.after.id, pose)),
                  before: side(before, Alignment.centerLeft),
                  after: side(summary.after, Alignment.centerRight),
                ),
        ),
        const SizedBox(height: Gap.xs),
        DefaultTextStyle.merge(
          style: theme.textTheme.labelMedium,
          child: Row(
            children: [
              if (before != null)
                Expanded(child: Text(dates.formatShortMonthDay(before.date))),
              Expanded(
                child: Text(
                  dates.formatShortMonthDay(summary.after.date),
                  textAlign: before == null ? TextAlign.center : TextAlign.end,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One day's photo filling its place, or why there is none, on the half
/// of the place [alignment] points to.
class _Side extends StatelessWidget {
  const _Side({
    required this.path,
    required this.files,
    required this.alignment,
  });

  final String? path;
  final Map<String, String> files;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (files[path] case final file?) {
      return Image.file(File(file), fit: BoxFit.cover);
    }
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Align(
        alignment: alignment,
        child: FractionallySizedBox(
          widthFactor: alignment == Alignment.center ? 1.0 : 0.5,
          child: Padding(
            padding: const EdgeInsets.all(Gap.sm),
            child: Text(
              path == null ? l10n.bodyPhotoNone : l10n.bodyPhotoMissing,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
      ),
    );
  }
}
