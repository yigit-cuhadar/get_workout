import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../l10n/app_localizations.dart';

/// A page of a one-question-per-page flow (onboarding, the generator):
/// Back and a progress bar of [count] parts up to [step] on top, the
/// question as [body] (an [OnboardingQuestionBody]) and its action
/// ([actionLabel], Continue) full width at the bottom, with a spinner
/// while [loading].
class OnboardingQuestion extends StatelessWidget {
  const OnboardingQuestion({
    super.key,
    required this.step,
    required this.count,
    required this.onBack,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.loading = false,
  });

  /// The question on screen, from 0.
  final int step;
  final int count;

  /// Null leaves Back to the route, which pops.
  final VoidCallback? onBack;
  final Widget body;
  final String actionLabel;

  /// Null while the question waits for an answer.
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, Gap.sm, 14, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            SizedBox(
              height: ForgeTheme.tapMin,
              child: Row(
                spacing: Gap.sm,
                children: [
                  Transform.translate(
                    offset: const Offset(-10, 0),
                    child: _BackButton(
                      onPressed: onBack ?? () => Navigator.maybePop(context),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: Gap.sm),
                      child: StepProgress(count: count, current: step + 1),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
            ForgeButton(
              label: actionLabel,
              onPressed: onAction,
              loading: loading,
              size: ForgeButtonSize.large,
            ),
          ],
        ),
      ),
    ),
  );
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: AppLocalizations.of(context).onboardingQuestionBack,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox.square(
        dimension: ForgeTheme.tapMin,
        child: Center(
          child: ForgeIcon(
            ForgeIcons.chevronLeft,
            size: 22,
            color: ForgeStyle.of(context).colors.ink,
          ),
        ),
      ),
    ),
  );
}

/// A question: its [title] and the line under it ([info]) at the top, the
/// [answer] anchored to the bottom, near the thumb. With [scrolls], a
/// taller answer scrolls; without, it must fit (a ruler or a wheel, whose
/// drags a scrolling page would take).
class OnboardingQuestionBody extends StatelessWidget {
  const OnboardingQuestionBody({
    super.key,
    required this.title,
    required this.answer,
    this.info,
    this.scrolls = true,
  });

  final String title;
  final Widget answer;
  final String? info;
  final bool scrolls;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final info = this.info;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.sm, Gap.xs, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Text(
                title,
                style: text.headlineMedium!.copyWith(
                  fontSize: 24,
                  height: 30 / 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.48,
                ),
              ),
              if (info != null)
                Text(
                  info,
                  style: text.bodyMedium!.copyWith(
                    color: ForgeStyle.of(context).colors.inkMuted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Spacer(),
        answer,
      ],
    );
    if (!scrolls) return column;
    // Sits at the bottom of the page when shorter than it.
    return CustomScrollView(
      slivers: [SliverFillRemaining(hasScrollBody: false, child: column)],
    );
  }
}

/// One answer of [values] as Forge's stacked choice rows: each its
/// [title] and, when it has one, the line under it ([subtitle]). A value
/// not [enabled] is faded and takes no tap. Null may be one of them, e.g.
/// "none".
class OnboardingChoices<T> extends StatelessWidget {
  const OnboardingChoices({
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
  Widget build(BuildContext context) {
    final index = values.indexWhere((value) => value == selected);
    return ChoiceGrid.list(
      form: ChoiceListForm.stacked,
      options: [
        for (final value in values)
          ChoiceOption(
            label: title(value),
            hint: subtitle?.call(value),
            enabled: enabled?.call(value) ?? true,
          ),
      ],
      selected: index < 0 ? null : index,
      onSelected: (i) => onChanged(values[i]),
    );
  }
}
