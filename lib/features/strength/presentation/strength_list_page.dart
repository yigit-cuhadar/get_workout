import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import 'strength_list_cubit.dart';

/// The exercises the user has done, most recently trained first, each
/// opening its records and e1RM chart.
class StrengthListPage extends StatelessWidget {
  const StrengthListPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<StrengthListCubit>(),
    child: const _StrengthListView(),
  );
}

class _StrengthListView extends StatefulWidget {
  const _StrengthListView();

  @override
  State<_StrengthListView> createState() => _StrengthListViewState();
}

class _StrengthListViewState extends State<_StrengthListView> {
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<StrengthListCubit>().setLanguage(
      Localizations.localeOf(context).languageCode,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<StrengthListCubit>();
    return BlocBuilder<StrengthListCubit, StrengthListState>(
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text(l10n.strengthTitle)),
        body: switch (state.status) {
          StrengthListStatus.loading => const LoadingView(),
          StrengthListStatus.failure => ErrorView(
            message: l10n.strengthLoadFailed,
            retryLabel: l10n.retry,
            onRetry: cubit.retry,
          ),
          StrengthListStatus.ready when state.trainedCount == 0 => EmptyView(
            message: l10n.strengthEmpty,
          ),
          StrengthListStatus.ready => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: TextField(
                  controller: _search,
                  onChanged: cubit.setQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: l10n.librarySearch,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: state.query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .deleteButtonTooltip,
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              cubit.setQuery('');
                            },
                          ),
                  ),
                ),
              ),
              Expanded(
                child: state.items.isEmpty
                    ? EmptyView(message: l10n.strengthNoResults)
                    : ListView.builder(
                        itemCount: state.items.length,
                        itemBuilder: (context, index) =>
                            _ExerciseTile(state.items[index]),
                      ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile(this.item);
  final StrengthItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final name =
        item.exercise?.localized(context).name ??
        (item.removed ? l10n.strengthRemovedExercise : '');
    return ListTile(
      title: Text(name),
      subtitle: Text(
        l10n.strengthLastDone(dates.formatMediumDate(item.lastTrained)),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(Routes.strengthExercise(item.exerciseId)),
    );
  }
}
