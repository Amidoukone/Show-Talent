import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/video_search_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppUser buildPlayer({
    String uid = 'player-1',
    String position = 'Avant-centre',
    Map<String, dynamic>? playerProfile,
  }) {
    return AppUser.fromMap({
      'uid': uid,
      'nom': 'Joueur Test',
      'email': '$uid@example.com',
      'role': 'joueur',
      'photoProfil': '',
      'position': position,
      'playerProfile': playerProfile,
      'followers': 0,
      'followings': 0,
      'emailVerified': true,
    });
  }

  Video buildVideo({
    String id = 'video-1',
    String uid = 'player-1',
    String caption = '',
  }) {
    return Video(
      id: id,
      videoUrl: 'https://cdn.example.com/$id.mp4',
      thumbnailUrl: '',
      description: '',
      caption: caption,
      profilePhoto: '',
      uid: uid,
      status: 'ready',
    );
  }

  test('normalizes accents for user-entered position searches', () {
    expect(normalizeVideoSearchText('Défenseur central'), 'defenseur central');
    expect(normalizeVideoSearchText('Réinitialiser'), 'reinitialiser');
  });

  test('matches attacker searches against common forward labels', () {
    final player = buildPlayer(position: 'Avant-centre');

    expect(matchesUserVideoSearch(player, 'attaquant'), isTrue);
    expect(matchesVideoSearch(buildVideo(), player, 'attaquant'), isTrue);
  });

  test('matches defensive and goalkeeper synonyms from advanced profiles', () {
    final defender = buildPlayer(
      position: '',
      playerProfile: {
        'positions': ['Défenseur central'],
      },
    );
    final keeper = buildPlayer(position: 'Gardien de but');

    expect(matchesUserVideoSearch(defender, 'defenseur'), isTrue);
    expect(matchesUserVideoSearch(keeper, 'goalkeeper'), isTrue);
  });

  test('keeps video caption search available when author is unknown', () {
    final video = buildVideo(caption: 'Très bon arrêt du gardien.');

    expect(matchesVideoSearch(video, null, 'gardien'), isTrue);
  });

  test('does not match the technical video status as visible copy', () {
    final video = buildVideo();

    expect(matchesVideoSearch(video, null, 'ready'), isFalse);
  });
}
