String? validateGmail(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter your email';
  }
  final gmailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@gmail\.com$');
  if (!gmailRegex.hasMatch(value)) {
    return 'Please enter a valid Gmail address';
  }
  return null;
}
