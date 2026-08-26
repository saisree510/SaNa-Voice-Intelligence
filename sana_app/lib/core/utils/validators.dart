/// Shared form-validation rules for auth screens.
abstract final class Validators {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static bool isValidEmail(String value) => _emailPattern.hasMatch(value.trim());

  static bool isValidPassword(String value) => value.length >= 6;

  /// Returns an error string for a [TextFormField.validator], or null if valid.
  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email';
    if (!isValidEmail(v)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter your password';
    if (!isValidPassword(v)) return 'Password must be at least 6 characters';
    return null;
  }
}
