import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/exercise_tips.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  test('the body model tip shows until seen, not before settings', () {
    expect(muscleModelTipDue(const {}), isTrue);
    expect(muscleModelTipDue(const {Tip.effort}), isTrue);
    expect(muscleModelTipDue(const {Tip.muscleModel}), isFalse);
    expect(muscleModelTipDue(null), isFalse);
  });
}
