import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/body_entry.dart';
import 'body_list_cubit.dart';
import 'body_photo.dart';
import 'body_text.dart';

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
              message: l10n.bodyLoadFailed,
              retryLabel: l10n.retry,
              onRetry: context.read<BodyListCubit>().retry,
            ),
            BodyListStatus.ready => EmptyView(message: l10n.bodyNotFound),
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
    final weight = entry.weightKg;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          MaterialLocalizations.of(context).formatMediumDate(entry.date),
        ),
        actions: [
          IconButton(
            tooltip: l10n.bodyEdit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: _deleting
                ? null
                : () => context.go(
                    entry.isWeightOnly
                        ? Routes.bodyEntryWeight(entry.id)
                        : Routes.bodyEntryMeasure(entry.id),
                  ),
          ),
          IconButton(
            tooltip: l10n.bodyDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleting ? null : () => _delete(entry),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gap.md),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.bodyWeightTitle),
            trailing: Text(
              weight == null
                  ? l10n.bodyNoValue
                  : l10n.bodyWeight(weight, settings.weightUnit),
            ),
          ),
          for (final MapEntry(key: measurement, value: cm)
              in entry.measurements.entries.toList()
                ..sort((a, b) => a.key.index.compareTo(b.key.index)))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.measurementName(measurement)),
              trailing: Text(l10n.bodyLength(cm, settings.lengthUnit)),
            ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.bodyDeleteTitle),
        content: Text(
          entry.photos.isEmpty ? l10n.bodyDeleteBody : l10n.bodyDeletePhotos,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.bodyDelete),
          ),
        ],
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failure is NetworkFailure ? l10n.errorNetwork : l10n.bodyDeleteFailed,
        ),
      ),
    );
  }
}
