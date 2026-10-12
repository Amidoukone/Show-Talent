import 'dart:io';

import 'package:adfoot/models/video.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pourquoi la grille d'un profil n'affichait aucune miniature.
///
/// Le document d'une vidéo portait `thumbnailPath` -- un *chemin* Storage,
/// `thumbnails/thumbnail_<id>.jpg` -- et pas `thumbnail`, l'URL qu'un client
/// peut aller chercher. Deux défauts se superposaient, et il faut les deux
/// pour que la tuile affiche une image.
///
/// **Côté serveur :** l'URL n'avait qu'un seul écrivain, `optimizeMp4Video`,
/// après FFmpeg. Cette fonction est déclenchée par l'arrivée de l'objet
/// *vidéo* dans Storage, alors que le client ne téléverse la miniature
/// qu'ensuite : sur un clip léger ou une connexion faible, l'optimiseur
/// atteignait la recherche avant que la miniature existe, n'écrivait rien, et
/// plus personne ne regardait jamais -- aucun déclencheur ne se déclenche pour
/// `thumbnails/`. `finalizeUpload`, qui s'exécute *après* le téléversement de
/// la miniature, ne notait que le chemin.
///
/// **Côté client :** `Video.fromMap` acceptait `thumbnailPath` en dernier
/// recours, produisant une chaîne non vide que rien ne peut charger. La grille
/// prenait donc la branche image avec une valeur condamnée au lieu de rendre
/// son repli -- une résolution réseau ratée par tuile et par reconstruction.
///
/// Le fil s'est vu dans le fil d'actualité ? Non : la miniature n'y est qu'un
/// placeholder fugace avant que la vidéo s'affiche. Dans la grille du profil,
/// c'est la seule chose affichée.
void main() {
  group('une miniature est une URL, jamais un chemin', () {
    test('un chemin Storage seul ne produit aucune miniature', () {
      final video = Video.fromMap({
        'id': 'video-1',
        'videoUrl': 'https://cdn.example.com/video.mp4',
        'thumbnailPath': 'thumbnails/thumbnail_video-1.jpg',
      });

      expect(
        video.thumbnailUrl,
        isEmpty,
        reason: 'une chaîne non vide envoie la tuile chercher une image qui '
            'ne peut pas exister, au lieu de rendre son repli tout de suite',
      );
    });

    test('l\'URL écrite par le serveur est retenue', () {
      final video = Video.fromMap({
        'id': 'video-1',
        'thumbnail': 'https://firebasestorage.googleapis.com/v0/b/b/o/t.jpg',
        'thumbnailPath': 'thumbnails/thumbnail_video-1.jpg',
      });

      expect(
        video.thumbnailUrl,
        'https://firebasestorage.googleapis.com/v0/b/b/o/t.jpg',
      );
    });

    test('les alias historiques restent acceptés, s\'ils sont des URL', () {
      for (final key in ['thumbnail', 'thumbnailUrl', 'thumbnail_url']) {
        final video = Video.fromMap({
          'id': 'video-1',
          key: 'https://cdn.example.com/$key.jpg',
        });
        expect(video.thumbnailUrl, 'https://cdn.example.com/$key.jpg');
      }
    });

    test('un document legacy dont thumbnailPath est déjà une URL passe', () {
      // C'est la forme qui décide, pas le nom du champ.
      final video = Video.fromMap({
        'id': 'video-1',
        'thumbnailPath': 'https://cdn.example.com/legacy.jpg',
      });

      expect(video.thumbnailUrl, 'https://cdn.example.com/legacy.jpg');
    });
  });

  group('deux écrivains résolvent la miniature, pas un seul', () {
    String read(String path) => File(path).readAsStringSync();

    test('la résolution est partagée, donc les deux ne peuvent pas diverger', () {
      final shared = read('functions/src/storage_download_url.ts');
      expect(shared, contains('export async function resolveThumbnailDownloadUrl'));
      expect(shared, contains('ensureDownloadToken'));

      // L'optimiseur, qui peut perdre la course.
      expect(
        read('functions/src/index.ts'),
        contains('resolveThumbnailDownloadUrl('),
      );

      // Et finalizeUpload, qui ne le peut pas : le client téléverse la
      // miniature avant de l'appeler.
      final upload = read('functions/src/upload_session.ts');
      expect(upload, contains('resolveThumbnailDownloadUrl('));
      expect(
        upload,
        contains('{thumbnail: resolvedThumbnailUrl}'),
        reason: 'finalizeUpload doit écrire l\'URL, pas seulement le chemin',
      );
    });

    test('la résolution précède la transaction', () {
      // C'est de l'I/O Storage, et le corps d'une transaction Firestore peut
      // être rejoué.
      final upload = read('functions/src/upload_session.ts');
      final resolve = upload.indexOf('resolvedThumbnailUrl = await');
      final transaction = upload.indexOf('await db.runTransaction', resolve);
      expect(resolve, isNonNegative);
      expect(transaction, greaterThan(resolve));
    });

    test('un script répare les vidéos déjà publiées', () {
      // Rien ne relance optimizeMp4Video, et aucun déclencheur n'existe pour
      // `thumbnails/` : les documents déjà en production restent cassés seuls.
      final repair = read('scripts/repair-video-thumbnails.mjs');
      expect(repair, contains('firebaseStorageDownloadTokens'));
      expect(
        repair,
        contains('Dry run: nothing was written'),
        reason: 'un script de réparation ne commence jamais par écrire',
      );
    });
  });
}
