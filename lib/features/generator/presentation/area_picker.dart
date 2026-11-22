import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/muscle_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/body_model_cubit.dart';
import '../domain/generator_options.dart';
import 'generator_text.dart';

/// How [AreaPicker] shows the areas.
enum AreaView { model, list }

/// Up to [max] body areas, picked on the body model, where a tap on a
/// muscle picks or drops its area of [areas] and the picked areas sit
/// under it as chips with their count, or in a list with tick boxes
/// ([view], which Model / List switches through [onView]). Without
/// [areas] (an older options document) only the list shows. At [max] no
/// other area can be picked. The leave-out form also shows the areas in
/// [focus], which cannot be picked, and paints the ones picked in a muted
/// neutral: the model takes one flat colour per muscle.
class AreaPicker extends StatelessWidget {
  const AreaPicker({
    super.key,
    required this.view,
    required this.onView,
    required this.areas,
    required this.model,
    required this.onRetryModel,
    required this.picked,
    required this.max,
    required this.onToggle,
  }) : focus = const {},
       _leaveOut = false;

  const AreaPicker.leaveOut({
    super.key,
    required this.view,
    required this.onView,
    required this.areas,
    required this.model,
    required this.onRetryModel,
    required this.picked,
    required this.max,
    required this.onToggle,
    required this.focus,
  }) : _leaveOut = true;

  final AreaView view;
  final ValueChanged<AreaView> onView;

  /// The muscles of each area, as the server acts on them on this page.
  final Map<FocusArea, Set<Muscle>>? areas;
  final BodyModelState model;
  final VoidCallback onRetryModel;
  final Set<FocusArea> picked;
  final int max;
  final ValueChanged<FocusArea> onToggle;
  final Set<FocusArea> focus;
  final bool _leaveOut;

  /// The part of the width the Model / List switch takes, as the model's
  /// Front / Back.
  static const double _switchShare = 1 / 3;

  bool _enabled(FocusArea area) =>
      picked.contains(area) || (picked.length < max && !focus.contains(area));

  void _tap(FocusArea? area) {
    if (area != null && _enabled(area)) onToggle(area);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final areas = this.areas;
    if (areas == null) return _list(context);
    final viewSwitch = Align(
      alignment: AlignmentDirectional.topStart,
      child: FractionallySizedBox(
        widthFactor: _switchShare,
        child: ForgeSegmentedControl<AreaView>(
          segments: [
            ForgeSegment(
              value: AreaView.model,
              label: l10n.generatorAreasModel,
            ),
            ForgeSegment(value: AreaView.list, label: l10n.generatorAreasList),
          ],
          selected: view,
          onChanged: onView,
        ),
      ),
    );
    return switch (view) {
      AreaView.model => Stack(
        children: [
          Positioned.fill(child: _model(context, areas)),
          PositionedDirectional(
            top: Gap.sm,
            start: Gap.sm,
            end: Gap.sm,
            child: viewSwitch,
          ),
        ],
      ),
      AreaView.list => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [viewSwitch, _list(context)],
      ),
    };
  }

  Widget _model(BuildContext context, Map<FocusArea, Set<Muscle>> areas) {
    final l10n = AppLocalizations.of(context);
    final chips = _Chips(picked: picked, max: max, onRemove: onToggle);
    return switch (model) {
      BodyModelReady(:final model) => MuscleModel(
        model: model,
        onOpen: (muscle) => _tap(areaOf(muscle, areas)),
        semanticLabel: l10n.generatorAreasModelLabel,
        colors: _colors(context, areas),
        footer: chips,
      ),
      BodyModelFailed() => MuscleModel.failed(
        message: l10n.generatorAreasModelFailed,
        onRetry: onRetryModel,
      ),
      BodyModelLoading() => MuscleModel.loading(footer: chips),
    };
  }

  Map<Muscle, Color> _colors(
    BuildContext context,
    Map<FocusArea, Set<Muscle>> areas,
  ) {
    final focusColor = GwColors.of(context).heatHigh;
    final leftOut = ForgeStyle.of(context).colors.inkMuted;
    // A muscle in two areas is painted for the first one, as a tap picks.
    Map<Muscle, Color> paint(Set<FocusArea> painted, Color color) => {
      for (final MapEntry(key: area, value: muscles) in areas.entries)
        if (painted.contains(area))
          for (final muscle in muscles)
            if (areaOf(muscle, areas) == area) muscle: color,
    };
    return _leaveOut
        ? {...paint(focus, focusColor), ...paint(picked, leftOut)}
        : paint(picked, focusColor);
  }

  Widget _list(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListRowCard(
      children: [
        for (final area in FocusArea.values)
          if (focus.contains(area))
            ListRow(
              title: l10n.focusAreaName(area),
              value: l10n.generatorAreaInFocus,
              disabled: true,
            )
          else
            ListRow(
              title: l10n.focusAreaName(area),
              checked: picked.contains(area),
              disabled: !_enabled(area),
              onTap: _enabled(area) ? () => onToggle(area) : null,
            ),
      ],
    );
  }
}

/// The picked areas as chips that drop them, and how many of [max].
class _Chips extends StatelessWidget {
  const _Chips({
    required this.picked,
    required this.max,
    required this.onRemove,
  });

  final Set<FocusArea> picked;
  final int max;
  final ValueChanged<FocusArea> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      spacing: Gap.sm,
      children: [
        Expanded(
          child: Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final area in FocusArea.values)
                if (picked.contains(area))
                  ForgeChip.removable(
                    label: l10n.focusAreaName(area),
                    onRemoved: () => onRemove(area),
                    removeHint: l10n.generatorAreaRemove,
                  ),
            ],
          ),
        ),
        Text(
          l10n.generatorAreasCount(picked.length, max),
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
            fontWeight: FontWeight.w400,
            color: ForgeStyle.of(context).colors.inkMuted,
          ),
        ),
      ],
    );
  }
}
