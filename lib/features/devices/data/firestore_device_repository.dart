import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../../core/device_details.dart';
import '../domain/device.dart';
import '../domain/device_repository.dart';

/// Records the device in Firestore. The install id is a random one kept in
/// [_directory] (the app's support directory: it survives updates, not a
/// reinstall), as is the last record.
class FirestoreDeviceRepository implements DeviceRepository {
  FirestoreDeviceRepository(
    this._firestore,
    this._details,
    this._directory, {
    Random? random,
  }) : _random = random ?? Random.secure();

  final FirebaseFirestore _firestore;
  final DeviceDetailsSource _details;
  final Future<Directory> Function() _directory;
  final Random _random;

  static final _installId = RegExp(r'^[0-9a-f]{32}$');

  /// The longest each text field may be, as the rules allow.
  static const maxLength = 100;

  Future<File> _file(String name) async =>
      File('${(await _directory()).path}/$name');

  Future<String> _readInstallId() async {
    final file = await _file('install_id');
    if (await file.exists()) {
      final id = (await file.readAsString()).trim();
      if (_installId.hasMatch(id)) return id;
    }
    final id = [
      for (var i = 0; i < 16; i++)
        _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    await file.parent.create(recursive: true);
    await file.writeAsString(id);
    return id;
  }

  static String _cut(String value) =>
      value.length > maxLength ? value.substring(0, maxLength) : value;

  @override
  Future<Result<Device>> current() => guard(() async {
    final installId = await _readInstallId();
    final details = await _details.read();
    return Device(
      installId: installId,
      model: _cut(details.deviceModel),
      platform: details.platform,
      osVersion: _cut(details.osVersion),
      appVersion: _cut(details.appVersion),
    );
  });

  @override
  Future<Result<DeviceRecord?>> lastRecord() => guard(() async {
    final file = await _file('device_record.json');
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    return DeviceRecord(
      uid: json['uid']! as String,
      at: DateTime.fromMillisecondsSinceEpoch(json['atMillis']! as int),
      device: Device(
        installId: json['installId']! as String,
        model: json['model']! as String,
        platform: json['platform']! as String,
        osVersion: json['osVersion']! as String,
        appVersion: json['appVersion']! as String,
      ),
    );
  });

  @override
  Future<Result<void>> record(String uid, Device device, DateTime at) =>
      guard(() async {
        await _firestore
            .doc('users/$uid/devices/${device.installId}')
            .set(toMap(device));
        final file = await _file('device_record.json');
        await file.parent.create(recursive: true);
        await file.writeAsString(
          jsonEncode({
            'uid': uid,
            'atMillis': at.millisecondsSinceEpoch,
            'installId': device.installId,
            'model': device.model,
            'platform': device.platform,
            'osVersion': device.osVersion,
            'appVersion': device.appVersion,
          }),
        );
      }, mapper: mapFirebaseError);

  /// The document, as `isDevice` in `firestore.rules` checks it.
  static Map<String, Object?> toMap(Device device) => {
    'model': device.model,
    'platform': device.platform,
    'osVersion': device.osVersion,
    'appVersion': device.appVersion,
    'lastSeenAt': FieldValue.serverTimestamp(),
  };
}
