import 'package:adfoot/videos/domain/resume_position_store.dart';
import 'package:adfoot/videos/video_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quitter Accueil détruit tout le contexte vidéo : `MainScreen` échange le
/// corps de ses onglets au lieu de les garder dans un `IndexedStack`, donc le
/// pager part avec l'écran et emporte chaque contrôleur. Revenir reconstruit
/// un lecteur sur la même vidéo, à l'index que le contrôleur a conservé, et
/// jusqu'ici à 0:00. Une vidéo entamée depuis vingt secondes recommençait, ce
/// qui se lit comme un rechargement même si aucun octet n'a bougé.
///
/// Ces tests tiennent les trois règles qui décident si une position mérite
/// d'être rendue, et le fait que la mémoire survive précisément à la
/// destruction qu'elle compense.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoManager manager;
  late ResumePositionStore store;

  const url = 'https://example.test/videos/clip.mp4';
  const duration = Duration(minutes: 2);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    manager = VideoManager();
    manager.clearResumePositionsForTests();
    store = ResumePositionStore();
  });

  test('une position significative est rendue telle quelle', () {
    manager.rememberResumePosition(
      'home',
      url,
      position: const Duration(seconds: 42),
      duration: duration,
    );

    expect(
      manager.resumePositionFor('home', url),
      const Duration(seconds: 42),
    );
  });

  test('les premières secondes ne sont pas mémorisées', () {
    manager.rememberResumePosition(
      'home',
      url,
      position: const Duration(seconds: 1),
      duration: duration,
    );

    expect(manager.resumePositionFor('home', url), isNull);
  });

  /// Reprendre à 0:28 d'un clip de 0:30 est pire que de le relancer.
  test('la fin du clip efface la position au lieu de la garder', () {
    manager.rememberResumePosition(
      'home',
      url,
      position: const Duration(seconds: 60),
      duration: duration,
    );
    expect(manager.resumePositionFor('home', url), isNotNull);

    manager.rememberResumePosition(
      'home',
      url,
      position: const Duration(minutes: 1, seconds: 58),
      duration: duration,
    );

    expect(manager.resumePositionFor('home', url), isNull);
  });

  test('les contextes ne se mélangent pas', () {
    manager.rememberResumePosition(
      'home',
      url,
      position: const Duration(seconds: 30),
      duration: duration,
    );

    expect(manager.resumePositionFor('profile:abc', url), isNull);
    expect(manager.resumePositionFor('home', url), isNotNull);
  });

  /// Le point entier : `disposeAllForContext` est le moment que cette mémoire
  /// compense, donc l'effacer là reviendrait à perdre la réponse à l'instant
  /// précis où la question se pose.
  test('la position survit à la destruction du contexte', () async {
    manager.rememberResumePosition(
      'home',
      url,
      position: const Duration(seconds: 25),
      duration: duration,
    );

    await manager.disposeAllForContext('home');

    expect(
      manager.resumePositionFor('home', url),
      const Duration(seconds: 25),
      reason:
          'Quitter l\'onglet détruit les contrôleurs ; la position doit être '
          'ce qui reste pour les reconstruire au bon endroit.',
    );
  });

  test('la table reste bornée et évince la plus ancienne', () {
    for (var index = 0; index < 70; index++) {
      store.remember(
        'home',
        'https://example.test/videos/$index.mp4',
        position: const Duration(seconds: 20),
        duration: duration,
      );
    }

    expect(store.length, ResumePositionStore.maxEntries);
    expect(
      store.positionFor('home', 'https://example.test/videos/0.mp4'),
      isNull,
      reason: 'La plus anciennement touchée part en premier.',
    );
    expect(
      store.positionFor('home', 'https://example.test/videos/69.mp4'),
      isNotNull,
    );
  });

  test('revoir une vidéo la remet en fin de file', () {
    for (var index = 0; index < ResumePositionStore.maxEntries; index++) {
      store.remember(
        'home',
        'https://example.test/videos/$index.mp4',
        position: const Duration(seconds: 20),
        duration: duration,
      );
    }

    // La plus ancienne est retouchée, donc ce n'est plus elle la candidate.
    store.remember(
      'home',
      'https://example.test/videos/0.mp4',
      position: const Duration(seconds: 35),
      duration: duration,
    );
    store.remember(
      'home',
      'https://example.test/videos/nouvelle.mp4',
      position: const Duration(seconds: 20),
      duration: duration,
    );

    expect(
      store.positionFor('home', 'https://example.test/videos/0.mp4'),
      const Duration(seconds: 35),
    );
    expect(
      store.positionFor('home', 'https://example.test/videos/1.mp4'),
      isNull,
    );
  });

  test('forgetResumePosition rend la vidéo à son début', () {
    manager.rememberResumePosition(
      'home',
      url,
      position: const Duration(seconds: 30),
      duration: duration,
    );

    manager.forgetResumePosition('home', url);

    expect(manager.resumePositionFor('home', url), isNull);
  });
}
