/// Label of the "Awaiting Acknowledgement" work status (TRAD-14).
const String kAwaitingAcknowledgement = 'Awaiting Acknowledgement';

/// Work status of a gig application, as the Bookings (services) tab shows it.
///
/// An application doc keeps its own `status` (usually Pending) even after the employer hires the applicant: the
/// hire is recorded on the job (`acceptedApplicantId` + `status`). The server sets the job to
/// `Awaiting Acknowledgment` on hire and moves it on once the Nyxian acknowledges, so the work status of the
/// hired applicant comes from the job; everybody else keeps the application's own status.
String workStatusFor({
  required String applicationStatus,
  required String applicantUid,
  Map<String, dynamic>? job,
}) {
  if (job == null) return applicationStatus;
  final hired = (job['acceptedApplicantId'] ?? '').toString();
  if (hired.isEmpty || hired != applicantUid) return applicationStatus;

  final jobStatus = (job['status'] ?? '').toString().trim();
  final s = jobStatus.toLowerCase().replaceAll('_', ' ');
  if (s == 'awaiting acknowledgment' || s == 'awaiting acknowledgement') return kAwaitingAcknowledgement;
  if (s == 'acknowledgment expired' || s == 'acknowledgement expired') return 'Acknowledgement Expired';
  if (jobStatus.isEmpty || s == 'open' || s == 'reviewing') return applicationStatus;
  return jobStatus;
}
