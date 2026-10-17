/// Le vocabulaire du football, affiché dans la langue de l'interface.
///
/// **Pourquoi ce fichier existe plutôt qu'une méthode dans le modèle.**
/// `lib/models/football_vocabulary.dart` porte déjà `labelFr` et `labelEn`,
/// et c'est là qu'un `label(...)` aurait naturellement sa place. Deux raisons
/// l'en excluent. Ce modèle est recopié à l'identique dans le portail admin
/// et `scripts/check-admin-mobile-contract.ps1` compare le fichier entier,
/// pas seulement les codes : une méthode ajoutée là-bas ferait échouer le
/// contrôle de contrat jusqu'à régénération du miroir. Et elle ferait
/// dépendre un modèle de données d'`AppLocalizations`, que le portail n'a
/// pas. L'extension vit donc ici, le modèle reste intact.
///
/// **La règle, une fois ce fichier en place.** Hors du modèle, on ne lit
/// jamais `labelFr` ni `labelEn` directement. Trois entrées, selon ce dont
/// l'appelant dispose et ce qu'il en fait :
///
/// - [label] quand un `AppLocalizations` est en main, c'est-à-dire partout
///   dans un `build` ;
/// - `labelForCurrentLocale` quand il n'y a aucun contexte, par exemple dans
///   un texte de partage construit depuis un contrôleur ;
/// - `searchLabels` quand il s'agit de faire correspondre une saisie, qui
///   rend les deux langues à la fois.
///
/// Cette dernière mérite son existence propre. Un libellé affiché doit être
/// dans une seule langue, celle de l'interface ; un libellé cherché doit
/// l'être dans toutes, sinon un recruteur passé en anglais perdrait les
/// fiches qu'il trouvait la veille en tapant « gardien ».
library;

import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/l10n/locale_preference.dart';
import 'package:adfoot/models/football_vocabulary.dart';

bool _isEnglish(AppLocalizations l10n) => l10n.localeName == 'en';

/// Vrai si l'un des [labels] contient [query], déjà en minuscules.
///
/// Le pendant de `searchLabels` côté appelant : sans lui, chaque filtre
/// réécrirait la même double boucle, et c'est en la réécrivant qu'on finit
/// par en oublier une langue.
bool matchesAnyLabel(Iterable<String> labels, String query) =>
    labels.any((label) => label.toLowerCase().contains(query));

/// La langue active, résolue sans contexte.
///
/// Passe par [resolveAppLocale] et non par `Get.locale` directement : c'est
/// la même source que celle dont `GetMaterialApp` tire sa locale, donc un
/// libellé construit ici ne peut pas diverger de l'écran qui l'affiche.
bool _currentLocaleIsEnglish() => resolveAppLocale().languageCode == 'en';

extension FootballPositionLabel on FootballPosition {
  String label(AppLocalizations l10n) => _isEnglish(l10n) ? labelEn : labelFr;

  String get labelForCurrentLocale =>
      _currentLocaleIsEnglish() ? labelEn : labelFr;

  /// Les deux langues, pour une mise en correspondance de saisie.
  Iterable<String> get searchLabels => <String>{labelFr, labelEn};
}

extension StrongFootLabel on StrongFoot {
  String label(AppLocalizations l10n) => _isEnglish(l10n) ? labelEn : labelFr;
}

extension ContractStatusLabel on ContractStatus {
  String label(AppLocalizations l10n) => _isEnglish(l10n) ? labelEn : labelFr;
}

extension ClubLevelLabel on ClubLevel {
  String label(AppLocalizations l10n) => _isEnglish(l10n) ? labelEn : labelFr;

  Iterable<String> get searchLabels => <String>{labelFr, labelEn};
}

/// Les catégories d'âge n'ont qu'une forme, `U17` ou `Senior`, identique dans
/// les deux langues.
///
/// L'extension existe quand même, et ce n'est pas de l'indirection gratuite :
/// elle rend la règle sans exception. Un lecteur n'a pas à se demander si
/// `AgeCategory` est le cas particulier où `labelFr` reste permis, et le jour
/// où une catégorie recevrait un libellé traduit, les appelants suivraient
/// sans qu'on ait à les retrouver.
extension AgeCategoryLabel on AgeCategory {
  String label(AppLocalizations l10n) => _isEnglish(l10n) ? labelEn : labelFr;

  Iterable<String> get searchLabels => <String>{labelFr, labelEn};
}
