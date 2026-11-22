import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../shell/admin_form.dart';
import '../../shell/admin_text.dart';
import '../domain/generator_rules.dart';
import 'generator_rules_cubit.dart';
import 'generator_sizes.dart';

final _decimal = RegExp(r'^-?\d*\.?\d*');

/// A number typed in. Only text that reads as a number is written: while
/// it does not ("", "-", "1."), the text stays and the value is kept. Empty
/// text writes [blank] (shown as the hint) or, when [optional], removes the
/// value. The text follows [value] when that changes elsewhere (a discard,
/// a restore, a moved row).
class NumberBox extends StatefulWidget {
  const NumberBox({
    super.key,
    required this.value,
    required this.onChanged,
    this.decimal = false,
    this.label,
    this.blank,
    this.optional = false,
    this.width = GeneratorSizes.number,
  });

  final num? value;
  final ValueChanged<num?> onChanged;

  /// Takes decimals and negative numbers, as scores do.
  final bool decimal;
  final String? label;
  final num? blank;
  final bool optional;
  final double? width;

  @override
  State<NumberBox> createState() => _NumberBoxState();
}

class _NumberBoxState extends State<NumberBox> {
  late final _text = TextEditingController(text: _format(widget.value));

  String _format(num? value) =>
      value == null || value == widget.blank ? '' : '$value';

  num? _parse(String text) =>
      widget.decimal ? num.tryParse(text) : int.tryParse(text);

  void _changed(String text) {
    if (_parse(text) case final number?) {
      widget.onChanged(number);
    } else if (text.isEmpty && (widget.blank != null || widget.optional)) {
      widget.onChanged(widget.blank);
    }
  }

  @override
  void didUpdateWidget(NumberBox old) {
    super.didUpdateWidget(old);
    final value = widget.value ?? widget.blank;
    if (widget.value != old.value &&
        (_parse(_text.text) ?? (_text.text.isEmpty ? widget.blank : null)) !=
            value) {
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
      onChanged: _changed,
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
    this.optional = false,
    this.width = GeneratorSizes.number,
  });

  final RulesPath path;
  final String? label;
  final bool decimal;
  final num? blank;

  /// Empty text removes the value.
  final bool optional;
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
        optional: optional,
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
      width: GeneratorSizes.rangeEnd,
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

/// The codes at [path] of the draft as chips, in vocabulary order. The
/// stored order is kept: a ticked code goes at the end, an unticked one
/// leaves its place. With [every], no code selected means every one (the
/// field is absent), offered as its own first chip.
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
    final stored = [
      if (value is List)
        for (final code in value) '$code',
    ];
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
                  selected: stored.contains(code.code),
                  onSelected: (on) => set([
                    for (final v in stored)
                      if (v != code.code) v,
                    if (on) code.code,
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
