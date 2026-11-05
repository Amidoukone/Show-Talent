import 'dart:io';
import 'dart:typed_data';

import 'package:adfoot/services/users/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// Un passeport televerse sous un nom .jpg qui n'en est pas un echoue a vie :
// passportViewPage (functions/src/passport_view.ts) deduit le type attendu
// du nom de fichier, puis compare les vrais octets a cette attente. Avant ce
// correctif, uploadPassportPhoto nommait tout `.jpg` sans jamais regarder les
// octets reels -- un screenshot Android (PNG) depose via la galerie passait
// toutes les regles (declarees, jamais verifiees), puis rendait 404 des la
// premiere consultation, sans aucune erreur montree au joueur qui l'avait
// deposee. Ce fichier verifie le detecteur qui empeche desormais ce defaut.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('passport_upload_test');
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeTempFile(String name, List<int> bytes) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(Uint8List.fromList(bytes));
    return file;
  }

  group('ProfileRepository passport image format detection', () {
    test('a real JPEG is detected as jpg', () async {
      final file = await writeTempFile('a.bin', [
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
      ]);

      final extension =
          await ProfileRepository.detectPassportImageExtensionForTests(file);

      expect(extension, 'jpg');
    });

    test('a real PNG is detected as png', () async {
      final file = await writeTempFile('b.bin', [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D,
      ]);

      final extension =
          await ProfileRepository.detectPassportImageExtensionForTests(file);

      expect(extension, 'png');
    });

    test(
        'a PNG renamed with a .jpg-shaped path is still detected by its '
        'real bytes, not by any filename', () async {
      // The whole point of the fix: nothing about this call ever looks at
      // file.path, only at the bytes -- which is what makes the extension
      // the upload method then chooses trustworthy.
      final file = await writeTempFile('looks-like-a-jpg', [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ]);

      final extension =
          await ProfileRepository.detectPassportImageExtensionForTests(file);

      expect(extension, 'png');
    });

    test('an unsupported format is rejected, not silently mislabeled',
        () async {
      // HEIC-ish / arbitrary bytes: neither JPEG nor PNG magic numbers.
      final file = await writeTempFile('c.bin', [
        0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70,
      ]);

      await expectLater(
        ProfileRepository.detectPassportImageExtensionForTests(file),
        throwsA(
          isA<PassportUploadValidationException>().having(
            (e) => e.messageKey,
            'messageKey',
            'profilePassportErrorUnsupportedFormat',
          ),
        ),
      );
    });

    test('an empty file is rejected, not mislabeled as either format',
        () async {
      final file = await writeTempFile('empty.bin', const []);

      await expectLater(
        ProfileRepository.detectPassportImageExtensionForTests(file),
        throwsA(isA<PassportUploadValidationException>()),
      );
    });
  });
}
