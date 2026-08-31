import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web/web.dart' as web;

/// Transactional Email Service powered by Mailtrap Email REST API with Cloudflare CORS Proxy support
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
      defaultValue: 'noreply@tranyx.app',
    ),
  );

  /// Default compile-time sender name (injected via `--dart-define=MAIL_TRAP_FROM_NAME=...`)
  static const String envSenderName = String.fromEnvironment(
    'MAIL_TRAP_FROM_NAME',
    defaultValue: 'Tranyx No-Reply',
  );

  /// Default compile-time proxy URL (injected via `--dart-define=MAIL_TRAP_PROXY_URL=...`)
  static const String envProxyUrl = String.fromEnvironment(
    'MAIL_TRAP_PROXY_URL',
    defaultValue: String.fromEnvironment('MAILTRAP_PROXY_URL'),
  );

  /// Default compile-time Sandbox Inbox ID (injected via `--dart-define=MAIL_TRAP_INBOX_ID=...`)
  static const String envInboxId = String.fromEnvironment(
    'MAIL_TRAP_INBOX_ID',
    defaultValue: '4886849',
  );

  static String? _cachedLocalEnvToken;
  static String? _cachedLocalEnvSenderEmail;
  static String? _cachedLocalEnvSenderName;
  static String? _cachedLocalEnvProxyUrl;
  static String? _cachedLocalEnvInboxId;
  static bool _runtimeEnvChecked = false;

  /// Loads .env at runtime during local development (`jaspr serve`) if not passed via compile-time define.
  static Future<void> _loadRuntimeEnv() async {
    if (_runtimeEnvChecked) return;
    _runtimeEnvChecked = true;
    try {
      final completer = Completer<String?>();
      final xhr = web.XMLHttpRequest();
      xhr.open('GET', '/.env', true);
      xhr.onLoad.listen((_) {
        if (xhr.status >= 200 && xhr.status < 300) {
          completer.complete(xhr.responseText);
        } else {
          completer.complete(null);
        }
      });
      xhr.onError.listen((_) => completer.complete(null));
      xhr.send();

      final content = await completer.future.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => null,
      );

      if (content != null && content.isNotEmpty) {
        for (final line in content.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final eqIdx = trimmed.indexOf('=');
          if (eqIdx > 0) {
            final key = trimmed.substring(0, eqIdx).trim();
            final value = trimmed.substring(eqIdx + 1).trim().replaceAll(RegExp(r'^["\x27]|["\x27]$'), '');
            if (key == 'MAIL_TRAP_TOKEN' || key == 'MAILTRAP_TOKEN' || key == 'MAILTRAP_API_KEY') {
              _cachedLocalEnvToken = value;
            } else if (key == 'MAIL_TRAP_FROM_EMAIL' || key == 'MAILTRAP_FROM_EMAIL') {
              _cachedLocalEnvSenderEmail = value;
            } else if (key == 'MAIL_TRAP_FROM_NAME' || key == 'MAILTRAP_FROM_NAME') {
              _cachedLocalEnvSenderName = value;
            } else if (key == 'MAIL_TRAP_PROXY_URL' || key == 'MAILTRAP_PROXY_URL') {
              _cachedLocalEnvProxyUrl = value;
            } else if (key == 'MAIL_TRAP_INBOX_ID' || key == 'MAILTRAP_INBOX_ID') {
              _cachedLocalEnvInboxId = value;
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Dynamically resolves the active Mailtrap API token.
  static Future<String> resolveApiToken([FirebaseFirestore? firestore]) async {
    if (envApiToken.isNotEmpty) {
      return envApiToken;
    }

    await _loadRuntimeEnv();
    if (_cachedLocalEnvToken != null && _cachedLocalEnvToken!.isNotEmpty) {
      return _cachedLocalEnvToken!;
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

    return '';
  }

  /// Dynamically resolves the Cloudflare Worker CORS Proxy URL.
  static Future<String> resolveProxyUrl([FirebaseFirestore? firestore]) async {
    if (envProxyUrl.isNotEmpty) {
      return envProxyUrl;
    }

    await _loadRuntimeEnv();
    if (_cachedLocalEnvProxyUrl != null && _cachedLocalEnvProxyUrl!.isNotEmpty) {
      return _cachedLocalEnvProxyUrl!;
    }

    for (final db in [FirebaseFirestore.instance, firestore]) {
      if (db == null) continue;
      try {
        final snap = await db.collection('system_config').doc('settings').get();
        if (snap.exists && snap.data() != null) {
          final proxy = snap.data()!['mailtrapProxyUrl'] ?? snap.data()!['mail_trap_proxy_url'];
          if (proxy != null && proxy.toString().trim().isNotEmpty) {
            return proxy.toString().trim();
          }
        }
      } catch (_) {}
    }

    return '';
  }

  /// Dynamically resolves the Sandbox Inbox ID.
  static Future<String> resolveInboxId([FirebaseFirestore? firestore]) async {
    await _loadRuntimeEnv();
    if (_cachedLocalEnvInboxId != null && _cachedLocalEnvInboxId!.isNotEmpty) {
      return _cachedLocalEnvInboxId!;
    }

    for (final db in [FirebaseFirestore.instance, firestore]) {
      if (db == null) continue;
      try {
        final snap = await db.collection('system_config').doc('settings').get();
        if (snap.exists && snap.data() != null) {
          final inbox = snap.data()!['mailtrapInboxId'] ?? snap.data()!['mail_trap_inbox_id'];
          if (inbox != null && inbox.toString().trim().isNotEmpty) {
            return inbox.toString().trim();
          }
        }
      } catch (_) {}
    }

    return envInboxId.isNotEmpty ? envInboxId : '4886849';
  }

  /// Dynamically resolves the sender email address.
  static Future<String> resolveSenderEmail([FirebaseFirestore? firestore]) async {
    await _loadRuntimeEnv();
    if (_cachedLocalEnvSenderEmail != null && _cachedLocalEnvSenderEmail!.isNotEmpty) {
      return _cachedLocalEnvSenderEmail!;
    }

    for (final db in [FirebaseFirestore.instance, firestore]) {
      if (db == null) continue;
      try {
        final snap = await db.collection('system_config').doc('settings').get();
        if (snap.exists && snap.data() != null) {
          final sender = snap.data()!['mailtrapFromEmail'] ??
              snap.data()!['mail_trap_from_email'] ??
              snap.data()!['senderEmail'];
          if (sender != null && sender.toString().trim().isNotEmpty) {
            final sStr = sender.toString().trim();
            return sStr.endsWith('@tranyx.com') ? sStr.replaceAll('@tranyx.com', '@tranyx.app') : sStr;
          }
        }
      } catch (_) {}
    }
    return envSenderEmail.isNotEmpty ? envSenderEmail : 'noreply@tranyx.app';
  }

  /// Dynamically resolves the sender display name.
  static Future<String> resolveSenderName([FirebaseFirestore? firestore]) async {
    await _loadRuntimeEnv();
    if (_cachedLocalEnvSenderName != null && _cachedLocalEnvSenderName!.isNotEmpty) {
      return _cachedLocalEnvSenderName!;
    }

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
    return envSenderName.isNotEmpty ? envSenderName : 'Tranyx No-Reply';
  }

  /// Extracts structured name and email from a formatted address string.
  /// Example: `"Tranyx No-Reply <noreply@tranyx.com>"` -> name: "Tranyx No-Reply", email: "noreply@tranyx.com"
  static Map<String, String> parseAddress(String address, {String fallbackName = 'Tranyx No-Reply'}) {
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

  /// Sends a transactional HTML email via Cloudflare CORS Proxy or Mailtrap REST API.
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

    final token = await resolveApiToken(firestore);
    if (token.isEmpty) {
      print('[MailtrapEmailService] No API token configured for Mailtrap.');
      return false;
    }

    final resolvedFromEmail = senderEmail ?? await resolveSenderEmail(firestore);
    final resolvedFromName = senderName ?? await resolveSenderName(firestore);
    final proxyUrl = await resolveProxyUrl(firestore);
    final inboxId = await resolveInboxId(firestore);
    final fromParsed = parseAddress(resolvedFromEmail, fallbackName: resolvedFromName);

    final completer = Completer<bool>();

    try {
      final targetUrl = proxyUrl.isNotEmpty ? proxyUrl : 'https://send.api.mailtrap.io/api/send';
      final xhr = web.XMLHttpRequest();
      xhr.open('POST', targetUrl, true);
      xhr.setRequestHeader('Authorization', 'Bearer $token');
      xhr.setRequestHeader('Api-Token', token);
      xhr.setRequestHeader('Content-Type', 'application/json');
      if (inboxId.isNotEmpty) {
        xhr.setRequestHeader('X-Inbox-Id', inboxId);
      }

      final toEntry = <String, dynamic>{
        'email': recipientEmail.trim(),
        if (recipientName != null && recipientName.trim().isNotEmpty) 'name': recipientName.trim(),
      };

      var fromEmail = fromParsed['email'] ?? 'noreply@tranyx.app';
      if (fromEmail.endsWith('@tranyx.com')) {
        fromEmail = fromEmail.replaceAll('@tranyx.com', '@tranyx.app');
      }

      final payloadMap = {
        'from': {
          'email': fromEmail,
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
        if (proxyUrl.isEmpty) {
          print('[MailtrapEmailService] ❌ CORS policy blocked direct browser request to Mailtrap API.');
          print('[MailtrapEmailService] 👉 Please configure MAIL_TRAP_PROXY_URL (Cloudflare Worker) in .env or Settings Console.');
        } else {
          print('[MailtrapEmailService] ❌ Network error connecting to Mailtrap proxy at $proxyUrl');
        }
        completer.complete(false);
      });

      xhr.send(payload.toJS);
    } catch (e) {
      print('[MailtrapEmailService] Exception sending email: $e');
      return false;
    }

    return completer.future;
  }

  /// Helper to send a quick integration test email matching the sample spec.
  static Future<bool> sendTestEmail({
    String recipientEmail = 'terraservices.ph@gmail.com',
    String? senderEmail,
    String? senderName,
    FirebaseFirestore? firestore,
  }) async {
    return sendEmail(
      recipientEmail: recipientEmail,
      subject: 'You are awesome!',
      textContent: 'Congrats for sending test email with Mailtrap!',
      htmlContent: '<p>Congrats for sending test email with <b>Mailtrap</b>!</p>',
      category: 'Integration Test',
      senderEmail: senderEmail,
      senderName: senderName,
      firestore: firestore,
    );
  }
}
