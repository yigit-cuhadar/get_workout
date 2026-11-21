import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/admin/admin_router.dart';

void main() {
  test('the menu lists the groups and sections of the S1 board', () {
    expect(
      [for (final section in adminSections) (section.group, section.label)],
      [
        (null, 'Dashboard'),
        ('People', 'Users'),
        ('People', 'Support inbox'),
        ('Content', 'Exercises'),
        ('Content', 'Programs'),
        ('Content', 'Announcements'),
        ('App', 'App settings'),
      ],
    );
  });

  test('Support inbox opens the feedback page for now', () {
    final inbox = adminSections.singleWhere((s) => s.label == 'Support inbox');
    expect(inbox.path, AdminRoutes.feedback);
  });

  group('opens', () {
    final exercises = adminSections.singleWhere(
      (s) => s.path == AdminRoutes.exercises,
    );

    test('marks the section on its page and its subpages', () {
      expect(exercises.opens(AdminRoutes.exercises), isTrue);
      expect(exercises.opens(AdminRoutes.newExercise), isTrue);
      expect(exercises.opens(AdminRoutes.exercise('squat')), isTrue);
    });

    test('leaves it unmarked elsewhere, even on a longer path', () {
      expect(exercises.opens(AdminRoutes.programs), isFalse);
      expect(exercises.opens('${AdminRoutes.exercises}-archive'), isFalse);
    });
  });
}
