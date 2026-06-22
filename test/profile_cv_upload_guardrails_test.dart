import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profile CV upload guardrails', () {
    test('mobile CV picker avoids eager PDF memory loading', () {
      final screen = File(
        'lib/screens/edit_profil_screen.dart',
      ).readAsStringSync();
      final cvSection = screen.substring(
        screen.indexOf('class CvUploaderSection'),
      );

      expect(cvSection, contains('withData: false'));
      expect(cvSection, contains('withReadStream: true'));
      expect(cvSection, contains('ProfileController.maxCvPdfBytes'));
      expect(cvSection, isNot(contains('pickedFile.name')));
    });

    test('repository validates PDF payloads before Storage upload', () {
      final repository = File(
        'lib/services/users/profile_repository.dart',
      ).readAsStringSync();

      expect(repository, contains('static const int maxCvPdfBytes'));
      expect(repository, contains("_pdfHeader"));
      expect(repository, contains("'cvs/\$uid/\$targetFileName'"));
      expect(repository, contains("'application/pdf'"));
      expect(repository, contains("'private, max-age=0, no-transform'"));
      expect(repository, contains('_ensureAuthenticatedOwner(uid)'));
      expect(repository, contains('_validatePdfBytes(uploadBytes)'));
      expect(repository, contains('_validatePdfFile(uploadFile'));
      expect(repository, contains('uploadFile.readAsBytes()'));
      expect(repository, contains('.putData(bytesToUpload, metadata)'));
      expect(repository, contains('_materializePdfStream(pdfReadStream)'));
      expect(repository, isNot(contains("'originalName'")));
      expect(repository, isNot(contains('.putFile(uploadFile')));
    });

    test('storage rules scope CV writes to small generated PDFs', () {
      final rules = File('storage.rules').readAsStringSync();
      final cvRules = rules.substring(
        rules.indexOf('match /cvs/{uid}/{fileName}'),
      );

      expect(rules, contains('function isCvFileName(fileName)'));
      expect(rules, contains("fileName.matches('^cv_[0-9]+\\\\.pdf\$')"));
      expect(rules, contains('request.resource.size <= 5 * 1024 * 1024'));
      expect(rules, contains("request.resource.contentType.matches"));
      expect(rules, contains("application/pdf(;.*)?"));
      expect(rules, contains('function canReadCv(uid)'));
      expect(rules, contains('function isAdminOperator()'));
      expect(rules, contains('request.auth.token.platformAdmin == true'));
      expect(rules, contains('isAdminOperator()'));
      expect(cvRules, contains('allow read: if canReadCv(uid);'));
      expect(cvRules, contains('allow create, update: if signedIn()'));
      expect(
        cvRules,
        contains('allow delete: if signedIn() && request.auth.uid == uid;'),
      );
      expect(cvRules, isNot(contains('allow write:')));
    });
  });
}
