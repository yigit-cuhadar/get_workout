import 'package:forge_core/forge_core.dart';

/// How long a promotional Premium grant lasts.
enum PremiumDuration {
  week,
  month,
  year,
  lifetime;

  /// When a grant made at [now] ends, as the server computes it (calendar
  /// month and year); null for [lifetime], which never ends.
  DateTime? endFrom(DateTime now) {
    final utc = now.toUtc();
    return switch (this) {
      week => utc.add(const Duration(days: 7)),
      month => _shifted(utc, months: 1),
      year => _shifted(utc, months: 12),
      lifetime => null,
    };
  }

  static DateTime _shifted(DateTime utc, {required int months}) => DateTime.utc(
    utc.year,
    utc.month + months,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
  );
}

/// A row of the latest sign-ups.
class UserRow extends Equatable {
  const UserRow({
    required this.uid,
    required this.email,
    required this.guest,
    required this.premium,
    required this.signedUp,
    required this.lastWorkout,
    required this.platform,
  });

  final String uid;
  final String? email;

  /// Signed in as a guest: no email and no sign-in method.
  final bool guest;

  /// Whether the server grants Premium now (`entitlements/{uid}`).
  final bool premium;
  final DateTime signedUp;
  final DateTime? lastWorkout;

  /// `ios` or `android`: the device last seen; null before any.
  final String? platform;

  @override
  List<Object?> get props => [
    uid,
    email,
    guest,
    premium,
    signedUp,
    lastWorkout,
    platform,
  ];
}

/// Where the next page of sign-ups starts: after this one.
class UserCursor extends Equatable {
  const UserCursor({required this.createdAtMillis, required this.uid});

  final int createdAtMillis;
  final String uid;

  @override
  List<Object?> get props => [createdAtMillis, uid];
}

/// A page of sign-ups, newest first; [next] is null on the last page.
typedef UsersPage = ({List<UserRow> users, UserCursor? next});

/// `entitlements/{uid}`: the Premium the server grants.
class ServerPremium extends Equatable {
  const ServerPremium({
    required this.premium,
    required this.expiresAt,
    required this.productId,
    required this.lastChange,
  });

  final bool premium;
  final DateTime? expiresAt;
  final String? productId;

  /// The latest RevenueCat event applied.
  final DateTime? lastChange;

  bool activeAt(DateTime now) =>
      premium && (expiresAt == null || expiresAt!.isAfter(now));

  @override
  List<Object?> get props => [premium, expiresAt, productId, lastChange];
}

/// A RevenueCat subscription; a promotional grant is one too.
class StoreSubscription extends Equatable {
  const StoreSubscription({
    required this.store,
    required this.status,
    required this.givesAccess,
    required this.productId,
    required this.periodEnds,
    required this.autoRenewal,
  });

  /// `app_store`, `play_store`, `promotional`, ...
  final String store;

  /// `trialing`, `active`, `expired`, `in_grace_period`, ...
  final String status;
  final bool givesAccess;
  final String? productId;
  final DateTime? periodEnds;

  /// `will_renew`, `will_not_renew`, ...
  final String autoRenewal;

  bool get promotional => store == 'promotional';

  @override
  List<Object?> get props => [
    store,
    status,
    givesAccess,
    productId,
    periodEnds,
    autoRenewal,
  ];
}

/// A device the app runs on, as it records itself
/// (`users/{uid}/devices/{installId}`).
class UserDevice extends Equatable {
  const UserDevice({
    required this.model,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
    required this.lastSeen,
  });

  /// "iPhone15,2", "Google Pixel 8".
  final String model;

  /// `ios` or `android`.
  final String platform;
  final String osVersion;

  /// "1.2.0+14".
  final String appVersion;
  final DateTime? lastSeen;

  @override
  List<Object?> get props => [model, platform, osVersion, appVersion, lastSeen];
}

/// What RevenueCat knows of the user.
class RevenueCatCustomer extends Equatable {
  const RevenueCatCustomer({
    required this.premium,
    required this.premiumEnds,
    required this.subscriptions,
  });

  /// Whether the `premium` entitlement is active.
  final bool premium;

  /// When it ends; null while [premium] never ends.
  final DateTime? premiumEnds;
  final List<StoreSubscription> subscriptions;

  /// The store subscription giving access, else the first one.
  StoreSubscription? get storeSubscription {
    final paid = subscriptions.where((s) => !s.promotional).toList();
    return paid.where((s) => s.givesAccess).firstOrNull ?? paid.firstOrNull;
  }

  /// The promotional grant giving access now.
  StoreSubscription? get promotional =>
      subscriptions.where((s) => s.promotional && s.givesAccess).firstOrNull;

  @override
  List<Object?> get props => [premium, premiumEnds, subscriptions];
}

enum RevenueCatState {
  ok,

  /// RevenueCat has never seen this user.
  noCustomer,

  /// RevenueCat failed or refused (the key may lack a permission).
  failed,
}

/// Everything a user's page shows.
class UserDetail extends Equatable {
  const UserDetail({
    required this.uid,
    required this.email,
    required this.guest,
    required this.providers,
    required this.admin,
    required this.signedUp,
    required this.lastActive,
    required this.server,
    required this.workouts,
    required this.lastWorkout,
    required this.activeProgram,
    required this.devices,
    required this.revenueCat,
    required this.revenueCatState,
  });

  final String uid;
  final String? email;
  final bool guest;

  /// Sign-in methods: `password`, `google.com`, `apple.com`.
  final List<String> providers;
  final bool admin;
  final DateTime signedUp;

  /// The last sign-in token refresh: about when the app was last open.
  final DateTime? lastActive;

  /// Null when no RevenueCat event ever reached the server.
  final ServerPremium? server;
  final int workouts;
  final DateTime? lastWorkout;
  final String? activeProgram;

  /// Last seen first.
  final List<UserDevice> devices;

  /// Set when [revenueCatState] is [RevenueCatState.ok].
  final RevenueCatCustomer? revenueCat;
  final RevenueCatState revenueCatState;

  bool get hasPassword => providers.contains('password');

  @override
  List<Object?> get props => [
    uid,
    email,
    guest,
    providers,
    admin,
    signedUp,
    lastActive,
    server,
    workouts,
    lastWorkout,
    activeProgram,
    devices,
    revenueCat,
    revenueCatState,
  ];
}

/// The action is refused on the admin's own account (demoting or deleting
/// it).
final class OwnAccountFailure extends Failure {
  const OwnAccountFailure([super.message = 'own account', Object? cause])
    : super(cause: cause);
}

/// RevenueCat refused or failed; [status] is its HTTP status when it
/// answered (403: the key lacks a permission).
final class RevenueCatFailure extends Failure {
  const RevenueCatFailure(super.message, {this.status, super.cause});

  final int? status;
}
