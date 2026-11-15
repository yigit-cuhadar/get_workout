import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/widgets/muscle_heat.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../volume/presentation/volume_page.dart';
import '../../volume/presentation/volume_text.dart';
import '../domain/program_volume.dart';
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

class _Volume extends StatelessWidget {
  const _Volume({required this.name, required this.volume});

  final String name;
  final ProgramVolume volume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.md),
      children: [
        // In the place of the weekly volume page's week picker.
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            spacing: Gap.sm,
            children: [
              Expanded(
                child: Text(
                  l10n.programVolumePerWeek(name),
                  style: Theme.of(context).textTheme.titleMedium,
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
          // A muscle of a program opens nothing yet.
          onOpen: (_) {},
        ),
        const Padding(
          padding: EdgeInsets.all(Gap.md),
          child: MuscleHeatLegend(),
        ),
        VolumeMuscleList(muscles: volume.ranked),
      ],
    );
  }
}
