import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../features/exercises/domain/vocabulary.dart';
import 'admin_text.dart';

/// The widest an editor's form grows on a desktop screen.
const maxFormWidth = 960.0;

/// A titled card of fields.
class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            for (final child in children) ...[
              const SizedBox(height: Gap.md),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// Fields side by side, sharing the width.
class FormRow extends StatelessWidget {
  const FormRow(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const SizedBox(width: Gap.md),
          // The child's key, so a keyed field keeps its state when the
          // fields before it come and go.
          Expanded(key: child.key, child: child),
        ],
      ],
    );
  }
}

/// The problems of one field, under it.
class FieldProblems extends StatelessWidget {
  const FieldProblems(this.messages, {super.key});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    final style = TextStyle(color: Theme.of(context).colorScheme.error);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final message in messages) Text(message, style: style)],
      ),
    );
  }
}

/// Every problem of a form, above it.
class ProblemSummary extends StatelessWidget {
  const ProblemSummary({
    super.key,
    required this.title,
    required this.messages,
  });

  final String title;
  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: scheme.onErrorContainer),
            ),
            for (final message in messages)
              Text(message, style: TextStyle(color: scheme.onErrorContainer)),
          ],
        ),
      ),
    );
  }
}

class TextInput extends StatelessWidget {
  const TextInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.problems = const [],
    this.enabled = true,
    this.multiline = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final List<String> problems;
  final bool enabled;

  /// Grows with the text instead of scrolling it on one line.
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: value,
          enabled: enabled,
          maxLines: multiline ? null : 1,
          decoration: InputDecoration(labelText: label),
          onChanged: onChanged,
        ),
        FieldProblems(problems),
      ],
    );
  }
}

/// A whole number; anything else reads as unset, which the rules report.
class NumberInput extends StatelessWidget {
  const NumberInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.problems = const [],
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: value?.toString() ?? '',
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (text) => onChanged(int.tryParse(text)),
        ),
        FieldProblems(problems),
      ],
    );
  }
}

class CodePicker<T extends Coded> extends StatelessWidget {
  const CodePicker({
    super.key,
    required this.label,
    required this.values,
    required this.value,
    required this.onChanged,
    this.optional = false,
    this.problems = const [],
  });

  final String label;
  final List<T> values;
  final T? value;
  final ValueChanged<T?> onChanged;
  final bool optional;
  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<T?>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [
            if (optional || value == null)
              DropdownMenuItem(child: Text(optional ? 'None' : 'Choose')),
            for (final value in values)
              DropdownMenuItem(value: value, child: Text(codeLabel(value))),
          ],
          onChanged: onChanged,
        ),
        FieldProblems(problems),
      ],
    );
  }
}

/// A dialog that picks one of [choices] (exercise ids) by name or id, and
/// pops it.
class ExercisePickerDialog extends StatefulWidget {
  const ExercisePickerDialog({
    super.key,
    required this.choices,
    required this.names,
  });

  final List<String> choices;
  final Map<String, String> names;

  @override
  State<ExercisePickerDialog> createState() => _ExercisePickerDialogState();
}

class _ExercisePickerDialogState extends State<ExercisePickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final matches = [
      for (final id in widget.choices)
        if ('$id ${widget.names[id]}'.toLowerCase().contains(needle)) id,
    ];
    return AlertDialog(
      title: const Text('Pick an exercise'),
      content: SizedBox(
        width: maxFormWidth / 2,
        height: MediaQuery.sizeOf(context).height / 2,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search name or id',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (query) => setState(() => _query = query),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final id = matches[index];
                  return ListTile(
                    title: Text(widget.names[id] ?? id),
                    subtitle: Text(id),
                    onTap: () => Navigator.pop(context, id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// The save buttons of an editor of content with a status: save as it is,
/// as draft, publish, retire. Publishing, and taking live content back,
/// ask first.
class StatusActions extends StatelessWidget {
  const StatusActions({
    super.key,
    required this.noun,
    required this.liveEffect,
    required this.hiddenEffect,
    required this.stored,
    required this.saving,
    required this.canSave,
    required this.onSave,
    required this.onSaveAs,
  });

  /// What is edited, e.g. "exercise".
  final String noun;

  /// What publishing does for users, as a sentence.
  final String liveEffect;

  /// What leaving live does for users, as a sentence.
  final String hiddenEffect;

  /// The stored status; null when nothing is stored yet.
  final ExerciseStatus? stored;
  final bool saving;

  /// Whether saving with a status (null: the current one) writes anything.
  final bool Function([ExerciseStatus? status]) canSave;
  final VoidCallback onSave;
  final ValueChanged<ExerciseStatus> onSaveAs;

  Future<void> _confirmThen(
    BuildContext context, {
    required String title,
    required String body,
    required String confirm,
    required VoidCallback action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    if (confirmed ?? false) action();
  }

  @override
  Widget build(BuildContext context) {
    final stored = this.stored;
    void publish() => _confirmThen(
      context,
      title: 'Publish this $noun?',
      body: liveEffect,
      confirm: 'Publish',
      action: () => onSaveAs(ExerciseStatus.live),
    );
    void retire() => _confirmThen(
      context,
      title: 'Retire this $noun?',
      body: '$hiddenEffect It is kept, and can be published again.',
      confirm: 'Retire',
      action: () => onSaveAs(ExerciseStatus.retired),
    );
    void toDraft() => stored == ExerciseStatus.live
        ? _confirmThen(
            context,
            title: 'Move this $noun back to draft?',
            body: hiddenEffect,
            confirm: 'Move to draft',
            action: () => onSaveAs(ExerciseStatus.draft),
          )
        : onSaveAs(ExerciseStatus.draft);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (saving) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            alignment: WrapAlignment.end,
            children: [
              if (stored != null)
                FilledButton(
                  onPressed: saving || !canSave() ? null : onSave,
                  child: Text('Save (stays ${codeLabel(stored)})'),
                ),
              if (stored != ExerciseStatus.draft)
                OutlinedButton(
                  onPressed: saving || !canSave(ExerciseStatus.draft)
                      ? null
                      : toDraft,
                  child: const Text('Save as draft'),
                ),
              if (stored != ExerciseStatus.live)
                OutlinedButton(
                  onPressed: saving || !canSave(ExerciseStatus.live)
                      ? null
                      : publish,
                  child: const Text('Publish'),
                ),
              if (stored != null && stored != ExerciseStatus.retired)
                OutlinedButton(
                  onPressed: saving || !canSave(ExerciseStatus.retired)
                      ? null
                      : retire,
                  child: const Text('Retire'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
