import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/max_length_formatter.dart';
import '../../../core/page_parts.dart';
import '../../../core/unsaved_changes.dart';
import '../../../core/widgets/check_sheet.dart';
import '../../../core/widgets/choice_sheet.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/custom_exercise.dart';
import '../domain/exercise.dart';
import '../domain/vocabulary.dart';
import 'custom_exercise_form_cubit.dart';
import 'exercise_catalogue_cubit.dart';
import 'vocabulary_labels.dart';

const _padding = EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md);

/// Between the form's parts.
const double _gap = 10;

/// [selected] in the order of [values].
List<T> _inOrder<T>(List<T> values, Set<T> selected) => [
  for (final value in values)
    if (selected.contains(value)) value,
];

/// Creates a custom exercise.
class CustomExerciseNewPage extends StatelessWidget {
  const CustomExerciseNewPage({super.key, this.name});

  /// The name it starts with, e.g. a search that found nothing.
  final String? name;

  @override
  Widget build(BuildContext context) => _CustomExerciseForm(switch (name) {
    final name? => CustomExercise(name: name),
    null => null,
  });
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
            appBar: ForgeAppBar(title: l10n.customEditTitle),
            body: switch (state) {
              CatalogueFailed() => ListView(
                padding: _padding,
                children: [
                  SurfaceCard(
                    child: ErrorView(
                      title: l10n.libraryLoadFailed,
                      message: l10n.loadFailedDetail,
                      retryLabel: l10n.retry,
                      onRetry: context.read<ExerciseCatalogueCubit>().retry,
                      compact: true,
                    ),
                  ),
                ],
              ),
              CatalogueReady() when state.knows(exerciseId) => EmptyView(
                title: l10n.detailNotFoundTitle,
                message: l10n.detailNotFound,
              ),
              // Still waiting for the user's custom exercises.
              CatalogueLoading() || CatalogueReady() => const _Loading(),
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
    return UnsavedChangesGuard(
      hasChanges: () => _cubit.hasChanges,
      confirmDiscard: _confirmDiscard,
      child: BlocConsumer<CustomExerciseFormCubit, CustomExerciseFormState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: (context, state) {
          switch (state.status) {
            // Saved, it returns the exercise's id, e.g. for the picker
            // to choose it.
            case CustomExerciseFormStatus.saved:
              context.pop(state.savedId);
            case CustomExerciseFormStatus.closed:
              context.pop();
            case CustomExerciseFormStatus.saveFailed:
              showForgeSnackbar(
                context,
                message: _failureText(l10n, state.failure),
                error: true,
              );
            default:
          }
        },
        builder: (context, state) {
          String? error(CustomExerciseIssue issue) =>
              state.issues.contains(issue) ? l10n.customIssueText(issue) : null;
          String? names<T>(List<T> values, String Function(T) labelOf) =>
              values.isEmpty ? null : values.map(labelOf).join(', ');
          final musclesError =
              error(CustomExerciseIssue.mainMusclesMissing) ??
              error(CustomExerciseIssue.musclesRepeated);
          final equipmentError = error(CustomExerciseIssue.equipmentInvalid);
          return PopScope(
            canPop: !_cubit.hasChanges,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              if (await UnsavedChangesGuard.ask(context) && context.mounted) {
                context.pop();
              }
            },
            child: Scaffold(
              appBar: ForgeAppBar(
                title: _cubit.isEditing
                    ? l10n.customEditTitle
                    : l10n.customNewTitle,
                // In the app bar, so the keyboard closing never moves it from
                // under the finger.
                actions: [
                  ForgeAppBarAction.text(
                    label: l10n.customSave,
                    onPressed: state.isSaving ? null : _cubit.save,
                  ),
                ],
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.isSaving)
                    Progress.indeterminate(label: l10n.workoutSaving),
                  Expanded(
                    child: ListView(
                      padding: _padding,
                      children: [
                        ForgeTextField(
                          label: l10n.customName,
                          hint: l10n.customNameHint,
                          controller: _name,
                          inputFormatters: [
                            maxLengthFormatter(
                              CustomExerciseLimits.maxNameLength,
                            ),
                          ],
                          errorText:
                              error(CustomExerciseIssue.nameMissing) ??
                              error(CustomExerciseIssue.nameTooLong),
                          onChanged: _cubit.setName,
                        ),
                        const SizedBox(height: _gap),
                        ListRowCard(
                          children: [
                            ListRow(
                              title: l10n.customMainMuscles,
                              value: names(
                                _inOrder(Muscle.values, state.mainMuscles),
                                l10n.muscleName,
                              ),
                              error: musclesError,
                              missing: musclesError != null,
                              end: ListRowEnd.chevron,
                              onTap: () => _pick(
                                title: l10n.customMainMuscles,
                                values: Muscle.values,
                                selected: state.mainMuscles,
                                labelOf: l10n.muscleName,
                                onSaved: _cubit.setMainMuscles,
                              ),
                            ),
                            ListRow(
                              title: l10n.customSecondaryMuscles,
                              value: names(
                                _inOrder(Muscle.values, state.secondaryMuscles),
                                l10n.muscleName,
                              ),
                              end: ListRowEnd.chevron,
                              onTap: () => _pick(
                                title: l10n.customSecondaryMuscles,
                                values: [
                                  for (final muscle in Muscle.values)
                                    if (!state.mainMuscles.contains(muscle))
                                      muscle,
                                ],
                                selected: state.secondaryMuscles,
                                labelOf: l10n.muscleName,
                                onSaved: _cubit.setSecondaryMuscles,
                              ),
                            ),
                            ListRow(
                              title: l10n.customEquipment,
                              value: names(
                                _inOrder(Equipment.values, state.equipment),
                                l10n.equipmentName,
                              ),
                              error: equipmentError,
                              missing: equipmentError != null,
                              end: ListRowEnd.chevron,
                              onTap: () => _pick(
                                title: l10n.customEquipment,
                                values: Equipment.values,
                                selected: state.equipment,
                                labelOf: l10n.equipmentName,
                                onSaved: _cubit.setEquipment,
                              ),
                            ),
                            ListRow(
                              title: l10n.customLoggingType,
                              value: l10n.loggingTypeName(state.loggingType),
                              end: ListRowEnd.chevron,
                              onTap: () async {
                                final type = await showChoiceSheet(
                                  context,
                                  title: l10n.customLoggingType,
                                  values: LoggingType.values,
                                  selected: state.loggingType,
                                  labelOf: l10n.loggingTypeName,
                                );
                                if (type != null) _cubit.setLoggingType(type);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: _gap),
                        ForgeTextField(
                          label: l10n.customNote,
                          controller: _note,
                          multiline: true,
                          inputFormatters: [
                            maxLengthFormatter(
                              CustomExerciseLimits.maxNoteLength,
                            ),
                          ],
                          errorText: error(CustomExerciseIssue.noteTooLong),
                          onChanged: _cubit.setNote,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Offers [values] in a check sheet; a save hands the ticked ones on.
  Future<void> _pick<T>({
    required String title,
    required List<T> values,
    required Set<T> selected,
    required String Function(T value) labelOf,
    required ValueChanged<Set<T>> onSaved,
  }) async {
    final picked = await showCheckSheet(
      context,
      title: title,
      values: values,
      selected: selected,
      labelOf: labelOf,
      saveLabel: AppLocalizations.of(context).customSave,
    );
    if (picked != null) onSaved(picked);
  }

  Future<bool> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context);
    final discard = await showForgeDialog<bool>(
      context: context,
      builder: (context) => ForgeDialog(
        title: l10n.programDiscardTitle,
        message: l10n.customDiscardBody,
        action: ForgeButton(
          label: l10n.programDiscard,
          variant: ForgeButtonVariant.danger,
          onPressed: () => Navigator.pop(context, true),
        ),
        cancel: ForgeButton(
          label: l10n.programKeepEditing,
          variant: ForgeButtonVariant.secondary,
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
    );
    return discard ?? false;
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

/// The form's shape in shimmering stand-ins: the name field, the four rows
/// and the note.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: _padding,
    children: [
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          SkeletonBar(widthFactor: 0.2, height: 10),
          SkeletonBar(
            widthFactor: 1,
            height: ForgeTheme.tapMin,
            radius: ForgeRadii.button,
          ),
        ],
      ),
      const SizedBox(height: _gap),
      ListRowCard(
        children: [for (var i = 0; i < 4; i++) ListRow.loading(index: i)],
      ),
      const SizedBox(height: _gap),
      const SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            SkeletonBar(widthFactor: 0.4, height: 14),
            SkeletonBar(widthFactor: 0.5, height: 10),
          ],
        ),
      ),
    ],
  );
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
