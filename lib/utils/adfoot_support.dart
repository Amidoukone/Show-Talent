import 'package:url_launcher/url_launcher.dart';

/// Les coordonnées de l'agence Adfoot, en un seul endroit.
///
/// Elles vivaient en constantes privées dans `setting_screen.dart`, où seul
/// l'écran Outils pouvait les lire. Dès qu'un second écran a eu besoin de
/// renvoyer l'utilisateur vers l'agence — le plafond de publication vidéo —
/// la seule alternative était de recopier le numéro, c'est-à-dire de créer
/// deux vérités pour un numéro de téléphone.
class AdfootSupport {
  AdfootSupport._();

  static const String phoneDisplay = '+223 70 45 33 45';
  static const String whatsappNumber = '22370453345';
  static const String website = 'adfoot.org';

  static Uri get whatsappUri => Uri.parse('https://wa.me/$whatsappNumber');

  /// Ouvre la conversation WhatsApp de l'agence.
  ///
  /// Renvoie `false` quand rien n'a pu être ouvert — WhatsApp absent, intent
  /// refusé — pour que l'appelant affiche le numéro en clair plutôt que de
  /// laisser l'utilisateur devant un bouton sans effet.
  static Future<bool> openWhatsApp() async {
    try {
      return await launchUrl(
        whatsappUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
