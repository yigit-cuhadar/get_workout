import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../exercises/presentation/vocabulary_labels.dart';
import '../strength_list_cubit.dart';
import '../strength_text.dart';

/// The exercises with stats as the Strength list shows them, with their
/// search: rows of [StrengthListCubit]'s state, each calling [onPick]; the
/// [selected] one ticked (in the Exercise sheet) or every row with a
/// chevron (on the list page). Inside a scrolling parent.
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
          else
            ListRowCard(
              children: [
                for (final item in state.items)
                  _Row(
                    item: item,
                    selected: selected,
                    onTap: () => onPick(item.exerciseId),
                  ),
              ],
            ),
        ],
      ),
    };
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.selected, required this.onTap});

  final StrengthItem item;
  final String? selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ForgeStyle.of(context).colors;
    final picked = item.exerciseId == selected;
    return Semantics(
      selected: selected == null ? null : picked,
      child: ListRow(
        title:
            item.exercise?.localized(context).name ??
            l10n.strengthRemovedExercise,
        detail: l10n.strengthLastDone(l10n.shortDate(item.lastTrained)),
        trailing: picked
            ? ForgeIcon(ForgeIcons.check, size: 18, color: colors.accent)
            : null,
        end: selected == null ? ListRowEnd.chevron : ListRowEnd.none,
        onTap: onTap,
      ),
    );
  }
}
