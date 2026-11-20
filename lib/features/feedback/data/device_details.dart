import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app and device a message is sent from; empty where unknown.
class DeviceDetails {
  const DeviceDetails({
    this.appVersion = '',
    this.platform = '',
    this.osVersion = '',
    this.deviceModel = '',
    this.locale = '',
  });

  /// "1.2.0+14": version and build.
  final String appVersion;

  /// `ios` or `android`.
  final String platform;
  final String osVersion;
  final String deviceModel;

  /// The device's language and region, such as "en-GB".
  final String locale;
}

abstract interface class DeviceDetailsSource {
  Future<DeviceDetails> read();
}

class PlatformDeviceDetails implements DeviceDetailsSource {
  const PlatformDeviceDetails(this._device);

  final DeviceInfoPlugin _device;

  @override
  Future<DeviceDetails> read() async {
    final app = await PackageInfo.fromPlatform();
    final (os, model) = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => await _device.iosInfo.then(
        (ios) => (ios.systemVersion, ios.utsname.machine),
      ),
      TargetPlatform.android => await _device.androidInfo.then(
        (android) => (
          android.version.release,
          '${android.manufacturer} ${android.model}',
        ),
      ),
      _ => ('', ''),
    };
    return DeviceDetails(
      appVersion: '${app.version}+${app.buildNumber}',
      platform: defaultTargetPlatform.name.toLowerCase(),
      osVersion: os,
      deviceModel: model,
      locale: WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
    );
  }
}
