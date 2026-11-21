import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/admin/announcements/domain/announcement.dart';
import 'package:get_workout/admin/announcements/presentation/send_confirm_dialog.dart';

void main() {
  const draft = AnnouncementDraft(title: 'New programs', body: 'Three.');

  /// Opens the dialog; [answer] gets what it pops.
  Future<void> open(WidgetTester tester, List<bool?> answer) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ForgeTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer.add(
              await showDialog<bool>(
                context: context,
                builder: (_) => const SendConfirmDialog(draft: draft),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the text and sends only once the box is ticked', (
    tester,
  ) async {
    final answer = <bool?>[];
    await open(tester, answer);
    expect(find.text('New programs'), findsOneWidget);
    expect(find.text('Three.'), findsOneWidget);

    await tester.tap(find.text('Send to everyone'));
    await tester.pumpAndSettle();
    expect(answer, isEmpty);

    await tester.tap(find.text('I understand it cannot be recalled'));
    await tester.pump();
    await tester.tap(find.text('Send to everyone'));
    await tester.pumpAndSettle();
    expect(answer, [true]);
  });

  testWidgets('Cancel sends nothing', (tester) async {
    final answer = <bool?>[];
    await open(tester, answer);
    await tester.tap(find.byType(ForgeCheckbox));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answer, [false]);
  });
}
