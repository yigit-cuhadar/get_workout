import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../shell/admin_form.dart';
import '../../shell/admin_text.dart';
import '../domain/generator_rules.dart';
import 'generator_rules_cubit.dart';

/// The width of a number in a table cell.
const numberWidth = 64.0;

final _decimal = RegExp(r'^-?\d*\.?\d*');

/// A number typed in. The text follows [value] when it changes from
/// elsewhere (a discard, a restore, a moved row) and is left alone while
/// it already reads as [value]; [blank] is what empty text counts as.
class NumberBox extends StatefulWidget {
  const NumberBox({
    super.key,
    required this.value,
    required this.onChanged,
    this.decimal = false,
    this.label,
    this.blank,
    this.width = numberWidth,
  });

  final num? value;
  final ValueChanged<num?> onChanged;

  /// Takes decimals and negative numbers, as scores do.
  final bool decimal;
  final String? label;
  final num? blank;
  final double? width;

  @override
  State<NumberBox> createState() => _NumberBoxState();
}

class _NumberBoxState extends State<NumberBox> {
  late final _text = TextEditingController(text: _format(widget.value));

  String _format(num? value) =>
      value == null || value == widget.blank ? '' : '$value';

  num? _parse(String text) =>
      (widget.decimal ? num.tryParse(text) : int.tryParse(text)) ??
      (text.isEmpty ? widget.blank : null);

  @override
  void didUpdateWidget(NumberBox old) {
    super.didUpdateWidget(old);
    if (_parse(_text.text) != (widget.value ?? widget.blank)) {
      _text.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    child: TextField(
      controller: _text,
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        hintText: widget.blank == null ? null : '${widget.blank}',
      ),
      keyboardType: TextInputType.numberWithOptions(
        decimal: widget.decimal,
        signed: widget.decimal,
      ),
      inputFormatters: [
        if (widget.decimal)
          FilteringTextInputFormatter.allow(_decimal)
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      onChanged: (text) => widget.onChanged(_parse(text)),
    ),
  );
}

/// A text typed in, following [value] like [NumberBox].
class TextBox extends StatefulWidget {
  const TextBox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.maxLength,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final int? maxLength;
  final bool enabled;

  @override
  State<TextBox> createState() => _TextBoxState();
}

class _TextBoxState extends State<TextBox> {
  late final _text = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(TextBox old) {
    super.didUpdateWidget(old);
    if (_text.text != widget.value) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    enabled: widget.enabled,
    maxLength: widget.maxLength,
    decoration: InputDecoration(
      isDense: true,
      labelText: widget.label,
      counterText: '',
    ),
    onChanged: widget.onChanged,
  );
}

/// "was 150" beside a changed field.
class WasText extends StatelessWidget {
  const WasText(this.was, {super.key});

  final String? was;

  @override
  Widget build(BuildContext context) {
    final was = this.was;
    if (was == null) return const SizedBox.shrink();
    return Text(
      'was $was',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: ForgeStyle.of(context).colors.inkMuted),
    );
  }
}

/// A field's input with its old value and its problems under it.
class _Field extends StatelessWidget {
  const _Field({required this.path, required this.child, this.exact = false});

  final RulesPath path;
  final Widget child;
  final bool exact;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GeneratorRulesCubit>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        WasText(state.wasAt(path)),
        FieldProblems(state.problemsAt(path, exact: exact)),
      ],
    );
  }
}

/// The number at [path] of the draft.
class RuleNumber extends StatelessWidget {
  const RuleNumber(
    this.path, {
    super.key,
    this.label,
    this.decimal = false,
    this.blank,
    this.width = numberWidth,
  });

  final RulesPath path;
  final String? label;
  final bool decimal;
  final num? blank;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final value = state.valueAt(path);
    return _Field(
      path: path,
      child: NumberBox(
        value: value is num ? value : null,
        label: label,
        decimal: decimal,
        blank: blank,
        width: width,
        onChanged: (number) => cubit.setValue(
          path,
          // A blank that the loaded rules leave absent stays absent.
          number == blank && !(state.rules?.has(path) ?? false) ? null : number,
        ),
      ),
    );
  }
}

/// The `[min, max]` at [path] of the draft.
class RuleRange extends StatelessWidget {
  const RuleRange(this.path, {super.key});

  final RulesPath path;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final value = context.watch<GeneratorRulesCubit>().state.valueAt(path);
    final range = value is List ? value : const [];
    Widget end(int i) => NumberBox(
      width: numberWidth * 0.75,
      value: switch (range.elementAtOrNull(i)) {
        final num n => n,
        _ => null,
      },
      onChanged: (number) => cubit.setValue([...path, i], number),
    );
    return _Field(
      path: path,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Gap.xs,
        children: [end(0), const Text('–'), end(1)],
      ),
    );
  }
}

/// The text at [path] of the draft; empty removes it when [optional].
class RuleText extends StatelessWidget {
  const RuleText(
    this.path, {
    super.key,
    this.label,
    this.maxLength,
    this.optional = false,
    this.enabled = true,
  });

  final RulesPath path;
  final String? label;
  final int? maxLength;
  final bool optional;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final value = context.watch<GeneratorRulesCubit>().state.valueAt(path);
    return _Field(
      path: path,
      exact: true,
      child: TextBox(
        value: value is String ? value : '',
        label: label,
        maxLength: maxLength,
        enabled: enabled,
        onChanged: (text) =>
            cubit.setValue(path, optional && text.isEmpty ? null : text),
      ),
    );
  }
}

/// The codes at [path] of the draft as chips, kept in vocabulary order.
/// With [every], no code selected means every one (the field is absent),
/// offered as its own first chip.
class RuleCodes<T extends Coded> extends StatelessWidget {
  const RuleCodes(
    this.path, {
    super.key,
    required this.values,
    this.label,
    this.every,
    this.emptyAbsent = false,
  });

  final RulesPath path;
  final List<T> values;
  final String? label;

  /// The label of the chip meaning "every value".
  final String? every;

  /// An empty selection removes the field.
  final bool emptyAbsent;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final value = context.watch<GeneratorRulesCubit>().state.valueAt(path);
    final selected = {if (value is List) ...value};
    final every = this.every;
    void set(List<String> codes) => cubit.setValue(
      path,
      codes.isEmpty && (emptyAbsent || every != null) ? null : codes,
    );
    return _Field(
      path: path,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label case final label?)
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: [
              if (every != null)
                FilterChip(
                  label: Text(every),
                  selected: value == null,
                  onSelected: (_) => set(const []),
                ),
              for (final code in values)
                FilterChip(
                  label: Text(codeLabel(code)),
                  selected: selected.contains(code.code),
                  onSelected: (on) => set([
                    for (final v in values)
                      if (v == code ? on : selected.contains(v.code)) v.code,
                  ]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A muted line explaining a field.
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: ForgeStyle.of(context).colors.inkMuted),
  );
}

/// A small table: a header row and rows of cells, each cell as wide as
/// its column needs.
class RulesTable extends StatelessWidget {
  const RulesTable({
    super.key,
    required this.header,
    required this.rows,
    this.footer,
  });

  final List<String> header;
  final List<List<Widget>> rows;
  final List<Widget>? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.labelMedium?.copyWith(
      color: ForgeStyle.of(context).colors.inkMuted,
    );
    final line = BorderSide(color: theme.dividerColor);
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: Gap.xs),
      child: child,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        border: TableBorder(horizontalInside: line),
        children: [
          TableRow(
            children: [
              for (final title in header) cell(Text(title, style: heading)),
            ],
          ),
          for (final row in [...rows, ?footer])
            TableRow(children: [for (final child in row) cell(child)]),
        ],
      ),
    );
  }
}
