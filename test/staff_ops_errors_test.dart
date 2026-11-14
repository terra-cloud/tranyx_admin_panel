import 'dart:io';

import 'package:tranyx_admin_portal/core/services/staff_ops_errors.dart';

/// Plain script test (same style as promotion_calculator_test.dart): `dart run test/staff_ops_errors_test.dart`.
void main() {
  var failed = 0;
  void check(String name, bool ok) {
    print('${ok ? 'PASS' : 'FAIL'}  $name');
    if (!ok) failed++;
  }

  StaffOpsException? thrown(int status, String body) {
    try {
      parseStaffOpsResponse(status, body);
    } on StaffOpsException catch (e) {
      return e;
    }
    return null;
  }

  final ok = parseStaffOpsResponse(200, '{"result":{"ok":true,"credited":250}}');
  check('success returns the result map', ok['ok'] == true && ok['credited'] == 250);

  final e1 = thrown(400, '{"error":{"status":"FAILED_PRECONDITION","message":"Already claimed by Ana.","details":{"code":"CLAIMED_BY_OTHER"}}}');
  check('callable error keeps status, message and reason code',
      e1 != null && e1.code == 'failed-precondition' && e1.detailCode == 'CLAIMED_BY_OTHER' && e1.message == 'Already claimed by Ana.' && !e1.isIndeterminate);

  final e2 = thrown(404, '<html>Not found</html>');
  check('404 (function not deployed) is reported as unreachable / indeterminate', e2 != null && e2.isIndeterminate);

  final e3 = thrown(500, 'oops');
  check('unparseable server error becomes an internal (indeterminate) error', e3 != null && e3.code == 'internal' && e3.isIndeterminate);

  final e4 = thrown(403, '{"error":{"status":"PERMISSION_DENIED","message":"Staff access required."}}');
  check('permission-denied maps to a non-indeterminate error', e4 != null && e4.code == 'permission-denied' && !e4.isIndeterminate);

  if (failed > 0) {
    print('$failed failed');
    exit(1);
  }
  print('All staff_ops_errors checks passed');
}
