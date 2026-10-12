import 'dart:io';

import 'package:adfoot/widgets/contact_intake_sheet.dart';
import 'package:flutter/material.dart';
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

  group('un seul widget souleve la feuille au-dessus du clavier', () {
    // Ce que fait `GetModalBottomSheetRoute.buildPage`, textuellement :
    //   Padding(padding: EdgeInsets.only(bottom: viewInsets.bottom), child: ...)
    // La route possede donc deja l'inset du clavier. Une feuille qui le
    // rajoute est soulevee de deux hauteurs de clavier : son bas flotte une
    // hauteur de clavier au-dessus du clavier, et ce qui lui reste est ecrase
    // d'autant, titre et champ de saisie compris.
    const double screenHeight = 812;
    const double keyboard = 346;
    const double topPadding = 44;

    /// Monte la composition route + feuille et rend le haut, le bas et la
    /// contrainte de hauteur de la feuille, en coordonnees ecran.
    Future<({double top, double bottom, double maxHeight})> layout(
      WidgetTester tester, {
      required bool sheetAddsItsOwnKeyboardPadding,
      required double contentHeight,
    }) async {
      final sheetKey = GlobalKey();

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, screenHeight);
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      tester.view.viewPadding = const FakeViewPadding(top: topPadding);
      tester.view.padding = const FakeViewPadding(top: topPadding);
      addTearDown(tester.view.reset);

      final maxHeight = ContactIntakeSheet.resolveSheetMaxHeight(
        screenHeight: screenHeight,
        keyboardInset: keyboard,
        topPadding: topPadding,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final insets = MediaQuery.of(context).viewInsets.bottom;
              Widget sheet = ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SizedBox(key: sheetKey, height: contentHeight),
              );
              if (sheetAddsItsOwnKeyboardPadding) {
                sheet = Padding(
                  padding: EdgeInsets.only(bottom: insets),
                  child: sheet,
                );
              }

              // La route, reproduite : `Padding(bottom: viewInsets)` par
              // dessus le layout qui colle la feuille en bas de ce qui reste.
              return Padding(
                padding: EdgeInsets.only(bottom: insets),
                child: Align(alignment: Alignment.bottomCenter, child: sheet),
              );
            },
          ),
        ),
      );

      final box = sheetKey.currentContext!.findRenderObject()! as RenderBox;
      final top = box.localToGlobal(Offset.zero).dy;
      return (top: top, bottom: top + box.size.height, maxHeight: maxHeight);
    }

    testWidgets('le defaut reproduit : un vide d\'une hauteur de clavier', (
      tester,
    ) async {
      final r = await layout(
        tester,
        sheetAddsItsOwnKeyboardPadding: true,
        contentHeight: 520,
      );

      // Le bas de la feuille flotte une hauteur de clavier au-dessus du
      // clavier : le vide noir des captures, a travers lequel on voit la
      // liste des utilisateurs.
      expect(r.bottom, lessThanOrEqualTo(screenHeight - 2 * keyboard + 0.5));
      // Et ce qui lui reste est tres en dessous de ce que sa propre
      // contrainte lui accordait : le haut du formulaire sort du cadre.
      expect(r.bottom - r.top, lessThan(r.maxHeight / 3));
    });

    testWidgets('corrige : la feuille est posee sur le clavier', (
      tester,
    ) async {
      final r = await layout(
        tester,
        sheetAddsItsOwnKeyboardPadding: false,
        contentHeight: 520,
      );

      expect(r.bottom, moreOrLessEquals(screenHeight - keyboard, epsilon: 0.5));
      expect(r.top, greaterThanOrEqualTo(topPadding));
      expect(r.bottom - r.top, moreOrLessEquals(r.maxHeight, epsilon: 0.5));
    });
  });

  group('la feuille laisse l\'inset du clavier a sa route', () {
    final source = File(
      'lib/widgets/contact_intake_sheet.dart',
    ).readAsStringSync();

    test('elle ne pose pas de marge de clavier elle-meme', () {
      expect(
        source.contains('EdgeInsets.only(bottom: bottomInset)'),
        isFalse,
        reason: 'GetModalBottomSheetRoute pose deja cette marge ; la poser '
            'ici soulevait la feuille de deux hauteurs de clavier',
      );
    });

    test('un seul SafeArea reclame le bas', () {
      // Le pied de page garde le sien (`minimum`), la racine y renonce.
      final rootStart = source.indexOf('return SafeArea(');
      expect(rootStart, isNonNegative);
      expect(
        source.substring(rootStart, rootStart + 120),
        contains('bottom: false'),
      );
    });

    test('elle n\'est ouverte que par Get.bottomSheet', () {
      // L'invariant ci-dessus ne tient que tant que c'est vrai : la route de
      // `showModalBottomSheet` n'ajoute aucune marge de clavier, et une
      // feuille ouverte par elle devrait reposer la sienne.
      var callSites = 0;
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('contact_intake_sheet.dart'));

      for (final file in files) {
        final text = file.readAsStringSync();
        for (var index = text.indexOf('ContactIntakeSheet(');
            index >= 0;
            index = text.indexOf('ContactIntakeSheet(', index + 1)) {
          callSites++;
          final before = text.substring(index < 400 ? 0 : index - 400, index);
          expect(
            before.contains('Get.bottomSheet'),
            isTrue,
            reason: 'ouverte depuis ${file.path}, cette feuille aurait besoin '
                'de sa propre marge de clavier',
          );
        }
      }

      expect(callSites, greaterThan(0));
    });
  });
}
