import 'dart:io';

import 'package:adfoot/utils/video_ui_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video share text keeps Adfoot context without captions', () {
    expect(
      VideoUiStrings.buildShareText(
        shareUrl: 'https://example.com/video',
        caption: '',
      ),
      'Regarde cette vidéo sur Adfoot.\nhttps://example.com/video',
    );
  });

  test('video share text trims long captions before sharing', () {
    final caption = '${'a' * 140} fin';
    final text = VideoUiStrings.buildShareText(
      shareUrl: 'https://example.com/video',
      caption: caption,
    );

    expect(text, startsWith('Regarde cette vidéo sur Adfoot : '));
    expect(text, endsWith('\nhttps://example.com/video'));
    expect(text.split('\n').first.length, lessThanOrEqualTo(154));
  });

  test('playback time formatting keeps short and long videos readable', () {
    expect(
      VideoUiStrings.formatPlaybackTime(const Duration(seconds: 9)),
      '00:09',
    );
    expect(
      VideoUiStrings.formatPlaybackTime(
        const Duration(hours: 1, minutes: 2, seconds: 3),
      ),
      '1:02:03',
    );
    expect(
      VideoUiStrings.playbackProgressValue(
        const Duration(seconds: 15),
        const Duration(minutes: 1),
      ),
      '00:15 sur 01:00',
    );
  });

  test('playback speed formatting keeps compact labels', () {
    expect(VideoUiStrings.formatPlaybackSpeed(1.0), '1x');
    expect(VideoUiStrings.formatPlaybackSpeed(1.5), '1.5x');
    expect(VideoUiStrings.formatPlaybackSpeed(0.75), '0.75x');
    expect(VideoUiStrings.selectPlaybackSpeed(1.5), 'Choisir la vitesse 1.5x');
  });

  test('video action and empty-state copy is centralized', () {
    expect(VideoUiStrings.emptyVideoFeedTitle, contains('vidéo'));
    expect(VideoUiStrings.emptyHomeVideoFeedTitle, contains('vidéo'));
    expect(
      VideoUiStrings.emptyHomeVideoFeedPlayerMessage,
      contains('première'),
    );
    expect(
      VideoUiStrings.emptyHomeVideoFeedPlayerMessage,
      contains('Soumettez'),
    );
    expect(VideoUiStrings.noInternetMessage, contains('réseau'));
    expect(VideoUiStrings.videoSearchUnavailable, contains('Réessayez'));
    expect(VideoUiStrings.emptyProfileVideoFeedMessage, contains('profil'));
    expect(VideoUiStrings.likeOffline, contains('hors connexion'));
    expect(VideoUiStrings.videoNotFound, 'Vidéo introuvable.');
    expect(VideoUiStrings.forwardTenSecondsFeedback, '+10s');
    expect(VideoUiStrings.rewindTenSecondsFeedback, '-10s');
  });

  test('sensitive video actions and upload states have centralized copy', () {
    expect(VideoUiStrings.deleteVideoPrimaryAction, contains('Supprimer'));
    expect(VideoUiStrings.deleteVideoSheetMessage, contains('feed'));
    expect(VideoUiStrings.reportVideoPrimaryAction, contains('signalement'));
    expect(VideoUiStrings.reportVideoSheetMessage, contains('identit'));
    expect(VideoUiStrings.addVideo, 'Ajouter');
    expect(VideoUiStrings.addVideoSemantic, contains('Soumettre'));
    expect(VideoUiStrings.uploadProgressTitle, contains('Soumission'));
    expect(VideoUiStrings.uploadVideoButton, contains('Soumettre'));
    expect(VideoUiStrings.uploadSubmittedForReview, contains('revue admin'));
    expect(VideoUiStrings.uploadSubmittedForReview, contains('validation'));
    // Deliberately not "revue admin": at this point the video is still being
    // optimized and has not reached moderation yet. What the message owes the
    // user is somewhere to look and a promise it will come back to them —
    // "it's processing", full stop, is what made an upload feel lost.
    expect(VideoUiStrings.uploadOptimizationPending, contains('profil'));
    expect(VideoUiStrings.uploadOptimizationPending, contains('notifié'));
    expect(VideoUiStrings.uploadReminder, contains('150 Mo'));
    expect(VideoUiStrings.uploadCurrentStepLabel, contains('Étape'));
    expect(VideoUiStrings.uploadStepPrepare, isNotEmpty);
    expect(VideoUiStrings.uploadStepFinalize, isNotEmpty);
  });

  test('video UI copy source stays UTF-8 and readable', () {
    final source = File('lib/utils/video_ui_strings.dart').readAsStringSync();
    final mojibakeMarkers = [
      String.fromCharCode(0x00c3),
      String.fromCharCode(0x00c2),
      String.fromCharCode(0xfffd),
    ];
    final unicodeEscapeMarker = String.fromCharCodes([0x005c, 0x0075]);

    for (final marker in mojibakeMarkers) {
      expect(source, isNot(contains(marker)));
    }
    expect(source, isNot(contains(unicodeEscapeMarker)));
    expect(source, contains('Vérifiez votre réseau'));
    expect(source, contains('Téléversement'));
  });
}
