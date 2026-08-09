import 'dart:convert';

import 'package:http/http.dart' as http;

/// Pulls a human-readable message out of a FastAPI error response.
///
/// FastAPI's own errors look like `{"detail": "message"}`; Pydantic
/// validation errors look like `{"detail": [{"msg": "message", ...}]}`.
/// Falls back to null (caller supplies its own generic message) if the
/// body doesn't match either shape — e.g. a proxy's HTML error page.
String? extractBackendErrorDetail(http.Response response) {
  try {
    final data = jsonDecode(response.body);
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) return first['msg'] as String;
      }
    }
  } catch (_) {
    // Not JSON — fall through to null.
  }
  return null;
}
