import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/body_entry.dart';
import '../domain/body_stats.dart';
import 'body_list_cubit.dart';
import 'body_photo.dart';
import 'body_text.dart';

/// Two entries side by side: their numbers with the change, then their
/// photos pose by pose. Starts with the oldest and the newest entry.
class BodyComparePage extends StatelessWidget {
  const BodyComparePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocProvider.value(
      value: sl<BodyListCubit>(),
      child: BlocBuilder<BodyListCubit, BodyListState>(
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(l10n.bodyCompare)),
          body: switch (state.status) {
            BodyListStatus.loading => const LoadingView(),
            BodyListStatus.failure => ErrorView(
              message: l10n.bodyLoadFailed,
              retryLabel: l10n.retry,
              onRetry: context.read<BodyListCubit>().retry,
            ),
            BodyListStatus.ready when state.entries.length < 2 => EmptyView(
              message: l10n.bodyCompareEmpty,
            ),
            BodyListStatus.ready => _Comparison(state),
          },
        ),
      ),
    );
  }
}

class _Comparison extends StatefulWidget {
  const _Comparison(this.state);
  final BodyListState state;

  @override
  State<_Comparison> createState() => _ComparisonState();
}

class _ComparisonState extends State<_Comparison> {
  late String _firstId = widget.state.entries.last.id;
  late String _secondId = widget.state.entries.first.id;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Fetches the chosen entries' photos that are not on this device.
  void _restore() {
    final state = widget.state;
    unawaited(
      context.read<BodyListCubit>().restore([
        for (final id in [_firstId, _secondId])
          ...?state.entry(id)?.photos.values,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final entries = widget.state.entries;
    // A chosen entry that was deleted meanwhile falls back to the defaults.
    final first = widget.state.entry(_firstId) ?? entries.last;
    final second = widget.state.entry(_secondId) ?? entries.first;
    final comparison = BodyComparison.of(first, second);
    final dates = MaterialLocalizations.of(context);
    final files = widget.state.photoFiles;

    Widget picker(BodyEntry selected, ValueChanged<String> onChanged) =>
        DropdownButtonFormField<String>(
          // A new field when the fallback replaces a deleted choice.
          key: ValueKey(selected.id),
          initialValue: selected.id,
          isExpanded: true,
          items: [
            for (final entry in entries)
              DropdownMenuItem(
                value: entry.id,
                child: Text(
                  dates.formatMediumDate(entry.date),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            setState(() => onChanged(id!));
            _restore();
          },
        );

    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Row(
          children: [
            Expanded(child: picker(first, (id) => _firstId = id)),
            const SizedBox(width: Gap.sm),
            Expanded(child: picker(second, (id) => _secondId = id)),
          ],
        ),
        const SizedBox(height: Gap.md),
        _Row(
          name: l10n.bodyWeightTitle,
          values: [comparison.weightKg],
          value: (kg) => l10n.bodyWeight(kg, settings.weightUnit),
          change: (kg) => l10n.bodyWeightChange(kg, settings.weightUnit),
        ),
        if (comparison.bodyFat(widget.state.bodyFat) case final bodyFat
            when bodyFat.before != null || bodyFat.after != null)
          _Row(
            name: l10n.bodyFatTitle,
            values: [bodyFat],
            value: l10n.bodyFat,
            change: l10n.bodyFatChange,
          ),
        for (final group in comparison.measurementGroups)
          _Row(
            name: l10n.measurementGroupName(group),
            values: [
              for (final measurement in group)
                comparison.measurements[measurement]!,
            ],
            value: (cm) => l10n.bodyLength(cm, settings.lengthUnit),
            change: (cm) => l10n.bodyLengthChange(cm, settings.lengthUnit),
          ),
        for (final pose in comparison.poses) ...[
          const SizedBox(height: Gap.md),
          PhotoRows([
            for (final entry in [comparison.before, comparison.after])
              BodyPhoto(
                file: files[entry.photos[pose]],
                label: l10n.bodyPoseOn(
                  l10n.poseName(pose),
                  dates.formatShortMonthDay(entry.date),
                ),
                missingText: entry.photos.containsKey(pose)
                    ? l10n.bodyPhotoMissing
                    : l10n.bodyPhotoNone,
              ),
          ]),
        ],
      ],
    );
  }
}

/// A value on both dates, then the change between them; for both sides of
/// a pair, the left and right values joined.
class _Row extends StatelessWidget {
  const _Row({
    required this.name,
    required this.values,
    required this.value,
    required this.change,
  });

  final String name;

  /// One, or the left and the right side.
  final List<ValuePair> values;
  final String Function(double) value;
  final String Function(double) change;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String joined(Iterable<String> texts) => switch (texts.toList()) {
      [final left, final right] => l10n.bodyPair(left, right),
      final single => single.single,
    };
    String text(double? Function(ValuePair) side) => joined([
      for (final pair in values)
        if (side(pair) case final metric?) value(metric) else l10n.bodyNoValue,
    ]);
    final differences = [for (final pair in values) pair.change];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(name)),
          Expanded(child: Text(text((pair) => pair.before))),
          Expanded(child: Text(text((pair) => pair.after))),
          Expanded(
            child: Text(
              differences.every((difference) => difference == null)
                  ? ''
                  : joined([
                      for (final difference in differences)
                        difference == null
                            ? l10n.bodyNoValue
                            : change(difference),
                    ]),
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
