import '../services/staff_ops_errors.dart';
import 'portal_role.dart';

/// Body for the workspace callable `syncStaffAccess`.
///
/// The callable is not in this repo. It must run with the Admin SDK in
/// `terra-cloud/tranyx` and read the caller's custom claims itself. This map
/// never includes a password or a claim for the caller.
Map<String, dynamic> buildSyncStaffAccessData({
  required String callerEmail,
  required String staffEmail,
  required String portalRole,
}) {
  final caller = callerEmail.trim().toLowerCase();
  final staff = staffEmail.trim().toLowerCase();
  if (caller.isEmpty || staff.isEmpty || !staff.contains('@')) {
    throw const StaffOpsException('invalid-argument', 'A staff email is required.', detailCode: 'invalid-argument');
  }
  if (caller == staff) {
    throw const StaffOpsException(
      'permission-denied',
      'You cannot change your own access. Another admin has to sync it.',
      detailCode: 'SELF_ROLE',
    );
  }
  final role = workspaceClaimRole(portalRole);
  if (role == null) {
    throw StaffOpsException(
      'invalid-argument',
      'Portal role "$portalRole" is not a workspace role. Access is not taken from the email address.',
      detailCode: 'invalid-argument',
    );
  }
  return {'staffEmail': staff, 'role': role};
}

String callableUrl({
  required String projectId,
  required String functionsBaseUrl,
  required String functionName,
}) {
  final base = functionsBaseUrl.trim();
  if (base.isNotEmpty) {
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$trimmed/$functionName';
  }
  return 'https://us-central1-$projectId.cloudfunctions.net/$functionName';
}
