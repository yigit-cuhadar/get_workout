import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/calendar_date.dart';
import '../domain/program_usecases.dart';
import 'program_list_cubit.dart';
import 'program_text.dart';

/// The three ways to resolve the active program's missed next day, under
/// its row in the Programs band, through the [ProgramListCubit] above it.
class MissedDayPrompt extends StatelessWidget {
  const MissedDayPrompt({
    super.key,
    required this.moveDate,
    required this.busy,
  });

  final CalendarDate moveDate;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm + Gap.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          ForgeButton(
            label: l10n.programMissedToday,
            loading: busy,
            onPressed: () => resolveMissedDay(context, MissedDayChoice.doToday),
          ),
          Row(
            spacing: Gap.sm,
            children: [
              Expanded(
                child: ForgeButton(
                  label: l10n.programMissedMove(
                    l10n.weekdayLong(moveDate.weekday),
                  ),
                  variant: ForgeButtonVariant.secondary,
                  onPressed: busy
                      ? null
                      : () => resolveMissedDay(
                          context,
                          MissedDayChoice.moveToNextWeekday,
                        ),
                ),
              ),
              Expanded(
                child: ForgeButton(
                  label: l10n.programMissedSkip,
                  variant: ForgeButtonVariant.secondary,
                  onPressed: busy
                      ? null
                      : () => resolveMissedDay(context, MissedDayChoice.skip),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Resolves the active program's missed day with [choice] through the
/// [ProgramListCubit] above [context]; a failure is reported here, by the
/// prompt that made the choice.
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
