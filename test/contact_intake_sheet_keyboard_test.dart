import 'package:adfoot/widgets/contact_intake_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pourquoi on ne voyait plus ce qu'on ecrivait dans le premier contact.
///
/// `conversations` etait vide en production : il n'existait aucune
/// conversation, donc l'ecran ou l'utilisateur butait n'etait pas `ChatScreen`
/// mais la feuille de premier contact, qui a son propre champ de saisie.
///
/// Cette feuille deduisait la hauteur du clavier de sa hauteur maximale **et**
/// la rajoutait en marge basse, avec un plancher de 260 dp applique apres la
/// deduction. L'arithmetique ne tenait donc que si le clavier laissait plus de
/// 260 dp : en dessous, la feuille reclamait plus que l'ecran et son haut --
/// avec le champ de saisie dedans -- passait hors du cadre.
///
/// L'invariant teste ici est le seul qui compte : la feuille et le clavier
/// tiennent ensemble dans l'ecran.
void main() {
  double total({
    required double screenHeight,
    required double keyboardInset,
    required double topPadding,
  }) {
    final maxHeight = ContactIntakeSheet.resolveSheetMaxHeight(
      screenHeight: screenHeight,
      keyboardInset: keyboardInset,
      topPadding: topPadding,
    );
    // L'AnimatedPadding de la feuille ajoute le clavier sous le contenu.
    return maxHeight + keyboardInset;
  }

  group('la feuille et le clavier tiennent dans l\'ecran', () {
    // Geometries reelles : petit, moyen et grand telephone, avec et sans
    // bandeau de suggestions au-dessus du clavier.
    const geometries = <List<double>>[
      [560, 320, 44],
      [560, 300, 44],
      [640, 320, 47],
      [700, 336, 47],
      [812, 346, 44],
      [896, 360, 44],
      // Cas extreme : un clavier qui prend presque tout.
      [560, 420, 44],
      [480, 300, 20],
    ];

    for (final g in geometries) {
      final h = g[0];
      final kb = g[1];
      final top = g[2];

      test('ecran ${h.toInt()} / clavier ${kb.toInt()} : rien ne depasse', () {
        expect(
          total(screenHeight: h, keyboardInset: kb, topPadding: top),
          lessThanOrEqualTo(h),
          reason: 'la feuille reclamait plus de place que l\'ecran : son haut '
              'sortait du cadre, et le champ de saisie avec lui',
        );
      });
    }

    // Le defaut, reproduit explicitement sur la geometrie qui l'a revele.
    test('le plancher de 260 dp depassait, 580 dp pour un cadre de 560', () {
      const screenHeight = 560.0;
      const keyboardInset = 320.0;
      const topPadding = 44.0;

      // Ancienne formule : max(260, 560 - 320 - 44 - 8) = 260, puis + 320.
      const ancien = 260.0 + keyboardInset;
      expect(ancien, greaterThan(screenHeight));

      expect(
        total(
          screenHeight: screenHeight,
          keyboardInset: keyboardInset,
          topPadding: topPadding,
        ),
        lessThanOrEqualTo(screenHeight),
      );
    });
  });

  group('la feuille reste genereuse quand la place existe', () {
    test('clavier ferme : elle occupe l\'ecran moins la barre d\'etat', () {
      final h = ContactIntakeSheet.resolveSheetMaxHeight(
        screenHeight: 812,
        keyboardInset: 0,
        topPadding: 44,
      );

      // Plafonnee a 92 % de l'ecran, comme avant.
      expect(h, lessThanOrEqualTo(812 * 0.92));
      expect(h, greaterThan(700));
    });

    test('clavier ouvert : tout l\'espace restant, pas moins', () {
      final h = ContactIntakeSheet.resolveSheetMaxHeight(
        screenHeight: 812,
        keyboardInset: 346,
        topPadding: 44,
      );

      expect(h, 812 - 346 - 44 - 8);
    });

    test('jamais negatif, meme si le clavier couvre tout', () {
      expect(
        ContactIntakeSheet.resolveSheetMaxHeight(
          screenHeight: 400,
          keyboardInset: 400,
          topPadding: 44,
        ),
        0,
      );
    });
  });
}
