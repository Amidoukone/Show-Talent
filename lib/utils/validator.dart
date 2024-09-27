String? validateField(String value, String field) {
  if (value.trim().isEmpty) {
    return "$field is required"; // Message d'erreur si le champ est vide
  }
  return null; // Aucun problème si le champ est rempli
}

String? validateEmail(String email) {
  RegExp regex = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
  if (email.isEmpty) {
    return "Email is required"; // Si l'email est vide
  } else if (!regex.hasMatch(email)) {
    return "Please enter a valid email address"; // Si l'email est incorrect
  }
  return null; // L'email est valide
}

String? validatePassword(String value) {
  if (value.isEmpty) {
    return "Password is required"; // Si le mot de passe est vide
  }
  return null; // Le mot de passe est valide
}
