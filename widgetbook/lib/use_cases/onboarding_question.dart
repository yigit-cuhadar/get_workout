import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/onboarding_question.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/presentation/profile_questions.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Choice question', type: OnboardingQuestion)
Widget choiceOnboardingQuestion(BuildContext context) => const _Goal();

@widgetbook.UseCase(name: 'Number question', type: OnboardingQuestion)
Widget numberOnboardingQuestion(BuildContext context) => const _Height();

@widgetbook.UseCase(name: 'With eyebrow', type: OnboardingQuestion)
Widget eyebrowOnboardingQuestion(BuildContext context) => OnboardingQuestion(
  step: 3,
  count: 9,
  onBack: () {},
  body: OnboardingQuestionBody(
    eyebrow: 'Generate a program',
    title: 'How long can a session be?',
    answer: OnboardingChoices<int>(
      values: const [30, 45, 60, 75, 90],
      selected: 60,
      title: (minutes) => '$minutes minutes',
      onChanged: (_) {},
    ),
  ),
  actionLabel: 'Continue',
  onAction: () {},
);

@widgetbook.UseCase(name: 'Recommended choice', type: OnboardingQuestion)
Widget recommendedOnboardingQuestion(BuildContext context) =>
    const _Recommended();

class _Recommended extends StatefulWidget {
  const _Recommended();

  @override
  State<_Recommended> createState() => _RecommendedState();
}

class _RecommendedState extends State<_Recommended> {
  int? _days;

  @override
  Widget build(BuildContext context) => OnboardingQuestion(
    step: 2,
    count: 9,
    onBack: () {},
    body: OnboardingQuestionBody(
      title: 'How many days a week can you train?',
      info: 'Most beginners train 3 days a week.',
      answer: OnboardingChoices<int>(
        values: const [2, 3, 4, 5, 6],
        selected: _days,
        title: (days) => '$days days',
        tag: (days) => days == 3 ? 'Recommended' : null,
        onChanged: (days) => setState(() => _days = days),
      ),
    ),
    actionLabel: 'Continue',
    onAction: _days == null ? null : () {},
  );
}

@widgetbook.UseCase(name: 'Equipment question', type: OnboardingQuestion)
Widget equipmentOnboardingQuestion(BuildContext context) => const _Equipment();

class _Equipment extends StatefulWidget {
  const _Equipment();

  @override
  State<_Equipment> createState() => _EquipmentState();
}

class _EquipmentState extends State<_Equipment> {
  Set<Equipment> _owned = {...EquipmentProfile.fullGym.equipment};

  @override
  Widget build(BuildContext context) => OnboardingQuestion(
    step: 4,
    count: 9,
    onBack: () {},
    body: OnboardingQuestionBody(
      eyebrow: 'Generate a program',
      title: 'What equipment do you have?',
      info: 'Pick the closest set. Bodyweight exercises are always included.',
      answer: EquipmentAnswer(
        owned: _owned,
        onPreset: (preset) => setState(() => _owned = {...preset.equipment}),
        onEquipment: (owned) => setState(() => _owned = owned),
      ),
    ),
    actionLabel: 'Continue',
    onAction: () {},
  );
}

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
      answer: NumberPicker.ruler(
        label: 'Height',
        unit: 'cm',
        min: 100,
        max: 250,
        step: 1,
        value: _cm,
        onChanged: (cm) => setState(() => _cm = cm),
        onValueTap: () {},
      ),
    ),
    actionLabel: 'Continue',
    onAction: () {},
  );
}
