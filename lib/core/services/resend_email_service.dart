import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web/web.dart' as web;

/// Transactional Email Service powered by Resend REST API
class ResendEmailService {
  ResendEmailService._();

  /// Default compile-time API key (injected via `--dart-define=RESEND_API_KEY=...`)
  static const String envApiKey = String.fromEnvironment('RESEND_API_KEY');

  /// Default compile-time sender address (injected via `--dart-define=RESEND_FROM_EMAIL=...`)
  static const String envSenderEmail = String.fromEnvironment(
    'RESEND_FROM_EMAIL',
    defaultValue: 'Tranyx Support <onboarding@resend.dev>',
  );

  /// Dynamically resolves the active Resend API key (Environment define -> Firestore settings -> empty).
  static Future<String> resolveApiKey(FirebaseFirestore firestore) async {
    if (envApiKey.isNotEmpty) {
      return envApiKey;
    }
    try {
      final snap = await firestore.collection('system_config').doc('settings').get();
      if (snap.exists && snap.data() != null) {
        final key = snap.data()!['resendApiKey'] ?? snap.data()!['resend_api_key'];
        if (key != null && key.toString().trim().isNotEmpty) {
          return key.toString().trim();
        }
      }
    } catch (_) {}
    return envApiKey;
  }

  /// Dynamically resolves the sender email address.
  static Future<String> resolveSenderEmail(FirebaseFirestore firestore) async {
    try {
      final snap = await firestore.collection('system_config').doc('settings').get();
      if (snap.exists && snap.data() != null) {
        final sender = snap.data()!['resendFromEmail'] ?? snap.data()!['senderEmail'];
        if (sender != null && sender.toString().trim().isNotEmpty) {
          return sender.toString().trim();
        }
      }
    } catch (_) {}
    return envSenderEmail.isNotEmpty ? envSenderEmail : 'Tranyx Support <onboarding@resend.dev>';
  }

  /// Sends a transactional HTML email directly via Resend REST API.
  static Future<bool> sendEmail({
    required String recipientEmail,
    required String subject,
    required String htmlContent,
    String? textContent,
    String? senderEmail,
    String? replyTo,
    FirebaseFirestore? firestore,
  }) async {
    if (recipientEmail.isEmpty || !recipientEmail.contains('@')) {
      print('[ResendEmailService] Skipping send: Invalid recipient email ($recipientEmail)');
      return false;
    }

    final key = firestore != null ? await resolveApiKey(firestore) : envApiKey;
    if (key.isEmpty) {
      print('[ResendEmailService] No API key configured for Resend.');
      return false;
    }

    final fromAddress = senderEmail ?? (firestore != null ? await resolveSenderEmail(firestore) : 'Tranyx No-Reply <onboarding@resend.dev>');
    final completer = Completer<bool>();

    try {
      final xhr = web.XMLHttpRequest();
      xhr.open('POST', 'https://api.resend.com/emails', true);
      xhr.setRequestHeader('Authorization', 'Bearer $key');
      xhr.setRequestHeader('Content-Type', 'application/json');

      final payload = jsonEncode({
        'from': fromAddress,
        'to': [recipientEmail.trim()],
        'subject': subject,
        'html': htmlContent,
        if (replyTo != null && replyTo.isNotEmpty) 'reply_to': replyTo,
        if (textContent != null && textContent.isNotEmpty) 'text': textContent,
      });

      xhr.onLoad.listen((_) {
        if (xhr.status >= 200 && xhr.status < 300) {
          print('[ResendEmailService] ✅ Email dispatched successfully to $recipientEmail (${xhr.responseText})');
          completer.complete(true);
        } else {
          print('[ResendEmailService] ⚠️ Resend API error (${xhr.status}): ${xhr.responseText}');
          completer.complete(false);
        }
      });

      xhr.onError.listen((_) {
        print('[ResendEmailService] ❌ Network error connecting to Resend API.');
        completer.complete(false);
      });

      xhr.send(payload.toJS);
    } catch (e) {
      print('[ResendEmailService] Exception sending email: $e');
      return false;
    }

    return completer.future;
  }
}
