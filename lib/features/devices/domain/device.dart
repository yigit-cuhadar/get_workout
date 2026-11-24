import 'package:forge_core/forge_core.dart';

/// This install of the app, as `users/{uid}/devices/{installId}` records
/// it for the admin panel and the panel's test announcements.
class Device extends Equatable {
  const Device({
    required this.installId,
    required this.model,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
    this.pushToken,
  });

  /// 32 lowercase hex characters, made once per install.
  final String installId;

  /// "iPhone15,2", "Google Pixel 8".
  final String model;

  /// `ios` or `android`.
  final String platform;
  final String osVersion;

  /// "1.2.0+14": version and build.
  final String appVersion;

  /// FCM's registration token; null while the install has none
  /// (notifications never allowed, no APNs or Play services).
  final String? pushToken;

  @override
  List<Object?> get props => [
    installId,
    model,
    platform,
    osVersion,
    appVersion,
    pushToken,
  ];
}

/// The last record this install wrote: for whom, what and when.
class DeviceRecord extends Equatable {
  const DeviceRecord({
    required this.uid,
    required this.device,
    required this.at,
  });

  final String uid;
  final Device device;
  final DateTime at;

  @override
  List<Object?> get props => [uid, device, at];
}
