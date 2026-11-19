import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/program_usecases.dart';
import 'program_list_cubit.dart';

/// Resolves the active program's missed day with [choice] through the
/// [ProgramListCubit] above [context]; a failure is reported here, by the
/// card that made the choice.
Future<void> resolveMissedDay(
  BuildContext context,
  MissedDayChoice choice,
) async {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<ProgramListCubit>();
  await cubit.resolveMissed(choice);
  final failure = cubit.state.resolveFailure;
  if (failure == null) return;
  if (context.mounted) {
    showForgeSnackbar(
      context,
      message: failure is NetworkFailure
          ? l10n.errorNetwork
          : l10n.programMissedFailed,
      error: true,
    );
  }
  cubit.resolveFailureShown();
}
