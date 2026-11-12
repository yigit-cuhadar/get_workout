import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/data/file_backup_queue.dart';
import 'package:get_workout/features/body/data/file_body_photo_store.dart';
import 'package:get_workout/features/body/domain/body_photos.dart';
import 'package:image/image.dart' as img;

void main() {
  const front = 'users/u1/photos/e1/front.jpg';
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('body_files_test');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<String> picture(int width, int height) async {
    final file = File('${root.path}/shot.jpg');
    await file.writeAsBytes(
      img.encodeJpg(img.Image(width: width, height: height)),
    );
    return file.path;
  }

  group('photo store', () {
    late FileBodyPhotoStore store;

    setUp(() {
      store = FileBodyPhotoStore(() async => root);
    });

    test('stores a large picture shrunk at its path', () async {
      final saved = await store.save(front, await picture(2000, 3000));

      expect(saved.valueOrNull, '${root.path}/$front');
      final stored = img.decodeJpg(
        await File('${root.path}/$front').readAsBytes(),
      )!;
      expect((stored.width, stored.height), (1067, FileBodyPhotoStore.maxSide));
    });

    test('keeps a small picture its size', () async {
      await store.save(front, await picture(600, 800));

      final stored = img.decodeJpg(
        await File('${root.path}/$front').readAsBytes(),
      )!;
      expect((stored.width, stored.height), (600, 800));
    });

    test('refuses what is not a picture', () async {
      final text = File('${root.path}/note.txt')..writeAsStringSync('hi');

      expect((await store.save(front, text.path)).isOk, isFalse);
      expect(await store.find([front]), isEmpty);
    });

    test('finds only stored photos and only photo paths', () async {
      await store.saveBytes(front, [1, 2]);

      expect(await store.find([front, 'users/u1/photos/e1/back.jpg']), {
        front: '${root.path}/$front',
      });
      expect(await store.find(['../../etc/passwd']), isEmpty);
      expect((await store.saveBytes('users/../x.jpg', [1])).isOk, isFalse);
    });

    test('delete removes the photos and their empty folder', () async {
      await store.saveBytes(front, [1, 2]);

      expect(
        (await store.delete([front, 'users/u1/photos/e1/back.jpg'])).isOk,
        isTrue,
      );

      expect(
        Directory('${root.path}/users/u1/photos/e1').existsSync(),
        isFalse,
      );
    });
  });

  group('backup queue', () {
    late FileBackupQueue queue;

    setUp(() {
      queue = FileBackupQueue(() async => root);
    });

    test('is empty at first, then holds what was saved', () async {
      expect((await queue.load()).valueOrNull, isEmpty);

      await queue.save({front: BackupTask.upload, 'b': BackupTask.delete});

      expect((await queue.load()).valueOrNull, {
        front: BackupTask.upload,
        'b': BackupTask.delete,
      });
    });

    test('an unreadable file or unknown task reads as nothing', () async {
      final file = File('${root.path}/body_photo_backup.json');
      file.writeAsStringSync('{not json');
      expect((await queue.load()).valueOrNull, isEmpty);

      file.writeAsStringSync('{"a": "upload", "b": "shred", "c": 3}');
      expect((await queue.load()).valueOrNull, {'a': BackupTask.upload});
    });
  });
}
