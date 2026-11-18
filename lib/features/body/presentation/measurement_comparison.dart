import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/choice_sheet.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/body_entry.dart';
import '../domain/entry_body_fat.dart';
import '../domain/measurement_summary.dart';
import 'body_text.dart';
import 'measurement_summary_cubit.dart';

/// A measurement day next to an earlier one, from the
/// [MeasurementSummaryCubit] above: the photos, the choice of what to
/// compare with, the changes as boxes and the way to the target weight.
/// With [compare] (Body's Compare) the photos come first and the later
/// day can be chosen too; otherwise (the Measurement summary) the dates
/// head the page and the photos come last. A day with no earlier one
/// shows its values alone.
class MeasurementComparison extends StatelessWidget {
  const MeasurementComparison({super.key, required this.compare});

  final bool compare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<MeasurementSummaryCubit, MeasurementSummaryState>(
      builder: (context, state) => switch (state.status) {
        MeasurementSummaryStatus.loading => _Loading(compare: compare),
        MeasurementSummaryStatus.failure => ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: [
            ErrorView(
              title: l10n.bodyLoadFailed,
              message: l10n.loadFailedDetail,
              retryLabel: l10n.retry,
              onRetry: context.read<MeasurementSummaryCubit>().retry,
              card: true,
            ),
          ],
        ),
        MeasurementSummaryStatus.notFound => ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: [
            EmptyView(
              icon: ForgeIcons.event,
              message: l10n.bodyNotFound,
              card: true,
            ),
          ],
        ),
        MeasurementSummaryStatus.noMeasurementDays => ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: [
            EmptyView(
              icon: ForgeIcons.event,
              title: l10n.bodyNoMeasurementDaysTitle,
              message: l10n.bodyNoMeasurementDays,
              actions: [
                ForgeButton(
                  label: l10n.bodyMeasurementDay,
                  variant: ForgeButtonVariant.secondary,
                  onPressed: () => context.go(Routes.bodyMeasureNew),
                ),
              ],
              card: true,
            ),
          ],
        ),
        MeasurementSummaryStatus.ready => _Summary(state, compare: compare),
      },
    );
  }
}

const _gap = SizedBox(height: 10);

/// [children] two to a row, each row as tall as its taller box.
class _Grid extends StatelessWidget {
  const _Grid(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    spacing: 10,
    children: [
      for (var i = 0; i < children.length; i += 2)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Expanded(child: children[i]),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
    ],
  );
}

class _Loading extends StatelessWidget {
  const _Loading({required this.compare});
  final bool compare;

  @override
  Widget build(BuildContext context) {
    const boxes = _Grid([
      StatTile.changeLoading(),
      StatTile.changeLoading(),
      StatTile.changeLoading(),
      StatTile.changeLoading(),
    ]);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: compare
          ? const [BeforeAfterSlider.loading(), _gap, boxes]
          : const [
              ListRowCard(children: [ListRow.loading()]),
              _gap,
              boxes,
              _gap,
              BeforeAfterSlider.loading(),
            ],
    );
  }
}

/// What to compare with.
enum _Choice { previous, first, other }

class _Summary extends StatelessWidget {
  const _Summary(this.state, {required this.compare});
  final MeasurementSummaryState state;
  final bool compare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summary = state.summary!;
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final before = summary.before;
    final photos = _Photos(state, compare: compare);
    final hasPhotos = summary.poses.isNotEmpty;
    final List<Widget> head;
    if (before == null) {
      head = [
        SectionCard.plain(
          title: compare
              ? l10n.bodyShortDayDate(summary.after.date)
              : l10n.bodyFullDayDate(summary.after.date),
          child: Text(l10n.bodySummaryAlone, style: theme.textTheme.bodyMedium),
        ),
        if (compare) ...[_gap, photos],
      ];
    } else {
      head = [
        if (compare)
          photos
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Gap.xs,
              children: [
                Text(
                  l10n.bodyDateSpan(before.date, summary.after.date),
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  l10n.bodySummarySaved,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: ForgeStyle.of(context).colors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        if (state.candidates.length > 1) ...[_gap, _BaselinePicker(state)],
        if (!hasPhotos) ...[_gap, _DateLine(state, compare: compare)],
      ];
    }
    final reason = _bodyFatReason(context, summary);
    final target = summary.target;
    return ListView(
      // Keeps its place while the Body page shows its other view.
      key: const PageStorageKey('comparison'),
      padding: const EdgeInsets.all(Gap.md),
      children: [
        ...head,
        if (reason != null) ...[_gap, reason],
        _gap,
        if (before == null) SectionLabel(l10n.bodyValues),
        _Grid(_boxes(l10n, summary, settings)),
        if (target != null) ...[
          _gap,
          FeaturedCard.target(
            title: l10n.bodyTargetCardTitle(
              l10n.bodyWeight(target.targetKg, settings.weightUnit),
            ),
            note: target.reached
                ? l10n.bodyTargetCardReached
                : switch (target.estimate) {
                    final date? => l10n.bodyTargetCardEstimate(
                      l10n.bodyShortDate(date),
                    ),
                    null => l10n.bodyTargetCardToGo(
                      l10n.bodyWeight(target.toGoKg.abs(), settings.weightUnit),
                    ),
                  },
          ),
        ],
        if (!compare) ...[_gap, SectionLabel(l10n.bodyPhotos), photos],
      ],
    );
  }

  /// Why body fat or fat and lean mass do not show, if they do not.
  static Widget? _bodyFatReason(
    BuildContext context,
    MeasurementSummary summary,
  ) {
    final l10n = AppLocalizations.of(context);
    final composition = summary.composition;
    if (composition != null && composition.fatKg != null) return null;
    final String message;
    Widget? action;
    if (composition != null) {
      message = l10n.bodySummaryNeedsWeight;
    } else {
      switch (summary.bodyFat) {
        case BodyFatNeedsMeasurements(:final missing):
          message = l10n.bodySummaryNeedsMeasurements(
            [
              for (final measurement in BodyMeasurement.values)
                if (missing.contains(measurement))
                  l10n.measurementName(measurement),
            ].join(', '),
          );
        case BodyFatOutOfRange():
          message = l10n.bodySummaryCheckMeasurements;
        default:
          message = l10n.bodySummaryNeedsProfile;
          action = ForgeButton(
            label: l10n.profileDetails,
            variant: ForgeButtonVariant.secondary,
            onPressed: () => context.go(Routes.profileDetails),
          );
      }
    }
    return NoticeBanner(
      icon: ForgeIcons.info,
      title: l10n.bodyFatNoneTitle,
      message: message,
      action: action,
    );
  }

  /// The boxes: weight, body fat, lean mass and fat mass, then every
  /// measurement in the usual order; with an earlier day each side of a
  /// pair has its own box with the change, alone the day's values.
  static List<Widget> _boxes(
    AppLocalizations l10n,
    MeasurementSummary summary,
    UserSettings settings,
  ) {
    final alone = summary.before == null;
    final weightUnit = settings.weightUnit;
    final lengthUnit = settings.lengthUnit;
    String side(double? value, String Function(double) number) =>
        value == null ? l10n.bodyNoValue : number(value);

    Widget box(
      String label,
      List<ValuePair> values, {
      required String Function(double) number,
      required String Function(double) change,
      required String Function(String) withUnit,
    }) {
      if (alone) {
        final after = [for (final pair in values) side(pair.after, number)];
        return StatTile.compact(
          label: label,
          figure: withUnit(
            after.length == 2
                ? l10n.bodyPair(after[0], after[1])
                : after.single,
          ),
        );
      }
      final pair = values.single;
      return StatTile.change(
        label: label,
        change: switch (pair.change) {
          final difference? => change(difference),
          null => l10n.bodyNoValue,
        },
        fromTo: withUnit(
          l10n.bodyFromTo(side(pair.before, number), side(pair.after, number)),
        ),
      );
    }

    String kg(String text) =>
        l10n.bodyQuantity(text, l10n.bodyWeightUnit(weightUnit));
    String cm(String text) =>
        l10n.bodyQuantity(text, l10n.bodyLengthUnit(lengthUnit));
    Widget weight(String label, ValuePair pair) => box(
      label,
      [pair],
      number: (value) => l10n.bodyWeightNumber(value, weightUnit),
      change: (value) => l10n.bodyWeightChangeNumber(value, weightUnit),
      withUnit: kg,
    );
    Widget length(String label, List<ValuePair> values) => box(
      label,
      values,
      number: (value) => l10n.bodyLengthNumber(value, lengthUnit),
      change: (value) => l10n.bodyLengthChangeNumber(value, lengthUnit),
      withUnit: cm,
    );
    final composition = summary.composition;
    return [
      if (summary.weightKg case final pair?) weight(l10n.bodyWeightTitle, pair),
      if (composition != null)
        box(
          l10n.bodyFatTitle,
          [composition.percent],
          number: l10n.bodyFatNumber,
          change: l10n.bodyFatChangeNumber,
          withUnit: l10n.bodyFatValue,
        ),
      if (composition?.leanKg case final pair?) weight(l10n.bodyLeanMass, pair),
      if (composition?.fatKg case final pair?) weight(l10n.bodyFatMass, pair),
      for (final row in summary.measurements)
        if (alone || row.measurements.length == 1)
          length(l10n.measurementGroupName(row.measurements), row.values)
        else ...[
          length(
            l10n.bodySideLeft(l10n.measurementPairName(row.measurements.first)),
            [row.values.first],
          ),
          length(
            l10n.bodySideRight(
              l10n.measurementPairName(row.measurements.first),
            ),
            [row.values.last],
          ),
        ],
    ];
  }
}

/// Previous / First / Other date; Other date opens the list of earlier
/// days, also when it is already chosen.
class _BaselinePicker extends StatelessWidget {
  const _BaselinePicker(this.state);
  final MeasurementSummaryState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<MeasurementSummaryCubit>();
    return ForgeSegmentedControl<_Choice>(
      segments: [
        ForgeSegment(value: _Choice.previous, label: l10n.bodyBaselinePrevious),
        ForgeSegment(value: _Choice.first, label: l10n.bodyBaselineFirst),
        ForgeSegment(value: _Choice.other, label: l10n.bodyBaselineOther),
      ],
      selected: switch (state.baseline) {
        PreviousDay() => _Choice.previous,
        FirstDay() => _Choice.first,
        ChosenDay() => _Choice.other,
      },
      onChanged: (choice) async {
        switch (choice) {
          case _Choice.previous:
            cubit.chooseBaseline(const PreviousDay());
          case _Choice.first:
            cubit.chooseBaseline(const FirstDay());
          case _Choice.other:
            final id = await _pickDay(
              context,
              title: l10n.bodyCompareWith,
              days: state.candidates,
              current: state.summary!.before?.id,
            );
            if (id != null) cubit.chooseBaseline(ChosenDay(id));
        }
      },
    );
  }
}

/// The compared dates in data, when there are no photos to carry them;
/// on Compare, a tap on the later one picks another later day.
class _DateLine extends StatelessWidget {
  const _DateLine(this.state, {required this.compare});
  final MeasurementSummaryState state;
  final bool compare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    final summary = state.summary!;
    final text = l10n.bodyFromTo(
      l10n.bodyShortDate(summary.before!.date),
      l10n.bodyShortDate(summary.after.date),
    );
    final line = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
      child: Text(
        text,
        style: style.data.copyWith(fontSize: 12, color: style.colors.inkMuted),
      ),
    );
    if (!compare || state.laterCandidates.length < 2) return line;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(onTap: () => _pickLater(context, state), child: line),
    );
  }
}

/// Offers the later days the earlier one can be compared with.
Future<void> _pickLater(
  BuildContext context,
  MeasurementSummaryState state,
) async {
  final cubit = context.read<MeasurementSummaryCubit>();
  final id = await _pickDay(
    context,
    title: AppLocalizations.of(context).bodyCompareLater,
    days: state.laterCandidates,
    current: state.summary!.after.id,
  );
  if (id != null) cubit.chooseAfter(id);
}

/// The id of one of [days] the user picks in a sheet, [current] ticked;
/// null when they pick none.
Future<String?> _pickDay(
  BuildContext context, {
  required String title,
  required List<BodyEntry> days,
  required String? current,
}) async {
  final l10n = AppLocalizations.of(context);
  final picked = await showChoiceSheet(
    context,
    title: title,
    values: days,
    selected: days.where((entry) => entry.id == current).firstOrNull,
    labelOf: (entry) => l10n.bodyFullDate(entry.date),
  );
  return picked?.id;
}

/// The photos of every pose either day has, compared on Forge's slider; a
/// pose only one day has shows that day's photo alone; a card saying there
/// are none. On Compare the later date picks another later day.
class _Photos extends StatelessWidget {
  const _Photos(this.state, {required this.compare});
  final MeasurementSummaryState state;
  final bool compare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = state.summary!;
    final before = summary.before;
    final after = summary.after;
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    if (summary.poses.isEmpty) {
      return EmptyView(
        icon: ForgeIcons.image,
        message: l10n.bodyNoPhotosOnDays,
        compact: true,
        card: true,
      );
    }
    ComparedPhoto photo(BodyEntry entry, PhotoPose pose) {
      final path = entry.photos[pose]!;
      if (state.photoFiles[path] case final file?) {
        return ComparedPhoto(FileImage(File(file)));
      }
      if (state.fetching.contains(path)) return const ComparedPhoto.loading();
      return ComparedPhoto.missing(l10n.bodyPhotoMissing);
    }

    final change = switch (summary.weightKg?.change) {
      final kg? => l10n.bodyWeightChange(kg, unit),
      null => null,
    };
    return BeforeAfterSlider(
      // Opens on the later photo again for another pair of days.
      key: ValueKey((before?.id, after.id)),
      sliderLabel: l10n.bodyPhotoSlider,
      onLaterDateTap: compare && state.laterCandidates.length > 1
          ? () => _pickLater(context, state)
          : null,
      views: [
        for (final pose in summary.poses)
          if (before == null || !before.photos.containsKey(pose))
            BeforeAfterView.single(
              name: l10n.poseShortName(pose),
              photo: photo(after, pose),
              date: l10n.bodyShortDate(after.date),
            )
          else if (!after.photos.containsKey(pose))
            BeforeAfterView.single(
              name: l10n.poseShortName(pose),
              photo: photo(before, pose),
              date: l10n.bodyShortDate(before.date),
            )
          else
            BeforeAfterView(
              name: l10n.poseShortName(pose),
              before: photo(before, pose),
              after: photo(after, pose),
              beforeDate: l10n.bodyShortDate(before.date),
              afterDate: l10n.bodyShortDate(after.date),
              change: change,
            ),
      ],
    );
  }
}
