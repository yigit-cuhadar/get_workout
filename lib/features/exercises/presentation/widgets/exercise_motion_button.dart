import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/exercise.dart';
import '../exercise_catalogue_cubit.dart';
import '../exercise_motion_cubit.dart';
import '../vocabulary_labels.dart';
import 'exercise_motion_view.dart';

/// A round play button for exercise [exerciseId] when it has an animation,
/// and nothing otherwise. It opens a sheet over the screen with the correct
/// form playing, the exercise's cues, and a way to its detail page at
/// [detailRoute].
class ExerciseMotionButton extends StatelessWidget {
  const ExerciseMotionButton({
    super.key,
    required this.exerciseId,
    required this.detailRoute,
  });

  final String exerciseId;
  final String detailRoute;

  static const double _stageHeight = 280;

  @override
  Widget build(BuildContext context) {
    final exercise = context.select(
      (ExerciseCatalogueCubit cubit) => switch (cubit.state) {
        CatalogueReady(:final exercises) =>
          exercises.where((e) => e.id == exerciseId).firstOrNull,
        _ => null,
      },
    );
    if (exercise == null || exercise.isCustom) return const SizedBox.shrink();
    return BlocProvider(
      create: (_) => sl<ExerciseMotionCubit>(param1: exerciseId)..load(),
      child: BlocBuilder<ExerciseMotionCubit, ExerciseMotionState>(
        buildWhen: (before, after) =>
            (before is MotionReady) != (after is MotionReady),
        builder: (context, state) => state is MotionReady
            ? ForgeIconButton(
                icon: ForgeIcons.playArrow,
                label: AppLocalizations.of(context).motionWatch,
                variant: ForgeIconButtonVariant.ink,
                fill: ForgeIconButtonFill.sunken,
                onPressed: () => _show(context, exercise),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _show(BuildContext context, Exercise exercise) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ExerciseMotionCubit>();
    final text = exercise.localized(context);
    return showForgeBottomSheet<void>(
      context: context,
      builder: (sheet) => BlocProvider.value(
        value: cubit,
        child: ForgeBottomSheet(
          title: text.name,
          headerAction: ForgeButton(
            label: l10n.motionFullDetails,
            variant: ForgeButtonVariant.text,
            onPressed: () {
              Navigator.pop(sheet);
              context.push(detailRoute);
            },
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.sm,
              children: [
                BlocBuilder<ExerciseMotionCubit, ExerciseMotionState>(
                  builder: (context, state) => state is MotionReady
                      ? ExerciseMotionView(
                          motion: state,
                          main: exercise.mainMuscles,
                          secondary: exercise.secondaryMuscles,
                          height: _stageHeight,
                        )
                      : const SizedBox(height: _stageHeight),
                ),
                if (text.cues.isNotEmpty) ...[
                  const SizedBox(height: Gap.sm),
                  Text(
                    l10n.detailCues,
                    style: Theme.of(sheet).textTheme.titleMedium,
                  ),
                  for (final cue in text.cues) Text(l10n.stepBullet(cue)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
