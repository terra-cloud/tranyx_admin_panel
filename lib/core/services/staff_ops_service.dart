import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../access/staff_access_sync.dart';
import 'staff_ops_contract.dart';
import 'staff_ops_errors.dart';

export 'staff_ops_contract.dart';
export 'staff_ops_errors.dart';

final Map<String, Future<void>> _appCheckActivation = {};

/// Calls the workspace `staffOps` Cloud Function.
///
/// Sends the staff ID token and an App Check token (`X-Firebase-AppCheck`) from [app].
/// [app] is the selected workspace app (`development`, `staging`, or `production`), and the
/// callable URL is that same project's `staffOps`. The default `tranyx-admin-portal` app is
/// not used here: its App Check token would not verify on the workspace function.
///
/// The provider is Fraud Defense (reCAPTCHA Enterprise): [ReCaptchaEnterpriseProvider].
/// Among the workspace projects, only `tranyx-app` is reported App Check-registered, and its
/// public site key is not in this repo. `tranyx-dev` and `tranyx-uat` are not assumed registered.
/// The separate `tranyx-admin-portal` Fraud Defense registration is not used for these calls.
/// Classic reCAPTCHA v3 is not constructed.
///
/// `APP_CHECK_DEBUG_TOKEN` is used only when `FUNCTIONS_BASE_URL` is set (emulator). It is
/// exchanged by the App Check debug provider; the raw UUID is not copied into the header.
/// Enforcement is not turned off when a token cannot be obtained: the call throws and no
/// request is sent.
///
/// A 401 is retried once with a refreshed ID token and a limited-use App Check token, which
/// still satisfies `enforceAppCheck` if the function also consumes tokens. A second 401 is
/// returned as a failure, not a success.
Future<Map<String, dynamic>> callStaffOps(
  FirebaseApp app,
  String action,
  Map<String, dynamic> data, {
  required String idempotencyKey,
  Duration timeout = const Duration(seconds: 70),
}) async {
  ensureSupportedStaffOpsAction(action);
  if (idempotencyKey.trim().isEmpty) {
    throw const StaffOpsException(
      'failed-precondition',
      'staffOps call is missing a stable idempotency key. No request was sent.',
      detailCode: 'IDEMPOTENCY_KEY_REQUIRED',
    );
  }

  final user = FirebaseAuth.instanceFor(app: app).currentUser;
  if (user == null) {
    throw const StaffOpsException(
      'unauthenticated',
      'You are not signed in to this environment. Sign out and in again.',
    );
  }

  const functionsBaseUrl = String.fromEnvironment('FUNCTIONS_BASE_URL');
  final url = staffOpsUrl(projectId: app.options.projectId, functionsBaseUrl: functionsBaseUrl);

  Future<http.Response> post(String idToken, String appCheckToken) {
    final prepared = prepareStaffOpsCall(
      url: url,
      action: action,
      idempotencyKey: idempotencyKey,
      data: data,
      idToken: idToken,
      appCheckToken: appCheckToken,
    );
    return http.post(Uri.parse(prepared.url), headers: prepared.headers, body: prepared.body).timeout(timeout);
  }

  http.Response res;
  try {
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const StaffOpsException(
        'unauthenticated',
        'You are not signed in to this environment. Sign out and in again.',
      );
    }
    final appCheck = await _appCheckToken(app, limitedUse: false);
    res = await post(idToken, appCheck);
    if (res.statusCode == 401) {
      final refreshed = await user.getIdToken(true);
      if (refreshed == null || refreshed.isEmpty) {
        throw const StaffOpsException(
          'unauthenticated',
          'You are not signed in to this environment. Sign out and in again.',
        );
      }
      final limited = await _appCheckToken(app, limitedUse: true);
      res = await post(refreshed, limited);
    }
  } on StaffOpsException {
    rethrow;
  } catch (_) {
    throw const StaffOpsException(
      'network',
      'The staff operations service could not be reached. Check your connection, or that the Cloud Functions are deployed for this environment, then try again.',
    );
  }

  return parseStaffOpsResponse(res.statusCode, res.body, presentedAppCheckToken: true);
}

Future<String> _appCheckToken(FirebaseApp app, {required bool limitedUse}) async {
  final config = AppCheckClientConfig.forProject(app.options.projectId);
  if (!config.ready) {
    throw StaffOpsException(
      'failed-precondition',
      config.blockingReason!,
      detailCode: 'APP_CHECK_NOT_CONFIGURED',
    );
  }
  if (!config.useDebugToken) {
    _clearStaleDebugProvider(app.name);
  }
  await _ensureActivated(app, config);
  final check = FirebaseAppCheck.instanceFor(app: app);
  try {
    final String? token = limitedUse ? await check.getLimitedUseToken() : await check.getToken();
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) {
      throw StaffOpsException(
        'failed-precondition',
        'App Check returned an empty token for ${app.options.projectId}. staffOps enforces App Check (ENFORCE_APP_CHECK defaults to true). No request was sent and enforcement was not disabled.',
        detailCode: 'APP_CHECK_TOKEN_MISSING',
      );
    }
    return trimmed;
  } on StaffOpsException {
    rethrow;
  } on FirebaseException catch (e) {
    throw StaffOpsException(
      'failed-precondition',
      'App Check token request failed (${e.code}) for ${app.options.projectId}. Confirm the Fraud Defense (reCAPTCHA Enterprise) site key registered in Firebase App Check for this project matches the dart-define, and that this portal origin is allowed. No staffOps request was sent and enforcement was not disabled.',
      detailCode: 'APP_CHECK_TOKEN_MISSING',
    );
  }
}

Future<void> _ensureActivated(FirebaseApp app, AppCheckClientConfig config) async {
  final pending = _appCheckActivation[app.name];
  if (pending != null) {
    await pending;
    return;
  }
  final future = _activateAppCheck(app, config);
  _appCheckActivation[app.name] = future;
  try {
    await future;
  } catch (_) {
    if (identical(_appCheckActivation[app.name], future)) {
      _appCheckActivation.remove(app.name);
    }
    rethrow;
  }
}

Future<void> _activateAppCheck(FirebaseApp app, AppCheckClientConfig config) async {
  final attestation = config.attestation;
  if (attestation == null) {
    throw StaffOpsException(
      'failed-precondition',
      config.blockingReason ??
          'App Check provider is not selected for ${app.options.projectId}. No staffOps request was sent and enforcement was not disabled.',
      detailCode: 'APP_CHECK_NOT_CONFIGURED',
    );
  }
  // Fraud Defense only. There is no reCAPTCHA v3 branch.
  final WebProvider provider = attestation == AppCheckWebAttestation.debug
      ? WebDebugProvider(debugToken: config.debugToken)
      : ReCaptchaEnterpriseProvider(config.siteKey!);
  try {
    final check = FirebaseAppCheck.instanceFor(app: app);
    await check.activate(providerWeb: provider);
    await check.setTokenAutoRefreshEnabled(!config.useDebugToken);
  } on StaffOpsException {
    rethrow;
  } on FirebaseException catch (e) {
    throw StaffOpsException(
      'failed-precondition',
      'App Check failed to start (${e.code}) for ${app.options.projectId}. No staffOps request was sent and enforcement was not disabled.',
      detailCode: 'APP_CHECK_NOT_CONFIGURED',
    );
  }
}

/// Calls a workspace HTTPS callable other than `staffOps` (for example `syncStaffAccess`).
/// Uses the selected workspace app's ID token and App Check token. The body is sent as the
/// callable `data` object and is not treated as a staffOps action.
Future<Map<String, dynamic>> callWorkspaceCallable(
  FirebaseApp app,
  String functionName,
  Map<String, dynamic> data, {
  Duration timeout = const Duration(seconds: 70),
}) async {
  final user = FirebaseAuth.instanceFor(app: app).currentUser;
  if (user == null) {
    throw const StaffOpsException(
      'unauthenticated',
      'You are not signed in to this environment. Sign out and in again.',
    );
  }
  const functionsBaseUrl = String.fromEnvironment('FUNCTIONS_BASE_URL');
  final url = callableUrl(
    projectId: app.options.projectId,
    functionsBaseUrl: functionsBaseUrl,
    functionName: functionName,
  );

  Future<http.Response> post(String idToken, String appCheckToken) {
    return http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
            'X-Firebase-AppCheck': appCheckToken,
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(timeout);
  }

  http.Response res;
  try {
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const StaffOpsException('unauthenticated', 'You are not signed in to this environment. Sign out and in again.');
    }
    final appCheck = await _appCheckToken(app, limitedUse: false);
    res = await post(idToken, appCheck);
    if (res.statusCode == 401) {
      final refreshed = await user.getIdToken(true);
      if (refreshed == null || refreshed.isEmpty) {
        throw const StaffOpsException('unauthenticated', 'You are not signed in to this environment. Sign out and in again.');
      }
      res = await post(refreshed, await _appCheckToken(app, limitedUse: true));
    }
  } on StaffOpsException {
    rethrow;
  } catch (_) {
    throw const StaffOpsException(
      'network',
      'The workspace function could not be reached. It may not be deployed for this environment yet.',
    );
  }
  return parseStaffOpsResponse(res.statusCode, res.body, presentedAppCheckToken: true);
}

/// Drops a debug provider left in web storage by an emulator session so a later
/// non-emulator call does not reuse it. The App Check plugin reads these keys itself.
void _clearStaleDebugProvider(String appName) {
  try {
    final typeKey = 'FlutterFire-$appName-recaptchaType';
    final siteKey = 'FlutterFire-$appName-recaptchaSiteKey';
    for (final store in [web.window.localStorage, web.window.sessionStorage]) {
      if (store.getItem(typeKey) == 'debug') {
        store.removeItem(typeKey);
        store.removeItem(siteKey);
      }
    }
  } catch (_) {}
}
