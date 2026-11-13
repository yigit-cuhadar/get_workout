import 'dart:async';

import 'package:flutter/material.dart';
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
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.addToProgramNone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.addToProgramCreate),
          ),
        ],
      ),
    );
    if (create == true && context.mounted) {
      // In Train the builder opens above this page and returns to it, so
      // the exercise can be added; elsewhere it opens in Train, leaving this
      // page to its own tab (or the workout's bar).
      if (isInTrain(GoRouterState.of(context).matchedLocation)) {
        unawaited(context.push(Routes.programNewReturning));
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
    title: l10n.addToProgramDay,
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
  final messenger = ScaffoldMessenger.of(context);
  final name = exercise.localized(context).name;
  final dayName = '${program.name} · ${l10n.dayName(program.days[day], day)}';
  final added = await cubit.add(program, day, exercise);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        added ? l10n.addToProgramDone(name, dayName) : l10n.addToProgramFailed,
      ),
    ),
  );
}

/// A sheet of [options] (value, label, enabled); null when dismissed.
Future<T?> _pick<T>(
  BuildContext context, {
  required String title,
  required List<(T, String, bool)> options,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final (value, label, enabled) in options)
          ListTile(
            enabled: enabled,
            title: Text(label),
            onTap: () => Navigator.pop(context, value),
          ),
      ],
    ),
  ),
);
