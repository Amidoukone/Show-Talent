import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/theme/app_theme.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Design system phase 1', () {
    test('app theme keeps Adfoot brand colors', () {
      final theme = AppTheme.light();

      expect(theme.colorScheme.primary, AdColors.brand);
      expect(theme.colorScheme.surface, AdColors.surface);
      expect(theme.scaffoldBackgroundColor, AdColors.surface);
    });

    test('tokens expose stable design primitives', () {
      expect(AdSpacing.md, 16);
      expect(AdRadius.md, 14);
      expect(AdElevation.medium, 6);
    });

    testWidgets('AdButton supports loading state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: AdButton(
              label: 'Continuer',
              loading: true,
              onPressed: null,
            ),
          ),
        ),
      );

      expect(find.text('Continuer'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('AdStatePanel.empty renders title and message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: AdStatePanel.empty(
              title: 'Aucun contenu',
              message: 'Commencez par créer votre premier élément.',
            ),
          ),
        ),
      );

      expect(find.text('Aucun contenu'), findsOneWidget);
      expect(
        find.text('Commencez par créer votre premier élément.'),
        findsOneWidget,
      );
    });
  });
}
