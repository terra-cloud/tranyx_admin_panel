import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web/web.dart' as web;

/// Service for uploading receipt and proof images directly to ImgBB.
class ImgBBService {
  /// Default compile-time API key (injected via `--dart-define=IMGBB_API_KEY=...` in CI/CD)
  static const String envApiKey = String.fromEnvironment(
    'IMGBB_API_KEY',
    defaultValue: 'abfd185244dc224ff987946bc9775bfc',
  );

  /// Dynamically resolves the active ImgBB API key (Environment define -> Firestore config -> Local fallback).
  static Future<String> resolveApiKey(FirebaseFirestore firestore) async {
    if (envApiKey.isNotEmpty && envApiKey != 'abfd185244dc224ff987946bc9775bfc') {
      return envApiKey;
    }
    try {
      final snap = await firestore.collection('config').doc('imgbb').get();
      if (snap.exists && snap.data() != null) {
        final key = snap.data()!['apiKey'] ?? snap.data()!['key'] ?? snap.data()!['api_key'];
        if (key != null && key.toString().trim().isNotEmpty) {
          return key.toString().trim();
        }
      }
    } catch (_) {}
    return envApiKey;
  }

  /// Uploads a selected [web.File] directly to ImgBB and returns the public hosted image URL.
  static Future<String> uploadFile(web.File file, {FirebaseFirestore? firestore, String? explicitApiKey}) async {
    final key = explicitApiKey ?? (firestore != null ? await resolveApiKey(firestore) : envApiKey);
    final completer = Completer<String>();

    final formData = web.FormData();
    formData.append('image', file);

    final xhr = web.XMLHttpRequest();
    xhr.open('POST', 'https://api.imgbb.com/1/upload?key=$key');

    xhr.onLoad.listen((_) {
      if (xhr.status >= 200 && xhr.status < 300) {
        try {
          final res = jsonDecode(xhr.responseText) as Map<String, dynamic>;
          final url = res['data']?['url'] ?? res['data']?['display_url'];
          if (url != null && url.toString().isNotEmpty) {
            completer.complete(url.toString());
            return;
          }
        } catch (e) {
          completer.completeError('Failed to parse ImgBB response: $e');
          return;
        }
      }
      completer.completeError('ImgBB upload error (${xhr.status}): ${xhr.responseText}');
    });

    xhr.onError.listen((_) {
      completer.completeError('Network error connecting to ImgBB API.');
    });

    xhr.send(formData);
    return completer.future;
  }

  /// Uploads a base64 or Data URL image string to ImgBB and returns the hosted image URL.
  static Future<String> uploadBase64(String base64OrDataUrl, {FirebaseFirestore? firestore, String? explicitApiKey}) async {
    final key = explicitApiKey ?? (firestore != null ? await resolveApiKey(firestore) : envApiKey);
    final completer = Completer<String>();

    String cleanBase64 = base64OrDataUrl.trim();
    if (cleanBase64.contains(',')) {
      cleanBase64 = cleanBase64.split(',').last;
    }

    final formData = web.FormData();
    formData.append('image', cleanBase64.toJS);

    final xhr = web.XMLHttpRequest();
    xhr.open('POST', 'https://api.imgbb.com/1/upload?key=$key');

    xhr.onLoad.listen((_) {
      if (xhr.status >= 200 && xhr.status < 300) {
        try {
          final res = jsonDecode(xhr.responseText) as Map<String, dynamic>;
          final url = res['data']?['url'] ?? res['data']?['display_url'];
          if (url != null && url.toString().isNotEmpty) {
            completer.complete(url.toString());
            return;
          }
        } catch (e) {
          completer.completeError('Failed to parse ImgBB response: $e');
          return;
        }
      }
      completer.completeError('ImgBB upload error (${xhr.status}): ${xhr.responseText}');
    });

    xhr.onError.listen((_) {
      completer.completeError('Network error connecting to ImgBB API.');
    });

    xhr.send(formData);
    return completer.future;
  }
}
