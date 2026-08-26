import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  static final _logger = Logger('AuthService');

  bool _isInitialized = false;
  bool _isMock = false;

  // State cache
  bool _isAuthenticated = false;
  String? _userEmail;
  String? _userName;
  String _assistantName = 'Soul';

  bool get isInitialized => _isInitialized;
  bool get isMock => _isMock;
  bool get isAuthenticated => _isAuthenticated;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String get assistantName => _assistantName;
  String? get accessToken => _supabase?.auth.currentSession?.accessToken;
  String? get userId {
    if (!_isAuthenticated) return null;
    if (!_isMock) return _supabase?.auth.currentUser?.id;
    final email = _userEmail?.trim().toLowerCase();
    if (email == null || email.isEmpty) return null;
    final encoded = base64Url.encode(utf8.encode(email)).replaceAll('=', '');
    return 'mock-$encoded';
  }

  bool get hasCompletedOnboarding => _userName != null && _userName!.trim().isNotEmpty;

  SupabaseClient? get _supabase {
    if (_isMock) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String _mockProfileKey(String field, [String? email]) {
    final account = (email ?? _userEmail ?? '').trim().toLowerCase();
    final encoded = base64Url.encode(utf8.encode(account)).replaceAll('=', '');
    return 'mock_${encoded}_$field';
  }

  /// Initialize Supabase or fall back to SharedPreferences local auth state
  Future<void> initialize() async {
    if (_isInitialized) return;

    final url = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';

    if (url.isNotEmpty && anonKey.isNotEmpty && url != '<your-supabase-url>') {
      try {
        _logger.info('Initializing live Supabase client...');
        await Supabase.initialize(
          url: url,
          // ignore: deprecated_member_use
          anonKey: anonKey,
        );
        _isMock = false;

        _supabase?.auth.onAuthStateChange.listen((data) {
          _handleSupabaseAuthState(data.session);
        });

        _handleSupabaseAuthState(_supabase?.auth.currentSession);
      } catch (e, st) {
        _logger.warning('Failed to initialize Supabase. Falling back to local mock mode: $e', e, st);
        await _initMockMode();
      }
    } else {
      _logger.info('No Supabase credentials in .env. Initializing local mock auth mode...');
      await _initMockMode();
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _initMockMode() async {
    _isMock = true;
    final prefs = await SharedPreferences.getInstance();
    _isAuthenticated = prefs.getBool('mock_is_logged_in') ?? false;
    _userEmail = prefs.getString('mock_user_email');
    _userName = prefs.getString(_mockProfileKey('user_name'));
    _assistantName = _brandAssistantName(prefs.getString(_mockProfileKey('assistant_name')));
  }

  void _handleSupabaseAuthState(Session? session) {
    if (session == null) {
      _isAuthenticated = false;
      _userEmail = null;
      _userName = null;
      _assistantName = 'Soul';
    } else {
      _isAuthenticated = true;
      _userEmail = session.user.email;
      final metadata = session.user.userMetadata ?? {};
      _userName = metadata['display_name'] as String? ?? metadata['user_name'] as String?;
      _assistantName = _brandAssistantName(metadata['assistant_name'] as String?);
    }
    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) async {
    if (_isMock) {
      final prefs = await SharedPreferences.getInstance();
      _isAuthenticated = true;
      _userEmail = email;
      _userName = prefs.getString(_mockProfileKey('user_name', email));
      _assistantName = _brandAssistantName(prefs.getString(_mockProfileKey('assistant_name', email)));

      await prefs.setBool('mock_is_logged_in', true);
      await prefs.setString('mock_user_email', email);
      notifyListeners();
      return;
    }

    final response = await _supabase!.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user != null) {
      _handleSupabaseAuthState(response.session);
    }
  }

  Future<void> signUp({required String email, required String password}) async {
    if (_isMock) {
      final prefs = await SharedPreferences.getInstance();
      _isAuthenticated = true;
      _userEmail = email;
      _userName = null; // Forces onboarding on new sign up
      _assistantName = 'Soul';

      await prefs.setBool('mock_is_logged_in', true);
      await prefs.setString('mock_user_email', email);
      await prefs.remove(_mockProfileKey('user_name', email));
      await prefs.setString(_mockProfileKey('assistant_name', email), 'Soul');
      notifyListeners();
      return;
    }

    final response = await _supabase!.auth.signUp(
      email: email,
      password: password,
      data: {
        'assistant_name': 'Soul',
      },
    );

    if (response.user != null) {
      if (response.session != null) {
        _handleSupabaseAuthState(response.session);
      } else {
        throw const AuthException(
          'Account created! Check your email for a confirmation link, or disable "Confirm email" in Supabase Auth Settings.',
        );
      }
    }
  }

  Future<void> resetPassword({required String email}) async {
    if (_isMock) {
      _logger.info('Mock password reset sent for $email');
      return;
    }
    await _supabase!.auth.resetPasswordForEmail(email);
  }

  Future<void> signOut() async {
    if (_isMock) {
      final prefs = await SharedPreferences.getInstance();
      _isAuthenticated = false;
      _userEmail = null;
      _userName = null;
      _assistantName = 'Soul';

      await prefs.setBool('mock_is_logged_in', false);
      notifyListeners();
      return;
    }

    await _supabase!.auth.signOut();
    _isAuthenticated = false;
    _userEmail = null;
    _userName = null;
    _assistantName = 'Soul';
    notifyListeners();
  }

  Future<void> saveProfile({
    required String userName,
    String assistantName = 'Soul',
  }) async {
    final cleanUserName = userName.trim();
    final cleanAssistantName = assistantName.trim().isEmpty ? 'Soul' : assistantName.trim();

    if (_isMock) {
      final prefs = await SharedPreferences.getInstance();
      _userName = cleanUserName;
      _assistantName = cleanAssistantName;

      await prefs.setString(_mockProfileKey('user_name'), cleanUserName);
      await prefs.setString(_mockProfileKey('assistant_name'), cleanAssistantName);
      notifyListeners();
      return;
    }

    await _supabase!.auth.updateUser(
      UserAttributes(
        data: {
          'display_name': cleanUserName,
          'user_name': cleanUserName,
          'assistant_name': cleanAssistantName,
        },
      ),
    );

    _userName = cleanUserName;
    _assistantName = cleanAssistantName;
    notifyListeners();
  }

  String _brandAssistantName(String? value) {
    final name = value?.trim();
    return name == null || name.isEmpty || name.toLowerCase() == 'sana' ? 'Soul' : name;
  }
}
