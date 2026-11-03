import 'dart:io';

import 'package:tranyx_admin_portal/core/models/work_status.dart';

/// Plain script test: `dart run test/work_status_test.dart`.
void main() {
  var failed = 0;
  void check(String name, bool ok) {
    print('${ok ? 'PASS' : 'FAIL'}  $name');
    if (!ok) failed++;
  }

  String ws(String app, String uid, Map<String, dynamic>? job) => workStatusFor(applicationStatus: app, applicantUid: uid, job: job);

  check('hired applicant of a job awaiting acknowledgment', ws('Pending', 'w1', {'acceptedApplicantId': 'w1', 'status': 'Awaiting Acknowledgment'}) == kAwaitingAcknowledgement);
  check('spelling / casing variants', ws('Pending', 'w1', {'acceptedApplicantId': 'w1', 'status': 'awaiting_acknowledgement'}) == kAwaitingAcknowledgement);
  check('other applicants keep their own status', ws('Pending', 'w2', {'acceptedApplicantId': 'w1', 'status': 'Awaiting Acknowledgment'}) == 'Pending');
  check('after the Nyxian acknowledges the job status drives it', ws('Pending', 'w1', {'acceptedApplicantId': 'w1', 'status': 'In Progress'}) == 'In Progress');
  check('expired acknowledgment is shown as such', ws('Pending', 'w1', {'acceptedApplicantId': 'w1', 'status': 'Acknowledgment Expired'}) == 'Acknowledgement Expired');
  check('no job doc: application status unchanged', ws('Accepted', 'w1', null) == 'Accepted');
  check('open job (re-opened): application status unchanged', ws('Pending', 'w1', {'acceptedApplicantId': 'w1', 'status': 'Open'}) == 'Pending');

  if (failed > 0) {
    print('$failed failed');
    exit(1);
  }
  print('All work_status checks passed');
}
