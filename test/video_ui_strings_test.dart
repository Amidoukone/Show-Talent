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
    expect(
      VideoUiStrings.selectPlaybackSpeed(1.5),
      'Choisir la vitesse 1.5x',
    );
  });

  test('video action and empty-state copy is centralized', () {
    expect(VideoUiStrings.emptyVideoFeedTitle, contains('vidéo'));
    expect(VideoUiStrings.emptyHomeVideoFeedTitle, contains('vidéo'));
    expect(
        VideoUiStrings.emptyHomeVideoFeedPlayerMessage, contains('première'));
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
    expect(VideoUiStrings.uploadProgressTitle, contains('Publication'));
    expect(VideoUiStrings.uploadCurrentStepLabel, contains('tape'));
    expect(VideoUiStrings.uploadStepPrepare, isNotEmpty);
    expect(VideoUiStrings.uploadStepFinalize, isNotEmpty);
  });
}
