import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../volume/presentation/volume_page.dart';
import '../../volume/presentation/volume_text.dart';
import '../domain/program_volume.dart';
import 'catalogue_detail_cubit.dart';
import 'program_list_cubit.dart';

/// Program [id]'s weekly sets per muscle as the weekly volume page shows a
/// logged week: the body model and every muscle's sets, under the program's
/// name and total.
class ProgramVolumePage extends StatelessWidget {
  const ProgramVolumePage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocProvider.value(
      value: sl<ProgramListCubit>(),
      child: Scaffold(
        appBar: ForgeAppBar(title: l10n.programVolumePageTitle),
        body: BlocBuilder<ProgramListCubit, ProgramListState>(
          builder: (context, list) {
            final catalogue = context.watch<ExerciseCatalogueCubit>();
            final program = list.program(id);
            return switch ((list.status, catalogue.state)) {
              (ProgramListStatus.failure, _) => ErrorView(
                title: l10n.programsLoadFailedTitle,
                message: l10n.loadFailedDetail,
                retryLabel: l10n.retry,
                onRetry: context.read<ProgramListCubit>().retry,
              ),
              (ProgramListStatus.ready, _) when program == null => EmptyView(
                title: l10n.programNotFoundTitle,
                message: l10n.programNotFound,
              ),
              (_, CatalogueFailed()) => ErrorView(
                title: l10n.programVolumeLoadFailed,
                message: l10n.loadFailedDetail,
                retryLabel: l10n.retry,
                onRetry: catalogue.retry,
              ),
              (ProgramListStatus.ready, CatalogueReady(:final exercises)) =>
                _Volume(
                  name: program!.name,
                  volume: programVolume(program, {
                    for (final exercise in exercises) exercise.id: exercise,
                  }),
                ),
              _ => const LoadingView(),
            };
          },
        ),
      ),
    );
  }
}

/// A ready-made program's weekly sets per muscle, as [ProgramVolumePage]
/// shows one of the user's own: pushed above its page in the Programs tab.
class CatalogueVolumePage extends StatelessWidget {
  const CatalogueVolumePage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    return BlocProvider(
      create: (_) => sl<CatalogueDetailCubit>(param1: id, param2: language),
      child: Scaffold(
        appBar: ForgeAppBar(title: l10n.programVolumePageTitle),
        body: BlocBuilder<CatalogueDetailCubit, CatalogueDetailState>(
          builder: (context, state) {
            final catalogue = context.watch<ExerciseCatalogueCubit>();
            final program = state.program;
            return switch ((state.status, catalogue.state)) {
              (CatalogueDetailStatus.notFound, _) => EmptyView(
                message: l10n.catalogueNotFound,
              ),
              (
                CatalogueDetailStatus.offline || CatalogueDetailStatus.failure,
                _,
              ) =>
                ErrorView(
                  title: l10n.catalogueLoadFailedTitle,
                  message: l10n.loadFailedDetail,
                  retryLabel: l10n.retry,
                  onRetry: context.read<CatalogueDetailCubit>().retry,
                ),
              (_, CatalogueFailed()) => ErrorView(
                title: l10n.programVolumeLoadFailed,
                message: l10n.loadFailedDetail,
                retryLabel: l10n.retry,
                onRetry: catalogue.retry,
              ),
              (CatalogueDetailStatus.ready, CatalogueReady(:final exercises))
                  when program != null =>
                _Volume(
                  name: program.text(language).name,
                  volume: programVolume(program.copy(state.days, language), {
                    for (final exercise in exercises) exercise.id: exercise,
                  }),
                ),
              _ => const SingleChildScrollView(
                padding: EdgeInsets.all(Gap.md),
                child: LoadingView(),
              ),
            };
          },
        ),
      ),
    );
  }
}

class _Volume extends StatelessWidget {
  const _Volume({required this.name, required this.volume});

  final String name;
  final ProgramVolume volume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
      children: [
        // In the place of the weekly volume page's week picker.
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xs, 0, Gap.xs, 10),
          child: Row(
            spacing: Gap.sm,
            children: [
              Expanded(
                child: Text(
                  l10n.programVolumePerWeek(name),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                l10n.setsText(volume.total.toDouble()),
                style: style.data.copyWith(color: style.colors.inkMuted),
              ),
            ],
          ),
        ),
        VolumeModel(
          sets: volume.sets,
          semanticLabel: l10n.programVolumeModelLabel(name),
        ),
        const SizedBox(height: 10),
        VolumeMuscleList(muscles: volume.ranked, total: volume.total),
      ],
    );
  }
}
