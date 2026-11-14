import 'package:flutter/material.dart';
import 'package:get_workout/core/widgets/onboarding_question.dart';
import 'package:get_workout/features/profile/presentation/ruler_picker.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Choice question', type: OnboardingQuestion)
Widget choiceOnboardingQuestion(BuildContext context) => const _Goal();

@widgetbook.UseCase(name: 'Number question', type: OnboardingQuestion)
Widget numberOnboardingQuestion(BuildContext context) => const _Height();

class _Goal extends StatefulWidget {
  const _Goal();

  @override
  State<_Goal> createState() => _GoalState();
}

class _GoalState extends State<_Goal> {
  static const _goals = {
    'Build muscle': 'Bigger, fuller muscles',
    'Get stronger': 'Lift heavier on the big lifts',
    'Lose fat': 'Keep muscle while you cut',
    'Stay fit': 'Feel good, move well',
  };

  String? _goal = 'Build muscle';

  @override
  Widget build(BuildContext context) => OnboardingQuestion(
    step: context.knobs.int.slider(label: 'Step', initialValue: 0, max: 8),
    count: 9,
    onBack: () {},
    body: OnboardingQuestionBody(
      title: "What's your main goal?",
      info: 'We use it to suggest your first program.',
      answer: OnboardingChoices<String>(
        values: _goals.keys.toList(),
        selected: _goal,
        title: (goal) => goal,
        subtitle: (goal) => _goals[goal],
        onChanged: (goal) => setState(() => _goal = goal),
      ),
    ),
    actionLabel: 'Continue',
    onAction: _goal == null ? null : () {},
  );
}

class _Height extends StatefulWidget {
  const _Height();

  @override
  State<_Height> createState() => _HeightState();
}

class _HeightState extends State<_Height> {
  double _cm = 180;

  @override
  Widget build(BuildContext context) => OnboardingQuestion(
    step: 6,
    count: 9,
    onBack: () {},
    body: OnboardingQuestionBody(
      title: 'How tall are you?',
      info: 'Drag the ruler or tap the number to type it.',
      scrolls: false,
      answer: Column(
        children: [
          Text(
            '${_cm.round()} cm',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          RulerPicker(
            min: 100,
            max: 250,
            step: 1,
            value: _cm,
            onChanged: (cm) => setState(() => _cm = cm),
          ),
        ],
      ),
    ),
    actionLabel: 'Continue',
    onAction: () {},
  );
}
