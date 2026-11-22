import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/day_time.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/body_entry.dart';
import '../domain/measurement_summary.dart';
import 'body_list_cubit.dart';
import 'body_photo.dart';
import 'body_text.dart';
import 'weight_sheet.dart';

/// Shows [builder] with the stored entry [id], taken from the shared list,
/// so it opens at once from the list and also works from a bare link.
class StoredEntry extends StatelessWidget {
  const StoredEntry({
    super.key,
    required this.id,
    required this.title,
    required this.builder,
  });

  final String id;

  /// Of the page while the entry is not there.
  final String title;
  final Widget Function(BodyEntry entry) builder;

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<BodyListCubit>(),
    child: BlocBuilder<BodyListCubit, BodyListState>(
      // Once found, the page keeps its entry; a delete removing it from
      // the list must not swap the page out while it closes.
      buildWhen: (previous, _) => previous.entry(id) == null,
      builder: (context, state) {
        if (state.entry(id) case final entry?) return builder(entry);
        final l10n = AppLocalizations.of(context);
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: switch (state.status) {
            BodyListStatus.loading => const LoadingView(),
            BodyListStatus.failure => ErrorView(
              title: l10n.bodyLoadFailed,
              message: l10n.loadFailedDetail,
              retryLabel: l10n.retry,
              onRetry: context.read<BodyListCubit>().retry,
            ),
            BodyListStatus.ready => EmptyView(
              title: l10n.bodyNotFoundTitle,
              message: l10n.bodyNotFound,
            ),
          },
        );
      },
    ),
  );
}

/// One entry: its weight, measurements and photos, with edit and delete.
class BodyEntryPage extends StatelessWidget {
  const BodyEntryPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => StoredEntry(
    id: id,
    title: AppLocalizations.of(context).bodyEntryTitle,
    builder: (entry) => _EntryView(entry),
  );
}

class _EntryView extends StatefulWidget {
  const _EntryView(this.entry);
  final BodyEntry entry;

  @override
  State<_EntryView> createState() => _EntryViewState();
}

class _EntryViewState extends State<_EntryView> {
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      context.read<BodyListCubit>().restore(widget.entry.photos.values),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    // The newest version of the entry, e.g. after an edit; the one the page
    // opened with once it is gone.
    final entry =
        context.select(
          (BodyListCubit cubit) => cubit.state.entry(widget.entry.id),
        ) ??
        widget.entry;
    final files = context.select(
      (BodyListCubit cubit) => cubit.state.photoFiles,
    );
    final bodyFat = context.select(
      (BodyListCubit cubit) => cubit.state.bodyFat[entry.id],
    );
    // A measurement day with an earlier one compares with it.
    final comparable = context.select(
      (BodyListCubit cubit) =>
          isMeasurementDay(entry) &&
          baselineCandidates(cubit.state.entries, entry).isNotEmpty,
    );
    final weight = entry.weightKg;
    String length(BodyMeasurement measurement) =>
        l10n.bodyLength(entry.measurements[measurement]!, settings.lengthUnit);
    return Scaffold(
      appBar: ForgeAppBar(
        title: MaterialLocalizations.of(context).formatMediumDate(entry.date),
        actions: [
          ForgeAppBarAction.icon(
            icon: ForgeIcons.edit,
            label: l10n.bodyEdit,
            onPressed: _deleting
                ? null
                : () => entry.isWeightOnly
                      ? showWeightSheet(context, entry: entry)
                      : context.go(Routes.bodyEntryMeasure(entry.id)),
          ),
          ForgeAppBarAction.icon(
            icon: ForgeIcons.delete,
            label: l10n.bodyDelete,
            onPressed: _deleting ? null : () => _delete(entry),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gap.md),
        children: [
          ListRowCard(
            children: [
              ListRow(
                title: l10n.bodyWeightTitle,
                value: weight == null
                    ? l10n.bodyNoValue
                    : l10n.bodyWeight(weight, settings.weightUnit),
                dataValue: true,
              ),
              if (entry.isWeightOnly)
                ListRow(
                  title: l10n.bodyDate,
                  value: dayTimeText(context, entry.date),
                  dataValue: true,
                ),
              if (bodyFat != null)
                ListRow(
                  title: l10n.bodyFatTitle,
                  value: l10n.bodyFat(bodyFat),
                  dataValue: true,
                ),
              for (final group in pairedMeasurements(
                entry.measurements.keys.toSet(),
              ))
                ListRow(
                  title: l10n.measurementGroupName(group),
                  value: switch (group) {
                    [final left, final right] => l10n.bodyPair(
                      length(left),
                      length(right),
                    ),
                    _ => length(group.single),
                  },
                  dataValue: true,
                ),
            ],
          ),
          if (comparable) ...[
            const SizedBox(height: Gap.md),
            ForgeButton(
              label: l10n.bodyCompare,
              leadingIcon: ForgeIcons.compare,
              variant: ForgeButtonVariant.secondary,
              onPressed: _deleting
                  ? null
                  : () => context.go(Routes.bodyEntryCompare(entry.id)),
            ),
          ],
          if (entry.photos.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            PhotoRows([
              for (final pose in PhotoPose.values)
                if (entry.photos[pose] case final path?)
                  BodyPhoto(
                    file: files[path],
                    label: l10n.poseName(pose),
                    missingText: l10n.bodyPhotoMissing,
                  ),
            ]),
          ],
        ],
      ),
    );
  }

  Future<void> _delete(BodyEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<BodyListCubit>();
    final confirmed = await showForgeDialog<bool>(
      context: context,
      builder: (dialog) => ForgeDialog(
        title: l10n.bodyDeleteTitle,
        message: entry.photos.isEmpty
            ? l10n.bodyDeleteBody
            : l10n.bodyDeletePhotos,
        action: ForgeButton(
          label: l10n.bodyDelete,
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
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final failure = await cubit.delete(entry);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (failure == null) {
      context.pop();
      return;
    }
    showForgeSnackbar(
      context,
      message: failure is NetworkFailure
          ? l10n.errorNetwork
          : l10n.bodyDeleteFailed,
      error: true,
    );
  }
}
