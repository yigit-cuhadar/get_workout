import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/day_time.dart';
import '../../../core/unsaved_changes.dart';
import '../../../core/widgets/choice_sheet.dart';
import '../../../l10n/app_localizations.dart';
import '../../calculators/presentation/calculator_input.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../workout/presentation/workout_editor_view.dart';
import '../domain/cardio_session.dart';
import '../domain/cardio_type.dart';
import '../domain/cardio_validation.dart';
import 'cardio_form_cubit.dart';
import 'cardio_list_cubit.dart';
import 'cardio_text.dart';

/// Logs a new session.
class CardioNewPage extends StatelessWidget {
  const CardioNewPage({super.key});

  @override
  Widget build(BuildContext context) => const _CardioForm(session: null);
}

/// A stored session, edited in place; it is deleted from its own page.
/// It is taken from the shared list, so it opens at once from the
/// session's page and also works from a bare link.
class CardioEditPage extends StatelessWidget {
  const CardioEditPage({super.key, required this.id});

  final String id;

  CardioSession? _find(CardioListState state) =>
      state.sessions.where((session) => session.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: sl<CardioListCubit>(),
      child: BlocBuilder<CardioListCubit, CardioListState>(
        // Once found, the form keeps its session; a delete removing it from
        // the list must not swap the form out while the page closes.
        buildWhen: (previous, _) => _find(previous) == null,
        builder: (context, state) {
          final session = _find(state);
          if (session != null) return _CardioForm(session: session);
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            appBar: AppBar(title: Text(l10n.cardioEditTitle)),
            body: switch (state.status) {
              CardioListStatus.loading => const LoadingView(),
              CardioListStatus.failure => ErrorView(
                title: l10n.cardioLoadFailed,
                message: l10n.loadFailedDetail,
                retryLabel: l10n.retry,
                onRetry: context.read<CardioListCubit>().retry,
              ),
              CardioListStatus.ready => EmptyView(message: l10n.cardioNotFound),
            },
          );
        },
      ),
    );
  }
}

class _CardioForm extends StatelessWidget {
  const _CardioForm({required this.session});

  final CardioSession? session;

  @override
  Widget build(BuildContext context) {
    final lengthUnit = context.read<SettingsCubit>().state.settings.lengthUnit;
    final unit = distanceUnitFor(lengthUnit);
    return BlocProvider(
      create: (_) => sl<CardioFormCubit>(param1: session, param2: unit),
      child: _CardioFormView(unit: unit),
    );
  }
}

class _CardioFormView extends StatefulWidget {
  const _CardioFormView({required this.unit});

  final DistanceUnit unit;

  @override
  State<_CardioFormView> createState() => _CardioFormViewState();
}

/// Each value a row that opens its picker (CL08), Save in the app bar,
/// faded until there is a duration (CL06), and the pace or speed under
/// the rows (CL09).
class _CardioFormViewState extends State<_CardioFormView> {
  late final CardioFormCubit _cubit = context.read<CardioFormCubit>();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<CardioFormCubit, CardioFormState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        switch (state.status) {
          case CardioFormStatus.saved || CardioFormStatus.closed:
            context.pop();
          case CardioFormStatus.saveFailed:
            showForgeSnackbar(
              context,
              message: state.failure is NetworkFailure
                  ? l10n.errorNetwork
                  : l10n.cardioSaveFailed,
              error: true,
            );
          default:
        }
      },
      builder: (context, state) {
        final rate = _rateLine(l10n, state);
        return UnsavedChangesGuard(
          hasChanges: () => _cubit.hasChanges,
          confirmDiscard: _confirmDiscard,
          child: Builder(
            builder: (context) => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) unawaited(_leave(context));
              },
              child: _page(context, l10n, state, rate),
            ),
          ),
        );
      },
    );
  }

  Widget _page(
    BuildContext context,
    AppLocalizations l10n,
    CardioFormState state,
    String? rate,
  ) {
    final type = state.type;
    final noValue = l10n.bodyNoValue;
    final missingDuration = state.duration <= Duration.zero;
    return Scaffold(
      appBar: ForgeAppBar(
        title: _cubit.isEditing ? l10n.cardioEditTitle : l10n.cardioLog,
        actions: [
          ForgeAppBarAction.text(
            label: l10n.cardioSave,
            onPressed: state.canSave ? _cubit.save : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gap.md),
        children: [
          ListRowCard(
            children: [
              ListRow(
                title: l10n.cardioType,
                value: l10n.typeName(type),
                end: ListRowEnd.chevron,
                onTap: () => _pickType(type),
              ),
              ListRow(
                title: l10n.cardioDateTime,
                value: dayTimeText(context, state.date),
                error: state.issues.contains(CardioIssue.dateInFuture)
                    ? l10n.cardioErrorDateInFuture
                    : null,
                dataValue: true,
                end: ListRowEnd.chevron,
                onTap: () => _pickDateTime(state.date),
              ),
              ListRow(
                title: l10n.cardioDuration,
                value: missingDuration
                    ? noValue
                    : formatDuration(state.duration),
                missing: missingDuration,
                error: missingDuration ? l10n.cardioErrorDuration : null,
                dataValue: true,
                end: ListRowEnd.chevron,
                onTap: () => _pickDuration(state.duration),
              ),
              if (type.distance)
                ListRow(
                  title: l10n.cardioDistanceRow,
                  value: switch (state.distance) {
                    final distance? => _distanceText(l10n, distance),
                    null => noValue,
                  },
                  dataValue: true,
                  end: ListRowEnd.chevron,
                  onTap: () => _pickNumber(
                    title: l10n.cardioDistanceRow,
                    label: l10n.cardioDistance(
                      l10n.distanceUnitLabel(widget.unit),
                    ),
                    field: _NumberField.distance(widget.unit),
                    error: l10n.cardioErrorDistance,
                    value: state.distance,
                    onPicked: _cubit.setDistance,
                  ),
                ),
              ListRow(
                title: l10n.cardioCaloriesRow,
                value: switch (state.calories) {
                  final kcal? => l10n.cardioKcal(kcal),
                  null => noValue,
                },
                dataValue: true,
                end: ListRowEnd.chevron,
                onTap: () => _pickNumber(
                  title: l10n.cardioCaloriesRow,
                  label: l10n.cardioCalories,
                  field: _NumberField.calories,
                  error: l10n.cardioErrorCalories,
                  value: state.calories?.toDouble(),
                  onPicked: (value) => _cubit.setCalories(value?.round()),
                ),
              ),
              ListRow(
                title: l10n.cardioHeartRateRow,
                value: switch (state.heartRate) {
                  final bpm? => l10n.cardioBpm(bpm),
                  null => noValue,
                },
                dataValue: true,
                end: ListRowEnd.chevron,
                onTap: () => _pickNumber(
                  title: l10n.cardioHeartRateRow,
                  label: l10n.cardioHeartRate,
                  field: _NumberField.heartRate,
                  error: l10n.cardioErrorHeartRate,
                  value: state.heartRate?.toDouble(),
                  onPicked: (value) => _cubit.setHeartRate(value?.round()),
                ),
              ),
              if (type.incline)
                ListRow(
                  title: l10n.cardioInclineRow,
                  value: switch (state.incline) {
                    final incline? => l10n.cardioInclinePercent(
                      formatDecimal(incline, 1),
                    ),
                    null => noValue,
                  },
                  dataValue: true,
                  end: ListRowEnd.chevron,
                  onTap: () => _pickNumber(
                    title: l10n.cardioInclineRow,
                    label: l10n.cardioIncline,
                    field: _NumberField.incline,
                    error: l10n.cardioErrorIncline,
                    value: state.incline,
                    onPicked: _cubit.setIncline,
                  ),
                ),
              ListRow(
                title: l10n.cardioNote,
                value: state.note.trim().isEmpty ? noValue : state.note,
                end: ListRowEnd.chevron,
                onTap: () => _editNote(state.note),
              ),
            ],
          ),
          if (rate != null) ...[
            const SizedBox(height: Gap.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              child: Text(
                rate,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: ForgeStyle.of(context).colors.inkMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Out of the form, after asking when something changed. [context] is
  /// below the [UnsavedChangesGuard].
  Future<void> _leave(BuildContext context) async {
    if (_cubit.hasChanges && !await UnsavedChangesGuard.ask(context)) return;
    if (context.mounted) context.pop();
  }

  Future<bool> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context);
    final discard = await showForgeDialog<bool>(
      context: context,
      builder: (dialog) => ForgeDialog(
        title: l10n.cardioDiscardTitle,
        action: ForgeButton(
          label: l10n.cardioDiscard,
          variant: ForgeButtonVariant.danger,
          onPressed: () => Navigator.pop(dialog, true),
        ),
        cancel: ForgeButton(
          label: l10n.cancel,
          variant: ForgeButtonVariant.secondary,
          onPressed: () => Navigator.pop(dialog, false),
        ),
      ),
    );
    return discard ?? false;
  }

  String _distanceText(AppLocalizations l10n, double value) {
    final text = formatDecimal(value, 2);
    return switch (widget.unit) {
      DistanceUnit.km => l10n.cardioDistanceKm(text),
      DistanceUnit.mile => l10n.cardioDistanceMi(text),
    };
  }

  /// "Pace 5:31 /km", or "Speed 22.4 km/h" for a type that shows speed.
  String? _rateLine(AppLocalizations l10n, CardioFormState state) {
    if (!state.type.distance) return null;
    final rate = l10n.rateText(_cubit.session, widget.unit);
    if (rate == null) return null;
    return state.type.rate == CardioRate.speed
        ? l10n.cardioSpeedLine(rate)
        : l10n.cardioPaceLine(rate);
  }

  Future<void> _pickType(CardioType current) async {
    final picked = await showChoiceSheet(
      context,
      title: AppLocalizations.of(context).cardioType,
      values: CardioType.values,
      selected: current,
      labelOf: AppLocalizations.of(context).typeName,
    );
    if (picked != null) _cubit.setType(picked);
  }

  /// The day, then the time on the Forge time wheel.
  Future<void> _pickDateTime(DateTime current) async {
    final day = await pickPastDay(context, current);
    if (day == null || !mounted) return;
    var date = DateTime(
      day.year,
      day.month,
      day.day,
      current.hour,
      current.minute,
    );
    _cubit.setDate(date);
    await showForgeTimeWheel(
      context: context,
      initial: TimeOfDay.fromDateTime(date),
      onChanged: (time) {
        date = DateTime(day.year, day.month, day.day, time.hour, time.minute);
        _cubit.setDate(date);
      },
    );
  }

  Future<void> _pickDuration(Duration current) {
    final l10n = AppLocalizations.of(context);
    return showForgeDurationWheel(
      context: context,
      wheel: ForgeDurationWheel.hoursMinutesSeconds(
        label: l10n.cardioDuration,
        initial: current,
        max: CardioLimits.maxDuration,
        hourUnit: l10n.cardioHours,
        minuteUnit: l10n.cardioMinutesShort,
        secondUnit: l10n.cardioSeconds,
        onChanged: _cubit.setDuration,
      ),
    );
  }

  /// A sheet to type [title]'s value in a field labelled [label] (B2):
  /// Clear while there is a value, and Save, which keeps the sheet open
  /// with [error] on a value outside [field]'s range; empty clears it.
  Future<void> _pickNumber({
    required String title,
    required String label,
    required _NumberField field,
    required String error,
    required double? value,
    required ValueChanged<double?> onPicked,
  }) async {
    final result = await showForgeBottomSheet<({double? value})>(
      context: context,
      builder: (_) => _NumberSheet(
        title: title,
        label: label,
        field: field,
        error: error,
        value: value,
      ),
    );
    if (result != null) onPicked(result.value);
  }

  Future<void> _editNote(String note) async {
    final l10n = AppLocalizations.of(context);
    var text = note;
    final saved = await showForgeBottomSheet<bool>(
      context: context,
      builder: (sheet) => ForgeBottomSheet(
        title: l10n.cardioNote,
        action: ForgeButton(
          label: l10n.cardioSave,
          size: ForgeButtonSize.large,
          onPressed: () => Navigator.pop(sheet, true),
        ),
        child: NoteField(
          initial: note,
          label: l10n.cardioNote,
          hint: l10n.cardioNoteHint,
          maxLength: CardioLimits.maxNoteLength,
          onChanged: (changed) => text = changed,
        ),
      ),
    );
    if (saved == true) _cubit.setNote(text);
  }
}

/// The range a number sheet accepts and how many decimals it takes.
class _NumberField {
  const _NumberField(this.min, this.max, {this.decimals = 0});

  _NumberField.distance(DistanceUnit unit)
    : min = unit.fromKm(CardioLimits.minDistanceKm),
      max = unit.fromKm(CardioLimits.maxDistanceKm),
      decimals = 2;

  final double min;
  final double max;
  final int decimals;

  static const calories = _NumberField(1, CardioLimits.maxCalories * 1.0);
  static const heartRate = _NumberField(
    CardioLimits.minHeartRate * 1.0,
    CardioLimits.maxHeartRate * 1.0,
  );
  static const incline = _NumberField(
    CardioLimits.minIncline,
    CardioLimits.maxIncline,
    decimals: 1,
  );
}

class _NumberSheet extends StatefulWidget {
  const _NumberSheet({
    required this.title,
    required this.label,
    required this.field,
    required this.error,
    required this.value,
  });

  final String title;
  final String label;
  final _NumberField field;
  final String error;
  final double? value;

  @override
  State<_NumberSheet> createState() => _NumberSheetState();
}

class _NumberSheetState extends State<_NumberSheet> {
  late final _controller = TextEditingController(
    text: switch (widget.value) {
      final value? => formatDecimal(value, widget.field.decimals),
      null => '',
    },
  );
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final field = widget.field;
    final read = readNumber(_controller.text);
    if (read == null) {
      Navigator.pop(context, (value: null));
      return;
    }
    // NaN fails both comparisons.
    if (!(read >= field.min - 1e-9 && read <= field.max + 1e-9) ||
        (field.decimals == 0 && read != read.roundToDouble())) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, (value: read));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signed = widget.field.min < 0;
    final decimal = widget.field.decimals > 0;
    return ForgeBottomSheet(
      title: widget.title,
      headerAction: widget.value == null
          ? null
          : ForgeButton(
              label: l10n.cardioClear,
              variant: ForgeButtonVariant.text,
              onPressed: () => Navigator.pop(context, (value: null)),
            ),
      action: ForgeButton(
        label: l10n.cardioSave,
        size: ForgeButtonSize.large,
        onPressed: _save,
      ),
      child: ForgeTextField(
        label: widget.label,
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(
          decimal: decimal,
          signed: signed,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp('[0-9${decimal ? '.,' : ''}${signed ? '-' : ''}]'),
          ),
          LengthLimitingTextInputFormatter(7),
        ],
        errorText: _invalid ? widget.error : null,
        textInputAction: TextInputAction.done,
        onChanged: (_) {
          if (_invalid) setState(() => _invalid = false);
        },
        onSubmitted: (_) => _save(),
      ),
    );
  }
}
