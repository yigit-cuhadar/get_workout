import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/body_entry.dart';
import '../domain/body_validation.dart';
import 'body_entry_page.dart';
import 'body_input.dart';
import 'body_text.dart';
import 'weight_form_cubit.dart';

/// Logs a weight.
class WeightNewPage extends StatelessWidget {
  const WeightNewPage({super.key});

  @override
  Widget build(BuildContext context) => const _WeightForm(entry: null);
}

/// The weight of a stored entry, edited in place.
class WeightEditPage extends StatelessWidget {
  const WeightEditPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => StoredEntry(
    id: id,
    title: AppLocalizations.of(context).bodyEditWeight,
    builder: (entry) => _WeightForm(entry: entry),
  );
}

class _WeightForm extends StatelessWidget {
  const _WeightForm({required this.entry});

  final BodyEntry? entry;

  @override
  Widget build(BuildContext context) {
    final unit = context.read<SettingsCubit>().state.settings.weightUnit;
    return BlocProvider(
      create: (_) => sl<WeightFormCubit>(param1: entry, param2: unit),
      child: _WeightFormView(unit: unit),
    );
  }
}

class _WeightFormView extends StatefulWidget {
  const _WeightFormView({required this.unit});

  final WeightUnit unit;

  @override
  State<_WeightFormView> createState() => _WeightFormViewState();
}

class _WeightFormViewState extends State<_WeightFormView> {
  late final WeightFormCubit _cubit = context.read<WeightFormCubit>();
  late final _weight = TextEditingController(text: _cubit.state.weight);

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<WeightFormCubit, WeightFormState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        switch (state.status) {
          case WeightFormStatus.saved || WeightFormStatus.closed:
            context.pop();
          case WeightFormStatus.saveFailed:
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.failure is NetworkFailure
                      ? l10n.errorNetwork
                      : l10n.bodySaveFailed,
                ),
              ),
            );
          default:
        }
      },
      builder: (context, state) {
        final saving = state.status == WeightFormStatus.saving;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _cubit.isEditing ? l10n.bodyEditWeight : l10n.bodyLogWeight,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              TextField(
                controller: _weight,
                autofocus: !_cubit.isEditing,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: decimalInput,
                decoration: InputDecoration(
                  labelText: l10n.bodyWeightLabel(
                    l10n.bodyWeightUnit(widget.unit),
                  ),
                  errorText: state.issues.contains(BodyIssue.weightOutOfRange)
                      ? l10n.bodyWeightRange(widget.unit)
                      : null,
                ),
                onChanged: _cubit.setWeight,
              ),
              const SizedBox(height: Gap.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.bodyDate),
                trailing: Text(
                  MaterialLocalizations.of(context)
                      .formatMediumDate(state.date),
                ),
                onTap: () => _pickDay(state.date),
              ),
              if (state.issues.contains(BodyIssue.dateInFuture))
                Text(
                  l10n.bodyErrorDateInFuture,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: Gap.lg),
              ForgeButton(
                label: l10n.bodySave,
                loading: saving,
                onPressed: saving ? null : _cubit.save,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDay(DateTime current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(now) ? now : current,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) _cubit.setDay(picked);
  }
}
