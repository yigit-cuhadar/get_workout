import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../profile/presentation/profile_questions.dart';
import '../domain/catalogue_program.dart';
import 'catalogue_detail_cubit.dart';
import 'catalogue_text.dart';
import 'premium_prompt.dart';
import 'program_day_section.dart';

/// One ready-made program: its card, its days when the user may see them,
/// and copying it into the user's programs.
class CatalogueDetailPage extends StatelessWidget {
  const CatalogueDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => sl<CatalogueDetailCubit>(
      param1: id,
      param2: Localizations.localeOf(context).languageCode,
    ),
    child: _CatalogueDetailView(sl<PremiumPrompt>()),
  );
}

class _CatalogueDetailView extends StatelessWidget {
  const _CatalogueDetailView(this.premium);

  final PremiumPrompt premium;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<CatalogueDetailCubit>();
    return BlocConsumer<CatalogueDetailCubit, CatalogueDetailState>(
      listenWhen: (previous, current) =>
          previous.copyStatus != current.copyStatus,
      listener: (context, state) async {
        switch (state.copyStatus) {
          case CopyStatus.copied:
            cubit.copyHandled();
            context.go(Routes.program(state.copyId!, created: true));
          case CopyStatus.alreadyCopied:
            final copyId = state.copyId!;
            cubit.copyHandled();
            await _offerCopy(context, copyId);
          case CopyStatus.failed:
            cubit.copyHandled();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(switch (state.copyFailure) {
                  NetworkFailure() => l10n.errorNetwork,
                  ValidationFailure() => l10n.catalogueCopyInvalid,
                  _ => l10n.catalogueCopyFailed,
                }),
              ),
            );
          case CopyStatus.idle || CopyStatus.copying:
        }
      },
      builder: (context, state) {
        final program = state.program;
        if (program == null) {
          return Scaffold(
            appBar: AppBar(),
            body: switch (state.status) {
              CatalogueDetailStatus.notFound => EmptyView(
                message: l10n.catalogueNotFound,
              ),
              CatalogueDetailStatus.offline => ErrorView(
                message: l10n.catalogueOffline,
                retryLabel: l10n.retry,
                onRetry: cubit.retry,
              ),
              CatalogueDetailStatus.failure => ErrorView(
                message: l10n.catalogueLoadFailed,
                retryLabel: l10n.retry,
                onRetry: cubit.retry,
              ),
              _ => const LoadingView(),
            },
          );
        }
        return _Program(program: program, state: state, premium: premium);
      },
    );
  }

  /// The user already has a copy: opens it, or adds another.
  Future<void> _offerCopy(BuildContext context, String copyId) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<CatalogueDetailCubit>();
    final copyAgain = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.catalogueAlreadyTitle),
        content: Text(l10n.catalogueAlreadyBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.catalogueCopyAgain),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.catalogueOpenCopy),
          ),
        ],
      ),
    );
    if (!context.mounted || copyAgain == null) return;
    if (copyAgain) {
      await cubit.copy();
    } else {
      context.go(Routes.program(copyId));
    }
  }
}

class _Program extends StatelessWidget {
  const _Program({
    required this.program,
    required this.state,
    required this.premium,
  });

  final CatalogueProgram program;
  final CatalogueDetailState state;
  final PremiumPrompt premium;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<CatalogueDetailCubit>();
    final text = program.text(Localizations.localeOf(context).languageCode);
    final ready = state.status == CatalogueDetailStatus.ready;
    // Bodyweight is everyone's; listing it says nothing.
    final equipment = [
      for (final e in program.equipment ?? const <Equipment>[])
        if (e != Equipment.bodyweight) e,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(text.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Gap.xl),
        children: [
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(text.summary, style: theme.textTheme.bodyLarge),
                const SizedBox(height: Gap.sm),
                Text(l10n.catalogueFacts(program)),
                Text(l10n.presetName(program.equipmentProfile)),
                if (equipment.isNotEmpty)
                  Text(l10n.catalogueEquipment(l10n.equipmentNames(equipment))),
                if (program.minutes case final minutes?)
                  Text(l10n.sessionMinutesText(minutes)),
                const SizedBox(height: Gap.md),
                _Action(state, premium),
              ],
            ),
          ),
          if (ready)
            for (final (index, day) in state.days.indexed)
              ProgramDaySection(
                day: day,
                index: index,
                onExerciseTap: (exerciseId) => context.push(
                  Routes.catalogueExercise(program.id, exerciseId),
                ),
              ),
          if (state.status == CatalogueDetailStatus.loading)
            const Padding(
              padding: EdgeInsets.all(Gap.lg),
              child: LoadingView(),
            ),
          if (state.status
              case CatalogueDetailStatus.offline ||
                  CatalogueDetailStatus.failure)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: _Notice(
                message: state.status == CatalogueDetailStatus.offline
                    ? l10n.catalogueDetailOffline
                    : l10n.catalogueDetailFailed,
                onRetry: cubit.retry,
              ),
            ),
          if (state.status == CatalogueDetailStatus.notFound)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Text(l10n.catalogueNotFound),
            ),
        ],
      ),
    );
  }
}

/// Use the program, or, when it is locked, the premium call to action.
class _Action extends StatelessWidget {
  const _Action(this.state, this.premium);

  final CatalogueDetailState state;
  final PremiumPrompt premium;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<CatalogueDetailCubit>();
    return switch (state.status) {
      CatalogueDetailStatus.ready => switch (state.useStatus) {
        UseStatus.exercisesMissing => Text(l10n.catalogueExercisesMissing),
        UseStatus.exercisesFailed => _Notice(
          message: l10n.catalogueExercisesFailed,
          onRetry: cubit.retryExercises,
        ),
        UseStatus.waiting || UseStatus.ready => ForgeButton(
          label: l10n.catalogueUse,
          loading:
              state.useStatus == UseStatus.waiting ||
              state.copyStatus == CopyStatus.copying,
          onPressed: cubit.use,
        ),
      },
      CatalogueDetailStatus.locked => PremiumLock(
        message: l10n.catalogueLockedBody,
        prompt: premium,
      ),
      CatalogueDetailStatus.unlocking => _Notice(
        message: l10n.catalogueUnlocking,
        onRetry: cubit.retry,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// A message with a retry.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(message),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          onPressed: onRetry,
          child: Text(AppLocalizations.of(context).retry),
        ),
      ),
    ],
  );
}
