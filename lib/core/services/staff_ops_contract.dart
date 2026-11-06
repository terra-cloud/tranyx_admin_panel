import 'dart:convert';
import 'dart:math' as math;

import 'staff_ops_errors.dart';

/// Client contract for the workspace `staffOps` callable.
///
/// Supported actions are the ones this portal already calls. Cashout proof, cashout
/// finalization, and manual cashout creation are not among them. Those flows fail closed
/// instead of writing balances from the browser.
///
/// Server defects in the separate `tranyx` repo are not fixed here: caller role trusts
/// writable user-doc flags, agents can self-approve deposits or claim their own cashout,
/// audit agents can read, and a cross-action idempotency replay can return the prior
/// action's result. Keys minted here differ per action and target so this client does not
/// reuse one key across actions. That does not change how the server scopes keys.
const Set<String> supportedStaffOpsActions = {
  'claimWithdrawal',
  'releaseClaim',
  'rejectWithdrawal',
  'approveDeposit',
  'resolveDispute',
};

const String knownStaffOpsActionsLabel =
    'claimWithdrawal, releaseClaim, rejectWithdrawal, approveDeposit, resolveDispute';

/// Portal operations that still have no staffOps action. [missingStaffOpMessage] is the
/// operator-facing reason; nothing in these flows writes Firestore.
enum MissingStaffOp { submitCashoutProof, approveCashout, createManualCashout }

String missingStaffOpMessage(MissingStaffOp op) {
  switch (op) {
    case MissingStaffOp.submitCashoutProof:
      return 'Proof was not submitted. staffOps has no action for cashout proof '
          '(known actions: $knownStaffOpsActionsLabel). '
          'A portal write of withdrawal status, proof, or balances would skip the server claim check, so no Firestore write was made. '
          'Server dependency: a staffOps action that checks the caller holds the claim and stores the reference and proof in that same transaction.';
    case MissingStaffOp.approveCashout:
      return 'Cashout was not finalized. staffOps has no approve-cashout action '
          '(known actions: $knownStaffOpsActionsLabel). approveWithdrawal was not called. '
          'No status, ledger, wallet, notification, or balance write was made. '
          'Server dependency: a staffOps action that checks the claim and completes the cashout without a client-side balance write. '
          'A client-side check that this browser holds the claim is not money authorization.';
    case MissingStaffOp.createManualCashout:
      return 'Manual cashout was not created. staffOps cannot create a withdrawal '
          '(known actions: $knownStaffOpsActionsLabel). '
          'requestWithdrawal is the user debit function and was not called, because it is not a staff authorization to debit another user. '
          'No withdrawal_requests, transactions, ledger, or balance document was written. '
          'Server dependency: a staff callable that creates the request and debits the recipient in one transaction.';
  }
}

void ensureSupportedStaffOpsAction(String action) {
  if (!supportedStaffOpsActions.contains(action)) {
    throw StaffOpsException(
      'failed-precondition',
      'staffOps action "$action" is not a supported contract (known actions: $knownStaffOpsActionsLabel). No request was sent.',
      detailCode: 'SERVER_ACTION_ABSENT',
    );
  }
}

/// Web attestation actually constructed for App Check. Fraud Defense is reCAPTCHA Enterprise.
/// Classic reCAPTCHA v3 is not a value here.
enum AppCheckWebAttestation { recaptchaEnterprise, debug }

/// One of the four Firebase apps this portal already initializes.
///
/// [mintsStaffOpsTokens] is true only for the workspace app. `staffOps` is invoked with that
/// named app, and that same project verifies the ID token and the App Check token.
/// `tranyx-admin-portal` is portal sign-in and Hosting. Its token is not reused for workspace
/// functions.
class PortalFirebaseApp {
  final String alias;
  final String firebaseAppName;
  final String projectId;
  final String appId;
  final bool mintsStaffOpsTokens;

  /// Console registration that was actually reported. This is not a site key.
  /// Only `tranyx-app` is reported registered among the workspace projects.
  /// `tranyx-admin-portal` is a separate Fraud Defense registration and does not mint staffOps tokens.
  final bool appCheckRegistrationReported;

  const PortalFirebaseApp({
    required this.alias,
    required this.firebaseAppName,
    required this.projectId,
    required this.appId,
    required this.mintsStaffOpsTokens,
    required this.appCheckRegistrationReported,
  });
}

const List<PortalFirebaseApp> portalFirebaseApps = [
  PortalFirebaseApp(
    alias: 'admin',
    firebaseAppName: '[DEFAULT]',
    projectId: 'tranyx-admin-portal',
    appId: '1:998364264423:web:f32052956a463360996f42',
    mintsStaffOpsTokens: false,
    appCheckRegistrationReported: true,
  ),
  PortalFirebaseApp(
    alias: 'dev',
    firebaseAppName: 'development',
    projectId: 'tranyx-dev',
    appId: '1:709467070093:web:4d38bcfda904b0d5df4cc4',
    mintsStaffOpsTokens: true,
    appCheckRegistrationReported: false,
  ),
  PortalFirebaseApp(
    alias: 'uat',
    firebaseAppName: 'staging',
    projectId: 'tranyx-uat',
    appId: '1:108125328804:web:f7ada108909ef0a5881d31',
    mintsStaffOpsTokens: true,
    appCheckRegistrationReported: false,
  ),
  PortalFirebaseApp(
    alias: 'prod',
    firebaseAppName: 'production',
    projectId: 'tranyx-app',
    appId: '1:174332525079:web:4ad05af27a88c4ba8f7a52',
    mintsStaffOpsTokens: true,
    appCheckRegistrationReported: true,
  ),
];

const String portalAuthProjectId = 'tranyx-admin-portal';

/// Public Fraud Defense site-key defines. Empty unless the build passes them.
/// These are reCAPTCHA Enterprise site keys, never classic reCAPTCHA keys and never secrets.
const Map<String, String> appCheckSiteKeyDefines = {
  'tranyx-dev': 'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_DEV',
  'tranyx-uat': 'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_UAT',
  'tranyx-app': 'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_PROD',
};

/// Resolved App Check setup for one Firebase project. [ready] is false when the client must
/// not call staffOps. Debug tokens are honored only when [emulator] is true.
class AppCheckClientConfig {
  final String projectId;
  final String? defineName;
  final String? siteKey;
  final bool emulator;
  final bool useDebugToken;
  final String? debugToken;
  final AppCheckWebAttestation? attestation;
  final String? blockingReason;

  const AppCheckClientConfig({
    required this.projectId,
    required this.defineName,
    required this.siteKey,
    required this.emulator,
    required this.useDebugToken,
    required this.debugToken,
    required this.attestation,
    required this.blockingReason,
  });

  bool get ready => blockingReason == null;

  /// Reads dart-defines. Tests should call [resolveAppCheckConfig] with explicit strings.
  factory AppCheckClientConfig.forProject(String projectId) {
    return resolveAppCheckConfig(
      projectId: projectId,
      functionsBaseUrl: const String.fromEnvironment('FUNCTIONS_BASE_URL'),
      siteKeysByDefine: const {
        'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_DEV': String.fromEnvironment(
          'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_DEV',
        ),
        'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_UAT': String.fromEnvironment(
          'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_UAT',
        ),
        'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_PROD': String.fromEnvironment(
          'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_PROD',
        ),
      },
      debugToken: const String.fromEnvironment('APP_CHECK_DEBUG_TOKEN'),
    );
  }
}

bool isUsableRecaptchaSiteKey(String raw) {
  if (raw.isEmpty || raw != raw.trim()) return false;
  if (raw.length < 20 || raw.length > 200) return false;
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(raw)) return false;
  final lower = raw.toLowerCase();
  const blocked = ['changeme', 'placeholder', 'yoursitekey', 'your-site-key', 'todo', 'insert', 'example', 'xxx'];
  for (final word in blocked) {
    if (lower == word || lower.startsWith('$word-') || lower.startsWith('${word}_')) return false;
  }
  return true;
}

bool isUsableAppCheckDebugToken(String raw) {
  return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(raw.trim()) &&
      raw.trim() == raw;
}

AppCheckClientConfig resolveAppCheckConfig({
  required String projectId,
  required String functionsBaseUrl,
  required Map<String, String> siteKeysByDefine,
  required String debugToken,
}) {
  final emulator = functionsBaseUrl.trim().isNotEmpty;
  final define = appCheckSiteKeyDefines[projectId];
  final debugOk = isUsableAppCheckDebugToken(debugToken);
  if (define == null) {
    final portal = projectId == portalAuthProjectId;
    return AppCheckClientConfig(
      projectId: projectId,
      defineName: null,
      siteKey: null,
      emulator: emulator,
      useDebugToken: false,
      debugToken: null,
      attestation: null,
      blockingReason: portal
          ? 'Project $portalAuthProjectId is portal sign-in and Hosting. staffOps runs on the selected workspace project (tranyx-dev, tranyx-uat, or tranyx-app) and verifies App Check there. A token from $portalAuthProjectId is not sent. No request was sent and enforcement was not disabled.'
          : 'No Fraud Defense site-key setting is known for Firebase project "$projectId". '
                'Workspace defines: APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_DEV (tranyx-dev), '
                '_UAT (tranyx-uat), _PROD (tranyx-app). '
                'No staffOps request was sent. App Check enforcement was not disabled.',
    );
  }

  final rawKey = siteKeysByDefine[define] ?? '';
  final keyOk = isUsableRecaptchaSiteKey(rawKey);
  if (emulator && debugOk) {
    return AppCheckClientConfig(
      projectId: projectId,
      defineName: define,
      siteKey: keyOk ? rawKey : null,
      emulator: true,
      useDebugToken: true,
      debugToken: debugToken,
      attestation: AppCheckWebAttestation.debug,
      blockingReason: null,
    );
  }

  final app = _portalApp(projectId);
  final appNote = app == null ? '' : ' Web app ${app.appId}.';
  if (!keyOk) {
    final why = rawKey.trim().isEmpty ? '$define is empty.' : '$define is not a usable reCAPTCHA Enterprise site key.';
    final debugNote = !emulator && debugToken.trim().isNotEmpty
        ? ' APP_CHECK_DEBUG_TOKEN is ignored unless FUNCTIONS_BASE_URL points at an emulator.'
        : emulator && debugToken.trim().isNotEmpty && !debugOk
        ? ' APP_CHECK_DEBUG_TOKEN is set but is not a UUID, so it was not used.'
        : '';
    final registration = app == null
        ? ''
        : !app.mintsStaffOpsTokens
        ? ''
        : app.appCheckRegistrationReported
        ? ' Among tranyx-dev, tranyx-uat, and tranyx-app, only tranyx-app is reported as App Check-registered. Its provider and public site key were not verified for this build, so none is assumed.'
        : ' $projectId is not reported as App Check-registered. No provider or site key is assumed for it.';
    return AppCheckClientConfig(
      projectId: projectId,
      defineName: define,
      siteKey: null,
      emulator: emulator,
      useDebugToken: false,
      debugToken: null,
      attestation: null,
      blockingReason:
          'App Check is not configured for $projectId. staffOps enforces App Check '
          '(ENFORCE_APP_CHECK defaults to true) and this client does not change that. '
          'ReCaptchaEnterpriseProvider is used only when this project\'s public Enterprise site key is supplied. '
          'Classic reCAPTCHA v3 is not used. '
          '$why Pass --dart-define=$define=<the public Enterprise site key for this project>. '
          'Copy that non-secret key from Google Cloud Fraud Defense for project $projectId '
          '(score-based Web key whose domains include this admin origin), the same key registered on that project\'s web app in Firebase App Check. '
          'Do not use a classic reCAPTCHA key, a secret key, or the tranyx-admin-portal Fraud Defense registration. '
          'Docs: https://firebase.google.com/docs/app-check/flutter/recaptcha-enterprise-provider. '
          'No staffOps request was sent.$registration$debugNote$appNote',
    );
  }

  return AppCheckClientConfig(
    projectId: projectId,
    defineName: define,
    siteKey: rawKey,
    emulator: emulator,
    useDebugToken: false,
    debugToken: null,
    attestation: AppCheckWebAttestation.recaptchaEnterprise,
    blockingReason: null,
  );
}

PortalFirebaseApp? _portalApp(String projectId) {
  for (final app in portalFirebaseApps) {
    if (app.projectId == projectId) return app;
  }
  return null;
}

String staffOpsUrl({required String projectId, required String functionsBaseUrl}) {
  final base = functionsBaseUrl.trim();
  if (base.isNotEmpty) {
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$trimmed/staffOps';
  }
  return 'https://us-central1-$projectId.cloudfunctions.net/staffOps';
}

class StaffOpsHttpRequest {
  final String url;
  final Map<String, String> headers;
  final String body;
  const StaffOpsHttpRequest({required this.url, required this.headers, required this.body});
}

/// Builds the callable HTTP request. Throws before any network I/O when the action, the
/// idempotency key, the ID token, or the App Check token is missing.
StaffOpsHttpRequest prepareStaffOpsCall({
  required String url,
  required String action,
  required String idempotencyKey,
  required Map<String, dynamic> data,
  required String? idToken,
  required String? appCheckToken,
}) {
  ensureSupportedStaffOpsAction(action);
  if (idempotencyKey.trim().isEmpty) {
    throw const StaffOpsException(
      'failed-precondition',
      'staffOps call is missing a stable idempotency key. No request was sent.',
      detailCode: 'IDEMPOTENCY_KEY_REQUIRED',
    );
  }
  if (idToken == null || idToken.isEmpty) {
    throw const StaffOpsException(
      'unauthenticated',
      'You are not signed in to this environment. Sign out and in again.',
    );
  }
  final token = appCheckToken?.trim() ?? '';
  if (token.isEmpty) {
    throw const StaffOpsException(
      'failed-precondition',
      'App Check token is missing. staffOps enforces App Check (ENFORCE_APP_CHECK defaults to true). No request was sent and enforcement was not disabled.',
      detailCode: 'APP_CHECK_TOKEN_MISSING',
    );
  }
  final payload = <String, dynamic>{...data, 'idempotencyKey': idempotencyKey, 'action': action};
  return StaffOpsHttpRequest(
    url: url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
      'X-Firebase-AppCheck': token,
    },
    body: jsonEncode({'data': payload}),
  );
}

String newStaffOpsIdempotencyKey() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = math.Random.secure();
  return 'so_${DateTime.now().millisecondsSinceEpoch}_${List.generate(10, (_) => chars[r.nextInt(chars.length)]).join()}';
}

/// One stable key per action and target. A settled result drops the key so the next gesture
/// is a new operation. An indeterminate result (network / internal / unavailable) keeps the
/// key so a retry replays instead of applying twice.
class StaffOpsIdempotencyKeys {
  StaffOpsIdempotencyKeys({String Function()? newKey}) : _newKey = newKey ?? newStaffOpsIdempotencyKey;

  final String Function() _newKey;
  final Map<String, String> _keys = {};

  static String _sig(String action, String target) => '$action\n$target';

  String obtain(String action, String target) => _keys.putIfAbsent(_sig(action, target), _newKey);

  void onSettled(String action, String target) {
    _keys.remove(_sig(action, target));
  }

  void onIndeterminate(String action, String target) {
    obtain(action, target);
  }
}

Future<T> withStableStaffOpsKey<T>(
  StaffOpsIdempotencyKeys keys,
  String action,
  String target,
  Future<T> Function(String idempotencyKey) run,
) async {
  final key = keys.obtain(action, target);
  try {
    final value = await run(key);
    keys.onSettled(action, target);
    return value;
  } on StaffOpsException catch (e) {
    if (e.isIndeterminate) {
      keys.onIndeterminate(action, target);
    } else {
      keys.onSettled(action, target);
    }
    rethrow;
  } catch (_) {
    keys.onIndeterminate(action, target);
    rethrow;
  }
}

class BatchClaimItemOutcome {
  final String withdrawalId;
  final bool claimed;
  final String? error;
  final bool retryable;

  const BatchClaimItemOutcome({
    required this.withdrawalId,
    required this.claimed,
    this.error,
    this.retryable = false,
  });
}

class BatchClaimReport {
  final List<BatchClaimItemOutcome> items;
  const BatchClaimReport(this.items);

  int get attempted => items.length;
  int get claimedCount => items.where((item) => item.claimed).length;
  int get failedCount => attempted - claimedCount;
  bool get allClaimed => failedCount == 0 && attempted > 0;

  /// Honest counts. A transport or server error is never described as a successful claim.
  String get summary {
    if (attempted == 0) return 'No waiting cashouts were claimed.';
    final failures = items
        .where((item) => !item.claimed)
        .map((item) => '${item.withdrawalId}: ${item.error ?? 'failed'}')
        .join('; ');
    if (allClaimed) return 'Claimed $claimedCount of $attempted cashout request(s) on the server.';
    if (claimedCount == 0) return 'Claimed 0 of $attempted. $failures';
    return 'Claimed $claimedCount of $attempted. $failedCount failed. $failures';
  }
}

/// Calls [claim] once per id. [claim] must perform the server call. Exceptions become
/// failed items; they are not counted as claimed.
Future<BatchClaimReport> executeBatchClaims({
  required List<String> withdrawalIds,
  required StaffOpsIdempotencyKeys keys,
  required Future<void> Function(String withdrawalId, String idempotencyKey) claim,
}) async {
  final items = <BatchClaimItemOutcome>[];
  for (final id in withdrawalIds) {
    final key = keys.obtain('claimWithdrawal', id);
    try {
      await claim(id, key);
      keys.onSettled('claimWithdrawal', id);
      items.add(BatchClaimItemOutcome(withdrawalId: id, claimed: true));
    } on StaffOpsException catch (e) {
      if (e.isIndeterminate) {
        keys.onIndeterminate('claimWithdrawal', id);
      } else {
        keys.onSettled('claimWithdrawal', id);
      }
      items.add(
        BatchClaimItemOutcome(
          withdrawalId: id,
          claimed: false,
          error: e.message,
          retryable: e.isIndeterminate,
        ),
      );
    } catch (e) {
      keys.onIndeterminate('claimWithdrawal', id);
      items.add(
        BatchClaimItemOutcome(
          withdrawalId: id,
          claimed: false,
          error: e.toString(),
          retryable: true,
        ),
      );
    }
  }
  return BatchClaimReport(items);
}

/// How the withdrawal address compares to the profile wallet. This is a display aid.
/// [backendAuthorization] is always false: format checks and field comparison do not
/// authorize a payout, and this portal does not verify the wallet with the backend.
enum RecipientWalletTrust { missing, invalidFormat, recordedOnly, mismatch, matchesLinkedProfile }

class RecipientWalletAssessment {
  final RecipientWalletTrust trust;
  final String? recordedAddress;
  final String? linkedProfileWallet;
  final String? copyableAddress;
  final bool documentSaysVerified;
  final String message;

  const RecipientWalletAssessment({
    required this.trust,
    required this.recordedAddress,
    required this.linkedProfileWallet,
    required this.copyableAddress,
    required this.documentSaysVerified,
    required this.message,
  });

  bool get backendAuthorization => false;
}

bool looksLikeSolanaAddress(String value) => RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(value);

String? _nonEmpty(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// Compares the address stored on the withdrawal (`walletPublicKey`, then `walletAddress`)
/// with the recipient profile's `walletPublicKey`. The profile value is never substituted
/// when it differs. A base58 match is not server verification.
RecipientWalletAssessment assessRecipientWallet({
  required Map<String, dynamic> withdrawal,
  String? linkedProfileWallet,
}) {
  final recorded = _nonEmpty(withdrawal['walletPublicKey']) ?? _nonEmpty(withdrawal['walletAddress']);
  final linkedRaw = _nonEmpty(linkedProfileWallet);
  final linked = linkedRaw != null && looksLikeSolanaAddress(linkedRaw) ? linkedRaw : null;
  final documentSaysVerified =
      withdrawal['walletVerified'] == true ||
      withdrawal['payoutWalletVerified'] == true ||
      withdrawal['destinationWalletVerified'] == true;
  final flagNote = documentSaysVerified
      ? ' The withdrawal document has a wallet-verified flag. This screen did not ask the backend to check that flag.'
      : '';

  if (recorded == null) {
    return RecipientWalletAssessment(
      trust: RecipientWalletTrust.missing,
      recordedAddress: null,
      linkedProfileWallet: linked,
      copyableAddress: null,
      documentSaysVerified: documentSaysVerified,
      message:
          'No wallet address is recorded on this withdrawal. Do not send funds. This portal cannot authorize a payout wallet.$flagNote',
    );
  }
  if (!looksLikeSolanaAddress(recorded)) {
    return RecipientWalletAssessment(
      trust: RecipientWalletTrust.invalidFormat,
      recordedAddress: recorded,
      linkedProfileWallet: linked,
      copyableAddress: null,
      documentSaysVerified: documentSaysVerified,
      message:
          'The address on this withdrawal is not a Solana address. It is not a payout destination. Base58 shape is not a security check.$flagNote',
    );
  }
  if (linked == null) {
    final linkedNote = linkedRaw == null
        ? 'The recipient profile has no Solana wallet to compare.'
        : 'The recipient profile wallet is not a Solana address, so it cannot confirm this withdrawal.';
    return RecipientWalletAssessment(
      trust: RecipientWalletTrust.recordedOnly,
      recordedAddress: recorded,
      linkedProfileWallet: linkedRaw,
      copyableAddress: null,
      documentSaysVerified: documentSaysVerified,
      message:
          'A Solana-shaped address is stored on the withdrawal. $linkedNote Copy is withheld. This comparison is not backend verification and does not authorize payment.$flagNote',
    );
  }
  if (recorded != linked) {
    return RecipientWalletAssessment(
      trust: RecipientWalletTrust.mismatch,
      recordedAddress: recorded,
      linkedProfileWallet: linked,
      copyableAddress: null,
      documentSaysVerified: documentSaysVerified,
      message:
          'The withdrawal address does not match the recipient profile wallet. Do not send. The profile wallet was not substituted. This screen does not verify either address with the backend.$flagNote',
    );
  }
  return RecipientWalletAssessment(
    trust: RecipientWalletTrust.matchesLinkedProfile,
    recordedAddress: recorded,
    linkedProfileWallet: linked,
    copyableAddress: recorded,
    documentSaysVerified: documentSaysVerified,
    message:
        'The withdrawal address matches the wallet stored on the recipient profile. That match is not backend verification. Do not treat it as authorization to pay; the server must still confirm the linked payout wallet.$flagNote',
  );
}
