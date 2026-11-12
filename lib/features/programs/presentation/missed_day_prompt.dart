import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/calendar_date.dart';
import '../domain/program.dart';
import '../domain/program_schedule.dart';
import '../domain/program_usecases.dart';
import 'program_list_cubit.dart';
import 'program_text.dart';

/// The active program's missed next day and the three ways to resolve it,
/// through the [ProgramListCubit] above it. Shown on the Programs and the
/// Today tab, so a failed choice is reported by the prompt that made it.
class MissedDayPrompt extends StatelessWidget {
  const MissedDayPrompt({
    super.key,
    required this.program,
    required this.missed,
    required this.moveDate,
    required this.busy,
  });

  final Program program;
  final PlannedDay missed;
  final CalendarDate moveDate;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final index = missed.dayIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.programMissedTitle(
              l10n.dayName(program.days[index], index),
              l10n.planDate(missed.date),
            ),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: Gap.sm),
          ForgeButton(
            label: l10n.programMissedToday,
            loading: busy,
            onPressed: () => _resolve(context, MissedDayChoice.doToday),
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _resolve(
                          context,
                          MissedDayChoice.moveToNextWeekday,
                        ),
                  child: Text(
                    l10n.programMissedMove(l10n.weekdayLong(moveDate.weekday)),
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _resolve(context, MissedDayChoice.skip),
                  child: Text(l10n.programMissedSkip),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(BuildContext context, MissedDayChoice choice) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<ProgramListCubit>();
    await cubit.resolveMissed(choice);
    final failure = cubit.state.resolveFailure;
    if (failure == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure is NetworkFailure
              ? l10n.errorNetwork
              : l10n.programMissedFailed,
        ),
      ),
    );
    cubit.resolveFailureShown();
  }
}
