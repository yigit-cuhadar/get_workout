import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/workout_tips.dart';

void main() {
  test('effort: due until seen, once settings are known', () {
    expect(effortTipDue(const {}), isTrue);
    expect(effortTipDue(const {Tip.effort}), isFalse);
    expect(effortTipDue(null), isFalse);
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
