import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/effort_question.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

const _byFeel = [
  EffortOption(label: 'Easy', meaning: '4+ reps left'),
  EffortOption(label: 'Moderate', meaning: '2–3 reps left'),
  EffortOption(label: 'Hard', meaning: '1 rep left'),
  EffortOption(label: 'Max', meaning: 'No reps left'),
  EffortOption(label: 'Failed', meaning: 'last rep missed'),
];

const _rir = [
  EffortOption(label: '5+', meaning: '5 or more reps left'),
  EffortOption(label: '4', meaning: '4 reps left'),
  EffortOption(label: '3', meaning: '3 reps left'),
  EffortOption(label: '2', meaning: '2 reps left'),
  EffortOption(label: '1', meaning: '1 rep left'),
  EffortOption(label: '0', meaning: 'No reps left'),
  EffortOption(label: 'Failed', meaning: 'last rep missed'),
];

const _rpe = [
  EffortOption(label: 'RPE 6 or less', meaning: '4+ reps left'),
  EffortOption(label: 'RPE 7', meaning: '3 reps left'),
  EffortOption(label: 'RPE 8', meaning: '2 reps left'),
  EffortOption(label: 'RPE 9', meaning: '1 rep left'),
  EffortOption(label: 'RPE 10', meaning: 'No reps left'),
  EffortOption(label: 'Failed', meaning: 'last rep missed'),
];

final _rest = EffortRest(
  time: '1:45',
  progress: 0.85,
  onAddTime: () {},
  onSkip: () {},
);

@widgetbook.UseCase(name: 'By feel', type: EffortQuestion)
Widget byFeelEffortQuestion(BuildContext context) => _Question(
  question: 'How hard was set 3?',
  values: '82.5 kg × 8',
  options: _byFeel,
  rest: _rest,
);

@widgetbook.UseCase(name: 'RIR', type: EffortQuestion)
Widget rirEffortQuestion(BuildContext context) => _Question(
  question: 'How many reps were left in set 3?',
  values: '82.5 kg × 8',
  options: _rir,
  rest: _rest,
);

@widgetbook.UseCase(name: 'RPE, a step picked', type: EffortQuestion)
Widget rpeEffortQuestion(BuildContext context) => _Question(
  question: "What was set 3's RPE?",
  values: '82.5 kg × 8',
  options: _rpe,
  rest: _rest,
  selected: 2,
);

@widgetbook.UseCase(name: 'No rest', type: EffortQuestion)
Widget noRestEffortQuestion(BuildContext context) => const _Question(
  question: 'How hard was it?',
  values: 'Set 1 done · 82.5 kg × 8',
  options: _byFeel,
);

@widgetbook.UseCase(name: 'Wording', type: EffortQuestion)
Widget wordingEffortQuestion(BuildContext context) => const Column(
  spacing: Gap.sm,
  children: [
    Expanded(
      child: _Question(
        question: 'How hard was it?',
        values: 'Drop set 4 done · 82.5 kg × 6',
        options: _byFeel,
      ),
    ),
    Expanded(
      child: _Question(
        question: 'How many more reps could you have done?',
        values: 'Overhead Press · Set 3 done · 50 kg × 8',
        options: _rir,
      ),
    ),
    Expanded(
      child: _Question(
        question: 'How hard was it, from 1 to 10?',
        values: 'Set 2 done · 82.5 kg × 8',
        options: _rpe,
      ),
    ),
  ],
);

/// The question at the bottom of the screen, on surface; a tap picks.
class _Question extends StatefulWidget {
  const _Question({
    required this.question,
    required this.values,
    required this.options,
    this.rest,
    this.selected,
  });

  final String question;
  final String values;
  final List<EffortOption> options;
  final EffortRest? rest;
  final int? selected;

  @override
  State<_Question> createState() => _QuestionState();
}

class _QuestionState extends State<_Question> {
  late int? _selected = widget.selected;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.end,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ColoredBox(
        color: ForgeStyle.of(context).colors.surface,
        child: EffortQuestion(
          question: widget.question,
          values: widget.values,
          options: widget.options,
          selected: _selected,
          onSelected: (i) => setState(() => _selected = i),
          onSkip: () {},
          onHelp: () {},
          rest: widget.rest,
        ),
      ),
    ],
  );
}
