import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/data/file_backup_queue.dart';
import 'package:get_workout/features/body/data/file_body_photo_store.dart';
import 'package:get_workout/features/body/domain/body_photos.dart';
import 'package:image/image.dart' as img;

void main() {
  const front = 'users/u1/photos/e1/front-1.jpg';
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('body_files_test');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<String> picture(int width, int height, {img.ExifData? exif}) async {
    final image = img.Image(width: width, height: height);
    if (exif != null) image.exif = exif;
    final file = File('${root.path}/shot.jpg');
    await file.writeAsBytes(img.encodeJpg(image));
    return file.path;
  }

  Future<img.Image> stored(String path) async =>
      img.decodeJpg(await File('${root.path}/$path').readAsBytes())!;

  group('photo store', () {
    late FileBodyPhotoStore store;
    late List<String> excluded;

    setUp(() {
      excluded = [];
      store = FileBodyPhotoStore(
        () async => root,
        excludeFromBackup: (path) async => excluded.add(path),
      );
    });

    test('stores a large picture shrunk, kept out of device backups', () async {
      final saved = await store.save(front, await picture(2000, 3000));

      expect(saved.valueOrNull, '${root.path}/$front');
      final image = await stored(front);
      expect((image.width, image.height), (1067, FileBodyPhotoStore.maxSide));
      expect(excluded, ['${root.path}/users']);
    });

    test('keeps a small picture its size', () async {
      await store.save(front, await picture(600, 800));

      final image = await stored(front);
      expect((image.width, image.height), (600, 800));
    });

    test('strips the metadata, location included', () async {
      final exif = img.ExifData();
      exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(41, 1);
      exif.imageIfd['Make'] = img.IfdValueAscii('PhoneCo');
      final source = await picture(600, 800, exif: exif);
      expect(
        img.decodeJpg(File(source).readAsBytesSync())!.exif.isEmpty,
        isFalse,
      );

      await store.save(front, source);

      expect((await stored(front)).exif.isEmpty, isTrue);
    });

    test('refuses what is not a picture', () async {
      final text = File('${root.path}/note.txt')..writeAsStringSync('hi');

      expect((await store.save(front, text.path)).isOk, isFalse);
      expect(await store.find([front]), isEmpty);
    });

    test('finds only stored photos and only photo paths', () async {
      await store.saveBytes(front, [1, 2]);

      expect(await store.find([front, 'users/u1/photos/e1/back-1.jpg']), {
        front: '${root.path}/$front',
      });
      expect(await store.find(['../../etc/passwd']), isEmpty);
      expect((await store.saveBytes('users/../x-1.jpg', [1])).isOk, isFalse);
      expect(
        (await store.saveBytes('users/u1/photos/e1/front.jpg', [1])).isOk,
        isFalse,
      );
    });

    test('delete removes the photos and their empty folder', () async {
      await store.saveBytes(front, [1, 2]);

      expect(
        (await store.delete([front, 'users/u1/photos/e1/back-1.jpg'])).isOk,
        isTrue,
      );

      expect(
        Directory('${root.path}/users/u1/photos/e1').existsSync(),
        isFalse,
      );
    });

    test("deleteUser removes only that user's photos", () async {
      await store.saveBytes(front, [1]);
      await store.saveBytes('users/u2/photos/e2/back-1.jpg', [1]);

      expect((await store.deleteUser('u1')).isOk, isTrue);

      expect(Directory('${root.path}/users/u1/photos').existsSync(), isFalse);
      expect(Directory('${root.path}/users/u2/photos').existsSync(), isTrue);
      expect((await store.deleteUser('../u2')).isOk, isFalse);
    });

    test(
      'deleteCapture removes the camera file; a missing one is fine',
      () async {
        final shot = await picture(10, 10);

        await store.deleteCapture(shot);
        await store.deleteCapture(shot);

        expect(File(shot).existsSync(), isFalse);
      },
    );
  });

  group('backup queue', () {
    late FileBackupQueue queue;
    late File file;

    setUp(() {
      queue = FileBackupQueue(() async => root, clock: () => DateTime(2026));
      file = File('${root.path}/${FileBackupQueue.fileName}');
    });

    test('is empty at first, then holds what was saved', () async {
      expect((await queue.load()).valueOrNull, isEmpty);

      await queue.save({front: BackupState.upload, 'b': BackupState.uploaded});

      expect((await queue.load()).valueOrNull, {
        front: BackupState.upload,
        'b': BackupState.uploaded,
      });
    });

    test(
      'saves started together are written one at a time, the last wins',
      () async {
        final results = await Future.wait([
          for (var i = 0; i < 20; i++) queue.save({'p$i': BackupState.upload}),
        ]);

        expect(results.every((result) => result.isOk), isTrue);
        expect((await queue.load()).valueOrNull, {'p19': BackupState.upload});
        expect(File('${file.path}.partial').existsSync(), isFalse);
      },
    );

    test(
      'an unreadable file is put aside, never overwritten, and reported',
      () async {
        file.writeAsStringSync('{not json');

        final loaded = await queue.load();

        expect(loaded.isOk, isFalse);
        expect(file.existsSync(), isFalse);
        final aside = File(
          '${file.path}.unreadable-${DateTime(2026).millisecondsSinceEpoch}',
        );
        expect(aside.readAsStringSync(), '{not json');
      },
    );

    test('unknown states are skipped', () async {
      file.writeAsStringSync(
        jsonEncode({
          'version': FileBackupQueue.version,
          'photos': {'a': 'upload', 'b': 'shred', 'c': 3},
        }),
      );

      expect((await queue.load()).valueOrNull, {'a': BackupState.upload});
    });
  });
}
