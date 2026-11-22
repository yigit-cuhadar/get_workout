import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout_widgetbook/all_forms.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookUseCase _titled(String name, String title) => WidgetbookUseCase(
  name: name,
  builder: (context) => Center(
    child: Text(context.knobs.string(label: 'Title', initialValue: title)),
  ),
);

void main() {
  final directories = withAllForms([
    WidgetbookFolder(
      name: 'Folder',
      children: [
        WidgetbookComponent(
          name: 'Two',
          useCases: [
            _titled('Short', 'First title'),
            _titled('Long', 'Second title'),
            WidgetbookUseCase(
              name: 'Page',
              builder: (context) => Scaffold(
                body: ListView(
                  children: [
                    Text(context.knobs.boolean(label: 'Title') ? 'On' : 'Off'),
                  ],
                ),
              ),
            ),
            WidgetbookUseCase(
              name: 'List',
              builder: (_) => ListView(children: const [Text('Row')]),
            ),
          ],
        ),
        WidgetbookComponent(
          name: 'One',
          useCases: [_titled('Only', 'Only title')],
        ),
      ],
    ),
  ]);
  final folder = directories.single;
  final two = folder.children![0] as WidgetbookComponent;
  final one = folder.children![1] as WidgetbookComponent;

  test('adds All forms first to components of several use cases', () {
    expect(two.useCases.map((u) => u.name), [
      'All forms',
      'Short',
      'Long',
      'Page',
      'List',
    ]);
    expect(one.useCases.map((u) => u.name), ['Only']);
  });

  testWidgets('shows every use case with its own knob defaults', (
    tester,
  ) async {
    final state = WidgetbookState(root: WidgetbookRoot(children: directories));
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WidgetbookScope(
          state: state,
          child: Builder(builder: two.useCases.first.builder),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (final text in [
      'Short',
      'Long',
      'Page',
      'First title',
      'Second title',
      'Off',
      'Row',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    // The page keeps its knobs off the panel.
    expect(state.knobs, isEmpty);
    // A full-screen use case gets a phone; a small one its own size.
    expect(tester.getSize(find.byType(Scaffold)), const Size(390, 844));
    expect(tester.getSize(find.byType(ListView).last), const Size(390, 844));
    expect(
      tester.getSize(
        find.ancestor(
          of: find.text('First title'),
          matching: find.byType(Center),
        ),
      ),
      tester.getSize(find.text('First title')),
    );
  });
}
