import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/exercise_row.dart';

import '../../component_harness.dart';

void main() {
  bool isStar(Widget widget) =>
      widget is ForgeIcon && widget.icon == ForgeIcons.star;

  testWidgets('a library row shows its marks and opens on a tap', (
    tester,
  ) async {
    var opened = 0;
    var toggled = 0;
    await pumpComponent(
      tester,
      ExerciseRow(
        name: 'Cable Hip Abduction',
        detail: 'Glutes · Cable',
        favorite: true,
        onFavorite: () => toggled++,
        custom: true,
        onTap: () => opened++,
      ),
    );

    expect(find.text('Glutes · Cable'), findsOneWidget);
    expect(find.widgetWithText(ForgeTag, 'Custom'), findsOneWidget);
    expect(find.byType(ForgeCheckbox), findsNothing);

    await tester.tap(find.text('Cable Hip Abduction'));
    expect((opened, toggled), (1, 0));
  });

  testWidgets('the star toggles the favourite across a 44px target', (
    tester,
  ) async {
    var favorite = false;
    var opened = 0;
    await pumpComponent(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ExerciseRow(
          name: 'Bench Press',
          detail: 'Chest · Barbell',
          favorite: favorite,
          onFavorite: () => setState(() => favorite = !favorite),
          onTap: () => opened++,
        ),
      ),
    );
    ForgeIcon star() =>
        tester.widget<ForgeIcon>(find.byWidgetPredicate(isStar));

    final colors = ForgeStyle.of(tester.element(find.byType(ExerciseRow)))
        .colors;
    expect(find.byType(ForgeIconButton), findsOneWidget);
    expect((star().filled, star().color), (false, colors.inkMuted));
    expect(find.bySemanticsLabel('Add to favourites'), findsOneWidget);

    // The edge of the target, away from the icon.
    final centre = tester.getCenter(find.byWidgetPredicate(isStar));
    await tester.tapAt(centre + const Offset(0, 20));
    await tester.pump();
    expect((star().filled, star().color), (true, colors.accent));
    expect(find.bySemanticsLabel('Remove from favourites'), findsOneWidget);
    expect(opened, 0);

    await tester.tap(find.byWidgetPredicate(isStar));
    await tester.pump();
    expect(star().filled, isFalse);
  });

  testWidgets('a similar exercise carries its relation', (tester) async {
    await pumpComponent(
      tester,
      ExerciseRow(
        name: 'Incline Bench Press',
        detail: 'Chest · Barbell',
        relation: 'Variation',
        onTap: () {},
      ),
    );

    expect(find.widgetWithText(ForgeTag, 'Variation'), findsOneWidget);
    expect(find.byWidgetPredicate(isStar), findsNothing);
  });

  testWidgets('a picker row toggles from the row and its checkbox', (
    tester,
  ) async {
    var toggled = 0;
    await pumpComponent(
      tester,
      ExerciseRow.pick(
        name: 'Bench Press',
        detail: 'Chest · Barbell',
        selected: true,
        onTap: () => toggled++,
      ),
    );

    expect(
      tester.widget<ForgeCheckbox>(find.byType(ForgeCheckbox)).value,
      true,
    );
    expect(
      tester.getSemantics(find.byType(ExerciseRow)),
      isSemantics(
        hasCheckedState: true,
        isChecked: true,
        hasTapAction: true,
        label: 'Bench Press\nChest · Barbell',
      ),
    );

    await tester.tap(find.text('Bench Press'));
    await tester.tap(find.byType(ForgeCheckbox));
    expect(toggled, 2);
  });

  testWidgets('a picker row off at the limit takes no taps', (tester) async {
    var toggled = 0;
    await pumpComponent(
      tester,
      ExerciseRow.pick(
        name: 'Cable Fly',
        detail: 'Chest · Cable',
        selected: false,
        enabled: false,
        onTap: () => toggled++,
      ),
    );

    expect(
      tester.getSemantics(find.byType(ExerciseRow)),
      isSemantics(
        hasCheckedState: true,
        hasEnabledState: true,
        label: 'Cable Fly\nChest · Cable',
      ),
    );
    await tester.tap(find.text('Cable Fly'));
    await tester.tap(find.byType(ForgeCheckbox));
    expect(toggled, 0);
  });
}
