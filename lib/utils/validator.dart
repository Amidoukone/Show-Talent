String? validateField(String value, String field) {
  if (value.trim().isEmpty) {
    return "$field est requis"; // Message d’erreur si le champ est vide
  }
  return null; // Aucun problème si le champ est rempli
}

String? validateEmail(String email) {
  RegExp regex = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
  if (email.isEmpty) {
    return "L’e-mail est requis"; // Si l’e-mail est vide
  } else if (!regex.hasMatch(email)) {
    return "Veuillez saisir une adresse e-mail valide"; // Si l’e-mail est incorrect
  }
  return null; // L’e-mail est valide
}

String? validatePassword(String value) {
  if (value.isEmpty) {
    return "Le mot de passe est requis"; // Si le mot de passe est vide
  }
  return null; // Le mot de passe est valide
}
