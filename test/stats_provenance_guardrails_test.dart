import 'dart:io';

import 'package:adfoot/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Qui repond des chiffres d'un dossier.
///
/// Un recruteur qui lit « 28 matchs, 11 buts » a besoin de savoir si le joueur
/// les declare ou si quelqu'un les atteste. Sans cette distinction, une base
/// declarative et une base attestee se ressemblent, et la ressemblance
/// decredibilise les deux.
///
/// Rien n'est stocke pour cela : la provenance **est** l'etat de verification
/// du compte, que seul le callable admin ecrit et que les regles invalident des
/// qu'une statistique bouge.
AppUser _player({
  bool profileVerified = false,
  bool emailVerified = true,
  bool authDisabled = false,
  DateTime? verifiedAt,
}) {
  return AppUser.fromMap(<String, dynamic>{
    'uid': 'p1',
    'nom': 'Awa Traore',
    'role': 'joueur',
    'emailVerified': emailVerified,
    'authDisabled': authDisabled,
    'profileVerified': profileVerified,
    'profileVerificationStatus': profileVerified ? 'verified' : 'unverified',
    'profileVerifiedAt': ?verifiedAt?.toIso8601String(),
  });
}

void main() {
  group('des chiffres disent toujours d ou ils viennent', () {
    test('sans verification, ils sont declares par le joueur', () {
      // L'etat par defaut, et il n'a rien d'infamant : il doit etre dit.
      expect(_player().statsProvenance, StatsProvenance.declared);
    });

    test('un dossier verifie porte une attestation', () {
      expect(
        _player(profileVerified: true).statsProvenance,
        StatsProvenance.attested,
      );
    });

    test('un compte desactive suspend l attestation sans la nier', () {
      // Les chiffres ne deviennent pas faux parce qu'un compte est ferme :
      // le dire ainsi evite de transformer une suspension en accusation.
      // « Actif » se lit ici sur `authDisabled` et `emailVerified`, pas sur
      // `estActif` : c'est ce que dit `isEffectivelyActiveAccount`, et la
      // provenance en decoule plutot que de refaire le test.
      for (final closed in <AppUser>[
        _player(profileVerified: true, emailVerified: false),
        _player(profileVerified: true, authDisabled: true),
      ]) {
        expect(closed.statsProvenance, StatsProvenance.suspended);
      }
    });

    test('le verdict ne change pas avec celui qui regarde', () {
      // Le piege deja rencontre sur « Dossier scout pret » : un jugement porte
      // sur un dossier ne peut pas dependre du lecteur. Les trois champs lus
      // ici vivent sur le document public, donc un visiteur les recoit.
      Map<String, dynamic> publicDoc() => <String, dynamic>{
        'uid': 'p1',
        'nom': 'Awa Traore',
        'role': 'joueur',
        'profileVerified': true,
        'profileVerificationStatus': 'verified',
        'emailVerified': true,
      };

      final asVisitor = AppUser.fromMap(publicDoc());
      final asOwner = AppUser.fromMap(
        publicDoc(),
        privateContact: <String, dynamic>{'phone': '+2250700000000'},
      );

      expect(asVisitor.statsProvenance, asOwner.statsProvenance);
    });
  });

  group('la provenance est derivee, jamais declaree', () {
    test('le titulaire ne peut ecrire la verification qu a false', () {
      // Une attestation qu'on s'accorde a soi-meme n'atteste rien.
      //
      // `profileVerified` est bien dans la liste blanche du titulaire, et il
      // doit y etre : c'est lui qui ecrit l'invalidation quand il modifie un
      // fait footballistique. La garantie n'est donc pas qu'il ne puisse pas
      // y toucher, mais qu'il ne puisse le poser qu'a false, avec la forme
      // complete de la remise a zero.
      final rules = _read('firestore.rules');
      final start = rules.indexOf(
        'function ownerProfileVerificationResetIsValid()',
      );
      expect(start, greaterThan(-1));
      // Le corps est une expression booleenne sans accolade interne : la
      // premiere fermante est donc bien celle de la fonction.
      final body = rules.substring(start, rules.indexOf('}', start));

      expect(body, contains('profileVerified == false'));
      expect(body, contains('profileVerificationStatus == "pending"'));
      expect(
        body,
        contains('profileVerificationInvalidatedBy == request.auth.uid'),
      );
    });

    test('l ecran recopie la regle au lieu de la refaire', () {
      // Deux endroits qui decident finissent par se contredire, et se
      // contredire ici afficherait une garantie que personne n'a donnee.
      final screen = _read('lib/screens/profile_screen.dart');

      expect(screen, contains('user.statsProvenance'));
      expect(screen, contains('_buildStatsProvenance(user)'));
      expect(screen, isNot(contains('user.profileVerified &&')));
    });

    test('les chiffres attestes ne peuvent pas changer en silence', () {
      // Ce qui donne sa valeur a l'attestation : la saison en cours et le
      // parcours sont des champs de confiance, donc les modifier oblige a
      // remettre la verification a zero.
      final rules = _read('firestore.rules');
      final start = rules.indexOf('function ownerProfileTrustFieldsChanged()');
      final trustList = rules.substring(start, rules.indexOf(']', start));

      for (final field in const <String>['currentSeason', 'seasonHistory']) {
        expect(trustList, contains('"$field"'), reason: field);
      }
    });
  });
}
