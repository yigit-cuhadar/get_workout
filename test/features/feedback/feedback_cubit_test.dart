import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/feedback/domain/feedback.dart';
import 'package:get_workout/features/feedback/domain/feedback_repository.dart';
import 'package:get_workout/features/feedback/domain/feedback_usecases.dart';
import 'package:get_workout/features/feedback/presentation/feedback_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockFeedbackRepository extends Mock implements FeedbackRepository {}

void main() {
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const guest = AuthUser(id: 'g1', isAnonymous: true);
  late MockAuthRepository auth;
  late MockFeedbackRepository repository;

  setUpAll(
    () => registerFallbackValue(
      const FeedbackDraft(source: FeedbackSource.profile),
    ),
  );

  setUp(() {
    auth = MockAuthRepository();
    repository = MockFeedbackRepository();
    when(() => auth.currentUser).thenReturn(member);
    when(() => repository.send(any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  FeedbackCubit build([FeedbackSource source = FeedbackSource.profile]) =>
      FeedbackCubit(
        sendFeedback: SendFeedback(repository),
        getCurrentUser: GetCurrentUser(auth),
        source: source,
      );

  test('starts with the account email, empty for a guest', () {
    expect(build().state.draft.email, 'a@b.co');
    when(() => auth.currentUser).thenReturn(guest);
    expect(build().state.draft.email, '');
  });

  blocTest<FeedbackCubit, FeedbackState>(
    'sends the message from its source, then is sent',
    build: () => build(FeedbackSource.rating),
    act: (cubit) async {
      cubit.setMessage('Add timers');
      await cubit.send();
    },
    skip: 1,
    expect: () => [
      isA<FeedbackState>().having(
        (s) => s.status,
        'status',
        FeedbackFormStatus.sending,
      ),
      isA<FeedbackState>().having(
        (s) => s.status,
        'status',
        FeedbackFormStatus.sent,
      ),
    ],
    verify: (_) => verify(
      () => repository.send(
        'u1',
        const FeedbackDraft(
          source: FeedbackSource.rating,
          message: 'Add timers',
          email: 'a@b.co',
        ),
      ),
    ).called(1),
  );

  blocTest<FeedbackCubit, FeedbackState>(
    'with problems only shows them, and they follow the typing',
    build: build,
    act: (cubit) async {
      cubit.setEmail('nope');
      await cubit.send();
      cubit.setMessage('Hi');
    },
    skip: 1,
    expect: () => [
      isA<FeedbackState>().having((s) => s.problems, 'problems', {
        FeedbackProblem.emptyMessage,
        FeedbackProblem.badEmail,
      }),
      isA<FeedbackState>().having((s) => s.problems, 'problems', {
        FeedbackProblem.badEmail,
      }),
    ],
    verify: (_) => verifyNever(() => repository.send(any(), any())),
  );

  blocTest<FeedbackCubit, FeedbackState>(
    'a failed send can be tried again',
    setUp: () =>
        when(() => repository.send(any(), any()))
            .thenAnswer((_) async => const Err(NetworkFailure('offline'))),
    build: build,
    seed: () => const FeedbackState(
      draft: FeedbackDraft(source: FeedbackSource.profile, message: 'Hi'),
    ),
    act: (cubit) => cubit.send(),
    expect: () => [
      isA<FeedbackState>().having(
        (s) => s.status,
        'status',
        FeedbackFormStatus.sending,
      ),
      isA<FeedbackState>()
          .having((s) => s.status, 'status', FeedbackFormStatus.failed)
          .having((s) => s.failure, 'failure', isA<NetworkFailure>()),
    ],
  );

  blocTest<FeedbackCubit, FeedbackState>(
    'signed out, nothing is written',
    setUp: () => when(() => auth.currentUser).thenReturn(null),
    build: build,
    seed: () => const FeedbackState(
      draft: FeedbackDraft(source: FeedbackSource.profile, message: 'Hi'),
    ),
    act: (cubit) => cubit.send(),
    expect: () => [
      isA<FeedbackState>().having(
        (s) => s.status,
        'status',
        FeedbackFormStatus.failed,
      ),
    ],
    verify: (_) => verifyNever(() => repository.send(any(), any())),
  );
}
