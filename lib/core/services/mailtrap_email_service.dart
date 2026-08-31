import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web/web.dart' as web;

/// Transactional Email Service powered by Mailtrap Email Sending REST API
class MailtrapEmailService {
  MailtrapEmailService._();

  /// Default compile-time API token (injected via `--dart-define=MAIL_TRAP_TOKEN=...`)
  static const String envApiToken = String.fromEnvironment(
    'MAIL_TRAP_TOKEN',
    defaultValue: String.fromEnvironment(
      'MAILTRAP_TOKEN',
      defaultValue: String.fromEnvironment('MAILTRAP_API_KEY'),
    ),
  );

  /// Default compile-time sender email (injected via `--dart-define=MAIL_TRAP_FROM_EMAIL=...`)
  static const String envSenderEmail = String.fromEnvironment(
    'MAIL_TRAP_FROM_EMAIL',
    defaultValue: String.fromEnvironment(
      'MAILTRAP_FROM_EMAIL',
      defaultValue: 'support@tranyx.com',
    ),
  );

  /// Default compile-time sender name (injected via `--dart-define=MAIL_TRAP_FROM_NAME=...`)
  static const String envSenderName = String.fromEnvironment(
    'MAIL_TRAP_FROM_NAME',
    defaultValue: 'Tranyx Support',
  );

  /// Dynamically resolves the active Mailtrap API token (Environment define -> system_config settings -> fallback).
  static Future<String> resolveApiToken([FirebaseFirestore? firestore]) async {
    if (envApiToken.isNotEmpty) {
      return envApiToken;
    }
    for (final db in [FirebaseFirestore.instance, firestore]) {
      if (db == null) continue;
      try {
        final snap = await db.collection('system_config').doc('settings').get();
        if (snap.exists && snap.data() != null) {
          final data = snap.data()!;
          final token = data['mailtrapToken'] ??
              data['mail_trap_token'] ??
              data['mailtrapApiKey'] ??
              data['mail_trap_api_key'];
          if (token != null && token.toString().trim().isNotEmpty) {
            return token.toString().trim();
          }
        }
      } catch (_) {}
    }
    return envApiToken;
  }

  /// Dynamically resolves the sender email address.
  static Future<String> resolveSenderEmail([FirebaseFirestore? firestore]) async {
    for (final db in [FirebaseFirestore.instance, firestore]) {
      if (db == null) continue;
      try {
        final snap = await db.collection('system_config').doc('settings').get();
        if (snap.exists && snap.data() != null) {
          final sender = snap.data()!['mailtrapFromEmail'] ??
              snap.data()!['mail_trap_from_email'] ??
              snap.data()!['senderEmail'];
          if (sender != null && sender.toString().trim().isNotEmpty) {
            return sender.toString().trim();
          }
        }
      } catch (_) {}
    }
    return envSenderEmail.isNotEmpty ? envSenderEmail : 'support@tranyx.com';
  }

  /// Dynamically resolves the sender display name.
  static Future<String> resolveSenderName([FirebaseFirestore? firestore]) async {
    for (final db in [FirebaseFirestore.instance, firestore]) {
      if (db == null) continue;
      try {
        final snap = await db.collection('system_config').doc('settings').get();
        if (snap.exists && snap.data() != null) {
          final name = snap.data()!['mailtrapFromName'] ??
              snap.data()!['mail_trap_from_name'] ??
              snap.data()!['senderName'];
          if (name != null && name.toString().trim().isNotEmpty) {
            return name.toString().trim();
          }
        }
      } catch (_) {}
    }
    return envSenderName.isNotEmpty ? envSenderName : 'Tranyx Support';
  }

  /// Extracts structured name and email from a formatted address string.
  /// Example: `"Tranyx Support <support@tranyx.com>"` -> name: "Tranyx Support", email: "support@tranyx.com"
  static Map<String, String> parseAddress(String address, {String fallbackName = 'Tranyx Support'}) {
    final trimmed = address.trim();
    final match = RegExp(r'^(.*?)\s*<([^>]+)>$').firstMatch(trimmed);
    if (match != null) {
      final name = match.group(1)?.trim() ?? fallbackName;
      final email = match.group(2)?.trim() ?? trimmed;
      return {
        'name': name.isNotEmpty ? name : fallbackName,
        'email': email,
      };
    }
    return {
      'name': fallbackName,
      'email': trimmed,
    };
  }

  /// Sends a transactional HTML email directly via Mailtrap Sending REST API.
  static Future<bool> sendEmail({
    required String recipientEmail,
    required String subject,
    required String htmlContent,
    String? recipientName,
    String? textContent,
    String? senderEmail,
    String? senderName,
    String? category,
    FirebaseFirestore? firestore,
  }) async {
    if (recipientEmail.isEmpty || !recipientEmail.contains('@')) {
      print('[MailtrapEmailService] Skipping send: Invalid recipient email ($recipientEmail)');
      return false;
    }

    final token = firestore != null ? await resolveApiToken(firestore) : envApiToken;
    if (token.isEmpty) {
      print('[MailtrapEmailService] No API token configured for Mailtrap.');
      return false;
    }

    final resolvedFromEmail = senderEmail ?? (firestore != null ? await resolveSenderEmail(firestore) : envSenderEmail);
    final resolvedFromName = senderName ?? (firestore != null ? await resolveSenderName(firestore) : envSenderName);
    final fromParsed = parseAddress(resolvedFromEmail, fallbackName: resolvedFromName);

    final completer = Completer<bool>();

    try {
      final xhr = web.XMLHttpRequest();
      xhr.open('POST', 'https://send.api.mailtrap.io/api/send', true);
      xhr.setRequestHeader('Authorization', 'Bearer $token');
      xhr.setRequestHeader('Content-Type', 'application/json');

      final toEntry = <String, dynamic>{
        'email': recipientEmail.trim(),
        if (recipientName != null && recipientName.trim().isNotEmpty) 'name': recipientName.trim(),
      };

      final payloadMap = {
        'from': {
          'email': fromParsed['email'],
          'name': fromParsed['name'],
        },
        'to': [toEntry],
        'subject': subject,
        'html': htmlContent,
        if (textContent != null && textContent.isNotEmpty) 'text': textContent,
        'category': category ?? 'Support Ticket Notifications',
      };

      final payload = jsonEncode(payloadMap);

      xhr.onLoad.listen((_) {
        if (xhr.status >= 200 && xhr.status < 300) {
          print('[MailtrapEmailService] ✅ Email dispatched successfully to $recipientEmail (${xhr.responseText})');
          completer.complete(true);
        } else {
          print('[MailtrapEmailService] ⚠️ Mailtrap API error (${xhr.status}): ${xhr.responseText}');
          completer.complete(false);
        }
      });

      xhr.onError.listen((_) {
        print('[MailtrapEmailService] ❌ Network error connecting to Mailtrap API.');
        completer.complete(false);
      });

      xhr.send(payload.toJS);
    } catch (e) {
      print('[MailtrapEmailService] Exception sending email: $e');
      return false;
    }

    return completer.future;
  }
}
