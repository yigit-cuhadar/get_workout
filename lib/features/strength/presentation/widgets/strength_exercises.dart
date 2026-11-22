import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../exercises/presentation/vocabulary_labels.dart';
import '../strength_list_cubit.dart';
import '../strength_text.dart';

/// The exercises with stats as the Strength list shows them, with their
/// search: rows of [StrengthListCubit]'s state, each calling [onPick]. On
/// the list page every row has a chevron and a removed exercise is muted;
/// in the Exercise sheet they are radio rows with the [selected] one
/// picked, a removed exercise as a normal row. Inside a scrolling parent.
class StrengthExercises extends StatelessWidget {
  const StrengthExercises({
    super.key,
    required this.search,
    required this.onPick,
    this.selected,
  });

  final TextEditingController search;
  final ValueChanged<String> onPick;

  /// The exercise the sheet was opened for; null on the list page.
  final String? selected;

  static const _loadingRows = 6;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<StrengthListCubit>();
    final state = context.watch<StrengthListCubit>().state;
    return switch (state.status) {
      StrengthListStatus.loading => ListRowCard(
        children: [
          for (var i = 0; i < _loadingRows; i++) ListRow.loading(index: i),
        ],
      ),
      StrengthListStatus.failure => ErrorView(
        title: l10n.strengthLoadFailed,
        message: l10n.loadFailedDetail,
        retryLabel: l10n.retry,
        onRetry: cubit.retry,
      ),
      StrengthListStatus.ready when state.trainedCount == 0 => EmptyView(
        message: l10n.strengthEmpty,
      ),
      StrengthListStatus.ready => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          ForgeSearchField(
            hint: l10n.librarySearch,
            clearLabel: l10n.librarySearchClear,
            controller: search,
            onChanged: cubit.setQuery,
          ),
          if (state.items.isEmpty)
            EmptyView(message: l10n.strengthNoResults)
          else if (selected case final selected?)
            _Choices(items: state.items, selected: selected, onPick: onPick)
          else
            ListRowCard(
              children: [
                for (final item in state.items)
                  ListRow(
                    title: _name(context, item),
                    detail: _lastDone(l10n, item),
                    muted: item.removed,
                    end: ListRowEnd.chevron,
                    onTap: () => onPick(item.exerciseId),
                  ),
              ],
            ),
        ],
      ),
    };
  }
}

String _name(BuildContext context, StrengthItem item) =>
    item.exercise?.localized(context).name ??
    AppLocalizations.of(context).strengthRemovedExercise;

String _lastDone(AppLocalizations l10n, StrengthItem item) =>
    l10n.strengthLastDone(l10n.shortDate(item.lastTrained));

/// The sheet's radio rows, the last day done under each name.
class _Choices extends StatelessWidget {
  const _Choices({
    required this.items,
    required this.selected,
    required this.onPick,
  });

  final List<StrengthItem> items;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final index = items.indexWhere((item) => item.exerciseId == selected);
    return ChoiceGrid.list(
      form: ChoiceListForm.stacked,
      options: [
        for (final item in items)
          ChoiceOption(
            label: _name(context, item),
            hint: _lastDone(l10n, item),
          ),
      ],
      selected: index < 0 ? null : index,
      onSelected: (i) => onPick(items[i].exerciseId),
    );
  }
}
