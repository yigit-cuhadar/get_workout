import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/number_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/cardio_session.dart';
import '../domain/cardio_type.dart';
import 'cardio_form_cubit.dart';
import 'cardio_list_cubit.dart';
import 'cardio_text.dart';

/// One session: its type and start, distance, time and pace (or speed) as
/// tiles, the other values it has as rows, Edit in the app bar and Delete
/// at the end. One read from the health store has neither and says where
/// to change it. Taken from the shared list, so it also works from a bare
/// link and follows edits.
class CardioSessionPage extends StatelessWidget {
  const CardioSessionPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocProvider.value(
      value: sl<CardioListCubit>(),
      child: BlocBuilder<CardioListCubit, CardioListState>(
        builder: (context, state) {
          final session = state.sessions
              .where((session) => session.id == id)
              .firstOrNull;
          if (session != null) return _Session(session);
          return Scaffold(
            appBar: ForgeAppBar(title: l10n.cardioTitle),
            body: switch (state.status) {
              CardioListStatus.loading => const _Loading(),
              CardioListStatus.failure => ErrorView(
                title: l10n.cardioLoadFailed,
                message: l10n.loadFailedDetail,
                retryLabel: l10n.retry,
                onRetry: context.read<CardioListCubit>().retry,
              ),
              CardioListStatus.ready => EmptyView(message: l10n.cardioNotFound),
            },
          );
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(Gap.md),
    children: const [
      SkeletonBar(widthFactor: 0.4, height: 20),
      SizedBox(height: Gap.sm),
      SkeletonBar(widthFactor: 0.55, height: 10),
      SizedBox(height: Gap.md),
      _Tiles([StatTile.compactLoading(), StatTile.compactLoading()]),
      SizedBox(height: Gap.md),
      ListRowCard(children: [ListRow.loading(), ListRow.loading(index: 1)]),
    ],
  );
}

class _Session extends StatelessWidget {
  const _Session(this.session);
  final CardioSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    final text = Theme.of(context).textTheme;
    final unit = context.select(
      (SettingsCubit cubit) => distanceUnitFor(cubit.state.settings.lengthUnit),
    );
    final type = l10n.typeName(session.type);
    final start = session.date;
    final distance = session.distanceKm;
    final calories = session.calories;
    final heartRate = session.avgHeartRate;
    final incline = session.incline;
    final note = session.note;
    final store = healthStoreName(context);
    final rows = [
      if (calories != null)
        ListRow(
          title: l10n.cardioCaloriesRow,
          value: l10n.cardioKcal(calories),
        ),
      if (heartRate != null)
        ListRow(
          title: l10n.cardioHeartRateRow,
          value: l10n.cardioBpm(heartRate),
        ),
      if (incline != null)
        ListRow(
          title: l10n.cardioInclineRow,
          value: l10n.cardioInclinePercent(formatDecimal(incline, 1)),
        ),
      if (note != null) ListRow(title: l10n.cardioNote, detail: note),
    ];
    return Scaffold(
      appBar: ForgeAppBar(
        title: type,
        actions: [
          if (!session.fromHealth)
            ForgeAppBarAction.text(
              label: l10n.cardioEdit,
              onPressed: () => _edit(context),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gap.md),
        children: [
          Semantics(header: true, child: Text(type, style: text.headlineSmall)),
          const SizedBox(height: Gap.xs),
          Text(
            '${l10n.planDate(CalendarDate.of(start))} · '
            '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(start))}',
            style: text.bodyMedium!.copyWith(color: style.colors.inkMuted),
          ),
          if (session.fromHealth) ...[
            const SizedBox(height: Gap.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ForgeTag(
                healthSourceName(context, session),
                kind: ForgeTagKind.source,
              ),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              l10n.cardioFromHealth(store),
              style: text.bodySmall!.copyWith(color: style.colors.inkMuted),
            ),
          ],
          const SizedBox(height: Gap.md),
          _Tiles([
            if (distance != null)
              StatTile.figure(
                figure: l10n.distanceText(distance, unit),
                caption: l10n.cardioStatDistance,
              ),
            StatTile.figure(
              figure: formatDuration(session.duration),
              caption: l10n.cardioStatTime,
            ),
            if (distance != null) ?_rate(l10n, unit),
          ]),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            ListRowCard(children: rows),
          ],
          if (!session.fromHealth) ...[
            const SizedBox(height: Gap.lg),
            SizedBox(
              width: double.infinity,
              child: ForgeButton(
                label: l10n.cardioDelete,
                variant: ForgeButtonVariant.danger,
                onPressed: () => _delete(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Pace for activities on foot, speed for cycling, by the type.
  Widget? _rate(AppLocalizations l10n, DistanceUnit unit) {
    switch (session.type.rate) {
      case CardioRate.pace:
        final pace = session.pace(unit);
        if (pace == null) return null;
        return StatTile.figure(
          figure: formatPace(pace),
          caption: switch (unit) {
            DistanceUnit.km => l10n.cardioPerKm,
            DistanceUnit.mile => l10n.cardioPerMi,
          },
        );
      case CardioRate.speed:
        final speed = session.speed(unit);
        if (speed == null) return null;
        return StatTile.figure(
          figure: formatDecimal(speed, 1),
          caption: switch (unit) {
            DistanceUnit.km => l10n.cardioKmh,
            DistanceUnit.mile => l10n.cardioMph,
          },
        );
      case CardioRate.none:
        return null;
    }
  }

  void _edit(BuildContext context) =>
      unawaited(context.push(Routes.cardioSessionEdit(session.id!)));

  Future<void> _delete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showForgeDialog<bool>(
      context: context,
      builder: (dialog) => ForgeDialog(
        title: l10n.cardioDeleteTitle,
        message: l10n.cardioDeleteBody,
        action: ForgeButton(
          label: l10n.cardioDelete,
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
    if (confirmed != true || !context.mounted) return;
    final unit = distanceUnitFor(
      context.read<SettingsCubit>().state.settings.lengthUnit,
    );
    final cubit = sl<CardioFormCubit>(param1: session, param2: unit);
    await cubit.delete();
    final state = cubit.state;
    await cubit.close();
    if (!context.mounted) return;
    if (state.status == CardioFormStatus.deleted) {
      Navigator.pop(context);
    } else {
      showForgeSnackbar(
        context,
        message: state.failure is NetworkFailure
            ? l10n.errorNetwork
            : l10n.cardioDeleteFailed,
        error: true,
      );
    }
  }
}

/// The figures side by side, each taking an equal share.
class _Tiles extends StatelessWidget {
  const _Tiles(this.tiles);
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [for (final tile in tiles) Expanded(child: tile)],
    ),
  );
}
