import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import 'staff_ops_errors.dart';
export 'staff_ops_errors.dart';

String _newKey() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = math.Random.secure();
  return 'so_${DateTime.now().millisecondsSinceEpoch}_${List.generate(10, (_) => chars[r.nextInt(chars.length)]).join()}';
}

/// Calls the workspace `staffOps` Cloud Function (staff / P2P-agent balance operations, run server-side with a
/// role check, an idempotency key, one Firestore transaction and an audit-log entry). The portal never writes
/// `tyxBalance` itself any more.
///
/// [app] is the Firebase app of the ACTIVE environment (the staff member is signed into it by `syncEnvAuth`);
/// `FUNCTIONS_BASE_URL` (dart-define) points at an emulator.
Future<Map<String, dynamic>> callStaffOps(
  FirebaseApp app,
  String action,
  Map<String, dynamic> data, {
  String? idempotencyKey,
  Duration timeout = const Duration(seconds: 70),
}) async {
  final user = FirebaseAuth.instanceFor(app: app).currentUser;
  if (user == null) {
    throw const StaffOpsException('unauthenticated', 'You are not signed in to this environment. Sign out and in again.');
  }
  const base = String.fromEnvironment('FUNCTIONS_BASE_URL');
  final url = base.isNotEmpty
      ? '$base/staffOps'
      : 'https://us-central1-${app.options.projectId}.cloudfunctions.net/staffOps';
  final key = idempotencyKey ?? _newKey();

  Future<http.Response> post(String? token) => http
      .post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
        body: jsonEncode({'data': {'idempotencyKey': key, 'action': action, ...data}}),
      )
      .timeout(timeout);

  http.Response res;
  try {
    res = await post(await user.getIdToken());
    if (res.statusCode == 401) res = await post(await user.getIdToken(true));
  } catch (_) {
    throw const StaffOpsException(
      'network',
      'The staff operations service could not be reached. Check your connection, or that the Cloud Functions are deployed for this environment, then try again.',
    );
  }

  return parseStaffOpsResponse(res.statusCode, res.body);
}
