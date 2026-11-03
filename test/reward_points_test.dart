import 'dart:io';

import 'package:tranyx_admin_portal/core/models/reward_points.dart';

/// Plain script test: `dart run test/reward_points_test.dart`.
void main() {
  var failed = 0;
  void check(String name, bool ok) {
    print('${ok ? 'PASS' : 'FAIL'}  $name');
    if (!ok) failed++;
  }

  check('plain number', parseAwardPoints('100') == 100);
  check('spaces and commas tolerated', parseAwardPoints(' 1,500 ') == 1500);
  check('empty / zero / negative / decimal / text rejected',
      parseAwardPoints('') == null && parseAwardPoints('0') == null && parseAwardPoints('-5') == null && parseAwardPoints('1.5') == null && parseAwardPoints('abc') == null);
  check('upper bound', parseAwardPoints('100000') == 100000 && parseAwardPoints('100001') == null);

  if (failed > 0) {
    print('$failed failed');
    exit(1);
  }
  print('All reward_points checks passed');
}
