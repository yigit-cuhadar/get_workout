import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/max_length_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/custom_exercise.dart';
import '../domain/exercise.dart';
import '../domain/vocabulary.dart';
import 'custom_exercise_form_cubit.dart';
import 'exercise_catalogue_cubit.dart';
import 'vocabulary_labels.dart';
import 'widgets/choice_section.dart';

/// Creates a custom exercise.
class CustomExerciseNewPage extends StatelessWidget {
  const CustomExerciseNewPage({super.key});

  @override
  Widget build(BuildContext context) => const _CustomExerciseForm(null);
}

/// A stored custom exercise, edited in place. It is taken from the
/// catalogue, which holds the user's custom exercises, so it also works from
/// a bare link.
class CustomExerciseEditPage extends StatelessWidget {
  const CustomExerciseEditPage({super.key, required this.exerciseId});

  final String exerciseId;

  Exercise? _find(ExerciseCatalogueState state) => state is CatalogueReady
      ? state.exercises
            .where((e) => e.id == exerciseId && e.isCustom)
            .firstOrNull
      : null;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ExerciseCatalogueCubit, ExerciseCatalogueState>(
        // Once found, the form keeps its exercise; a save changing it in the
        // catalogue must not swap the form out while the page closes.
        buildWhen: (previous, _) => _find(previous) == null,
        builder: (context, state) {
          final exercise = _find(state);
          if (exercise != null) {
            return _CustomExerciseForm(CustomExercise.of(exercise));
          }
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            appBar: AppBar(title: Text(l10n.customEditTitle)),
            body: switch (state) {
              CatalogueFailed() => ErrorView(
                message: l10n.libraryLoadFailed,
                retryLabel: l10n.retry,
                onRetry: context.read<ExerciseCatalogueCubit>().retry,
              ),
              CatalogueReady() when state.knows(exerciseId) => EmptyView(
                message: l10n.detailNotFound,
              ),
              // Still waiting for the user's custom exercises.
              CatalogueLoading() || CatalogueReady() => const LoadingView(),
            },
          );
        },
      );
}

class _CustomExerciseForm extends StatelessWidget {
  const _CustomExerciseForm(this.exercise);

  final CustomExercise? exercise;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<CustomExerciseFormCubit>(param1: exercise),
    child: const _FormView(),
  );
}

class _FormView extends StatefulWidget {
  const _FormView();

  @override
  State<_FormView> createState() => _FormViewState();
}

class _FormViewState extends State<_FormView> {
  late final CustomExerciseFormCubit _cubit = context
      .read<CustomExerciseFormCubit>();
  late final _name = TextEditingController(text: _cubit.state.name);
  late final _note = TextEditingController(text: _cubit.state.note);

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<CustomExerciseFormCubit, CustomExerciseFormState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        switch (state.status) {
          case CustomExerciseFormStatus.saved ||
              CustomExerciseFormStatus.closed:
            context.pop();
          case CustomExerciseFormStatus.saveFailed:
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_failureText(l10n, state.failure))),
            );
          default:
        }
      },
      builder: (context, state) {
        String? error(CustomExerciseIssue issue) =>
            state.issues.contains(issue) ? l10n.customIssueText(issue) : null;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _cubit.isEditing ? l10n.customEditTitle : l10n.customNew,
            ),
            // In the app bar, so the keyboard closing never moves it from
            // under the finger.
            actions: [
              TextButton(
                onPressed: state.isSaving ? null : _cubit.save,
                child: Text(l10n.customSave),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: Gap.md),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [
                    maxLengthFormatter(CustomExerciseLimits.maxNameLength),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.customName,
                    errorText:
                        error(CustomExerciseIssue.nameMissing) ??
                        error(CustomExerciseIssue.nameTooLong),
                  ),
                  onChanged: _cubit.setName,
                ),
              ),
              const SizedBox(height: Gap.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: DropdownButtonFormField<LoggingType>(
                  initialValue: state.loggingType,
                  decoration: InputDecoration(
                    labelText: l10n.customLoggingType,
                  ),
                  items: [
                    for (final type in LoggingType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(l10n.loggingTypeName(type)),
                      ),
                  ],
                  onChanged: (type) => _cubit.setLoggingType(type!),
                ),
              ),
              ChoiceSection(
                title: l10n.customMainMuscles,
                values: Muscle.values,
                selected: state.mainMuscles,
                labelOf: l10n.muscleName,
                onToggle: _cubit.toggleMainMuscle,
                error:
                    error(CustomExerciseIssue.mainMusclesMissing) ??
                    error(CustomExerciseIssue.musclesRepeated),
              ),
              ChoiceSection(
                title: l10n.customSecondaryMuscles,
                values: [
                  for (final muscle in Muscle.values)
                    if (!state.mainMuscles.contains(muscle)) muscle,
                ],
                selected: state.secondaryMuscles,
                labelOf: l10n.muscleName,
                onToggle: _cubit.toggleSecondaryMuscle,
              ),
              ChoiceSection(
                title: l10n.customEquipment,
                values: Equipment.values,
                selected: state.equipment,
                labelOf: l10n.equipmentName,
                onToggle: _cubit.toggleEquipment,
                error: error(CustomExerciseIssue.equipmentInvalid),
              ),
              const SizedBox(height: Gap.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: TextField(
                  controller: _note,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [
                    maxLengthFormatter(CustomExerciseLimits.maxNoteLength),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.customNote,
                    errorText: error(CustomExerciseIssue.noteTooLong),
                  ),
                  onChanged: _cubit.setNote,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _failureText(AppLocalizations l10n, Failure? failure) =>
      switch (failure) {
        CustomExerciseLimits.limitReached => l10n.customLimitReached(
          CustomExerciseLimits.maxCount,
        ),
        NetworkFailure() => l10n.errorNetwork,
        _ => l10n.customSaveFailed,
      };
}

extension on AppLocalizations {
  String customIssueText(CustomExerciseIssue issue) => switch (issue) {
    CustomExerciseIssue.nameMissing => customErrorName,
    CustomExerciseIssue.nameTooLong => customErrorNameTooLong(
      CustomExerciseLimits.maxNameLength,
    ),
    CustomExerciseIssue.mainMusclesMissing => customErrorMainMuscles,
    CustomExerciseIssue.musclesRepeated => customErrorMusclesRepeated,
    CustomExerciseIssue.equipmentInvalid => customErrorEquipment,
    CustomExerciseIssue.noteTooLong => customErrorNote(
      CustomExerciseLimits.maxNoteLength,
    ),
  };
}
