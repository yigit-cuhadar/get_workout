import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/domain/catalogue_rules.dart' show formatSets;
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_day_section.dart';
import '../domain/generator_answers.dart';
import '../domain/program_generator.dart';
import '../../volume/presentation/volume_charts.dart';
import 'generator_preview_cubit.dart';
import 'generator_text.dart';

/// The program generated from [answers]: its weekly sets and days, made
/// again on Regenerate, stored on Save and then opened.
class GeneratorPreviewPage extends StatelessWidget {
  const GeneratorPreviewPage({super.key, required this.answers});

  final GeneratorAnswers answers;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<GeneratorPreviewCubit>(param1: answers),
    child: const _PreviewView(),
  );
}

class _PreviewView extends StatelessWidget {
  const _PreviewView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<GeneratorPreviewCubit>();
    return BlocConsumer<GeneratorPreviewCubit, GeneratorPreviewState>(
      listenWhen: (previous, current) =>
          previous.saveStatus != current.saveStatus,
      listener: (context, state) {
        switch (state.saveStatus) {
          case SaveStatus.saved:
            context.go(Routes.program(state.savedId!, created: true));
          case SaveStatus.failed:
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(switch (state.saveFailure) {
                  NetworkFailure() => l10n.errorNetwork,
                  AuthFailure() => l10n.generatorSaveSignedOut,
                  NotFoundFailure() => l10n.generatorSaveLibraryLoading,
                  ValidationFailure() => l10n.generatorSaveInvalid,
                  _ => l10n.programSaveFailed,
                }),
              ),
            );
            cubit.saveFailureShown();
          case SaveStatus.idle || SaveStatus.saving:
        }
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text(l10n.generatorPreviewTitle)),
        body: switch (state.status) {
          PreviewStatus.loading => const LoadingView(),
          PreviewStatus.libraryFailed => ErrorView(
            message: l10n.libraryLoadFailed,
            retryLabel: l10n.retry,
            onRetry: cubit.retry,
          ),
          PreviewStatus.impossible => EmptyView(
            message: l10n.generationIssueText(state.issue!),
            action: OutlinedButton(
              onPressed: () => context.pop(),
              child: Text(l10n.generatorChangeAnswers),
            ),
          ),
          PreviewStatus.ready => _Program(
            program: state.program!,
            answers: cubit.answers,
          ),
        },
        bottomNavigationBar: state.status == PreviewStatus.ready
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.generatorRegenerate),
                          onPressed: state.saveStatus == SaveStatus.idle
                              ? cubit.regenerate
                              : null,
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: ForgeButton(
                          label: l10n.generatorSave,
                          loading: state.saveStatus == SaveStatus.saving,
                          onPressed: () => cubit.save(
                            name: l10n.generatorProgramName(
                              l10n.splitName(state.program!.split),
                              cubit.answers.daysPerWeek,
                            ),
                            dayName: l10n.generatedDayName,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _Program extends StatelessWidget {
  const _Program({required this.program, required this.answers});

  final GeneratedProgram program;
  final GeneratorAnswers answers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Text(l10n.splitName(program.split), style: theme.textTheme.titleLarge),
        Text(
          l10n.generatorSummary(answers.daysPerWeek, answers.sessionMinutes),
        ),
        if (program.uncovered.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(
                Icons.warning_amber_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                l10n.generatorUncovered(l10n.muscleNames(program.uncovered)),
              ),
            ),
          ),
        ],
        const SizedBox(height: Gap.md),
        _WeeklySets(program),
        const SizedBox(height: Gap.md),
        _Days(program),
      ],
    );
  }
}

/// Each target muscle's weekly sets as a bar over the reference band, and
/// against its target for these answers.
class _WeeklySets extends StatelessWidget {
  const _WeeklySets(this.program);

  final GeneratedProgram program;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scale = volumeScale(program.weeklySets.values);
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              l10n.generatorWeeklySets,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Text(l10n.generatorWeeklySetsInfo),
          ),
          for (final MapEntry(key: muscle, value: target)
              in program.targets.entries)
            ListTile(
              title: Text(l10n.muscleName(muscle)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: VolumeBandBar(
                  sets: program.weeklySets[muscle] ?? 0,
                  scale: scale,
                ),
              ),
              trailing: Text(
                l10n.generatorSetsOfTarget(
                  formatSets(program.weeklySets[muscle] ?? 0),
                  target,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The days as cards that open to their exercises, the first one open; so
/// again for each program Regenerate makes.
class _Days extends StatefulWidget {
  const _Days(this.program);

  final GeneratedProgram program;

  @override
  State<_Days> createState() => _DaysState();
}

class _DaysState extends State<_Days> {
  var _open = {0};

  @override
  void didUpdateWidget(_Days oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.program != oldWidget.program) _open = {0};
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, day) in widget.program.days.indexed) ...[
          if (index > 0) const SizedBox(height: Gap.sm),
          ProgramDayCard(
            day: ProgramDay(name: l10n.generatedDayName(day), items: day.items),
            index: index,
            open: _open.contains(index),
            onToggle: () => setState(() {
              if (!_open.remove(index)) _open.add(index);
            }),
          ),
        ],
      ],
    );
  }
}
