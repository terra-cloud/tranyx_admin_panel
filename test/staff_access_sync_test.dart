import 'dart:io';

import 'package:tranyx_admin_portal/core/access/portal_role.dart';
import 'package:tranyx_admin_portal/core/access/staff_access_sync.dart';
import 'package:tranyx_admin_portal/core/services/staff_ops_errors.dart';

/// `dart run test/staff_access_sync_test.dart`
void main() {
  var failed = 0;
  void check(String name, bool ok) {
    print('${ok ? 'PASS' : 'FAIL'}  $name');
    if (!ok) failed++;
  }

  check('email text is not an admin role', !portalRoleIsAdmin('admin@tranyx.app') && !portalRoleIsAdmin('zeus.agent@tranyx.app'));
  check('assigned admin role is admin', portalRoleIsAdmin('admin') && portalRoleIsAdmin('super_admin'));
  check('staff and agent may use the portal', portalRoleMayUsePortal('staff') && portalRoleMayUsePortal('agent'));
  check('a blank role may not use the portal', !portalRoleMayUsePortal('') && !portalRoleMayUsePortal('user'));

  final body = buildSyncStaffAccessData(
    callerEmail: 'admin@tranyx.app',
    staffEmail: 'zeus.agent@tranyx.app',
    portalRole: 'agent',
  );
  check(
    'sync body is email plus the portal role only',
    body.length == 2 && body['staffEmail'] == 'zeus.agent@tranyx.app' && body['role'] == 'agent' && !body.containsKey('password'),
  );

  StaffOpsException? self;
  try {
    buildSyncStaffAccessData(callerEmail: 'admin@tranyx.app', staffEmail: 'admin@tranyx.app', portalRole: 'admin');
  } on StaffOpsException catch (e) {
    self = e;
  }
  check('a caller cannot sync their own role', self != null && self.detailCode == 'SELF_ROLE');

  check(
    'syncStaffAccess URL stays on the selected workspace project',
    callableUrl(projectId: 'tranyx-app', functionsBaseUrl: '', functionName: 'syncStaffAccess') ==
        'https://us-central1-tranyx-app.cloudfunctions.net/syncStaffAccess',
  );

  if (failed > 0) {
    print('$failed failed');
    exit(1);
  }
  print('All staff_access_sync checks passed');
}
