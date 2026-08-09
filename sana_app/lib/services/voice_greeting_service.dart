import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/errors/app_exception.dart';

/// Synthesizes short one-off lines (currently: the onboarding screen's
/// spoken greeting) via `sana_backend`'s `/api/voice/speak`, which uses
/// the exact same Cartesia voice as the live voice-mode agent — so SANA
/// sounds like the same SANA here as in an actual voice conversation,
/// instead of the browser/device's generic built-in TTS voice.
class VoiceGreetingService {
  Future<Uint8List> synthesize({required String text, required String authToken}) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/api/voice/speak'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $authToken'},
        body: jsonEncode({'text': text}),
      );
    } catch (e) {
      throw NetworkException("Couldn't reach SANA's voice service. Is the backend running?", e);
    }
    if (response.statusCode != 200) {
      throw NetworkException('Voice synthesis returned an error (${response.statusCode}).');
    }
    return response.bodyBytes;
  }
}
