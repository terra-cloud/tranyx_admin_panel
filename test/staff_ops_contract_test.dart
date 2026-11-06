import 'dart:convert';
import 'dart:io';

import 'package:tranyx_admin_portal/core/services/staff_ops_contract.dart';
import 'package:tranyx_admin_portal/core/services/staff_ops_errors.dart';

/// `dart run test/staff_ops_contract_test.dart`
///
/// Deterministic checks for idempotency keys, batch claim results, App Check request
/// failures, and wallet display. No Firebase, Firestore, or network.
void main() async {
  var failed = 0;
  void check(String name, bool ok) {
    print('${ok ? 'PASS' : 'FAIL'}  $name');
    if (!ok) failed++;
  }

  var seq = 0;
  StaffOpsIdempotencyKeys keys() => StaffOpsIdempotencyKeys(newKey: () => 'k${seq++}');

  // Stable idempotency: same click/retry keeps the key; a settled result starts a new one.
  {
    final store = keys();
    final first = store.obtain('rejectWithdrawal', 'w1');
    final again = store.obtain('rejectWithdrawal', 'w1');
    check('repeat obtain keeps one key for the same action and target', first == again && first == 'k0');

    final otherAction = store.obtain('claimWithdrawal', 'w1');
    final otherTarget = store.obtain('rejectWithdrawal', 'w2');
    check(
      'a different action or target gets its own key',
      otherAction != first && otherTarget != first && otherAction != otherTarget,
    );

    Object? error;
    try {
      await withStableStaffOpsKey(store, 'rejectWithdrawal', 'w1', (key) async {
        check('in-flight call uses the stored key', key == first);
        throw const StaffOpsException('network', 'timed out');
      });
    } catch (e) {
      error = e;
    }
    check('indeterminate failure is rethrown', error is StaffOpsException && error.isIndeterminate);
    check('indeterminate failure keeps the key for a safe retry', store.obtain('rejectWithdrawal', 'w1') == first);

    await withStableStaffOpsKey(store, 'rejectWithdrawal', 'w1', (key) async => key);
    final afterSettle = store.obtain('rejectWithdrawal', 'w1');
    check('a settled result resets the key for a genuinely new operation', afterSettle != first);
  }

  // Batch claims call the server and report partial failure. They do not count a throw as success.
  {
    final store = keys();
    final calls = <String, String>{};
    final report = await executeBatchClaims(
      withdrawalIds: ['a', 'b', 'c'],
      keys: store,
      claim: (id, key) async {
        calls[id] = key;
        if (id == 'b') {
          throw const StaffOpsException(
            'failed-precondition',
            'Already claimed by Ana.',
            detailCode: 'CLAIMED_BY_OTHER',
          );
        }
        if (id == 'c') throw const StaffOpsException('unavailable', 'upstream reset');
      },
    );
    check('batch invokes the server once per selected withdrawal', calls.length == 3);
    check(
      'batch counts only server successes',
      report.claimedCount == 1 && report.failedCount == 2 && report.attempted == 3,
    );
    check(
      'batch summary states the partial outcome',
      report.summary.contains('Claimed 1 of 3') &&
          report.summary.contains('b: Already claimed by Ana.') &&
          report.summary.contains('c: upstream reset') &&
          !report.summary.toLowerCase().contains('successfully claimed'),
    );
    final retryKey = calls['c']!;
    String? retried;
    await executeBatchClaims(
      withdrawalIds: ['c'],
      keys: store,
      claim: (id, key) async => retried = key,
    );
    check('an indeterminate batch failure retries with the same key', retried == retryKey);
    String? reclaimed;
    await executeBatchClaims(
      withdrawalIds: ['b'],
      keys: store,
      claim: (id, key) async => reclaimed = key,
    );
    check('a determinate claim error starts a new key on the next attempt', reclaimed != calls['b']);

    final empty = await executeBatchClaims(withdrawalIds: const [], keys: store, claim: (id, key) async {});
    check(
      'an empty batch does not report a successful claim',
      empty.claimedCount == 0 && empty.summary == 'No waiting cashouts were claimed.',
    );
  }

  // Callable request: App Check header is required, and unsupported actions are not sent.
  {
    final prepared = prepareStaffOpsCall(
      url: 'https://example.test/staffOps',
      action: 'claimWithdrawal',
      idempotencyKey: 'k-stable',
      data: {'withdrawalId': 'w9', 'action': 'rejectWithdrawal', 'idempotencyKey': 'forged'},
      idToken: 'id-token',
      appCheckToken: 'app-check-token',
    );
    final decoded = jsonDecode(prepared.body) as Map<String, dynamic>;
    final data = (decoded['data'] as Map).cast<String, dynamic>();
    check(
      'request carries Authorization and X-Firebase-AppCheck',
      prepared.headers['Authorization'] == 'Bearer id-token' &&
          prepared.headers['X-Firebase-AppCheck'] == 'app-check-token',
    );
    check(
      'payload action and idempotency key cannot be overridden by caller data',
      data['action'] == 'claimWithdrawal' && data['idempotencyKey'] == 'k-stable' && data['withdrawalId'] == 'w9',
    );

    StaffOpsException? missingToken;
    try {
      prepareStaffOpsCall(
        url: 'https://example.test/staffOps',
        action: 'approveDeposit',
        idempotencyKey: 'k',
        data: const {'depositId': 'd1'},
        idToken: 'id-token',
        appCheckToken: '  ',
      );
    } on StaffOpsException catch (e) {
      missingToken = e;
    }
    check(
      'missing App Check token fails before a request',
      missingToken != null &&
          missingToken.detailCode == 'APP_CHECK_TOKEN_MISSING' &&
          missingToken.message.contains('ENFORCE_APP_CHECK') &&
          missingToken.message.contains('No request was sent') &&
          missingToken.message.contains('not disabled'),
    );

    StaffOpsException? absent;
    try {
      prepareStaffOpsCall(
        url: 'https://example.test/staffOps',
        action: 'approveWithdrawal',
        idempotencyKey: 'k',
        data: const {'withdrawalId': 'w1'},
        idToken: 'id-token',
        appCheckToken: 'token',
      );
    } on StaffOpsException catch (e) {
      absent = e;
    }
    check(
      'an unsupported action is rejected and not renamed into a call',
      absent != null &&
          absent.detailCode == 'SERVER_ACTION_ABSENT' &&
          !supportedStaffOpsActions.contains('approveWithdrawal'),
    );

    final denied = () {
      try {
        return parseStaffOpsResponse(
          401,
          '{"error":{"status":"UNAUTHENTICATED","message":"Unauthenticated"}}',
          presentedAppCheckToken: true,
        );
      } on StaffOpsException catch (e) {
        return e;
      }
    }();
    check(
      'HTTP 401 after both tokens is an App Check or auth failure',
      denied is StaffOpsException &&
          denied.code == 'unauthenticated' &&
          denied.detailCode == 'APP_CHECK_OR_AUTH_REJECTED' &&
          denied.message.contains('App Check') &&
          !denied.isIndeterminate,
    );

    final appCheckBody = () {
      try {
        return parseStaffOpsResponse(
          401,
          '{"error":{"status":"UNAUTHENTICATED","message":"App Check token was rejected."}}',
          presentedAppCheckToken: true,
        );
      } on StaffOpsException catch (e) {
        return e;
      }
    }();
    check(
      'an App Check error body keeps a specific reason code',
      appCheckBody is StaffOpsException && appCheckBody.detailCode == 'APP_CHECK_REJECTED',
    );
  }

  // App Check configuration. No site key is invented; debug tokens are emulator-only.
  {
    const siteKey = '6Labcdefghijklmnopqrstuvwxyz0123456789ab';
    check('fixture site key is shaped like a public reCAPTCHA key', isUsableRecaptchaSiteKey(siteKey));
    check(
      'placeholder and short keys are rejected',
      !isUsableRecaptchaSiteKey('changeme-abcdefghijklmnop') && !isUsableRecaptchaSiteKey('short'),
    );

    final blocked = resolveAppCheckConfig(
      projectId: 'tranyx-app',
      functionsBaseUrl: '',
      siteKeysByDefine: const {},
      debugToken: '00112233-4455-6677-8899-aabbccddeeff',
    );
    check(
      'production without an Enterprise site key fails closed and ignores a debug token',
      !blocked.ready &&
          blocked.attestation == null &&
          blocked.blockingReason!.contains('APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_PROD') &&
          blocked.blockingReason!.contains('ReCaptchaEnterpriseProvider') &&
          blocked.blockingReason!.contains('does not change that') &&
          blocked.blockingReason!.contains('only tranyx-app is reported as App Check-registered') &&
          blocked.blockingReason!.contains('APP_CHECK_DEBUG_TOKEN is ignored') &&
          blocked.blockingReason!.contains('1:174332525079:web:4ad05af27a88c4ba8f7a52') &&
          !blocked.blockingReason!.contains('6LfRzBIuAAAAAG0WSzlXuPZDi2aJPgUoZ48lvlX5') &&
          !blocked.useDebugToken &&
          !blocked.blockingReason!.contains('00112233'),
    );

    final devUnregistered = resolveAppCheckConfig(
      projectId: 'tranyx-dev',
      functionsBaseUrl: '',
      siteKeysByDefine: const {},
      debugToken: '',
    );
    final uatUnregistered = resolveAppCheckConfig(
      projectId: 'tranyx-uat',
      functionsBaseUrl: '',
      siteKeysByDefine: const {},
      debugToken: '',
    );
    check(
      'dev and uat are not assumed to be App Check-registered',
      !devUnregistered.ready &&
          !uatUnregistered.ready &&
          devUnregistered.blockingReason!.contains('tranyx-dev is not reported as App Check-registered') &&
          uatUnregistered.blockingReason!.contains('tranyx-uat is not reported as App Check-registered') &&
          devUnregistered.attestation == null &&
          uatUnregistered.attestation == null,
    );

    const badKey = 'not a valid key !!!';
    final invalid = resolveAppCheckConfig(
      projectId: 'tranyx-dev',
      functionsBaseUrl: '',
      siteKeysByDefine: const {'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_DEV': badKey},
      debugToken: '',
    );
    check(
      'an invalid Enterprise site key is refused without echoing it',
      !invalid.ready && !invalid.blockingReason!.contains(badKey) && invalid.blockingReason!.contains('not a usable'),
    );

    final ready = resolveAppCheckConfig(
      projectId: 'tranyx-app',
      functionsBaseUrl: '',
      siteKeysByDefine: const {'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_PROD': siteKey},
      debugToken: '00112233-4455-6677-8899-aabbccddeeff',
    );
    check(
      'an explicit production Enterprise site key selects Fraud Defense and not the debug token',
      ready.ready &&
          ready.siteKey == siteKey &&
          !ready.useDebugToken &&
          ready.attestation == AppCheckWebAttestation.recaptchaEnterprise,
    );

    final prodOnly = resolveAppCheckConfig(
      projectId: 'tranyx-dev',
      functionsBaseUrl: '',
      siteKeysByDefine: const {'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_PROD': siteKey},
      debugToken: '',
    );
    check('a tranyx-app Enterprise key does not configure tranyx-dev', !prodOnly.ready && prodOnly.attestation == null);

    final adminProject = resolveAppCheckConfig(
      projectId: 'tranyx-admin-portal',
      functionsBaseUrl: '',
      siteKeysByDefine: const {'APP_CHECK_RECAPTCHA_ENTERPRISE_SITE_KEY_PROD': siteKey},
      debugToken: '',
    );
    check(
      'the portal project is not given a workspace App Check token',
      !adminProject.ready &&
          adminProject.blockingReason!.contains('token from tranyx-admin-portal is not sent') &&
          !adminProject.blockingReason!.contains(siteKey),
    );

    final emulator = resolveAppCheckConfig(
      projectId: 'tranyx-dev',
      functionsBaseUrl: 'http://127.0.0.1:5001/tranyx-dev/us-central1',
      siteKeysByDefine: const {},
      debugToken: '00112233-4455-6677-8899-aabbccddeeff',
    );
    check(
      'emulator debug token is exchanged only when FUNCTIONS_BASE_URL is set',
      emulator.ready &&
          emulator.useDebugToken &&
          emulator.attestation == AppCheckWebAttestation.debug &&
          emulator.debugToken != null &&
          emulator.siteKey == null,
    );
    check(
      'staffOps emulator URL stays on the configured base',
      staffOpsUrl(
        projectId: 'tranyx-dev',
        functionsBaseUrl: 'http://127.0.0.1:5001/tranyx-dev/us-central1/',
      ).endsWith('/staffOps'),
    );
  }

  // Wallet display. Matching fields is not a server-side security fix.
  {
    const recorded = 'So11111111111111111111111111111111111111112';
    check('fixture address is base58-shaped', looksLikeSolanaAddress(recorded));

    final missing = assessRecipientWallet(withdrawal: const {}, linkedProfileWallet: recorded);
    check(
      'a missing withdrawal address is not replaced by the profile wallet',
      missing.trust == RecipientWalletTrust.missing &&
          missing.copyableAddress == null &&
          missing.recordedAddress == null,
    );

    final only = assessRecipientWallet(withdrawal: const {'walletPublicKey': recorded}, linkedProfileWallet: null);
    check(
      'base58 alone does not authorize a copy',
      only.trust == RecipientWalletTrust.recordedOnly &&
          only.copyableAddress == null &&
          !only.backendAuthorization &&
          only.message.contains('not backend verification'),
    );

    final mismatch = assessRecipientWallet(
      withdrawal: const {'walletPublicKey': recorded, 'walletVerified': true},
      linkedProfileWallet: 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
    );
    check(
      'a mismatched profile wallet is not substituted, even if the document flag is set',
      mismatch.trust == RecipientWalletTrust.mismatch &&
          mismatch.copyableAddress == null &&
          mismatch.documentSaysVerified &&
          !mismatch.backendAuthorization &&
          mismatch.message.contains('not substituted'),
    );

    final match = assessRecipientWallet(
      withdrawal: const {'walletAddress': recorded},
      linkedProfileWallet: recorded,
    );
    check(
      'a matching stored address can be copied and is still not backend verification',
      match.trust == RecipientWalletTrust.matchesLinkedProfile &&
          match.copyableAddress == recorded &&
          !match.backendAuthorization &&
          match.message.contains('not backend verification'),
    );

    final invalid = assessRecipientWallet(
      withdrawal: const {'walletPublicKey': 'not-a-wallet'},
      linkedProfileWallet: recorded,
    );
    check(
      'a non-address is not presented as a payout destination',
      invalid.trust == RecipientWalletTrust.invalidFormat && invalid.copyableAddress == null,
    );
  }

  // Four configured Firebase apps. staffOps tokens come from the workspace app, not the portal app.
  {
    check('the portal configures four Firebase apps', portalFirebaseApps.length == 4);
    final projects = portalFirebaseApps.map((app) => app.projectId).toSet();
    check(
      'portal, dev, uat, and production workspace stay distinct',
      projects.length == 4 && projects.contains(portalAuthProjectId) && projects.contains('tranyx-app'),
    );
    final staffOpsProjects = portalFirebaseApps
        .where((app) => app.mintsStaffOpsTokens)
        .map((app) => app.projectId)
        .toSet();
    check(
      'staffOps is limited to the three workspace projects',
      staffOpsProjects.length == 3 && !staffOpsProjects.contains(portalAuthProjectId),
    );
    final reportedWorkspace = portalFirebaseApps
        .where((app) => app.mintsStaffOpsTokens && app.appCheckRegistrationReported)
        .map((app) => app.projectId)
        .toList();
    check(
      'only production is reported App Check-registered among workspace projects',
      reportedWorkspace.length == 1 && reportedWorkspace.single == 'tranyx-app',
    );
    check(
      'dev and uat registration flags stay off and the portal registration does not mint staffOps tokens',
      portalFirebaseApps.any(
            (app) => app.projectId == 'tranyx-dev' && !app.appCheckRegistrationReported && app.mintsStaffOpsTokens,
          ) &&
          portalFirebaseApps.any(
            (app) => app.projectId == 'tranyx-uat' && !app.appCheckRegistrationReported && app.mintsStaffOpsTokens,
          ) &&
          portalFirebaseApps.any(
            (app) =>
                app.projectId == portalAuthProjectId && app.appCheckRegistrationReported && !app.mintsStaffOpsTokens,
          ),
    );
    final prodUrl = staffOpsUrl(projectId: 'tranyx-app', functionsBaseUrl: '');
    check(
      'production staffOps is verified by tranyx-app, not the portal project',
      prodUrl == 'https://us-central1-tranyx-app.cloudfunctions.net/staffOps' && !prodUrl.contains(portalAuthProjectId),
    );

    final envSource = File('lib/core/config/firebase_environments.dart').readAsStringSync();
    final rc = File('.firebaserc').readAsStringSync();
    final service = File('lib/core/services/staff_ops_service.dart').readAsStringSync();
    var wiringOk = true;
    for (final app in portalFirebaseApps) {
      if (!envSource.contains('projectId: "${app.projectId}"') || !envSource.contains('appId: "${app.appId}"')) {
        wiringOk = false;
      }
      if (!rc.contains('"${app.projectId}"')) wiringOk = false;
    }
    check('FirebaseEnv and .firebaserc match the four-project catalog', wiringOk);
    check(
      '.firebaserc default hosting project is the portal project',
      rc.contains('"default": "tranyx-admin-portal"') && rc.contains('"admin": "tranyx-admin-portal"'),
    );
    check(
      'the callable client constructs Enterprise App Check and not reCAPTCHA v3',
      service.contains('ReCaptchaEnterpriseProvider') && !service.contains('ReCaptchaV3Provider'),
    );
    final lib = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    final shippedClassic = lib.any((f) => f.readAsStringSync().contains('6LfRzBIuAAAAAG0WSzlXuPZDi2aJPgUoZ48lvlX5'));
    check('the unverified classic tranyx.app site key is not compiled in', !shippedClassic);
    final envAuth = File('lib/core/providers/environment_provider.dart').readAsStringSync();
    check(
      'workspace sign-in does not write user-doc staff flags',
      !envAuth.contains("'isAdmin': true") &&
          !envAuth.contains("'isP2pAgent': true") &&
          !envAuth.contains("collection('p2p_agents')") &&
          envAuth.contains('FirebaseAuth.instanceFor(app: app)'),
    );
  }

  for (final op in MissingStaffOp.values) {
    final message = missingStaffOpMessage(op);
    final ok =
        message.contains(knownStaffOpsActionsLabel) &&
        message.contains('Server dependency') &&
        !message.toLowerCase().contains('successfully') &&
        !supportedStaffOpsActions.contains('approveWithdrawal') &&
        !supportedStaffOpsActions.contains('submitCashoutProof') &&
        !supportedStaffOpsActions.contains('createWithdrawal');
    check('missing ${op.name} fails closed on the known contract', ok);
  }

  if (failed > 0) {
    print('$failed failed');
    exit(1);
  }
  print('All staff_ops_contract checks passed');
}
