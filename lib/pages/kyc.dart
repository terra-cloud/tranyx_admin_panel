import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../core/providers/environment_provider.dart';

class KycSubmission {
  final String uid;
  final String userName;
  final String idType;
  final String idNumber;
  final String status;
  final int submittedAt;

  KycSubmission({
    required this.uid,
    required this.userName,
    required this.idType,
    required this.idNumber,
    required this.status,
    required this.submittedAt,
  });

  factory KycSubmission.fromMap(String uid, Map<String, dynamic> map) {
    int parseDateTime(dynamic val) {
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }
    return KycSubmission(
      uid: uid,
      userName: map['userName'] ?? map['name'] ?? 'Unknown User',
      idType: map['idType'] ?? 'Government ID',
      idNumber: map['idNumber'] ?? 'N/A',
      status: map['status'] ?? 'Pending',
      submittedAt: parseDateTime(map['submittedAt'] ?? map['createdAt']),
    );
  }
}

final kycQueueStreamProvider = StreamProvider<List<KycSubmission>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('kyc_submissions')
      .snapshots()
      .map((snap) {
        final list = snap.docs.map((doc) => KycSubmission.fromMap(doc.id, doc.data())).toList();
        list.sort((a, b) {
          if (a.status == 'Pending' && b.status != 'Pending') return -1;
          if (a.status != 'Pending' && b.status == 'Pending') return 1;
          return b.submittedAt.compareTo(a.submittedAt);
        });
        return list;
      })
      .handleError((err) {
        print('[KYC] Stream failed: $err');
        return <KycSubmission>[];
      });
});

class KycPage extends StatelessComponent {
  const KycPage({super.key});

  @override
  Component build(BuildContext context) {
    final kycListAsync = context.watch(kycQueueStreamProvider);

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0]', [
      // Modern Header block
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [text('KYC Verification Queue')]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            text('Audit user verification documents and clear trust levels.'),
          ]),
        ]),
        kycListAsync.when(
          data: (list) {
            final pending = list.where((k) => k.status == 'Pending').length;
            return span(
              classes:
                  'text-xs font-bold px-4 py-1.5 bg-white border border-zinc-200/50 rounded-full text-amber-500 shadow-sm',
              [text('$pending Pending Requests')],
            );
          },
          loading: () => span([text('Loading...')]),
          error: (_, __) => span([text('Error')]),
        ),
      ]),

      // Queue List View in light theme card
      kycListAsync.when(
        data: (kycList) {
          if (kycList.isEmpty) {
            return div(
              classes:
                  'flex-grow flex flex-col items-center justify-center text-center p-16 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
              [
                span(classes: 'text-3xl mb-3', [text('🗂️')]),
                h3(classes: 'text-sm font-bold text-zinc-900', [text('KYC queue is empty')]),
                p(classes: 'text-xs text-zinc-500 mt-1', [text('No verification files in this environment database.')]),
              ],
            );
          }

          return div(classes: 'flex flex-col gap-4 overflow-y-auto max-h-[600px] pr-2 no-scrollbar', [
            for (final submission in kycList)
              div(
                classes:
                    'p-5 rounded-[24px] bg-white border border-zinc-200/50 flex flex-col sm:flex-row justify-between sm:items-center gap-4 hover:border-zinc-300 transition-all duration-200 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
                [
                  div(classes: 'flex items-start gap-4', [
                    span(classes: 'text-2xl p-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-2xl', [
                      text(submission.idType.toLowerCase().contains('passport') ? '🛂' : '🪪'),
                    ]),
                    div(classes: 'flex flex-col gap-1 min-w-0', [
                      span(classes: 'font-bold text-sm text-zinc-900', [text(submission.userName)]),
                      div(classes: 'flex items-center gap-2 mt-0.5', [
                        span(classes: 'text-[10px] text-zinc-400 font-mono', [text('UID: ${submission.uid}')]),
                        span(classes: 'text-[10px] text-zinc-300', [text('•')]),
                        span(classes: 'text-[10px] text-zinc-500 font-medium', [
                          text('${submission.idType}: ${submission.idNumber}'),
                        ]),
                      ]),
                    ]),
                  ]),

                  // Status Badge or Approve/Reject Controls
                  if (submission.status == 'Pending')
                    div(classes: 'flex items-center gap-2 self-end sm:self-auto', [
                      button(
                        onClick: () async {
                          final firestore = context.read(firestoreProvider);
                          await firestore.collection('kyc_submissions').doc(submission.uid).update({
                            'status': 'Rejected',
                          });
                          await firestore.collection('users').doc(submission.uid).update({
                            'idVerified': false,
                            'verificationLevel': 0,
                          });
                        },
                        classes:
                            'px-4 py-2 rounded-full border border-red-200 bg-red-50/50 hover:bg-red-100/50 text-red-500 text-xs font-bold transition-all',
                        [text('Reject')],
                      ),
                      button(
                        onClick: () async {
                          final firestore = context.read(firestoreProvider);
                          final userDoc = await firestore.collection('users').doc(submission.uid).get();
                          final isBgChecked = userDoc.data()?['bgChecked'] ?? false;

                          await firestore.collection('kyc_submissions').doc(submission.uid).update({
                            'status': 'Approved',
                          });
                          await firestore.collection('users').doc(submission.uid).update({
                            'idVerified': true,
                            'verificationLevel': isBgChecked ? 2 : 1,
                          });
                        },
                        classes:
                            'px-4 py-2 rounded-full bg-black hover:bg-zinc-800 text-white text-xs font-bold transition-all shadow-md shadow-black/10',
                        [text('Approve')],
                      ),
                    ])
                  else if (submission.status == 'Approved')
                    span(
                      classes:
                          'self-end sm:self-auto px-4 py-1.5 rounded-full border border-emerald-200 bg-[#e2f1e9] text-[#0fa958] text-[10px] font-extrabold flex items-center gap-1',
                      [text('✓ Approved')],
                    )
                  else
                    span(
                      classes:
                          'self-end sm:self-auto px-4 py-1.5 rounded-full border border-red-200 bg-red-50 text-red-500 text-[10px] font-extrabold flex items-center gap-1',
                      [text('✗ Rejected')],
                    ),
                ],
              ),
          ]);
        },
        loading: () => div(
          classes:
              'flex-grow flex justify-center items-center py-20 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
          [div(classes: 'animate-spin h-6 w-6 border-2 border-zinc-200 border-t-indigo-500 rounded-full', [])],
        ),
        error: (err, _) => div(
          classes: 'p-6 bg-red-50/5 border border-red-500/10 text-red-500 text-xs rounded-[20px] font-mono shadow-sm',
          [text('Error loading KYC: $err')],
        ),
      ),
    ]);
  }
}
