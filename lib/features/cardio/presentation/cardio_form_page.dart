import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_cubit.dart';
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

/// A stored session, edited in place. It is taken from the shared list, so
/// it opens at once from the list and also works from a bare link.
class CardioSessionPage extends StatelessWidget {
  const CardioSessionPage({super.key, required this.id});

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
                message: l10n.cardioLoadFailed,
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

class _CardioFormViewState extends State<_CardioFormView> {
  late final CardioFormCubit _cubit = context.read<CardioFormCubit>();
  late final _hours = _controller(_part(_cubit.state.duration.inHours));
  late final _minutes = _controller(
    _part(_cubit.state.duration.inMinutes % 60),
  );
  late final _seconds = _controller(
    _part(_cubit.state.duration.inSeconds % 60),
  );
  late final _distance = _controller(_cubit.state.distance);
  late final _calories = _controller(_cubit.state.calories);
  late final _heartRate = _controller(_cubit.state.heartRate);
  late final _incline = _controller(_cubit.state.incline);
  late final _note = _controller(_cubit.state.note);
  final _controllers = <TextEditingController>[];

  TextEditingController _controller(String text) {
    final controller = TextEditingController(text: text);
    _controllers.add(controller);
    return controller;
  }

  /// Empty when the session has no time in this part, so a new form starts
  /// with blank fields.
  String _part(int value) =>
      _cubit.state.duration == Duration.zero ? '' : '$value';

  void _durationChanged(String _) {
    int read(TextEditingController c) => int.tryParse(c.text) ?? 0;
    _cubit.setDuration(
      Duration(
        hours: read(_hours),
        minutes: read(_minutes),
        seconds: read(_seconds),
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<CardioFormCubit, CardioFormState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        switch (state.status) {
          case CardioFormStatus.saved || CardioFormStatus.deleted:
            context.pop();
          case CardioFormStatus.saveFailed || CardioFormStatus.deleteFailed:
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(_failureText(l10n, state))));
          default:
        }
      },
      builder: (context, state) {
        String? error(CardioIssue issue) =>
            state.issues.contains(issue) ? l10n.issueText(issue) : null;
        final durationError =
            error(CardioIssue.durationMissing) ??
            error(CardioIssue.durationTooLong);
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _cubit.isEditing ? l10n.cardioEditTitle : l10n.cardioLog,
            ),
            actions: [
              if (_cubit.isEditing)
                IconButton(
                  tooltip: l10n.cardioDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: state.isBusy ? null : () => _delete(l10n),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              DropdownButtonFormField<CardioType>(
                initialValue: state.type,
                decoration: InputDecoration(labelText: l10n.cardioType),
                items: [
                  for (final type in CardioType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(l10n.typeName(type)),
                    ),
                ],
                onChanged: (type) => _cubit.setType(type!),
              ),
              const SizedBox(height: Gap.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.cardioDate),
                trailing: Text(
                  MaterialLocalizations.of(context)
                      .formatMediumDate(state.date),
                ),
                onTap: () => _pickDate(state.date),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.cardioTime),
                trailing: Text(
                  TimeOfDay.fromDateTime(state.date).format(context),
                ),
                onTap: () => _pickTime(state.date),
              ),
              if (error(CardioIssue.dateInFuture) case final text?)
                _ErrorText(text),
              const SizedBox(height: Gap.sm),
              Text(l10n.cardioDuration),
              Row(
                children: [
                  for (final (controller, label) in [
                    (_hours, l10n.cardioHours),
                    (_minutes, l10n.cardioMinutesShort),
                    (_seconds, l10n.cardioSeconds),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                        child: TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(labelText: label),
                          onChanged: _durationChanged,
                        ),
                      ),
                    ),
                ],
              ),
              if (durationError != null) _ErrorText(durationError),
              if (state.type.distance)
                _NumberField(
                  controller: _distance,
                  label: l10n.cardioDistance(
                    l10n.distanceUnitLabel(widget.unit),
                  ),
                  error: error(CardioIssue.distanceOutOfRange),
                  decimal: true,
                  onChanged: _cubit.setDistance,
                ),
              _NumberField(
                controller: _calories,
                label: l10n.cardioCalories,
                error: error(CardioIssue.caloriesOutOfRange),
                onChanged: _cubit.setCalories,
              ),
              _NumberField(
                controller: _heartRate,
                label: l10n.cardioHeartRate,
                error: error(CardioIssue.heartRateOutOfRange),
                onChanged: _cubit.setHeartRate,
              ),
              if (state.type.incline)
                _NumberField(
                  controller: _incline,
                  label: l10n.cardioIncline,
                  error: error(CardioIssue.inclineOutOfRange),
                  decimal: true,
                  signed: true,
                  onChanged: _cubit.setIncline,
                ),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: _note,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.cardioNote),
                onChanged: _cubit.setNote,
              ),
              const SizedBox(height: Gap.lg),
              ForgeButton(
                label: l10n.cardioSave,
                loading: state.status == CardioFormStatus.saving,
                onPressed: state.isBusy ? null : _cubit.save,
              ),
            ],
          ),
        );
      },
    );
  }

  static String _failureText(AppLocalizations l10n, CardioFormState state) =>
      switch (state.failure) {
        NetworkFailure() => l10n.errorNetwork,
        _ when state.status == CardioFormStatus.deleteFailed =>
          l10n.cardioDeleteFailed,
        _ => l10n.cardioSaveFailed,
      };

  Future<void> _delete(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cardioDeleteTitle),
        content: Text(l10n.cardioDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.cardioDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _cubit.delete();
  }

  Future<void> _pickDate(DateTime current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(now) ? now : current,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked == null) return;
    _cubit.setDate(
      DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      ),
    );
  }

  Future<void> _pickTime(DateTime current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    _cubit.setDate(
      DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.error,
    required this.onChanged,
    this.decimal = false,
    this.signed = false,
  });

  final TextEditingController controller;
  final String label;
  final String? error;
  final ValueChanged<String> onChanged;
  final bool decimal;
  final bool signed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.sm),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimal,
        signed: signed,
      ),
      decoration: InputDecoration(labelText: label, errorText: error),
      onChanged: onChanged,
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}
