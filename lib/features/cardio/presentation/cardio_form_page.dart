import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/day_time.dart';
import '../../../core/widgets/choice_sheet.dart';
import '../../../l10n/app_localizations.dart';
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
        final type = state.type;
        final noValue = l10n.bodyNoValue;
        final missingDuration = state.duration <= Duration.zero;
        final rate = _rateLine(l10n, state);
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
                        unit: l10n.distanceUnitLabel(widget.unit),
                        field: _NumberField.distance(widget.unit),
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
                      field: _NumberField.calories,
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
                      field: _NumberField.heartRate,
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
                        field: _NumberField.incline,
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
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: ForgeStyle.of(context).colors.inkMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
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

  /// A sheet with [field]'s picker, at [value] or the field's start, Save
  /// and, while there is a value, Clear.
  Future<void> _pickNumber({
    required String title,
    required _NumberField field,
    required double? value,
    required ValueChanged<double?> onPicked,
    String? unit,
  }) async {
    final l10n = AppLocalizations.of(context);
    var picked = value ?? field.start;
    final result = await showForgeBottomSheet<({double? value})>(
      context: context,
      builder: (sheet) => ForgeBottomSheet(
        title: title,
        headerAction: value == null
            ? null
            : ForgeButton(
                label: l10n.cardioClear,
                variant: ForgeButtonVariant.text,
                onPressed: () => Navigator.pop(sheet, (value: null)),
              ),
        action: ForgeButton(
          label: l10n.cardioSave,
          size: ForgeButtonSize.large,
          onPressed: () => Navigator.pop(sheet, (value: picked)),
        ),
        child: unit == null
            ? NumberPicker.wheel(
                label: title,
                min: field.min,
                max: field.max,
                step: field.step,
                value: picked,
                onChanged: (next) => picked = next,
              )
            : NumberPicker.ruler(
                label: title,
                unit: unit,
                min: field.min,
                max: field.max,
                step: field.step,
                value: picked,
                onChanged: (next) => picked = next,
              ),
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

/// The range a number sheet picks from, its step and where it starts
/// without a value.
class _NumberField {
  const _NumberField(this.min, this.max, this.step, this.start);

  _NumberField.distance(DistanceUnit unit)
    : min = 0.1,
      max = (unit.fromKm(CardioLimits.maxDistanceKm) * 10).floor() / 10,
      step = 0.1,
      start = 5;

  final double min;
  final double max;
  final double step;
  final double start;

  static const calories = _NumberField(
    1,
    CardioLimits.maxCalories * 1.0,
    1,
    300,
  );
  static const heartRate = _NumberField(
    CardioLimits.minHeartRate * 1.0,
    CardioLimits.maxHeartRate * 1.0,
    1,
    140,
  );
  static const incline = _NumberField(
    CardioLimits.minIncline,
    CardioLimits.maxIncline,
    0.5,
    0,
  );
}
