/// The entrypoint for the **client** app.
///
/// This file is compiled to javascript and executed on the client when loading the page.
library;

import 'dart:js_interop';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart' hide runApp;
import 'package:jaspr/client.dart';
import 'package:web/web.dart' as web;

import 'app.dart';
import 'core/config/firebase_environments.dart';
import 'main.client.options.dart';

/// Safely initialize a Firebase app.
/// Only ignores duplicate-app (hot-reload); rethrows everything else.
Future<void> _initApp({String? name, required FirebaseOptions options}) async {
  try {
    await Firebase.initializeApp(name: name, options: options);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
}

/// Write a styled fatal error directly into the DOM.
/// Called only when the critical [DEFAULT] admin app fails to initialize.
void _writeDomError(String message) {
  web.document.getElementById('app-loading')?.remove();
  web.document.body?.innerHTML = '''
    <div style="background:#09090b;min-height:100vh;display:flex;flex-direction:column;
      align-items:center;justify-content:center;gap:16px;padding:2rem;font-family:system-ui,sans-serif">
      <div style="font-size:2.5rem">⚠️</div>
      <h1 style="color:#f4f4f5;font-size:1.25rem;font-weight:700">Portal Failed to Initialize</h1>
      <p style="color:#ef4444;font-size:0.75rem;font-family:monospace;max-width:600px;
        text-align:center;background:#1c1917;padding:1rem;border-radius:0.75rem;
        border:1px solid rgba(239,68,68,0.2);word-break:break-all">$message</p>
      <p style="color:#52525b;font-size:0.75rem;text-align:center;max-width:400px">
        Check your Firebase project configuration and ensure the admin project 
        has Email/Password authentication enabled.</p>
      <button onclick="location.reload()" style="margin-top:8px;padding:10px 20px;
        background:#6366f1;color:white;border:none;border-radius:8px;
        font-size:0.75rem;font-weight:700;cursor:pointer">Retry</button>
    </div>
  '''.toJS;
}

void main() async {
  // Initialize Jaspr client options (registers Firebase Core, Auth, and Firestore web plugins)
  Jaspr.initializeApp(options: defaultClientOptions);

  // Required in Jaspr flutter-plugins mode: bootstraps Flutter's binding
  // system (ServicesBinding, etc.) before any Flutter plugin is used.
  WidgetsFlutterBinding.ensureInitialized();

  // ── Step 1: Initialize the [DEFAULT] Admin app ──────────────────────────
  // This is required before any Firebase Auth or Firestore calls.
  // If it fails, write a visible error to the DOM and abort.
  try {
    await _initApp(options: FirebaseEnv.adminOptions);
  } catch (e) {
    _writeDomError(e.toString());
    return;
  }

  // ── Step 2: Pre-initialize environment apps in background ───────────────
  // Non-blocking — env apps are also lazily initialized in firebaseAppProvider
  // so failures here are non-fatal; the provider will retry on first access.
  for (final env in Environment.values) {
    _initApp(name: env.name, options: FirebaseEnv.optionsFor(env))
        .catchError((e) => print('[Firebase] ${env.name} pre-init skipped: $e'));
  }

  // ── Step 3: Remove loading screen and mount Jaspr app ───────────────────
  web.document.getElementById('app-loading')?.remove();
  runApp(const App());
}
