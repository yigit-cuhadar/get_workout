import 'package:forge_core/forge_core.dart';

import 'admin_user.dart';
import 'admin_user_repository.dart';

class ListLatestUsers implements UseCase<UsersPage, UserCursor?> {
  const ListLatestUsers(this._repository);
  final AdminUserRepository _repository;

  @override
  Future<Result<UsersPage>> call(UserCursor? params) =>
      _repository.latest(after: params);
}

/// The uid for an email or uid; an empty query fails without asking.
class FindUser implements UseCase<String, String> {
  const FindUser(this._repository);
  final AdminUserRepository _repository;

  @override
  Future<Result<String>> call(String params) async {
    final query = params.trim();
    if (query.isEmpty) return const Err(ValidationFailure('empty query'));
    return _repository.find(query);
  }
}

class GetAdminUser implements UseCase<UserDetail, String> {
  const GetAdminUser(this._repository);
  final AdminUserRepository _repository;

  @override
  Future<Result<UserDetail>> call(String params) => _repository.user(params);
}

class GrantPromotionalPremium
    implements UseCase<DateTime?, ({String uid, PremiumDuration duration})> {
  const GrantPromotionalPremium(this._repository);
  final AdminUserRepository _repository;

  @override
  Future<Result<DateTime?>> call(
    ({String uid, PremiumDuration duration}) params,
  ) => _repository.grantPremium(params.uid, params.duration);
}

class RevokePromotionalPremium implements UseCase<void, String> {
  const RevokePromotionalPremium(this._repository);
  final AdminUserRepository _repository;

  @override
  Future<Result<void>> call(String params) => _repository.revokePremium(params);
}

class SetUserAdmin implements UseCase<void, ({String uid, bool admin})> {
  const SetUserAdmin(this._repository);
  final AdminUserRepository _repository;

  @override
  Future<Result<void>> call(({String uid, bool admin}) params) =>
      _repository.setAdmin(params.uid, admin: params.admin);
}

class DeleteUserAccount implements UseCase<void, String> {
  const DeleteUserAccount(this._repository);
  final AdminUserRepository _repository;

  @override
  Future<Result<void>> call(String params) => _repository.delete(params);
}
