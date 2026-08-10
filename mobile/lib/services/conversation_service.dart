import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/conversation_model.dart';

class ConversationService extends ChangeNotifier {
  static final _logger = Logger('ConversationService');
  static const uuid = Uuid();

  List<ConversationSession> _conversations = [];
  bool _isLoading = false;

  List<ConversationSession> get conversations => _conversations;
  bool get isLoading => _isLoading;

  SupabaseClient? get _supabase {
    final url = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';
    if (url.isEmpty || anonKey.isEmpty || url == '<your-supabase-url>') {
      return null;
    }
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get _isLiveSupabase => _supabase != null && _supabase!.auth.currentSession != null;

  Future<List<ConversationSession>> fetchUserConversations() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_isLiveSupabase) {
        try {
          final userId = _supabase!.auth.currentUser!.id;
          final response = await _supabase!
              .from('conversations')
              .select()
              .eq('user_id', userId)
              .order('updated_at', ascending: false);

          _conversations = (response as List)
              .map((item) => ConversationSession.fromMap(item as Map<String, dynamic>))
              .toList();
        } on PostgrestException catch (pe) {
          _logger.warning('Supabase table error ($pe). Falling back to local storage.');
          await _fetchLocalConversations();
        }
      } else {
        await _fetchLocalConversations();
      }
    } catch (e, st) {
      _logger.warning('Failed to fetch user conversations: $e', e, st);
      await _fetchLocalConversations();
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    return _conversations;
  }

  Future<void> _fetchLocalConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString('local_conversations');
    if (rawJson != null && rawJson.isNotEmpty) {
      final List decoded = json.decode(rawJson) as List;
      _conversations = decoded
          .map((item) => ConversationSession.fromMap(item as Map<String, dynamic>))
          .toList();
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      _conversations = [];
    }
  }

  Future<ConversationSession> createConversation({
    String title = 'New Conversation',
    String mode = 'general',
  }) async {
    final session = ConversationSession(
      id: uuid.v4(),
      userId: _isLiveSupabase ? _supabase!.auth.currentUser!.id : 'local_user',
      title: title,
      mode: mode,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      if (_isLiveSupabase) {
        try {
          await _supabase!.from('conversations').insert(session.toMap());
        } catch (_) {
          await _saveLocalSession(session);
        }
      } else {
        await _saveLocalSession(session);
      }
      _conversations.removeWhere((c) => c.id == session.id);
      _conversations.insert(0, session);
      notifyListeners();
    } catch (e, st) {
      _logger.severe('Error creating conversation session: $e', e, st);
    }

    return session;
  }

  Future<void> _saveLocalSession(ConversationSession session) async {
    final prefs = await SharedPreferences.getInstance();
    _conversations.removeWhere((c) => c.id == session.id);
    _conversations.insert(0, session);
    await prefs.setString(
      'local_conversations',
      json.encode(_conversations.map((c) => c.toMap()).toList()),
    );
  }

  Future<void> saveMessage({
    required String conversationId,
    required String sender,
    required String content,
    required String source,
    String? idempotencyKey,
  }) async {
    final cleanContent = content.trim();
    if (cleanContent.isEmpty) return;

    final key = idempotencyKey ?? uuid.v4();
    final message = PersistedMessage(
      id: uuid.v4(),
      conversationId: conversationId,
      sender: sender,
      content: cleanContent,
      source: source,
      idempotencyKey: key,
      createdAt: DateTime.now(),
    );

    // Update preview title and timestamp locally immediately
    final previewTitle = cleanContent.length > 35
        ? '${cleanContent.substring(0, 35)}...'
        : cleanContent;

    final sessionIdx = _conversations.indexWhere((c) => c.id == conversationId);
    if (sessionIdx >= 0) {
      final existing = _conversations[sessionIdx];
      final updated = ConversationSession(
        id: existing.id,
        userId: existing.userId,
        title: existing.title == 'New Conversation' && sender == 'user'
            ? previewTitle
            : existing.title,
        mode: existing.mode,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now(),
        previewText: cleanContent,
      );
      _conversations[sessionIdx] = updated;
      notifyListeners();
    }

    // Save to local storage as fallback
    await _saveLocalMessage(conversationId, message, key);

    // If Supabase is available, attempt remote save as well
    if (_isLiveSupabase) {
      try {
        await _supabase!.from('messages').upsert(
          message.toMap(),
          onConflict: 'conversation_id,idempotency_key',
        );

        await _supabase!.from('conversations').update({
          'preview_text': cleanContent,
          'title': previewTitle,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', conversationId);
      } catch (e) {
        _logger.fine('Supabase remote message save failed ($e). Saved locally.');
      }
    }
  }

  Future<void> _saveLocalMessage(
    String conversationId,
    PersistedMessage message,
    String key,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final rawMessages = prefs.getString('messages_$conversationId');
    List<Map<String, dynamic>> messages = [];
    if (rawMessages != null && rawMessages.isNotEmpty) {
      messages = (json.decode(rawMessages) as List).cast<Map<String, dynamic>>();
    }

    final existingIdx = messages.indexWhere((m) => m['idempotency_key'] == key);
    if (existingIdx >= 0) {
      messages[existingIdx] = message.toMap();
    } else {
      messages.add(message.toMap());
    }
    await prefs.setString('messages_$conversationId', json.encode(messages));

    // Save local sessions
    await prefs.setString(
      'local_conversations',
      json.encode(_conversations.map((c) => c.toMap()).toList()),
    );
  }

  Future<List<PersistedMessage>> fetchMessages(String conversationId) async {
    if (_isLiveSupabase) {
      try {
        final response = await _supabase!
            .from('messages')
            .select()
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: true);

        final list = (response as List)
            .map((item) => PersistedMessage.fromMap(item as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    final rawMessages = prefs.getString('messages_$conversationId');
    if (rawMessages != null && rawMessages.isNotEmpty) {
      final List decoded = json.decode(rawMessages) as List;
      return decoded
          .map((item) => PersistedMessage.fromMap(item as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<void> updateMode({
    required String conversationId,
    required String mode,
    String? fromMode,
  }) async {
    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0) {
      final existing = _conversations[idx];
      _conversations[idx] = ConversationSession(
        id: existing.id,
        userId: existing.userId,
        title: existing.title,
        mode: mode,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now(),
        previewText: existing.previewText,
      );
      notifyListeners();
    }

    await logEvent(
      conversationId: conversationId,
      eventType: 'mode_changed',
      fromMode: fromMode,
      toMode: mode,
    );

    if (_isLiveSupabase) {
      try {
        await _supabase!.from('conversations').update({
          'mode': mode,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', conversationId);
      } catch (e) {
        _logger.fine('Supabase mode update failed: $e');
      }
    }
  }

  Future<void> logEvent({
    required String conversationId,
    required String eventType,
    String? fromMode,
    String? toMode,
    Map<String, dynamic>? payload,
  }) async {
    final eventMap = {
      'id': uuid.v4(),
      'conversation_id': conversationId,
      'event_type': eventType,
      'from_mode': fromMode,
      'to_mode': toMode,
      'payload': payload ?? {},
      'created_at': DateTime.now().toIso8601String(),
    };

    if (_isLiveSupabase) {
      try {
        await _supabase!.from('conversation_events').insert(eventMap);
      } catch (e) {
        _logger.fine('Supabase event log failed: $e');
      }
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('messages_$conversationId');
      _conversations.removeWhere((c) => c.id == conversationId);
      await prefs.setString(
        'local_conversations',
        json.encode(_conversations.map((c) => c.toMap()).toList()),
      );

      if (_isLiveSupabase) {
        try {
          await _supabase!.from('messages').delete().eq('conversation_id', conversationId);
          await _supabase!.from('conversation_events').delete().eq('conversation_id', conversationId);
          await _supabase!.from('conversations').delete().eq('id', conversationId);
        } catch (_) {}
      }
      notifyListeners();
    } catch (e, st) {
      _logger.warning('Error deleting conversation $conversationId: $e', e, st);
    }
  }
}
