/// Base type for all expected, handled errors in SANA.
///
/// Feature services throw a specific subtype; UI code catches
/// [AppException] and shows [message] rather than a raw stack trace.
/// Extend this as later phases add auth, network, AI, and voice calls.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  /// User-facing, non-technical explanation of what went wrong.
  final String message;

  /// The underlying error/exception, kept for logging — never shown to
  /// the user and never logged if it could contain conversation content.
  final Object? cause;

  @override
  String toString() => message;
}

/// Network/connectivity failures (unreachable backend, timeout, etc.).
final class NetworkException extends AppException {
  const NetworkException([
    String message = "Couldn't reach SANA's servers. Check your connection and try again.",
    Object? cause,
  ]) : super(message, cause: cause);
}

/// Authentication failures (bad credentials, expired session, etc.).
final class AuthException extends AppException {
  const AuthException(super.message, {super.cause});
}

/// Failures from the AI/conversation backend.
final class AiException extends AppException {
  const AiException([
    String message = "SANA couldn't generate a response. Please try again.",
    Object? cause,
  ]) : super(message, cause: cause);
}

/// Failures from Build mode's build-job API (BuildAgent) — starting a
/// build, checking its status, listing/reading files, downloading the
/// artifact.
final class BuildException extends AppException {
  const BuildException([
    String message = 'Something went wrong with the build. Please try again.',
    Object? cause,
  ]) : super(message, cause: cause);
}

/// Failures from microphone/speech-to-text/text-to-speech.
final class VoiceException extends AppException {
  const VoiceException(super.message, {super.cause});
}

/// A required permission (microphone, etc.) was denied.
final class PermissionException extends AppException {
  const PermissionException(super.message, {super.cause});
}

/// Fallback for anything unexpected — still shown as a friendly message
/// rather than crashing the UI.
final class UnknownException extends AppException {
  const UnknownException([
    String message = 'Something went wrong. Please try again.',
    Object? cause,
  ]) : super(message, cause: cause);
}
