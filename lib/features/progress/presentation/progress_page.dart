import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../body/domain/measurement_summary.dart';
import '../../body/presentation/body_list_cubit.dart';

/// The Progress tab: one row per kind of progress.
class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabProgress)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: Text(l10n.progressCalendar),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.calendar),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.progressHistory),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.calendar),
          ),
          ListTile(
            leading: const Icon(Icons.accessibility_new),
            title: Text(l10n.progressVolume),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.volume),
          ),
          ListTile(
            leading: const Icon(Icons.trending_up),
            title: Text(l10n.progressStrength),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.strength),
          ),
          ListTile(
            leading: const Icon(Icons.directions_run),
            title: Text(l10n.progressCardio),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.cardio),
          ),
          ListTile(
            leading: const Icon(Icons.directions_walk),
            title: Text(l10n.progressSteps),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.steps),
          ),
          ListTile(
            leading: const Icon(Icons.monitor_weight_outlined),
            title: Text(l10n.progressBody),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.body),
          ),
          const _CompareTile(),
        ],
      ),
    );
  }
}

/// Opens the newest measurement day compared with the previous one; off,
/// saying why, until there are two.
class _CompareTile extends StatelessWidget {
  const _CompareTile();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocProvider.value(
      value: sl<BodyListCubit>(),
      child: BlocSelector<BodyListCubit, BodyListState, (bool, String?)>(
        selector: (state) => (
          state.status == BodyListStatus.ready,
          newestComparable(state.entries)?.id,
        ),
        builder: (context, selected) {
          final (ready, id) = selected;
          return ListTile(
            leading: const Icon(Icons.compare),
            title: Text(l10n.progressCompare),
            subtitle: ready && id == null
                ? Text(l10n.progressCompareNeedsTwo)
                : null,
            trailing: const Icon(Icons.chevron_right),
            enabled: id != null,
            onTap: id == null
                ? null
                : () => context.go(Routes.bodyEntryCompare(id)),
          );
        },
      ),
    );
  }
}
