import 'dart:convert';
import 'dart:io';

import 'package:tranyx_admin_portal/core/access/partner_contract.dart';
import 'package:tranyx_admin_portal/core/access/portal_role.dart';
import 'package:tranyx_admin_portal/core/services/staff_ops_errors.dart';

/// `dart run test/partner_contract_test.dart`
void main() {
  var failed = 0;
  void check(String name, bool ok) {
    print('${ok ? 'PASS' : 'FAIL'}  $name');
    if (!ok) failed++;
  }

  check('calbayog and calbayog city are different slugs', slugArea('Calbayog') == 'calbayog' && slugArea('Calbayog City') == 'calbayog-city');

  StaffOpsException? duplicate;
  try {
    partnerAreas([
      {'city': 'Calbayog', 'municipality': '', 'province': 'Samar', 'region': ''},
      {'city': 'Calbayog', 'municipality': '', 'province': 'Leyte', 'region': ''},
    ]);
  } on StaffOpsException catch (error) {
    duplicate = error;
  }
  check('a repeated area is already-exists before the request', duplicate != null && duplicate.code == 'already-exists' && duplicate.detailCode == 'DUPLICATE_AREA');

  final created = partnerCreateData(
    callerEmail: 'admin@tranyx.app',
    email: 'partner@example.com',
    password: 'Calbayog1',
    areas: [
      {'city': 'Calbayog', 'municipality': '', 'province': 'Samar', 'region': 'Eastern Visayas'},
    ],
    termMonths: 36,
    licenseFeePaid: 50000,
  );
  check(
    'create stores the license and sends the password only in the callable body',
    created['action'] == 'create' &&
        created['email'] == 'partner@example.com' &&
        created['password'] == 'Calbayog1' &&
        created['termMonths'] == 36 &&
        created['licenseFeePaid'] == 50000 &&
        created['partnerShareBps'] == partnerShareDefaultBps &&
        partnerShareDefaultBps == 3000 &&
        tranyxShareDefaultBps == 7000 &&
        !created.containsKey('targets') &&
        !created.containsKey('passwordSetupLink') &&
        partnerAccountsData()['action'] == 'accounts',
  );
  StaffOpsException? weak;
  try {
    partnerCreateData(callerEmail: 'admin@tranyx.app', email: 'p@example.com', password: 'short', areas: [
      {'city': 'Calbayog', 'municipality': '', 'province': '', 'region': ''},
    ]);
  } on StaffOpsException catch (error) {
    weak = error;
  }
  check('a weak password is refused before it is sent', weak != null && !weak.message.contains('short'));

  final directory = partnerDirectoryData(areaKey: 'Calbayog', kind: 'hosts');
  check('directory sends the area slug', directory['areaKey'] == 'calbayog' && directory['kind'] == 'hosts');
  check(
    'review is approve, verify, or flag and not a user suspension',
    partnerReviewData(kind: 'rental', id: 'r1', decision: 'verified')['decision'] == 'verified' &&
        reviewKindForDirectory('gigs') == 'job' &&
        reviewKindForDirectory('bookings').isEmpty,
  );

  StaffOpsException? flag;
  try {
    partnerReviewData(kind: 'provider', id: 'u1', decision: 'flagged', reason: 'no');
  } on StaffOpsException catch (error) {
    flag = error;
  }
  check('a flag needs a short reason', flag != null && flag.message.contains('reason'));

  final outside = partnerFacingError(const StaffOpsException('permission-denied', 'That area is outside this license.', detailCode: 'OUTSIDE_AREA'));
  final taken = partnerFacingError(const StaffOpsException('already-exists', 'Another active partner already covers calbayog.', detailCode: 'DUPLICATE_AREA'));
  final mfa = partnerFacingError(const StaffOpsException('failed-precondition', 'Partner sign-in requires a second factor.', detailCode: 'MFA_REQUIRED'));
  check('OUTSIDE_AREA stays visible', outside.startsWith('OUTSIDE_AREA:'));
  check('already-exists stays visible', taken.startsWith('already-exists:'));
  check('MFA_REQUIRED tells the partner to enable 2FA', mfa.startsWith('Enable 2FA'));

  StaffOpsException? listed;
  try {
    parseStaffOpsResponse(403, jsonEncode({
      'error': {
        'status': 'PERMISSION_DENIED',
        'message': 'That area is outside this license.',
        'details': [
          {'reason': 'OUTSIDE_AREA'},
        ],
      },
    }));
  } on StaffOpsException catch (error) {
    listed = error;
  }
  check('list-shaped callable details keep OUTSIDE_AREA', listed != null && listed.detailCode == 'OUTSIDE_AREA');
  check('partner is a portal role and not an admin or a staff claim', portalRoleIsPartner('partner') && portalRoleMayUsePortal('partner') && !portalRoleIsAdmin('partner') && workspaceClaimRole('partner') == null);
  check('phase 1 does not build a statement body', !partnerDirectoryKinds.contains('statement') && partnerProfileData()['action'] == 'profile');
  final resend = partnerResendVerificationData(email: 'Partner@Example.com');
  check(
    'resend verification names the email and does not carry a password',
    resend['action'] == 'resendVerification' && resend['email'] == 'partner@example.com' && !resend.containsKey('password') && partnerRevenueData()['action'] == 'revenue',
  );

  if (failed > 0) {
    print('$failed failed');
    exit(1);
  }
  print('All partner_contract checks passed');
}
