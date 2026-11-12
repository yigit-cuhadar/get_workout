import 'package:forge_auth/forge_auth.dart';
import 'package:get_workout/features/calculators/domain/calculators_usecases.dart';
import 'package:get_workout/features/calculators/domain/known_body_values.dart';

/// The current user for the calculator cubits; [user] null is signed out,
/// which loads no known values.
class FakeCurrentUser implements GetCurrentUser {
  FakeCurrentUser([this.user = const AuthUser(id: 'u1', isAnonymous: false)]);
  final AuthUser? user;

  @override
  AuthUser? call() => user;
}

/// Known values that arrive when [answer] completes.
class FakeKnownValues implements GetKnownBodyValues {
  final requests = <String>[];
  Future<KnownBodyValues> answer = Future.value(const KnownBodyValues());

  @override
  Future<KnownBodyValues> call(String uid) {
    requests.add(uid);
    return answer;
  }
}

final signedOut = FakeCurrentUser(null);
final noKnownValues = FakeKnownValues();
