import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveKitTokenResponse {
  final String token;
  final String url;
  final String roomName;
  final String participantIdentity;
  final String mode;

  LiveKitTokenResponse({
    required this.token,
    required this.url,
    required this.roomName,
    required this.participantIdentity,
    required this.mode,
  });

  factory LiveKitTokenResponse.fromJson(Map<String, dynamic> json) {
    return LiveKitTokenResponse(
      token: json['token'] as String,
      url: json['url'] as String,
      roomName: json['room_name'] as String,
      participantIdentity: json['participant_identity'] as String,
      mode: json['mode'] as String? ?? 'general',
    );
  }
}

class TokenService {
  final String backendUrl;

  TokenService({
    this.backendUrl = 'http://192.168.1.204:8000',
  });

  /// Fetches a user-scoped LiveKit token from the FastAPI backend endpoint `/v1/livekit/token`
  Future<LiveKitTokenResponse?> fetchToken({
    String mode = 'general',
    String? roomName,
  }) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      if (session?.accessToken != null) {
        headers['Authorization'] = 'Bearer ${session!.accessToken}';
      }

      final uri = Uri.parse('$backendUrl/v1/livekit/token');
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'mode': mode,
          if (roomName != null) 'room_name': roomName,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return LiveKitTokenResponse.fromJson(data);
      } else {
        if (kDebugMode) {
          print('TokenService: HTTP ${response.statusCode} - ${response.body}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('TokenService: Failed to fetch LiveKit token: $e');
      }
      return null;
    }
  }
}
