import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/widgets/program_volume_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/body_model_cubit.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../domain/program.dart';
import '../domain/program_volume.dart';

/// A program's weekly sets as a [ProgramVolumeCard] once its exercises and
/// the body model are known, the card's loading and error forms before;
/// a tap opens the full list through [onOpen].
class ProgramVolumeSection extends StatefulWidget {
  const ProgramVolumeSection({
    super.key,
    required this.program,
    required this.onOpen,
  });

  final Program program;
  final VoidCallback onOpen;

  @override
  State<ProgramVolumeSection> createState() => _ProgramVolumeSectionState();
}

class _ProgramVolumeSectionState extends State<ProgramVolumeSection> {
  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final open = widget.onOpen;
    final catalogue = context.watch<ExerciseCatalogueCubit>();
    final model = context.watch<BodyModelCubit>();
    SectionCard failed(VoidCallback retry) => SectionCard.error(
      title: l10n.programVolumeTitle,
      onTap: open,
      message: l10n.programVolumeLoadFailed,
      retryLabel: l10n.retry,
      onRetry: retry,
    );
    return switch ((catalogue.state, model.state)) {
      (CatalogueFailed(), _) => failed(catalogue.retry),
      (_, BodyModelFailed()) => failed(model.load),
      (CatalogueReady(:final exercises), BodyModelReady(model: final body)) =>
        () {
          final volume = programVolume(widget.program, {
            for (final exercise in exercises) exercise.id: exercise,
          });
          return ProgramVolumeCard(
            model: body,
            sets: volume.sets,
            total: volume.total,
            onTap: open,
          );
        }(),
      _ => SectionCard.loading(title: l10n.programVolumeTitle, onTap: open),
    };
  }
}
