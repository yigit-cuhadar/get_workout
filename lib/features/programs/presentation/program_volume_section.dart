import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/widgets/program_volume_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../domain/program.dart';
import '../domain/program_volume.dart';

/// A program's weekly sets as a [ProgramVolumeCard] once its exercises are
/// known, the card's loading and error forms before; a tap opens the full
/// list through [onOpen].
class ProgramVolumeSection extends StatelessWidget {
  const ProgramVolumeSection({
    super.key,
    required this.program,
    required this.onOpen,
  });

  final Program program;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final open = onOpen;
    final catalogue = context.watch<ExerciseCatalogueCubit>();
    SectionCard failed(VoidCallback retry) => SectionCard.error(
      title: l10n.programVolumeTitle,
      onTap: open,
      message: l10n.programVolumeLoadFailed,
      retryLabel: l10n.retry,
      onRetry: retry,
    );
    return switch (catalogue.state) {
      CatalogueFailed() => failed(catalogue.retry),
      CatalogueReady(:final exercises) => () {
        final volume = programVolume(program, {
          for (final exercise in exercises) exercise.id: exercise,
        });
        return ProgramVolumeCard(
          sets: volume.sets,
          total: volume.total,
          onTap: open,
        );
      }(),
      _ => SectionCard.loading(title: l10n.programVolumeTitle, onTap: open),
    };
  }
}
