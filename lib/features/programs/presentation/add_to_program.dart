import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../domain/program.dart';
import 'add_to_program_cubit.dart';
import 'program_text.dart';

/// Lets the user pick one of their programs and a day, and appends
/// [exercise] to it with [cubit]. Without programs it offers to create one.
Future<void> addToProgram(
  BuildContext context,
  Exercise exercise,
  AddToProgramCubit cubit,
) async {
  final l10n = AppLocalizations.of(context);
  var state = cubit.state;
  if (!state.ready) {
    try {
      state = await cubit.stream
          .firstWhere((s) => s.ready)
          .timeout(AddToProgramCubit.catalogueWait);
    } on Object {
      return;
    }
    if (!context.mounted) return;
  }
  if (state.programs.isEmpty) {
    final create = await showForgeDialog<bool>(
      context: context,
      builder: (context) => ForgeDialog(
        title: l10n.addToProgramNoneTitle,
        message: l10n.addToProgramNone,
        action: ForgeButton(
          label: l10n.addToProgramCreate,
          onPressed: () => Navigator.pop(context, true),
        ),
        cancel: ForgeButton(
          label: l10n.cancel,
          variant: ForgeButtonVariant.secondary,
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
    );
    if (create == true && context.mounted) {
      // In the Programs or Exercises tab the builder opens above this page
      // and returns to it, so the exercise can be added; elsewhere it opens
      // in the Programs tab, leaving this page to its own tab (or the
      // workout's bar).
      final returning = returningProgramNew(
        GoRouterState.of(context).matchedLocation,
      );
      if (returning != null) {
        unawaited(context.push(returning));
      } else {
        context.go(Routes.programNew);
      }
    }
    return;
  }
  final program = await _pick<Program>(
    context,
    title: l10n.addToProgramPick,
    options: [for (final p in state.programs) (p, p.name, true)],
  );
  if (program == null || !context.mounted) return;
  final day = await _pick<int>(
    context,
    title: l10n.addToProgramDayOf(program.name),
    options: [
      for (final (i, d) in program.days.indexed)
        (
          i,
          d.items.length >= ProgramLimits.maxItemsPerDay
              ? '${l10n.dayName(d, i)} · ${l10n.addToProgramDayFull}'
              : l10n.dayName(d, i),
          d.items.length < ProgramLimits.maxItemsPerDay,
        ),
    ],
  );
  if (day == null || !context.mounted) return;
  final name = exercise.localized(context).name;
  final dayName = '${program.name} · ${l10n.dayName(program.days[day], day)}';
  final added = await cubit.add(program, day, exercise);
  if (!context.mounted) return;
  showForgeSnackbar(
    context,
    message: added
        ? l10n.addToProgramDone(name, dayName)
        : l10n.addToProgramFailed,
    error: !added,
  );
}

/// A sheet of [options] (value, label, enabled) as rows, a full one
/// drawn off; null when dismissed.
Future<T?> _pick<T>(
  BuildContext context, {
  required String title,
  required List<(T, String, bool)> options,
}) => showForgeBottomSheet<T>(
  context: context,
  builder: (context) => ForgeBottomSheet(
    title: title,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (value, label, enabled) in options)
            ListRow(
              title: label,
              disabled: !enabled,
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    ),
  ),
);
