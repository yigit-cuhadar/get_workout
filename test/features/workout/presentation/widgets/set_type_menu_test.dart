import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_bubble.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_type_menu.dart';

void main() {
  /// Shows [home] with text [scale]d.
  Widget app(Widget home, {double scale = 1}) => MaterialApp(
    theme: AppPreset.slate.lightTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  );

  double rowHeight(WidgetTester tester, String label) => tester
      .getSize(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      )
      .height;

  Future<List<String>> openMenu(WidgetTester tester, {double scale = 1}) async {
    final ran = <String>[];
    await tester.pumpWidget(
      app(
        scale: scale,
        Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => SetBubble(
                label: '3',
                semanticLabel: 'Set 3',
                onTap: () {},
                onLongPress: () => showSetTypeMenu(
                  context: context,
                  types: [
                    SetTypeMenuItem(
                      label: 'Warm-up',
                      bubble: 'W',
                      warmup: true,
                      onTap: () => ran.add('warmup'),
                    ),
                    SetTypeMenuItem(
                      label: 'Working',
                      bubble: '3',
                      current: true,
                      onTap: () => ran.add('working'),
                    ),
                    SetTypeMenuItem(
                      label: 'Drop set',
                      bubble: '3D',
                      onTap: () => ran.add('drop'),
                    ),
                  ],
                  removeLabel: 'Remove set',
                  onRemove: () => ran.add('remove'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(SetBubble));
    await tester.pumpAndSettle();
    return ran;
  }

  testWidgets('a long press opens the types under the bubble', (tester) async {
    await openMenu(tester);
    expect(find.byType(SetTypeMenu), findsOneWidget);
    // The other types show the bubble they would give, not the current.
    expect(find.text('W'), findsOneWidget);
    expect(find.text('3D'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(SetTypeMenu)).dy,
      greaterThan(tester.getBottomLeft(find.byType(SetBubble)).dy),
    );
    expect(
      tester.getTopLeft(find.byType(SetTypeMenu)).dx,
      tester.getTopLeft(find.byType(SetBubble)).dx,
    );
  });

  testWidgets('a row closes the menu, then runs', (tester) async {
    final ran = await openMenu(tester);
    await tester.tap(find.text('Drop set'));
    await tester.pumpAndSettle();
    expect(ran, ['drop']);
    expect(find.byType(SetTypeMenu), findsNothing);
  });

  testWidgets('Remove set runs its action', (tester) async {
    final ran = await openMenu(tester);
    await tester.tap(find.text('Remove set'));
    await tester.pumpAndSettle();
    expect(ran, ['remove']);
  });

  testWidgets('a tap outside closes it', (tester) async {
    final ran = await openMenu(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(SetTypeMenu), findsNothing);
    expect(ran, isEmpty);
  });

  testWidgets('the current type is marked selected', (tester) async {
    await openMenu(tester);
    Finder selected(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.selected == true,
      ),
    );
    expect(selected('Working'), findsOneWidget);
    expect(selected('Warm-up'), findsNothing);
  });

  testWidgets('the add sheet lists each type with its bubble and line', (
    tester,
  ) async {
    final picked = <String>[];
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppPreset.slate.lightTheme(),
        home: Scaffold(
          body: AddSetSheet(
            title: 'Add set',
            tip: TextButton(
              onPressed: () => dismissed++,
              child: const Text('Got it'),
            ),
            options: [
              AddSetOption(
                label: 'Normal',
                hint: 'A working set at the end',
                bubble: '5',
                onTap: () => picked.add('normal'),
              ),
              AddSetOption(
                label: 'Warm-up',
                hint: 'Goes after the other warm-ups',
                bubble: 'W',
                warmup: true,
                onTap: () => picked.add('warmup'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Add set'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('A working set at the end'), findsOneWidget);
    await tester.tap(find.text('Warm-up'));
    await tester.tap(find.text('Got it'));
    expect(picked, ['warmup']);
    expect(dismissed, 1);
  });

  testWidgets('menu rows are 44px and grow with the text', (tester) async {
    Future<void> pump({double scale = 1}) => tester.pumpWidget(
      app(
        scale: scale,
        Center(
          child: SetTypeMenu(
            types: [
              SetTypeMenuItem(label: 'Working', bubble: '3', onTap: () {}),
            ],
            removeLabel: 'Remove set',
            onRemove: () {},
          ),
        ),
      ),
    );
    await pump();
    expect(rowHeight(tester, 'Remove set'), 44);
    await pump(scale: 3);
    expect(rowHeight(tester, 'Remove set'), greaterThan(44));
  });

  testWidgets('add sheet rows are 64px and grow with the text', (tester) async {
    Future<void> pump({double scale = 1}) => tester.pumpWidget(
      app(
        scale: scale,
        Scaffold(
          body: AddSetSheet(
            title: 'Add set',
            options: [
              AddSetOption(
                label: 'Normal',
                hint: 'A working set at the end',
                bubble: '5',
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await pump();
    expect(rowHeight(tester, 'Normal'), 64);
    await pump(scale: 2);
    expect(rowHeight(tester, 'Normal'), greaterThan(64));
  });
}
