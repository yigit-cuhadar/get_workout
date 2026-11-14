import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_bubble.dart';

Future<void> _pump(WidgetTester tester, Widget bubble) => tester.pumpWidget(
  MaterialApp(
    theme: AppPreset.slate.lightTheme(),
    home: Scaffold(body: Center(child: bubble)),
  ),
);

void main() {
  testWidgets('a tap selects and a long press opens the menu', (tester) async {
    var taps = 0;
    var holds = 0;
    await _pump(
      tester,
      SetBubble(
        label: '2',
        semanticLabel: 'Set 2',
        onTap: () => taps++,
        onLongPress: () => holds++,
      ),
    );
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byType(SetBubble));
    await tester.longPress(find.byType(SetBubble));
    expect((taps, holds), (1, 1));
  });

  testWidgets('it is 48px and tells a screen reader its set and state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      SetBubble(
        label: '1',
        semanticLabel: 'Set 1, done',
        done: true,
        selected: true,
        onTap: () {},
        actions: {const CustomSemanticsAction(label: 'Remove set'): () {}},
      ),
    );
    expect(tester.getSize(find.byType(SetBubble)), const Size.square(48));
    expect(
      tester.getSemantics(find.byType(SetBubble)),
      matchesSemantics(
        label: 'Set 1, done',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        customActions: [const CustomSemanticsAction(label: 'Remove set')],
      ),
    );
    semantics.dispose();
  });

  testWidgets('the add bubble is off without an action', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      const SetBubble.add(semanticLabel: 'Add set', onTap: null),
    );
    expect(
      tester.getSemantics(find.byType(SetBubble)),
      matchesSemantics(
        label: 'Add set',
        isButton: true,
        hasEnabledState: true,
        hasSelectedState: true,
      ),
    );
    semantics.dispose();
  });
}
