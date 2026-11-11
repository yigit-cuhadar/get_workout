import 'package:forge_core/forge_core.dart';

import 'cardio_repository.dart';
import 'cardio_session.dart';
import 'cardio_validation.dart';

typedef CardioSave = ({String uid, CardioSession session});
typedef CardioDelete = ({String uid, String id});

class WatchCardioSessions {
  const WatchCardioSessions(this._repository);
  final CardioRepository _repository;

  Stream<List<CardioSession>> call(String uid) =>
      _repository.watchSessions(uid);
}

/// Saves a valid session; an invalid one is refused with a
/// [ValidationFailure] and never reaches the repository.
class SaveCardioSession implements UseCase<void, CardioSave> {
  SaveCardioSession(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final CardioRepository _repository;
  final DateTime Function() _clock;

  @override
  Future<Result<void>> call(CardioSave params) async {
    final issues = validateCardio(params.session, now: _clock());
    if (issues.isNotEmpty) {
      return Err(ValidationFailure(issues.map((i) => i.name).join(', ')));
    }
    return _repository.saveSession(params.uid, params.session);
  }
}

class DeleteCardioSession implements UseCase<void, CardioDelete> {
  const DeleteCardioSession(this._repository);
  final CardioRepository _repository;

  @override
  Future<Result<void>> call(CardioDelete params) =>
      _repository.deleteSession(params.uid, params.id);
}
