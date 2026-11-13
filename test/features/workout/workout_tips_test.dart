import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/workout_tips.dart';

void main() {
  const set = (exercise: 0, set: 1);

  group('effort', () {
    test('due with the row about the set just ticked', () {
      expect(
        effortTipDue(const {}, offered: true, asked: set, ticked: set),
        isTrue,
      );
    });

    test('not about a selected done set, nor without the row', () {
      expect(
        effortTipDue(
          const {},
          offered: true,
          asked: set,
          ticked: (exercise: 0, set: 0),
        ),
        isFalse,
      );
      expect(
        effortTipDue(const {}, offered: true, asked: null, ticked: set),
        isFalse,
      );
    });

    test('not once seen, while settings are unknown, or where not offered', () {
      expect(
        effortTipDue(
          const {Tip.effort},
          offered: true,
          asked: set,
          ticked: set,
        ),
        isFalse,
      );
      expect(
        effortTipDue(null, offered: true, asked: set, ticked: set),
        isFalse,
      );
      expect(
        effortTipDue(const {}, offered: false, asked: set, ticked: set),
        isFalse,
      );
    });
  });

  test('set types: due until seen, once settings are known', () {
    expect(setTypesTipDue(const {}), isTrue);
    expect(setTypesTipDue(const {Tip.setTypes}), isFalse);
    expect(setTypesTipDue(null), isFalse);
  });

  test('automatic warm-ups: due only once they were added', () {
    expect(autoWarmupsTipDue(const {}, added: true), isTrue);
    expect(autoWarmupsTipDue(const {}, added: false), isFalse);
    expect(autoWarmupsTipDue(const {Tip.autoWarmups}, added: true), isFalse);
    expect(autoWarmupsTipDue(null, added: true), isFalse);
  });
}
