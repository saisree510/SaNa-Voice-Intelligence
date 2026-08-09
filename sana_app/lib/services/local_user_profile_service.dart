import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_profile_service.dart';

/// [UserProfileService] backed by on-device storage ([SharedPreferences]).
///
/// This is the one piece of V1 auth that's real persistence (not mocked
/// away): it's what makes "close the app, log back in, SANA still knows
/// your name" work without a backend. Swappable later for a Firestore-
/// backed implementation behind the same interface.
class LocalUserProfileService implements UserProfileService {
  String _keyFor(String userId) => 'sana_profile_$userId';

  @override
  Future<UserProfile?> loadProfile(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(userId));
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return UserProfile(
      userId: userId,
      name: map['name'] as String?,
      onboardingCompleted: map['onboardingCompleted'] as bool? ?? false,
    );
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyFor(profile.userId),
      jsonEncode({
        'name': profile.name,
        'onboardingCompleted': profile.onboardingCompleted,
      }),
    );
  }
}
