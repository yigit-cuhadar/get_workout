import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/feedback/domain/feedback.dart';
import 'package:get_workout/features/feedback/domain/feedback_repository.dart';
import 'package:get_workout/features/feedback/domain/feedback_usecases.dart';
import 'package:mocktail/mocktail.dart';

class MockFeedbackRepository extends Mock implements FeedbackRepository {}

void main() {
  const draft = FeedbackDraft(source: FeedbackSource.profile);

  group('FeedbackDraft.problems', () {
    test('needs a message that is not only spaces', () {
      expect(draft.problems, {FeedbackProblem.emptyMessage});
      expect(draft.copyWith(message: '  \n ').problems, {
        FeedbackProblem.emptyMessage,
      });
      expect(draft.copyWith(message: ' Hi ').problems, isEmpty);
    });

    test('counts the trimmed message against the limit', () {
      final longest = 'a' * FeedbackLimits.message;
      expect(draft.copyWith(message: ' $longest ').problems, isEmpty);
      expect(draft.copyWith(message: '${longest}a').problems, {
        FeedbackProblem.longMessage,
      });
    });

    test('takes no email, or one that looks like an address', () {
      FeedbackDraft withEmail(String email) =>
          draft.copyWith(message: 'Hi', email: email);
      expect(withEmail('').problems, isEmpty);
      expect(withEmail(' a@b.co ').problems, isEmpty);
      for (final bad in ['a', 'a@b', '@b.co', 'a b@c.co', 'a@@b.co']) {
        expect(withEmail(bad).problems, {
          FeedbackProblem.badEmail,
        }, reason: bad);
      }
      final long = '${'a' * FeedbackLimits.email}@b.co';
      expect(withEmail(long).problems, {FeedbackProblem.badEmail});
    });
  });

  group('SendFeedback', () {
    late MockFeedbackRepository repository;

    setUpAll(() => registerFallbackValue(draft));

    setUp(() {
      repository = MockFeedbackRepository();
      when(() => repository.send(any(), any()))
          .thenAnswer((_) async => const Ok(null));
    });

    test('sends the trimmed draft', () async {
      final result = await SendFeedback(repository)((
        uid: 'u1',
        draft: draft.copyWith(message: ' Hi \n', email: ' a@b.co '),
      ));

      expect(result.isOk, isTrue);
      verify(
        () => repository.send(
          'u1',
          const FeedbackDraft(
            source: FeedbackSource.profile,
            message: 'Hi',
            email: 'a@b.co',
          ),
        ),
      ).called(1);
    });

    test('refuses a draft with problems without writing', () async {
      final result = await SendFeedback(repository)((uid: 'u1', draft: draft));

      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => repository.send(any(), any()));
    });
  });
}
