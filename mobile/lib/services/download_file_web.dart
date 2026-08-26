// ignore_for_file: deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

Future<bool> downloadFile(Uri url, String filename) async {
  try {
    final request = await html.HttpRequest.request(
      url.toString(),
      method: 'GET',
      responseType: 'arraybuffer',
    );
    if (request.status != 200 || request.response is! ByteBuffer) return false;

    final bytes = Uint8List.view(request.response as ByteBuffer);
    final blob = html.Blob([bytes], 'application/zip');
    final objectUrl = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: objectUrl)
      ..download = filename
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(objectUrl);
    return true;
  } catch (_) {
    return false;
  }
}
