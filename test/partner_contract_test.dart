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
  check('province is not part of the slug', slugArea('Calbayog') == slugArea('  calbayog '));

  StaffOpsException? duplicate;
  try {
    partnerAreas([
      {'city': 'Calbayog', 'municipality': '', 'province': 'Samar', 'region': ''},
      {'city': 'Calbayog', 'municipality': '', 'province': 'Leyte', 'region': ''},
    ]);
  } on StaffOpsException catch (error) {
    duplicate = error;
  }
  check(
    'a repeated active slug is already-exists before the request',
    duplicate != null && duplicate.code == 'already-exists' && duplicate.detailCode == 'DUPLICATE_AREA',
  );

  final created = partnerCreateData(
    callerEmail: 'admin@tranyx.app',
    email: 'partner@example.com',
    areas: [
      {'city': 'Calbayog City', 'municipality': '', 'province': 'Samar', 'region': 'Eastern Visayas'},
    ],
  );
  check(
    'create sends the partnerAdmin fields and no password',
    created['action'] == 'create' &&
        created['email'] == 'partner@example.com' &&
        created['termMonths'] == 36 &&
        created['partnerShareBps'] == 7000 &&
        !created.containsKey('password') &&
        (created['areas'] as List).length == 1,
  );
  check('tranyx share is the remainder of 10000', tranyxShareBps(7000) == 3000);

  StaffOpsException? self;
  try {
    partnerCreateData(callerEmail: 'admin@tranyx.app', email: 'admin@tranyx.app', areas: [
      {'city': 'Calbayog', 'municipality': '', 'province': '', 'region': ''},
    ]);
  } on StaffOpsException catch (error) {
    self = error;
  }
  check('a caller cannot make their own account a partner', self != null && self.detailCode == 'SELF_ROLE');

  final update = partnerUpdateData(partnerId: 'uid1', termMonths: 24, partnerShareBps: 6500);
  check('update names partnerId and the changed license fields', update['action'] == 'update' && update['partnerId'] == 'uid1' && update['termMonths'] == 24);

  check(
    'suspend and payout bodies stay on the contract actions',
    partnerStatusData(action: 'suspend', partnerId: 'uid1')['action'] == 'suspend' &&
        partnerPayoutData(action: 'markPayoutPaid', payoutId: 'uid1_2026-03')['payoutId'] == 'uid1_2026-03' &&
        partnerRevenueConfigData(includeSubscriptions: true)['includeSubscriptions'] == true &&
        partnerOverviewData()['action'] == 'overview',
  );

  final directory = partnerDeskData(action: 'directory', areaKey: 'Calbayog City', kind: 'users');
  check('directory sends the slug and a masked-list kind', directory['areaKey'] == 'calbayog-city' && directory['kind'] == 'users');

  StaffOpsException? outsidePeriod;
  try {
    partnerDeskData(action: 'statement', period: 'March');
  } on StaffOpsException catch (error) {
    outsidePeriod = error;
  }
  check('a statement period must be YYYY-MM', outsidePeriod != null && outsidePeriod.message.contains('YYYY-MM'));

  StaffOpsException? flag;
  try {
    partnerDeskData(action: 'review', kind: 'rental', id: 'r1', decision: 'flagged', reason: 'no');
  } on StaffOpsException catch (error) {
    flag = error;
  }
  check('a flag needs a short reason', flag != null && flag.message.contains('reason'));

  final outside = partnerFacingError(const StaffOpsException(
    'permission-denied',
    'That area is outside this license.',
    detailCode: 'OUTSIDE_AREA',
  ));
  final taken = partnerFacingError(const StaffOpsException(
    'already-exists',
    'Another active partner already covers calbayog.',
    detailCode: 'DUPLICATE_AREA',
  ));
  final mfa = partnerFacingError(const StaffOpsException(
    'failed-precondition',
    'Partner sign-in requires a second factor.',
    detailCode: 'MFA_REQUIRED',
  ));
  check('OUTSIDE_AREA stays visible', outside.startsWith('OUTSIDE_AREA:'));
  check('already-exists stays visible', taken.startsWith('already-exists:'));
  check('MFA_REQUIRED tells the partner to enable 2FA', mfa.startsWith('Enable 2FA'));

  StaffOpsException? listed;
  try {
    parseStaffOpsResponse(
      403,
      jsonEncode({
        'error': {
          'status': 'PERMISSION_DENIED',
          'message': 'That area is outside this license.',
          'details': [
            {'reason': 'OUTSIDE_AREA'},
          ],
        },
      }),
    );
  } on StaffOpsException catch (error) {
    listed = error;
  }
  check('list-shaped callable details keep OUTSIDE_AREA', listed != null && listed.detailCode == 'OUTSIDE_AREA');

  final pdf = utf8.decode(buildStatementPdf({
    'period': '2026-03',
    'partnerId': 'uid1',
    'grossBookings': 10,
    'platformRevenue': 4,
    'partnerShare': 2.8,
    'tranyxShare': 1.2,
    'lines': [
      {'source': 'vehicle_rental', 'sourceId': 'escrow1', 'areaKey': 'calbayog', 'status': 'settled', 'partnerShare': 2.8},
    ],
  }));
  check('the client PDF is a PDF and names the statement period', pdf.startsWith('%PDF-1.4') && pdf.contains('Period 2026-03') && pdf.contains('%%EOF'));
  check('the CSV header matches the workspace contract', statementCsvHeader.startsWith('period,source,sourceId,areaKey,status,gross'));

  check('partner is a portal role and not an admin or a staff claim', portalRoleIsPartner('partner') && portalRoleMayUsePortal('partner') && !portalRoleIsAdmin('partner') && workspaceClaimRole('partner') == null);
  check('manila period uses the UTC month of ms plus eight hours', manilaPeriod(DateTime.utc(2026, 3, 1).millisecondsSinceEpoch - 8 * 3600000) == '2026-03');

  if (failed > 0) {
    print('$failed failed');
    exit(1);
  }
  print('All partner_contract checks passed');
}
