import 'package:adfoot/models/user.dart';
import 'package:adfoot/models/video.dart';
import 'package:adfoot/utils/video_search_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Un joueur decrit par la liste fermee, comme la refonte l'ecrit.
  ///
  /// Le poste en texte libre n'est plus alimente pour un joueur : la recherche
  /// lit `positionCodes` et rend le libelle francais du code
  /// (`ST` -> « Attaquant »), qui est ce qu'un utilisateur tape.
  AppUser buildPlayer({
    String uid = 'player-1',
    List<String> positionCodes = const <String>['ST'],
    String role = 'joueur',
    String? position,
  }) {
    return AppUser.fromMap({
      'uid': uid,
      'nom': 'Joueur Test',
      'email': '$uid@example.com',
      'role': role,
      'photoProfil': '',
      'positionCodes': positionCodes,
      'position': ?position,
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
    final player = buildPlayer(positionCodes: const <String>['ST']);

    expect(matchesUserVideoSearch(player, 'attaquant'), isTrue);
    expect(matchesUserVideoSearch(player, 'buteur'), isTrue);
    expect(matchesVideoSearch(buildVideo(), player, 'attaquant'), isTrue);
  });

  test('matches defensive and goalkeeper synonyms from typed positions', () {
    final defender = buildPlayer(positionCodes: const <String>['CB']);
    final keeper = buildPlayer(positionCodes: const <String>['GK']);

    expect(matchesUserVideoSearch(defender, 'defenseur'), isTrue);
    expect(matchesUserVideoSearch(keeper, 'goalkeeper'), isTrue);
  });

  test('a coach stays searchable by the function they typed', () {
    // Le texte libre n'a pas disparu pour tout le monde : « preparateur
    // physique » n'a pas de code dans la liste fermee des postes de terrain.
    final coach = buildPlayer(
      uid: 'coach-1',
      role: 'coach',
      positionCodes: const <String>[],
      position: 'Préparateur physique',
    );

    expect(matchesUserVideoSearch(coach, 'preparateur'), isTrue);
  });

  test('a stale free-text position no longer answers for a player', () {
    // Un compte anterieur a la bascule peut porter les deux : le poste libre
    // qu'il avait tape, et les codes qu'il a coches depuis. Repondre sur
    // l'ancien ferait remonter un joueur sur un poste qu'il ne joue plus.
    final player = buildPlayer(
      positionCodes: const <String>['GK'],
      position: 'Avant-centre',
    );

    expect(matchesUserVideoSearch(player, 'gardien'), isTrue);
    expect(matchesUserVideoSearch(player, 'attaquant'), isFalse);
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
