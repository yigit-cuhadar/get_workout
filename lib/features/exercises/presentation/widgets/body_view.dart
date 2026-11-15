import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/widgets/muscle_model.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/vocabulary.dart';
import '../body_model_cubit.dart';

/// Opens the exercise list for [muscle] above the page of [context], unless
/// a page already covers it: a second tap, or a slide ending, while the
/// list is coming in or open opens nothing more.
void openMuscleList(BuildContext context, Muscle muscle) {
  if (ModalRoute.isCurrentOf(context) ?? true) {
    context.push(Routes.exerciseListOf(muscle));
  }
}

/// The body model: tap a muscle, or press and slide across muscles, to open
/// the exercise list filtered to it.
class BodyView extends StatefulWidget {
  const BodyView({super.key});

  @override
  State<BodyView> createState() => _BodyViewState();
}

class _BodyViewState extends State<BodyView> {
  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
      child: BlocBuilder<BodyModelCubit, BodyModelState>(
        builder: (context, state) => switch (state) {
          BodyModelLoading() => const MuscleModel.loading(),
          BodyModelFailed() => MuscleModel.failed(
            message: l10n.muscleModelSearchStillWorks,
            onRetry: context.read<BodyModelCubit>().load,
          ),
          BodyModelReady(:final model) => MuscleModel(
            model: model,
            onOpen: (muscle) => openMuscleList(context, muscle),
            semanticLabel: l10n.libraryModelLabel,
            hint: l10n.muscleModelHint,
          ),
        },
      ),
    );
  }
}
