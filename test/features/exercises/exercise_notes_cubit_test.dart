import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/exercises/presentation/exercise_notes_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUserLibraryRepository extends Mock implements UserLibraryRepository {}

void main() {
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const other = AuthUser(id: 'u2', email: 'c@d.co');

  late MockAuthRepository auth;
  late MockUserLibraryRepository library;
  late StreamController<AuthUser?> users;
  late Map<String, StreamController<Map<String, String>>> watched;

  setUp(() {
    auth = MockAuthRepository();
    library = MockUserLibraryRepository();
    users = StreamController<AuthUser?>();
    watched = {};
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => library.watchExerciseNotes(any())).thenAnswer((call) {
      final controller = StreamController<Map<String, String>>();
      watched[call.positionalArguments.first as String] = controller;
      return controller.stream;
    });
    when(() => library.setExerciseNote(any(), any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  ExerciseNotesCubit build() => ExerciseNotesCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchExerciseNotes: WatchExerciseNotes(library),
    setExerciseNote: SetExerciseNote(library),
  );

  Future<void> signIn(AuthUser user, Map<String, String> notes) async {
    users.add(user);
    await pumpEventQueue();
    watched[user.id]!.add(notes);
    await pumpEventQueue();
  }

  test('follows whoever is signed in and resets on a user change', () async {
    final cubit = build();
    await signIn(member, {'squat': 'Wide stance'});
    expect(cubit.state.of('squat'), 'Wide stance');

    users.add(other);
    await pumpEventQueue();
    expect(cubit.state.notes, isEmpty);
    await cubit.close();
  });

  test('saves the note trimmed for the signed-in user', () async {
    final cubit = build();
    await signIn(member, {});

    expect(await cubit.save('squat', '  Wide stance \n'), isNull);
    verify(() => library.setExerciseNote('u1', 'squat', 'Wide stance'))
        .called(1);
    await cubit.close();
  });

  test('a blank note removes it', () async {
    final cubit = build();
    await signIn(member, {'squat': 'Wide stance'});

    await cubit.save('squat', '   ');
    verify(() => library.setExerciseNote('u1', 'squat', '')).called(1);
    await cubit.close();
  });

  test('a note over the limit is refused without a write', () async {
    final cubit = build();
    await signIn(member, {});

    final failure = await cubit.save(
      'squat',
      'x' * (maxExerciseNoteLength + 1),
    );
    expect(failure, isA<ValidationFailure>());
    verifyNever(() => library.setExerciseNote(any(), any(), any()));
    await cubit.close();
  });

  test('reports a failed write', () async {
    when(() => library.setExerciseNote(any(), any(), any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final cubit = build();
    await signIn(member, {});

    expect(await cubit.save('squat', 'Wide stance'), isA<NetworkFailure>());
    await cubit.close();
  });

  test('saving while signed out writes nothing', () async {
    final cubit = build();
    users.add(null);
    await pumpEventQueue();

    expect(await cubit.save('squat', 'Wide stance'), isNotNull);
    verifyNever(() => library.setExerciseNote(any(), any(), any()));
    await cubit.close();
  });
}
