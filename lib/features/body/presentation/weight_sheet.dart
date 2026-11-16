import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/day_time.dart';
import '../../../core/widgets/sheet_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../../profile/presentation/profile_questions.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/body_entry.dart';
import '../domain/body_stats.dart';
import '../domain/body_validation.dart';
import 'body_list_cubit.dart';
import 'body_text.dart';
import 'weight_form_cubit.dart';

/// Opens the weight sheet over the page: a new log, its ruler at the last
/// weigh-in, else the profile weight; or [entry]'s weight and date.
Future<void> showWeightSheet(BuildContext context, {BodyEntry? entry}) {
  final unit = context.read<SettingsCubit>().state.settings.weightUnit;
  final WeightFormSetup setup = (
    initial: entry,
    startKg: startWeightKg(
      previous: previousWeighIn(sl<BodyListCubit>().state.entries),
      profileKg: context.read<ProfileCubit>().state.profile.weightKg,
    ),
  );
  return showForgeBottomSheet<void>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) => sl<WeightFormCubit>(param1: setup, param2: unit),
      child: WeightSheet(unit: unit),
    ),
  );
}

/// The ruler with the weight large above it, the day and time with Change,
/// and Save. A failed save says so over the sheet.
class WeightSheet extends StatefulWidget {
  const WeightSheet({super.key, required this.unit});

  final WeightUnit unit;

  /// The ruler's steps, in the user's unit.
  static const step = 0.1;

  @override
  State<WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends State<WeightSheet> {
  late final WeightFormCubit _cubit = context.read<WeightFormCubit>();
  final _snackbar = SheetSnackbar();

  @override
  void dispose() {
    _snackbar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ForgeStyle.of(context).colors;
    final unit = widget.unit;
    final range = rulerRange(
      BodyLimits.minWeightKg,
      BodyLimits.maxWeightKg,
      unit.fromKg,
      WeightSheet.step,
    );
    return BlocConsumer<WeightFormCubit, WeightFormState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        switch (state.status) {
          case WeightFormStatus.saved || WeightFormStatus.closed:
            Navigator.pop(context);
          case WeightFormStatus.saveFailed:
            _snackbar.show(
              context,
              state.failure is NetworkFailure
                  ? l10n.errorNetwork
                  : l10n.bodySaveFailed,
            );
          default:
        }
      },
      builder: (context, state) {
        final saving = state.status == WeightFormStatus.saving;
        return ForgeBottomSheet(
          title: _cubit.isEditing ? l10n.bodyEditWeight : l10n.bodyLogWeight,
          action: ForgeButton(
            label: l10n.bodySave,
            size: ForgeButtonSize.large,
            loading: saving,
            onPressed: saving ? null : _cubit.save,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.sm,
            children: [
              NumberPicker.ruler(
                label: l10n.bodyWeightTitle,
                unit: l10n.bodyWeightUnit(unit),
                min: range.min,
                max: range.max,
                step: WeightSheet.step,
                value: state.weight,
                onChanged: _cubit.setWeight,
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dayTimeText(context, state.date),
                      style: Theme.of(context).textTheme.bodyMedium!
                          .copyWith(color: colors.inkMuted),
                    ),
                  ),
                  ForgeButton(
                    label: l10n.bodyChangeDate,
                    variant: ForgeButtonVariant.text,
                    size: ForgeButtonSize.small,
                    onPressed: saving ? null : () => _pickDay(state.date),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDay(DateTime current) async {
    final picked = await pickPastDay(context, current);
    if (picked != null) _cubit.setDay(picked);
  }
}
