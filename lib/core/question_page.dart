import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// A page of a one-question-per-page flow (onboarding, the generator):
/// Back, one progress segment per question and [progress] ("3 / 9") in the
/// app bar, the question as [body] and [action] fixed at the bottom.
class QuestionScaffold extends StatelessWidget {
  const QuestionScaffold({
    super.key,
    required this.step,
    required this.count,
    required this.progress,
    required this.onBack,
    required this.body,
    required this.action,
  });

  /// The question on screen, from 0.
  final int step;
  final int count;
  final String progress;

  /// Null leaves Back to the route, which pops.
  final VoidCallback? onBack;
  final Widget body;
  final Widget action;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: BackButton(onPressed: onBack),
      title: _Progress(step: step, count: count),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: Gap.md),
          child: Text(progress),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: body),
          Padding(padding: const EdgeInsets.all(Gap.md), child: action),
        ],
      ),
    ),
  );
}

/// One segment per question, those up to [step] filled.
class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.count});

  final int step;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) const SizedBox(width: Gap.xs),
        Expanded(child: LinearProgressIndicator(value: i <= step ? 1 : 0)),
      ],
    ],
  );
}

/// A question: [caption] and [title] at the top with [info] under them,
/// [answer] at the bottom, near the thumb. With [scrolls], a taller answer
/// scrolls the page; without, it must fit (a ruler or a wheel, whose drags
/// a scrolling page would take).
class QuestionLayout extends StatelessWidget {
  const QuestionLayout({
    super.key,
    required this.title,
    required this.answer,
    this.caption,
    this.info,
    this.scrolls = true,
  });

  final String title;
  final Widget answer;
  final String? caption;
  final String? info;
  final bool scrolls;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = this.caption;
    final info = this.info;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption != null) ...[
          Text(caption, style: theme.textTheme.labelLarge),
          const SizedBox(height: Gap.sm),
        ],
        Text(title, style: theme.textTheme.headlineSmall),
        if (info != null) ...[
          const SizedBox(height: Gap.sm),
          Text(info, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Gap.md),
        const Spacer(),
        answer,
      ],
    );
    const padding = EdgeInsets.all(Gap.md);
    if (!scrolls) return Padding(padding: padding, child: column);
    // Sits at the bottom of the page when shorter than it.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverFillRemaining(hasScrollBody: false, child: column),
        ),
      ],
    );
  }
}

/// One answer of [values], as a radio list. Null may be one of them, e.g.
/// "none".
class ChoiceAnswer<T> extends StatelessWidget {
  const ChoiceAnswer({
    super.key,
    required this.values,
    required this.selected,
    required this.title,
    required this.onChanged,
    this.subtitle,
    this.enabled,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) title;
  final String? Function(T value)? subtitle;
  final bool Function(T value)? enabled;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => RadioGroup<T>(
    groupValue: selected,
    // Nothing is toggleable, so a null value is the answer "none".
    onChanged: (value) => onChanged(value as T),
    child: Column(
      children: [
        for (final value in values)
          RadioListTile<T>(
            value: value,
            enabled: enabled?.call(value) ?? true,
            title: Text(title(value)),
            subtitle: switch (subtitle?.call(value)) {
              final text? => Text(text),
              null => null,
            },
          ),
      ],
    ),
  );
}
