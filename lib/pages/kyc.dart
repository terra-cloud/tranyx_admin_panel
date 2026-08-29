import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../core/providers/environment_provider.dart';
import 'users.dart';

class KycSubmission {
  final String uid;
  final String userName;
  final String idType;
  final String idNumber;
  final String status;
  final int submittedAt;
  final String? frontUrl;
  final String? backUrl;
  final String? selfieUrl;
  final String? clearanceType;
  final String? clearanceNumber;
  final String? expiryDate;
  final String? documentUrl;

  KycSubmission({
    required this.uid,
    required this.userName,
    required this.idType,
    required this.idNumber,
    required this.status,
    required this.submittedAt,
    this.frontUrl,
    this.backUrl,
    this.selfieUrl,
    this.clearanceType,
    this.clearanceNumber,
    this.expiryDate,
    this.documentUrl,
  });

  factory KycSubmission.fromMap(String uid, Map<String, dynamic> map) {
    int parseDateTime(dynamic val) {
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    final idMap = map['idVerification'] as Map<String, dynamic>?;
    final bgMap = map['backgroundCheck'] as Map<String, dynamic>?;

    String rawStatus = map['status'] ?? 'Pending';
    if (idMap != null && idMap['status'] != null) {
      rawStatus = idMap['status'];
    } else if (bgMap != null && bgMap['status'] != null) {
      rawStatus = bgMap['status'];
    }

    // Case-insensitive normalization to Title Case
    String resStatus = 'Pending';
    final normalized = rawStatus.toLowerCase();
    if (normalized == 'approved') {
      resStatus = 'Approved';
    } else if (normalized == 'rejected') {
      resStatus = 'Rejected';
    } else {
      resStatus = 'Pending';
    }

    return KycSubmission(
      uid: uid,
      userName: map['fullName'] ?? map['userName'] ?? map['name'] ?? 'Unknown User',
      idType: map['idType'] ?? idMap?['idType'] ?? 'Government ID',
      idNumber: map['idNumber'] ?? idMap?['idNumber'] ?? 'N/A',
      status: resStatus,
      submittedAt: parseDateTime(
        map['submittedAt'] ?? map['createdAt'] ?? idMap?['submittedAt'] ?? bgMap?['submittedAt'],
      ),
      frontUrl: idMap?['frontUrl'],
      backUrl: idMap?['backUrl'],
      selfieUrl: idMap?['selfieUrl'],
      clearanceType: bgMap?['clearanceType'],
      clearanceNumber: bgMap?['clearanceNumber'],
      expiryDate: bgMap?['expiryDate'],
      documentUrl: bgMap?['documentUrl'],
    );
  }
}

final kycQueueStreamProvider = StreamProvider<List<KycSubmission>>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(<KycSubmission>[]);
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('kyc_submissions')
      .snapshots()
      .map((snap) {
        final list = snap.docs.map((doc) => KycSubmission.fromMap(doc.id, doc.data())).toList();
        list.sort((kycA, kycB) {
          if (kycA.status == 'Pending' && kycB.status != 'Pending') return -1;
          if (kycA.status != 'Pending' && kycB.status == 'Pending') return 1;
          return kycB.submittedAt.compareTo(kycA.submittedAt);
        });
        return list;
      })
      .handleError((err) {
        print('[KYC] Stream failed: $err');
        return <KycSubmission>[];
      });
});

class KycPage extends StatefulComponent {
  const KycPage({super.key});

  @override
  State<KycPage> createState() => _KycPageState();
}

class _KycPageState extends State<KycPage> {
  KycSubmission? _selectedSubmission;

  // Unified status update helper to keep root and sub-map statuses in perfect sync
  Future<void> _updateKycStatus(String uid, String status, {bool isApprove = false}) async {
    final firestore = context.read(firestoreProvider);
    final submissionDoc = await firestore.collection('kyc_submissions').doc(uid).get();
    final data = submissionDoc.data() ?? {};

    final updates = <String, dynamic>{
      'status': status,
    };

    final lowercaseStatus = status.toLowerCase();

    if (data['idVerification'] != null) {
      final idVal = Map<String, dynamic>.from(data['idVerification']);
      idVal['status'] = lowercaseStatus;
      updates['idVerification'] = idVal;
    }
    if (data['backgroundCheck'] != null) {
      final bgVal = Map<String, dynamic>.from(data['backgroundCheck']);
      bgVal['status'] = lowercaseStatus;
      updates['backgroundCheck'] = bgVal;
    }

    await firestore.collection('kyc_submissions').doc(uid).update(updates);

    if (isApprove) {
      final userDoc = await firestore.collection('users').doc(uid).get();
      final isBgChecked = userDoc.data()?['bgChecked'] ?? false;
      await firestore.collection('users').doc(uid).update({
        'idVerified': true,
        'verificationLevel': isBgChecked ? 2 : 1,
      });
    } else {
      await firestore.collection('users').doc(uid).update({
        'idVerified': false,
        'verificationLevel': 0,
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final kycListAsync = context.watch(kycQueueStreamProvider);
    final users = context.watch(usersStreamProvider).value ?? [];

    return div(classes: 'flex-grow p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0] relative', [
      // Modern Header block
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [Component.text('KYC Verification Queue')]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text('Audit user verification documents and clear trust levels.'),
          ]),
        ]),
        kycListAsync.when(
          data: (list) {
            final pending = list.where((k) => k.status == 'Pending').length;
            return span(
              classes:
                  'text-xs font-bold px-4 py-1.5 bg-white border border-zinc-200/50 rounded-full text-amber-500 shadow-sm',
              [Component.text('$pending Pending Requests')],
            );
          },
          loading: () => span([Component.text('Loading...')]),
          error: (err, stack) => span([Component.text('Error')]),
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
                span(classes: 'text-3xl mb-3', [Component.text('🗂️')]),
                h3(classes: 'text-sm font-bold text-zinc-900', [Component.text('KYC queue is empty')]),
                p(classes: 'text-xs text-zinc-500 mt-1', [
                  Component.text('No verification files in this environment database.'),
                ]),
              ],
            );
          }

          return div(classes: 'flex flex-col gap-4 overflow-y-auto max-h-[600px] pr-2 no-scrollbar', [
            for (final submission in kycList)
              () {
                final userProfile = users.firstWhere(
                  (userItem) => userItem.uid == submission.uid,
                  orElse: () => UserProfileModel(
                    uid: submission.uid,
                    name: submission.userName,
                    email: '',
                    idVerified: false,
                    bgChecked: false,
                    verificationLevel: 0,
                    banned: false,
                  ),
                );
                final resolvedName = userProfile.name == 'Unknown User' ? submission.userName : userProfile.name;

                return div(
                  classes:
                      'p-5 rounded-[24px] bg-white border border-zinc-200/50 flex flex-col sm:flex-row justify-between sm:items-center gap-4 hover:border-zinc-300 transition-all duration-200 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
                  [
                    div(
                      events: {'click': (_) => setState(() => _selectedSubmission = submission)},
                      classes:
                          'flex items-start gap-4 cursor-pointer hover:opacity-85 transition-opacity flex-1 min-w-0',
                      [
                        span(
                          classes: 'text-2xl p-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-2xl flex-shrink-0',
                          [
                            Component.text(submission.idType.toLowerCase().contains('passport') ? '🛂' : '🪪'),
                          ],
                        ),
                        div(classes: 'flex flex-col gap-1 min-w-0', [
                          span(
                            classes:
                                'font-bold text-sm text-zinc-900 hover:text-indigo-600 transition-colors flex items-center gap-1.5',
                            [
                              Component.text(resolvedName),
                              span(
                                classes:
                                    'text-[10px] text-indigo-500 font-semibold px-2 py-0.5 rounded-full bg-indigo-50 border border-indigo-100',
                                [Component.text('Inspect File')],
                              ),
                            ],
                          ),
                          div(classes: 'flex items-center gap-2 mt-0.5 flex-wrap', [
                            span(classes: 'text-[10px] text-zinc-400 font-mono', [
                              Component.text('UID: ${submission.uid}'),
                            ]),
                            span(classes: 'text-[10px] text-zinc-300', [Component.text('•')]),
                            span(classes: 'text-[10px] text-zinc-500 font-medium', [
                              Component.text('${submission.idType}: ${submission.idNumber}'),
                            ]),
                          ]),
                        ]),
                      ],
                    ),

                    // Status Badge or Approve/Reject Controls
                    if (submission.status == 'Pending')
                      div(classes: 'flex items-center gap-2 self-end sm:self-auto', [
                        button(
                          onClick: () async {
                            await _updateKycStatus(submission.uid, 'Rejected', isApprove: false);
                          },
                          classes:
                              'px-4 py-2 rounded-full border border-red-200 bg-red-50/50 hover:bg-red-100/50 text-red-500 text-xs font-bold transition-all cursor-pointer outline-none',
                          [Component.text('Reject')],
                        ),
                        button(
                          onClick: () async {
                            await _updateKycStatus(submission.uid, 'Approved', isApprove: true);
                          },
                          classes:
                              'px-4 py-2 rounded-full bg-black hover:bg-zinc-800 text-white text-xs font-bold transition-all shadow-md shadow-black/10 cursor-pointer border-0 outline-none',
                          [Component.text('Approve')],
                        ),
                      ])
                    else if (submission.status == 'Approved')
                      span(
                        classes:
                            'self-end sm:self-auto px-4 py-1.5 rounded-full border border-emerald-200 bg-[#e2f1e9] text-[#0fa958] text-[10px] font-extrabold flex items-center gap-1',
                        [Component.text('✓ Approved')],
                      )
                    else
                      span(
                        classes:
                            'self-end sm:self-auto px-4 py-1.5 rounded-full border border-red-200 bg-red-50 text-red-500 text-[10px] font-extrabold flex items-center gap-1',
                        [Component.text('✗ Rejected')],
                      ),
                  ],
                );
              }(),
          ]);
        },
        loading: () => div(
          classes:
              'flex-grow flex justify-center items-center py-20 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
          [div(classes: 'animate-spin h-6 w-6 border-2 border-zinc-200 border-t-indigo-500 rounded-full', [])],
        ),
        error: (err, _) => div(
          classes: 'p-6 bg-red-50/5 border border-red-500/10 text-red-500 text-xs rounded-[20px] font-mono shadow-sm',
          [Component.text('Error loading KYC: $err')],
        ),
      ),

      // Expandable detailed inspection Modal dialog
      if (_selectedSubmission != null)
        () {
          final userProfile = users.firstWhere(
            (userItem) => userItem.uid == _selectedSubmission!.uid,
            orElse: () => UserProfileModel(
              uid: _selectedSubmission!.uid,
              name: _selectedSubmission!.userName,
              email: '',
              idVerified: false,
              bgChecked: false,
              verificationLevel: 0,
              banned: false,
            ),
          );
          final resolvedName = userProfile.name == 'Unknown User' ? _selectedSubmission!.userName : userProfile.name;

          return div(
            classes: 'fixed inset-0 bg-black/55 backdrop-blur-sm z-[9999] flex items-center justify-center p-4',
            events: {
              'click': (e) {
                final target = e.target as dynamic;
                if (target.getAttribute?.call('id') == 'modal-backdrop') {
                  setState(() => _selectedSubmission = null);
                }
              },
            },
            attributes: {'id': 'modal-backdrop'},
            [
              div(
                classes:
                    'bg-white rounded-[28px] border border-zinc-200 shadow-2xl w-full max-w-2xl overflow-hidden flex flex-col',
                [
                  // Modal Header
                  div(classes: 'p-6 border-b border-zinc-150/60 bg-zinc-50 flex justify-between items-center', [
                    div([
                      h3(classes: 'text-sm font-black text-zinc-950 uppercase tracking-wider', [
                        Component.text('Inspection: $resolvedName'),
                      ]),
                      p(classes: 'text-[11px] text-zinc-400 font-semibold font-mono mt-0.5', [
                        Component.text('UID: ${_selectedSubmission!.uid}'),
                      ]),
                    ]),
                    button(
                      onClick: () => setState(() => _selectedSubmission = null),
                      classes:
                          'p-2 text-zinc-400 hover:text-zinc-700 bg-transparent border-0 cursor-pointer text-lg font-bold outline-none',
                      [Component.text('✕')],
                    ),
                  ]),

                  // Modal Content
                  div(classes: 'p-6 overflow-y-auto max-h-[500px] flex flex-col gap-6 text-left', [
                    // User Details Profile block
                    div(classes: 'flex flex-col gap-3', [
                      h4(
                        classes:
                            'text-xs font-black text-zinc-900 uppercase tracking-wide border-l-2 border-indigo-500 pl-2',
                        [Component.text('User Information')],
                      ),
                      div(
                        classes: 'grid grid-cols-2 gap-3 text-xs bg-zinc-50 p-4 rounded-xl border border-zinc-200/50',
                        [
                          div([
                            span(classes: 'text-zinc-400 font-bold', [Component.text('Full Name: ')]),
                            Component.text(resolvedName),
                          ]),
                          div([
                            span(classes: 'text-zinc-400 font-bold', [Component.text('Email Address: ')]),
                            Component.text(userProfile.email.isNotEmpty ? userProfile.email : 'N/A'),
                          ]),
                          div([
                            span(classes: 'text-zinc-400 font-bold', [Component.text('Phone Number: ')]),
                            Component.text(userProfile.phoneNumber ?? 'N/A'),
                          ]),
                          div([
                            span(classes: 'text-zinc-400 font-bold', [Component.text('Verification Level: ')]),
                            Component.text('Level ${userProfile.verificationLevel}'),
                          ]),
                        ],
                      ),
                    ]),

                    // ID Verification Section
                    if (_selectedSubmission!.frontUrl != null ||
                        _selectedSubmission!.backUrl != null ||
                        _selectedSubmission!.selfieUrl != null ||
                        _selectedSubmission!.idNumber != 'N/A')
                      div(classes: 'flex flex-col gap-3', [
                        h4(
                          classes:
                              'text-xs font-black text-zinc-900 uppercase tracking-wide border-l-2 border-indigo-500 pl-2',
                          [Component.text('Government ID Verification')],
                        ),
                        div(
                          classes: 'grid grid-cols-2 gap-2 text-xs bg-zinc-50 p-3 rounded-xl border border-zinc-200/50',
                          [
                            div([
                              span(classes: 'text-zinc-400 font-bold', [Component.text('ID Type: ')]),
                              Component.text(_selectedSubmission!.idType),
                            ]),
                            div([
                              span(classes: 'text-zinc-400 font-bold', [Component.text('ID Number: ')]),
                              Component.text(_selectedSubmission!.idNumber),
                            ]),
                          ],
                        ),
                        if (_selectedSubmission!.frontUrl != null ||
                            _selectedSubmission!.backUrl != null ||
                            _selectedSubmission!.selfieUrl != null)
                          div(classes: 'grid grid-cols-1 sm:grid-cols-3 gap-4 mt-2', [
                            if (_selectedSubmission!.frontUrl != null)
                              div(classes: 'flex flex-col gap-1.5', [
                                span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                                  Component.text('ID Front'),
                                ]),
                                a(
                                  href: _selectedSubmission!.frontUrl!,
                                  target: Target.blank,
                                  classes:
                                      'block border border-zinc-200 rounded-xl overflow-hidden bg-zinc-50 hover:opacity-95 transition-opacity shadow-sm',
                                  [
                                    img(
                                      src: _selectedSubmission!.frontUrl!,
                                      classes: 'w-full h-32 object-cover bg-zinc-100',
                                    ),
                                  ],
                                ),
                              ]),
                            if (_selectedSubmission!.backUrl != null)
                              div(classes: 'flex flex-col gap-1.5', [
                                span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                                  Component.text('ID Back'),
                                ]),
                                a(
                                  href: _selectedSubmission!.backUrl!,
                                  target: Target.blank,
                                  classes:
                                      'block border border-zinc-200 rounded-xl overflow-hidden bg-zinc-50 hover:opacity-95 transition-opacity shadow-sm',
                                  [
                                    img(
                                      src: _selectedSubmission!.backUrl!,
                                      classes: 'w-full h-32 object-cover bg-zinc-100',
                                    ),
                                  ],
                                ),
                              ]),
                            if (_selectedSubmission!.selfieUrl != null)
                              div(classes: 'flex flex-col gap-1.5', [
                                span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                                  Component.text('Selfie Verification'),
                                ]),
                                a(
                                  href: _selectedSubmission!.selfieUrl!,
                                  target: Target.blank,
                                  classes:
                                      'block border border-zinc-200 rounded-xl overflow-hidden bg-zinc-50 hover:opacity-95 transition-opacity shadow-sm',
                                  [
                                    img(
                                      src: _selectedSubmission!.selfieUrl!,
                                      classes: 'w-full h-32 object-cover bg-zinc-100',
                                    ),
                                  ],
                                ),
                              ]),
                          ]),
                      ]),

                    // Background Check Section
                    if (_selectedSubmission!.documentUrl != null || _selectedSubmission!.clearanceType != null)
                      div(classes: 'flex flex-col gap-3', [
                        h4(
                          classes:
                              'text-xs font-black text-zinc-900 uppercase tracking-wide border-l-2 border-indigo-500 pl-2',
                          [Component.text('Background Check Details')],
                        ),
                        div(
                          classes: 'grid grid-cols-3 gap-2 text-xs bg-zinc-50 p-3 rounded-xl border border-zinc-200/50',
                          [
                            div([
                              span(classes: 'text-zinc-400 font-bold', [Component.text('Type: ')]),
                              Component.text(_selectedSubmission!.clearanceType ?? 'N/A'),
                            ]),
                            div([
                              span(classes: 'text-zinc-400 font-bold', [Component.text('Clearance No: ')]),
                              Component.text(_selectedSubmission!.clearanceNumber ?? 'N/A'),
                            ]),
                            div([
                              span(classes: 'text-zinc-400 font-bold', [Component.text('Expiry: ')]),
                              Component.text(_selectedSubmission!.expiryDate ?? 'N/A'),
                            ]),
                          ],
                        ),
                        if (_selectedSubmission!.documentUrl != null)
                          div(classes: 'flex flex-col gap-1.5 mt-2', [
                            span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                              Component.text('Clearance Document'),
                            ]),
                            _selectedSubmission!.documentUrl!.toLowerCase().contains('.pdf')
                                ? a(
                                    href: _selectedSubmission!.documentUrl!,
                                    target: Target.blank,
                                    classes:
                                        'inline-flex items-center gap-2 p-3 border border-zinc-200 rounded-xl bg-zinc-50 hover:bg-zinc-100 text-xs font-bold text-indigo-650 transition-all no-underline w-fit',
                                    [
                                      span(classes: 'text-lg', [Component.text('📄')]),
                                      Component.text('View Clearance Document (PDF)'),
                                    ],
                                  )
                                : a(
                                    href: _selectedSubmission!.documentUrl!,
                                    target: Target.blank,
                                    classes:
                                        'block border border-zinc-200 rounded-xl overflow-hidden bg-zinc-50 hover:opacity-95 transition-opacity max-w-sm shadow-sm',
                                    [
                                      img(
                                        src: _selectedSubmission!.documentUrl!,
                                        classes: 'w-full h-48 object-contain bg-zinc-100',
                                      ),
                                    ],
                                  ),
                          ]),
                      ]),
                  ]),

                  // Modal Actions / Footer
                  div(classes: 'p-6 border-t border-zinc-150/60 bg-zinc-50 flex justify-end gap-3', [
                    if (_selectedSubmission!.status == 'Pending') ...[
                      button(
                        onClick: () async {
                          await _updateKycStatus(_selectedSubmission!.uid, 'Rejected', isApprove: false);
                          setState(() => _selectedSubmission = null);
                        },
                        classes:
                            'px-5 py-2.5 rounded-xl border border-red-200 bg-red-50/50 hover:bg-red-100/50 text-red-500 text-xs font-bold transition-all cursor-pointer outline-none',
                        [Component.text('Reject Submission')],
                      ),
                      button(
                        onClick: () async {
                          await _updateKycStatus(_selectedSubmission!.uid, 'Approved', isApprove: true);
                          setState(() => _selectedSubmission = null);
                        },
                        classes:
                            'px-5 py-2.5 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-bold transition-all shadow-md shadow-black/10 cursor-pointer border-0 outline-none',
                        [Component.text('Approve Verification')],
                      ),
                    ] else ...[
                      button(
                        onClick: () => setState(() => _selectedSubmission = null),
                        classes:
                            'px-5 py-2.5 rounded-xl bg-zinc-200 hover:bg-zinc-300 text-zinc-800 text-xs font-bold transition-all cursor-pointer border-0 outline-none',
                        [Component.text('Close')],
                      ),
                    ],
                  ]),
                ],
              ),
            ],
          );
        }(),
    ]);
  }
}
