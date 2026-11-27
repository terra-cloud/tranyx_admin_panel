import 'dart:io';

import 'package:tranyx_admin_portal/core/access/staff_award_points.dart';
import 'package:tranyx_admin_portal/core/services/staff_ops_errors.dart';

/// `dart run test/staff_award_points_test.dart`
void main() {
  var failed = 0;
  void check(String name, bool ok) {
    print('${ok ? 'PASS' : 'FAIL'}  $name');
    if (!ok) failed++;
  }

  final named = buildStaffAwardPointsData(
    targetUid: 'member',
    questId: 'register_account',
    category: 'Onboarding',
    title: 'Register Account',
    points: 500,
  );
  check(
    'named quest body has no client points',
    named.length == 2 && named['targetUid'] == 'member' && named['questId'] == 'register_account' && !named.containsKey('points'),
  );

  final custom = buildStaffAwardPointsData(
    targetUid: ' member ',
    questId: 'custom_173000',
    category: 'Custom',
    title: '  Community bonus  ',
    points: 1000,
  );
  check(
    'custom award sends the cap, the reason, and no extra fields',
    custom.length == 4 &&
        custom['targetUid'] == 'member' &&
        custom['questId'] == 'custom_173000' &&
        custom['points'] == 1000 &&
        custom['reason'] == 'Community bonus',
  );

  StaffOpsException? over;
  try {
    buildStaffAwardPointsData(
      targetUid: 'member',
      questId: 'custom_1',
      category: 'Custom',
      title: 'Too much',
      points: 1001,
    );
  } on StaffOpsException catch (e) {
    over = e;
  }
  check('custom points above 1000 are refused', over != null && over.code == 'invalid-argument');

  StaffOpsException? blank;
  try {
    buildStaffAwardPointsData(
      targetUid: 'member',
      questId: 'custom_1',
      category: 'Custom',
      title: '   ',
      points: 10,
    );
  } on StaffOpsException catch (e) {
    blank = e;
  }
  check('a custom award without a reason is refused', blank != null);

  if (failed > 0) {
    print('$failed failed');
    exit(1);
  }
  print('All staff_award_points checks passed');
}
