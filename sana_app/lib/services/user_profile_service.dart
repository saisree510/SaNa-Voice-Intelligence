/// A user's persisted SANA profile — currently just their name and
/// whether they've completed first-run onboarding. Extend this (not
/// [AuthUser]) as more personalization is added; auth identity and
/// profile data are deliberately kept as separate concerns.
class UserProfile {
  const UserProfile({
    required this.userId,
    this.name,
    this.onboardingCompleted = false,
  });

  final String userId;
  final String? name;
  final bool onboardingCompleted;

  UserProfile copyWith({String? name, bool? onboardingCompleted}) => UserProfile(
        userId: userId,
        name: name ?? this.name,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      );
}

/// Persists [UserProfile]s across app restarts, keyed by user id, so a
/// returning user is greeted by name without being asked for it again.
abstract interface class UserProfileService {
  Future<UserProfile?> loadProfile(String userId);

  Future<void> saveProfile(UserProfile profile);
}
