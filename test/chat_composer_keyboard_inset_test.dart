import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pourquoi on ne voyait plus ce qu'on ecrivait, clavier ouvert.
///
/// `ChatScreen` empile, de haut en bas : la banniere de contexte du premier
/// contact, l'`Expanded` qui porte la liste des messages, puis le composeur.
/// La banniere et le composeur ont une hauteur fixe ; seul l'`Expanded`
/// absorbe la difference. Clavier ouvert, `resizeToAvoidBottomInset` retire la
/// hauteur du clavier du corps, et il ne reste qu'environ 280 dp sur un
/// telephone courant.
///
/// Depliee, la banniere fait ~200 dp -- titre, contexte, motif, suivi
/// d'agence, retour participant, bouton « Donner un retour » -- et **toutes**
/// les conversations de cette application en ont une, puisqu'elles passent
/// toutes par le premier contact guide. La banniere et le composeur prenaient
/// donc l'essentiel de la place : la colonne debordait, l'`Expanded` tombait a
/// zero et le composeur sortait du cadre, sous le clavier.
///
/// Ces tests mesurent la composition, pas l'ecran complet : monter
/// `ChatScreen` demande Firebase, GetX et quatre controleurs. Ce qui se casse
/// est la contrainte de hauteur, et c'est exactement ce qui est reproduit.
void main() {
  const double appBarHeight = 56;
  const double composerHeight = 60;
  const double systemBar = 48;

  /// Monte la forme de ChatScreen a une taille d'ecran et une hauteur de
  /// clavier donnees.
  ///
  /// Les insets sont poses sur la *vue* de test, pas sur un `MediaQueryData`
  /// fabrique a la main : c'est la vue qui les fournit au framework sur un
  /// vrai appareil, et `padding` n'y est pas independant de `viewInsets` --
  /// le clavier recouvre la barre systeme, donc `padding.bottom` retombe a
  /// zero. Un test qui poserait les deux a leur valeur pleine decrirait un
  /// etat qui n'existe nulle part, et ferait croire a un double comptage de
  /// l'inset du bas qui n'a pas lieu.
  Future<({double listHeight, double composerBottom, Object? exception})>
  layout(
    WidgetTester tester, {
    required double screenHeight,
    required double keyboard,
    required double bannerHeight,
  }) async {
    final listKey = GlobalKey();
    final composerKey = GlobalKey();
    const dpr = 1.0;

    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = Size(360, screenHeight) * dpr;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
    tester.view.viewPadding = const FakeViewPadding(bottom: systemBar * dpr);
    // Ce que fait le moteur : la barre systeme disparait derriere le clavier.
    tester.view.padding = FakeViewPadding(
      bottom: (systemBar - keyboard).clamp(0.0, systemBar) * dpr,
    );
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(toolbarHeight: appBarHeight),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                SizedBox(height: bannerHeight),
                Expanded(child: SizedBox.expand(key: listKey)),
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(key: composerKey, height: composerHeight),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final listBox = listKey.currentContext!.findRenderObject()! as RenderBox;
    final composerBox =
        composerKey.currentContext!.findRenderObject()! as RenderBox;

    return (
      listHeight: listBox.size.height,
      composerBottom: composerBox
          .localToGlobal(Offset(0, composerBox.size.height))
          .dy,
      // Un debordement de colonne est signale par le moteur de rendu, pas par
      // une mesure : il faut le consommer pour que le test ne le compte pas
      // comme un echec inattendu.
      exception: tester.takeException(),
    );
  }

  group('la conversation garde de la place pour le texte en cours', () {
    // Le defaut, reproduit : 560 dp d'ecran, un clavier de 320 dp avec son
    // bandeau de suggestions, une banniere depliee de 200 dp.
    testWidgets('banniere depliee : la colonne deborde et le composeur sort', (
      tester,
    ) async {
      final result = await layout(
        tester,
        screenHeight: 560,
        keyboard: 320,
        bannerHeight: 200,
      );

      expect(
        result.exception.toString(),
        contains('overflowed'),
        reason: 'la banniere et le composeur ne tiennent pas dans ce qui '
            'reste du corps',
      );
      expect(result.listHeight, 0);
      // Sous le bord superieur du clavier : hors de vue.
      expect(result.composerBottom, greaterThan(560 - 320));
    });

    // Repliee a une ligne, la banniere rend ~160 dp a la conversation.
    testWidgets('banniere repliee : le composeur tient et la liste respire', (
      tester,
    ) async {
      final result = await layout(
        tester,
        screenHeight: 560,
        keyboard: 320,
        bannerHeight: 36,
      );

      expect(result.exception, isNull);
      expect(result.composerBottom, lessThanOrEqualTo(560 - 320));
      expect(result.listHeight, greaterThan(50));
    });

    // Clavier ferme, la banniere depliee est tout a fait a sa place.
    testWidgets('clavier ferme : la banniere depliee ne gene personne', (
      tester,
    ) async {
      final result = await layout(
        tester,
        screenHeight: 560,
        keyboard: 0,
        bannerHeight: 200,
      );

      expect(result.exception, isNull);
      expect(result.composerBottom, lessThanOrEqualTo(560));
      expect(result.listHeight, greaterThan(180));
    });

    // Et le composeur garde l'inset du bas quand il n'y a pas de clavier :
    // c'est son SafeArea, desormais seul proprietaire, qui s'en charge.
    testWidgets('clavier ferme : le composeur degage la barre systeme', (
      tester,
    ) async {
      final result = await layout(
        tester,
        screenHeight: 560,
        keyboard: 0,
        bannerHeight: 36,
      );

      expect(result.composerBottom, 560 - systemBar);
    });
  });

  group('un seul widget possede l\'inset du bas', () {
    test('ChatScreen laisse le bas au composeur', () {
      final screen = File('lib/screens/chat_screen.dart').readAsStringSync();
      final bodyStart = screen.indexOf('body: DecoratedBox(');
      expect(bodyStart, isNonNegative);

      expect(
        screen.substring(bodyStart, bodyStart + 1200),
        contains('bottom: false'),
        reason: 'le SafeArea du corps posait sa marge sous la barre de '
            'saisie, qui a deja la sienne',
      );

      final widgets = File(
        'lib/screens/chat_screen_widgets.dart',
      ).readAsStringSync();
      final barStart = widgets.indexOf('class MessageInputBar');
      expect(barStart, isNonNegative);
      expect(
        widgets.substring(barStart, barStart + 900),
        contains('minimum: const EdgeInsets.only(bottom: 8)'),
        reason: 'le composeur reste le seul proprietaire de l\'inset du bas',
      );
    });

    test('la banniere se replie pendant la frappe', () {
      final screen = File('lib/screens/chat_screen.dart').readAsStringSync();

      expect(screen, contains('Widget _buildCollapsedGuidedContextBanner('));

      final start = screen.indexOf(
        'Widget _buildGuidedContextBanner(Conversation? conversation) {',
      );
      expect(start, isNonNegative);
      final body = screen.substring(start, start + 700);

      expect(
        body,
        contains('MediaQuery.of(context).viewInsets.bottom > 0'),
        reason: 'la hauteur fixe de la banniere est ce qui chassait le '
            'composeur du cadre',
      );
      expect(
        body,
        contains('_buildCollapsedGuidedContextBanner(conversation)'),
      );
    });
  });
}
