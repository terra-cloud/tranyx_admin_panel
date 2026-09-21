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
  final String status; // Overall status: 'Pending', 'Approved', 'Rejected'
  final String idStatus; // 'Pending', 'Approved', 'Rejected', 'None'
  final String bgStatus; // 'Pending', 'Approved', 'Rejected', 'None'
  final bool hasIdVerification;
  final bool hasBackgroundCheck;
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
    required this.idStatus,
    required this.bgStatus,
    required this.hasIdVerification,
    required this.hasBackgroundCheck,
    required this.submittedAt,
    this.frontUrl,
    this.backUrl,
    this.selfieUrl,
    this.clearanceType,
    this.clearanceNumber,
    this.expiryDate,
    this.documentUrl,
  });

  bool get isIdPending => hasIdVerification && idStatus == 'Pending';
  bool get isBgPending => hasBackgroundCheck && bgStatus == 'Pending';
  bool get isAnyPending => isIdPending || isBgPending;
  bool get isIdApproved => idStatus == 'Approved';
  bool get isBgApproved => bgStatus == 'Approved';
  bool get isFullyApproved =>
      (!hasIdVerification || isIdApproved) &&
      (!hasBackgroundCheck || isBgApproved) &&
      (hasIdVerification || hasBackgroundCheck);

  factory KycSubmission.fromMap(String uid, Map<String, dynamic> map) {
    int parseDateTime(dynamic val) {
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    String normalizeStatus(dynamic raw) {
      if (raw == null) return 'Pending';
      final n = raw.toString().toLowerCase().trim();
      if (n == 'approved' || n == 'verified' || n == 'cleared') return 'Approved';
      if (n == 'rejected' || n == 'declined') return 'Rejected';
      return 'Pending';
    }

    final idMap = map['idVerification'] as Map<String, dynamic>?;
    final bgMap = map['backgroundCheck'] as Map<String, dynamic>?;

    final hasId = idMap != null || map['idNumber'] != null || map['frontUrl'] != null;
    final hasBg = bgMap != null || map['clearanceNumber'] != null || map['documentUrl'] != null;

    final idStatus = hasId ? normalizeStatus(idMap?['status'] ?? (bgMap == null ? map['status'] : null)) : 'None';
    final bgStatus = hasBg ? normalizeStatus(bgMap?['status'] ?? (idMap == null ? map['status'] : null)) : 'None';

    String overallStatus;
    if (idStatus == 'Pending' || bgStatus == 'Pending') {
      overallStatus = 'Pending';
    } else if ((idStatus == 'Approved' || !hasId) && (bgStatus == 'Approved' || !hasBg) && (hasId || hasBg)) {
      overallStatus = 'Approved';
    } else if (idStatus == 'Rejected' || bgStatus == 'Rejected') {
      overallStatus = 'Rejected';
    } else {
      overallStatus = normalizeStatus(map['status']);
    }

    return KycSubmission(
      uid: uid,
      userName: map['fullName'] ?? map['userName'] ?? map['name'] ?? 'Unknown User',
      idType: map['idType'] ?? idMap?['idType'] ?? 'Government ID',
      idNumber: map['idNumber'] ?? idMap?['idNumber'] ?? 'N/A',
      status: overallStatus,
      idStatus: idStatus,
      bgStatus: bgStatus,
      hasIdVerification: hasId,
      hasBackgroundCheck: hasBg,
      submittedAt: parseDateTime(
        map['submittedAt'] ?? map['createdAt'] ?? idMap?['submittedAt'] ?? bgMap?['submittedAt'],
      ),
      frontUrl: idMap?['frontUrl'] ?? map['frontUrl'],
      backUrl: idMap?['backUrl'] ?? map['backUrl'],
      selfieUrl: idMap?['selfieUrl'] ?? map['selfieUrl'],
      clearanceType: bgMap?['clearanceType'] ?? map['clearanceType'],
      clearanceNumber: bgMap?['clearanceNumber'] ?? map['clearanceNumber'],
      expiryDate: bgMap?['expiryDate'] ?? map['expiryDate'],
      documentUrl: bgMap?['documentUrl'] ?? map['documentUrl'],
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
          if (kycA.isAnyPending && !kycB.isAnyPending) return -1;
          if (!kycA.isAnyPending && kycB.isAnyPending) return 1;
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
  KycSubmission? _selectedBgCheckSubmission;
  String _activeTab = 'all'; // 'all', 'id', 'bg'
  bool _isProcessing = false;

  // Independent ID Verification update helper
  Future<void> _updateIdStatus(String uid, String status, {bool isApprove = false}) async {
    setState(() => _isProcessing = true);
    try {
      final firestore = context.read(firestoreProvider);
      final submissionDoc = await firestore.collection('kyc_submissions').doc(uid).get();
      final data = submissionDoc.data() ?? {};

      final lowercaseStatus = status.toLowerCase();
      final updates = <String, dynamic>{};

      if (data['idVerification'] != null) {
        final idVal = Map<String, dynamic>.from(data['idVerification']);
        idVal['status'] = lowercaseStatus;
        updates['idVerification'] = idVal;
      } else {
        updates['idVerification'] = {'status': lowercaseStatus};
      }

      final bgMap = data['backgroundCheck'] as Map<String, dynamic>?;
      final bgStatus = (bgMap?['status'] as String? ?? '').toLowerCase();

      // Root status computation
      if (isApprove) {
        if (bgMap == null || bgStatus == 'approved' || bgStatus == 'cleared') {
          updates['status'] = 'Approved';
        } else {
          updates['status'] = 'Pending';
        }
      } else {
        if (bgStatus == 'approved' || bgStatus == 'cleared') {
          updates['status'] = 'Pending';
        } else {
          updates['status'] = 'Rejected';
        }
      }

      await firestore.collection('kyc_submissions').doc(uid).update(updates);

      final userDoc = await firestore.collection('users').doc(uid).get();
      final isBgChecked = userDoc.data()?['bgChecked'] ?? false;

      int newLevel = 0;
      if (isApprove) {
        newLevel = isBgChecked ? 2 : 1;
      } else {
        newLevel = 0;
      }

      await firestore.collection('users').doc(uid).update({
        'idVerified': isApprove,
        'verificationLevel': newLevel,
      });

      // Update local selection if modal is open
      if (_selectedSubmission?.uid == uid) {
        final updatedDoc = await firestore.collection('kyc_submissions').doc(uid).get();
        if (updatedDoc.exists) {
          setState(() => _selectedSubmission = KycSubmission.fromMap(uid, updatedDoc.data()!));
        }
      }
    } catch (e) {
      print('[KYC] Error updating ID status: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // Independent Background Check update helper (Clears user bgChecked in users collection)
  Future<void> _updateBgCheckStatus(String uid, String status, {bool isApprove = false}) async {
    setState(() => _isProcessing = true);
    try {
      final firestore = context.read(firestoreProvider);
      final submissionDoc = await firestore.collection('kyc_submissions').doc(uid).get();
      final data = submissionDoc.data() ?? {};

      final lowercaseStatus = status.toLowerCase();
      final updates = <String, dynamic>{};

      if (data['backgroundCheck'] != null) {
        final bgVal = Map<String, dynamic>.from(data['backgroundCheck']);
        bgVal['status'] = lowercaseStatus;
        updates['backgroundCheck'] = bgVal;
      } else {
        updates['backgroundCheck'] = {'status': lowercaseStatus};
      }

      final idMap = data['idVerification'] as Map<String, dynamic>?;
      final idStatus = (idMap?['status'] as String? ?? '').toLowerCase();

      // Root status computation
      if (isApprove) {
        if (idMap == null || idStatus == 'approved' || idStatus == 'verified') {
          updates['status'] = 'Approved';
        } else {
          updates['status'] = 'Pending';
        }
      } else {
        if (idStatus == 'approved' || idStatus == 'verified') {
          updates['status'] = 'Pending';
        } else {
          updates['status'] = 'Rejected';
        }
      }

      await firestore.collection('kyc_submissions').doc(uid).update(updates);

      final userDoc = await firestore.collection('users').doc(uid).get();
      final isIdVerified = userDoc.data()?['idVerified'] ?? false;

      int newLevel = 0;
      if (isApprove) {
        newLevel = isIdVerified ? 2 : 1;
      } else {
        newLevel = isIdVerified ? 1 : 0;
      }

      // Update both bgChecked and verificationLevel on the user profile!
      await firestore.collection('users').doc(uid).update({
        'bgChecked': isApprove,
        'verificationLevel': newLevel,
      });

      // Update local modal selections if open
      final updatedDoc = await firestore.collection('kyc_submissions').doc(uid).get();
      if (updatedDoc.exists) {
        final updatedSub = KycSubmission.fromMap(uid, updatedDoc.data()!);
        setState(() {
          if (_selectedSubmission?.uid == uid) _selectedSubmission = updatedSub;
          if (_selectedBgCheckSubmission?.uid == uid) _selectedBgCheckSubmission = updatedSub;
        });
      }
    } catch (e) {
      print('[KYC] Error updating Background Check status: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // Update both ID and Background Check simultaneously (Approve/Reject All)
  Future<void> _updateBothStatus(String uid, String status, {bool isApprove = false}) async {
    setState(() => _isProcessing = true);
    try {
      final firestore = context.read(firestoreProvider);
      final submissionDoc = await firestore.collection('kyc_submissions').doc(uid).get();
      final data = submissionDoc.data() ?? {};

      final lowercaseStatus = status.toLowerCase();
      final updates = <String, dynamic>{
        'status': status,
      };

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

      await firestore.collection('users').doc(uid).update({
        'idVerified': isApprove,
        'bgChecked': isApprove,
        'verificationLevel': isApprove ? 2 : 0,
      });

      final updatedDoc = await firestore.collection('kyc_submissions').doc(uid).get();
      if (updatedDoc.exists) {
        final updatedSub = KycSubmission.fromMap(uid, updatedDoc.data()!);
        setState(() {
          if (_selectedSubmission?.uid == uid) _selectedSubmission = updatedSub;
          if (_selectedBgCheckSubmission?.uid == uid) _selectedBgCheckSubmission = updatedSub;
        });
      }
    } catch (e) {
      print('[KYC] Error updating both verification statuses: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Component build(BuildContext context) {
    final kycListAsync = context.watch(kycQueueStreamProvider);
    final users = context.watch(usersStreamProvider).value ?? [];

    return div(classes: 'flex-grow p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0] relative', [
      // Modern Header block with Category Tabs
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [Component.text('KYC Verification Queue')]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text('Audit user identity documents, review background check clearances, and assign trust levels.'),
          ]),
        ]),

        // Tab selection pills
        kycListAsync.when(
          data: (list) {
            final pendingTotal = list.where((k) => k.isAnyPending).length;
            final pendingId = list.where((k) => k.isIdPending).length;
            final pendingBg = list.where((k) => k.isBgPending).length;

            return div(classes: 'flex items-center gap-2 bg-white p-1 border border-zinc-200/50 rounded-full shadow-sm', [
              button(
                onClick: () => setState(() => _activeTab = 'all'),
                classes:
                    'px-4 py-1.5 rounded-full text-xs font-bold transition-all border-0 cursor-pointer outline-none flex items-center gap-1.5 '
                    '${_activeTab == 'all' ? 'bg-black text-white shadow-sm' : 'bg-transparent text-zinc-600 hover:text-zinc-900'}',
                [
                  Component.text('All Queue'),
                  if (pendingTotal > 0)
                    span(
                      classes:
                          'text-[10px] px-1.5 py-0.2 rounded-full ${_activeTab == 'all' ? 'bg-zinc-700 text-white' : 'bg-amber-100 text-amber-800'}',
                      [Component.text('$pendingTotal')],
                    ),
                ],
              ),
              button(
                onClick: () => setState(() => _activeTab = 'id'),
                classes:
                    'px-4 py-1.5 rounded-full text-xs font-bold transition-all border-0 cursor-pointer outline-none flex items-center gap-1.5 '
                    '${_activeTab == 'id' ? 'bg-indigo-600 text-white shadow-sm' : 'bg-transparent text-zinc-600 hover:text-zinc-900'}',
                [
                  Component.text('🪪 ID Verifications'),
                  if (pendingId > 0)
                    span(
                      classes:
                          'text-[10px] px-1.5 py-0.2 rounded-full ${_activeTab == 'id' ? 'bg-indigo-800 text-white' : 'bg-indigo-100 text-indigo-800'}',
                      [Component.text('$pendingId')],
                    ),
                ],
              ),
              button(
                onClick: () => setState(() => _activeTab = 'bg'),
                classes:
                    'px-4 py-1.5 rounded-full text-xs font-bold transition-all border-0 cursor-pointer outline-none flex items-center gap-1.5 '
                    '${_activeTab == 'bg' ? 'bg-emerald-600 text-white shadow-sm' : 'bg-transparent text-zinc-600 hover:text-zinc-900'}',
                [
                  Component.text('🛡️ Background Checks'),
                  if (pendingBg > 0)
                    span(
                      classes:
                          'text-[10px] px-1.5 py-0.2 rounded-full ${_activeTab == 'bg' ? 'bg-emerald-800 text-white' : 'bg-amber-500 text-white font-black animate-pulse'}',
                      [Component.text('$pendingBg')],
                    ),
                ],
              ),
            ]);
          },
          loading: () => span([Component.text('Loading...')]),
          error: (err, stack) => span([Component.text('Error')]),
        ),
      ]),

      // Queue List View in light theme card
      kycListAsync.when(
        data: (kycList) {
          final filteredList = kycList.where((submission) {
            if (_activeTab == 'id') {
              return submission.hasIdVerification;
            } else if (_activeTab == 'bg') {
              return submission.hasBackgroundCheck;
            }
            return true;
          }).toList();

          if (filteredList.isEmpty) {
            return div(
              classes:
                  'flex-grow flex flex-col items-center justify-center text-center p-16 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
              [
                span(classes: 'text-3xl mb-3', [Component.text(_activeTab == 'bg' ? '🛡️' : '🗂️')]),
                h3(classes: 'text-sm font-bold text-zinc-900', [
                  Component.text(
                    _activeTab == 'bg'
                        ? 'No Background Check submissions'
                        : _activeTab == 'id'
                        ? 'No ID Verification submissions'
                        : 'KYC queue is empty',
                  ),
                ]),
                p(classes: 'text-xs text-zinc-500 mt-1', [
                  Component.text('No submissions found in this environment matching the selected filter.'),
                ]),
              ],
            );
          }

          return div(classes: 'flex flex-col gap-4 overflow-y-auto max-h-[600px] pr-2 no-scrollbar', [
            for (final submission in filteredList)
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
                      'p-5 rounded-[24px] bg-white border border-zinc-200/50 flex flex-col lg:flex-row justify-between lg:items-center gap-4 hover:border-zinc-300 transition-all duration-200 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
                  [
                    // Left Column: User info & click to inspect
                    div(
                      events: {'click': (_) => setState(() => _selectedSubmission = submission)},
                      classes:
                          'flex items-start gap-4 cursor-pointer hover:opacity-85 transition-opacity flex-1 min-w-0',
                      [
                        span(
                          classes:
                              'text-2xl p-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-2xl flex-shrink-0 flex items-center justify-center',
                          [
                            Component.text(
                              submission.hasBackgroundCheck && submission.hasIdVerification
                                  ? '🛡️'
                                  : submission.idType.toLowerCase().contains('passport')
                                  ? '🛂'
                                  : '🪪',
                            ),
                          ],
                        ),
                        div(classes: 'flex flex-col gap-1.5 min-w-0', [
                          div(classes: 'flex items-center gap-2 flex-wrap', [
                            span(
                              classes:
                                  'font-bold text-sm text-zinc-900 hover:text-indigo-600 transition-colors flex items-center gap-1.5',
                              [Component.text(resolvedName)],
                            ),
                            span(
                              classes:
                                  'text-[10px] text-zinc-600 font-semibold px-2 py-0.5 rounded-full bg-zinc-100 border border-zinc-200',
                              [Component.text('Level ${userProfile.verificationLevel}')],
                            ),
                            span(
                              classes:
                                  'text-[10px] text-indigo-500 font-semibold px-2 py-0.5 rounded-full bg-indigo-50 border border-indigo-100 hover:bg-indigo-100 transition-colors',
                              [Component.text('Inspect File ↗')],
                            ),
                          ]),
                          div(classes: 'flex items-center gap-2 flex-wrap', [
                            span(classes: 'text-[10px] text-zinc-400 font-mono', [
                              Component.text('UID: ${submission.uid}'),
                            ]),
                            span(classes: 'text-[10px] text-zinc-300', [Component.text('•')]),
                            span(classes: 'text-[10px] text-zinc-500 font-medium', [
                              Component.text('${submission.idType}: ${submission.idNumber}'),
                            ]),
                            if (submission.clearanceType != null) ...[
                              span(classes: 'text-[10px] text-zinc-300', [Component.text('•')]),
                              span(classes: 'text-[10px] text-emerald-700 font-medium', [
                                Component.text('${submission.clearanceType}: ${submission.clearanceNumber ?? "Attached"}'),
                              ]),
                            ],
                          ]),

                          // Dual verification status badges
                          div(classes: 'flex items-center gap-2 mt-1 flex-wrap', [
                            // ID Status Pill
                            if (submission.hasIdVerification)
                              span(
                                classes:
                                    'text-[9px] font-extrabold px-2.5 py-0.5 rounded-full border '
                                    '${submission.idStatus == 'Approved' ? 'bg-[#e2f1e9] text-[#0fa958] border-emerald-200' : submission.idStatus == 'Rejected' ? 'bg-red-50 text-red-500 border-red-200' : 'bg-amber-50 text-amber-600 border-amber-200'}',
                                [
                                  Component.text(
                                    submission.idStatus == 'Approved'
                                        ? '✓ ID Approved'
                                        : submission.idStatus == 'Rejected'
                                        ? '✗ ID Rejected'
                                        : '⏳ ID Pending',
                                  ),
                                ],
                              ),

                            // Background Check Status Pill
                            if (submission.hasBackgroundCheck)
                              span(
                                classes:
                                    'text-[9px] font-extrabold px-2.5 py-0.5 rounded-full border '
                                    '${submission.bgStatus == 'Approved' ? 'bg-[#e2f1e9] text-[#0fa958] border-emerald-200' : submission.bgStatus == 'Rejected' ? 'bg-red-50 text-red-500 border-red-200' : 'bg-emerald-50 text-emerald-700 border-emerald-300 ring-1 ring-emerald-400/30'}',
                                [
                                  Component.text(
                                    submission.bgStatus == 'Approved'
                                        ? '✓ BG Cleared'
                                        : submission.bgStatus == 'Rejected'
                                        ? '✗ BG Rejected'
                                        : '⏳ BG Check Pending',
                                  ),
                                ],
                              )
                            else
                              span(
                                classes: 'text-[9px] font-semibold px-2 py-0.5 rounded-full bg-zinc-100 text-zinc-400',
                                [Component.text('No BG Submitted')],
                              ),
                          ]),
                        ]),
                      ],
                    ),

                    // Right Column: Controls & Actions
                    div(classes: 'flex items-center gap-2 self-end lg:self-auto flex-wrap justify-end', [
                      // Dedicated Background Check review window trigger button
                      if (submission.hasBackgroundCheck)
                        button(
                          onClick: () => setState(() => _selectedBgCheckSubmission = submission),
                          classes:
                              'px-3.5 py-2 rounded-full border text-xs font-bold transition-all cursor-pointer outline-none flex items-center gap-1.5 '
                              '${submission.isBgPending ? 'border-emerald-300 bg-emerald-50 text-emerald-700 hover:bg-emerald-100 shadow-sm' : 'border-zinc-200 bg-zinc-50 hover:bg-zinc-100 text-zinc-700'}',
                          [
                            span(classes: 'text-xs', [Component.text('🛡️')]),
                            Component.text(submission.isBgPending ? 'Review Clearance' : 'Clearance Window'),
                          ],
                        ),

                      // Quick action buttons
                      if (submission.isIdPending && !submission.isBgPending) ...[
                        button(
                          onClick: () async {
                            if (_isProcessing) return;
                            await _updateIdStatus(submission.uid, 'Rejected', isApprove: false);
                          },
                          classes:
                              'px-3.5 py-2 rounded-full border border-red-200 bg-red-50/50 hover:bg-red-100/50 text-red-500 text-xs font-bold transition-all cursor-pointer outline-none',
                          [Component.text('Reject ID')],
                        ),
                        button(
                          onClick: () async {
                            if (_isProcessing) return;
                            await _updateIdStatus(submission.uid, 'Approved', isApprove: true);
                          },
                          classes:
                              'px-3.5 py-2 rounded-full bg-black hover:bg-zinc-800 text-white text-xs font-bold transition-all shadow-md shadow-black/10 cursor-pointer border-0 outline-none',
                          [Component.text('Approve ID')],
                        ),
                      ] else if (submission.isBgPending && !submission.isIdPending) ...[
                        button(
                          onClick: () async {
                            if (_isProcessing) return;
                            await _updateBgCheckStatus(submission.uid, 'Approved', isApprove: true);
                          },
                          classes:
                              'px-3.5 py-2 rounded-full bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-bold transition-all shadow-md shadow-emerald-600/20 cursor-pointer border-0 outline-none flex items-center gap-1',
                          [
                            span(classes: 'text-xs', [Component.text('✓')]),
                            Component.text('Clear BG Check'),
                          ],
                        ),
                      ] else if (submission.isIdPending && submission.isBgPending) ...[
                        button(
                          onClick: () async {
                            if (_isProcessing) return;
                            await _updateBothStatus(submission.uid, 'Approved', isApprove: true);
                          },
                          classes:
                              'px-4 py-2 rounded-full bg-black hover:bg-zinc-800 text-white text-xs font-bold transition-all shadow-md shadow-black/10 cursor-pointer border-0 outline-none flex items-center gap-1',
                          [
                            span(classes: 'text-xs', [Component.text('✓')]),
                            Component.text('Approve All (Lvl 2)'),
                          ],
                        ),
                      ] else if (submission.isFullyApproved) ...[
                        span(
                          classes:
                              'px-3.5 py-1.5 rounded-full border border-emerald-200 bg-[#e2f1e9] text-[#0fa958] text-[10px] font-extrabold flex items-center gap-1',
                          [
                            Component.text(
                              submission.hasBackgroundCheck && submission.hasIdVerification
                                  ? '✓ Fully Cleared (Lvl 2)'
                                  : '✓ Verified (Lvl 1)',
                            ),
                          ],
                        ),
                      ] else ...[
                        span(
                          classes:
                              'px-3.5 py-1.5 rounded-full border border-zinc-200 bg-zinc-100 text-zinc-500 text-[10px] font-extrabold flex items-center gap-1',
                          [Component.text(submission.status)],
                        ),
                      ],
                    ]),
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

      // DEDICATED BACKGROUND CHECK APPROVAL WINDOW / MODAL
      if (_selectedBgCheckSubmission != null)
        _buildBgCheckApprovalModal(_selectedBgCheckSubmission!, users),

      // Expandable detailed General Inspection Modal dialog
      if (_selectedSubmission != null)
        _buildGeneralInspectionModal(_selectedSubmission!, users),
    ]);
  }

  // Dedicated Background Check Approval Window
  Component _buildBgCheckApprovalModal(KycSubmission submission, List<UserProfileModel> users) {
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

    // Check expiry validity if available
    bool isExpired = false;
    if (submission.expiryDate != null && submission.expiryDate!.isNotEmpty) {
      try {
        final parsedExpiry = DateTime.tryParse(submission.expiryDate!);
        if (parsedExpiry != null && parsedExpiry.isBefore(DateTime.now())) {
          isExpired = true;
        }
      } catch (_) {}
    }

    return div(
      classes: 'fixed inset-0 bg-black/60 backdrop-blur-sm z-[10000] flex items-center justify-center p-4',
      events: {
        'click': (e) {
          final target = e.target as dynamic;
          if (target.getAttribute?.call('id') == 'bg-modal-backdrop') {
            setState(() => _selectedBgCheckSubmission = null);
          }
        },
      },
      attributes: {'id': 'bg-modal-backdrop'},
      [
        div(
          classes:
              'bg-white rounded-[28px] border border-zinc-200 shadow-2xl w-full max-w-2xl overflow-hidden flex flex-col animate-in fade-in zoom-in-95 duration-150',
          [
            // Modal Header
            div(
              classes:
                  'p-6 border-b border-zinc-150/60 bg-gradient-to-r from-emerald-50/50 via-zinc-50 to-white flex justify-between items-center',
              [
                div(classes: 'flex items-center gap-3', [
                  span(classes: 'text-3xl p-2 bg-emerald-100/50 border border-emerald-200/50 rounded-2xl', [
                    Component.text('🛡️'),
                  ]),
                  div([
                    h3(classes: 'text-sm font-black text-zinc-950 uppercase tracking-wider flex items-center gap-2', [
                      Component.text('Background Check Clearance Approval Window'),
                    ]),
                    p(classes: 'text-[11px] text-zinc-500 font-medium mt-0.5', [
                      Component.text('Review government clearance records, verify expiration, and grant Level 2 clearance.'),
                    ]),
                  ]),
                ]),
                button(
                  onClick: () => setState(() => _selectedBgCheckSubmission = null),
                  classes:
                      'p-2 text-zinc-400 hover:text-zinc-700 bg-transparent border-0 cursor-pointer text-lg font-bold outline-none',
                  [Component.text('✕')],
                ),
              ],
            ),

            // Modal Body
            div(classes: 'p-6 overflow-y-auto max-h-[520px] flex flex-col gap-6 text-left', [
              // User Information strip
              div(classes: 'flex flex-col gap-2', [
                div(classes: 'flex items-center justify-between', [
                  h4(
                    classes:
                        'text-xs font-black text-zinc-900 uppercase tracking-wide border-l-2 border-emerald-500 pl-2',
                    [Component.text('Applicant Profile')],
                  ),
                  span(
                    classes:
                        'text-[10px] font-bold px-2.5 py-0.5 rounded-full border '
                        '${userProfile.bgChecked ? "bg-[#e2f1e9] text-[#0fa958] border-emerald-200" : "bg-amber-50 text-amber-600 border-amber-200"}',
                    [
                      Component.text(
                        userProfile.bgChecked
                            ? 'Workspace Status: Cleared'
                            : 'Workspace Status: Pending Clearance',
                      ),
                    ],
                  ),
                ]),
                div(
                  classes: 'grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs bg-zinc-50 p-4 rounded-xl border border-zinc-200/50',
                  [
                    div([
                      span(classes: 'text-zinc-400 font-bold block text-[10px] uppercase', [Component.text('Full Name')]),
                      span(classes: 'font-semibold text-zinc-900', [Component.text(resolvedName)]),
                    ]),
                    div([
                      span(classes: 'text-zinc-400 font-bold block text-[10px] uppercase', [Component.text('Email Address')]),
                      span(classes: 'font-semibold text-zinc-900 truncate block', [
                        Component.text(userProfile.email.isNotEmpty ? userProfile.email : 'N/A'),
                      ]),
                    ]),
                    div([
                      span(classes: 'text-zinc-400 font-bold block text-[10px] uppercase', [Component.text('Phone')]),
                      span(classes: 'font-semibold text-zinc-900', [Component.text(userProfile.phoneNumber ?? 'N/A')]),
                    ]),
                    div([
                      span(classes: 'text-zinc-400 font-bold block text-[10px] uppercase', [Component.text('Current Level')]),
                      span(classes: 'font-black text-indigo-600', [Component.text('Level ${userProfile.verificationLevel}')]),
                    ]),
                  ],
                ),
              ]),

              // Clearance Details Card
              div(classes: 'flex flex-col gap-3', [
                h4(
                  classes:
                      'text-xs font-black text-zinc-900 uppercase tracking-wide border-l-2 border-emerald-500 pl-2',
                  [Component.text('Clearance Record Details')],
                ),
                div(
                  classes: 'grid grid-cols-1 sm:grid-cols-3 gap-3 text-xs bg-zinc-50 p-4 rounded-xl border border-zinc-200/50',
                  [
                    div([
                      span(classes: 'text-zinc-400 font-bold block text-[10px] uppercase', [Component.text('Clearance Type')]),
                      span(classes: 'font-bold text-zinc-900', [Component.text(submission.clearanceType ?? 'N/A')]),
                    ]),
                    div([
                      span(classes: 'text-zinc-400 font-bold block text-[10px] uppercase', [Component.text('Clearance Number')]),
                      span(classes: 'font-mono font-bold text-zinc-900', [Component.text(submission.clearanceNumber ?? 'N/A')]),
                    ]),
                    div([
                      span(classes: 'text-zinc-400 font-bold block text-[10px] uppercase', [Component.text('Expiry Date')]),
                      div(classes: 'flex items-center gap-1.5 mt-0.5', [
                        span(classes: 'font-bold text-zinc-900', [Component.text(submission.expiryDate ?? 'N/A')]),
                        if (submission.expiryDate != null && submission.expiryDate!.isNotEmpty)
                          span(
                            classes:
                                'text-[9px] font-black px-1.5 py-0.2 rounded '
                                '${isExpired ? "bg-red-100 text-red-600" : "bg-emerald-100 text-emerald-700"}',
                            [Component.text(isExpired ? 'EXPIRED' : 'VALID')],
                          ),
                      ]),
                    ]),
                  ],
                ),
              ]),

              // Document Preview Card
              div(classes: 'flex flex-col gap-2', [
                div(classes: 'flex justify-between items-center', [
                  h4(
                    classes:
                        'text-xs font-black text-zinc-900 uppercase tracking-wide border-l-2 border-emerald-500 pl-2',
                    [Component.text('Submitted Clearance Document')],
                  ),
                  if (submission.documentUrl != null)
                    a(
                      href: submission.documentUrl!,
                      target: Target.blank,
                      classes: 'text-[11px] font-bold text-emerald-600 hover:text-emerald-700 hover:underline',
                      [Component.text('Open Full Document in New Tab ↗')],
                    ),
                ]),
                if (submission.documentUrl == null || submission.documentUrl!.isEmpty)
                  div(
                    classes: 'p-8 text-center bg-zinc-50 border border-zinc-200/50 rounded-xl text-zinc-400 text-xs',
                    [Component.text('No clearance file attached to this record.')],
                  )
                else if (submission.documentUrl!.toLowerCase().contains('.pdf'))
                  a(
                    href: submission.documentUrl!,
                    target: Target.blank,
                    classes:
                        'flex items-center justify-between p-4 border border-zinc-200 rounded-xl bg-zinc-50 hover:bg-emerald-50/50 hover:border-emerald-300 text-zinc-800 transition-all no-underline shadow-sm group',
                    [
                      div(classes: 'flex items-center gap-3', [
                        span(classes: 'text-2xl', [Component.text('📄')]),
                        div([
                          span(classes: 'font-bold text-xs text-zinc-900 group-hover:text-emerald-700 transition-colors', [
                            Component.text('Clearance Record Document (PDF)'),
                          ]),
                          p(classes: 'text-[10px] text-zinc-400 font-medium mt-0.5', [
                            Component.text('Click to view or download full official PDF clearance.'),
                          ]),
                        ]),
                      ]),
                      span(classes: 'text-xs font-bold text-emerald-600 px-3 py-1.5 bg-emerald-50 border border-emerald-200 rounded-lg', [
                        Component.text('View PDF ↗'),
                      ]),
                    ],
                  )
                else
                  div(classes: 'flex flex-col gap-2', [
                    a(
                      href: submission.documentUrl!,
                      target: Target.blank,
                      classes:
                          'block border border-zinc-200 rounded-2xl overflow-hidden bg-zinc-50 hover:opacity-95 transition-opacity shadow-sm',
                      [
                        img(
                          src: submission.documentUrl!,
                          classes: 'w-full max-h-72 object-contain bg-zinc-100 p-2',
                        ),
                      ],
                    ),
                    span(classes: 'text-[10px] text-zinc-400 text-center font-medium', [
                      Component.text('Click image to open high-resolution original in new tab'),
                    ]),
                  ]),
              ]),
            ]),

            // Modal Actions / Footer
            div(classes: 'p-6 border-t border-zinc-150/60 bg-zinc-50 flex justify-between items-center gap-3', [
              div(classes: 'text-left', [
                span(classes: 'text-[11px] text-zinc-400 font-medium', [
                  Component.text(
                    submission.bgStatus == 'Approved'
                        ? 'Record is cleared. Approving will keep Level 2 trust status active.'
                        : 'Approval will immediately update user.bgChecked and sync provider workspace.',
                  ),
                ]),
              ]),
              div(classes: 'flex items-center gap-3', [
                if (submission.bgStatus == 'Approved') ...[
                  button(
                    onClick: () async {
                      if (_isProcessing) return;
                      await _updateBgCheckStatus(submission.uid, 'Rejected', isApprove: false);
                      setState(() => _selectedBgCheckSubmission = null);
                    },
                    classes:
                        'px-4 py-2.5 rounded-xl border border-red-200 bg-red-50 hover:bg-red-100 text-red-500 text-xs font-bold transition-all cursor-pointer outline-none',
                    [Component.text('Revoke Clearance')],
                  ),
                  button(
                    onClick: () => setState(() => _selectedBgCheckSubmission = null),
                    classes:
                        'px-5 py-2.5 rounded-xl bg-zinc-200 hover:bg-zinc-300 text-zinc-800 text-xs font-bold transition-all cursor-pointer border-0 outline-none',
                    [Component.text('Close Window')],
                  ),
                ] else ...[
                  button(
                    onClick: () async {
                      if (_isProcessing) return;
                      await _updateBgCheckStatus(submission.uid, 'Rejected', isApprove: false);
                      setState(() => _selectedBgCheckSubmission = null);
                    },
                    classes:
                        'px-4 py-2.5 rounded-xl border border-red-200 bg-red-50/50 hover:bg-red-100/50 text-red-500 text-xs font-bold transition-all cursor-pointer outline-none',
                    [Component.text('Reject Clearance')],
                  ),
                  button(
                    onClick: () async {
                      if (_isProcessing) return;
                      await _updateBgCheckStatus(submission.uid, 'Approved', isApprove: true);
                      setState(() => _selectedBgCheckSubmission = null);
                    },
                    classes:
                        'px-5 py-2.5 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-black transition-all shadow-md shadow-emerald-600/20 cursor-pointer border-0 outline-none flex items-center gap-2',
                    [
                      span(classes: 'text-sm', [Component.text('🛡️')]),
                      Component.text(_isProcessing ? 'Clearing...' : 'Approve & Clear Background Check'),
                    ],
                  ),
                ],
              ]),
            ]),
          ],
        ),
      ],
    );
  }

  // Full General Inspection Modal (ID + Background Check)
  Component _buildGeneralInspectionModal(KycSubmission submission, List<UserProfileModel> users) {
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
                  Component.text('KYC Inspection: $resolvedName'),
                ]),
                p(classes: 'text-[11px] text-zinc-400 font-semibold font-mono mt-0.5', [
                  Component.text('UID: ${submission.uid} • Verification Level ${userProfile.verificationLevel}'),
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
                  classes: 'grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs bg-zinc-50 p-4 rounded-xl border border-zinc-200/50',
                  [
                    div([
                      span(classes: 'text-zinc-400 font-bold block text-[10px]', [Component.text('Full Name')]),
                      Component.text(resolvedName),
                    ]),
                    div([
                      span(classes: 'text-zinc-400 font-bold block text-[10px]', [Component.text('Email Address')]),
                      Component.text(userProfile.email.isNotEmpty ? userProfile.email : 'N/A'),
                    ]),
                    div([
                      span(classes: 'text-zinc-400 font-bold block text-[10px]', [Component.text('Phone Number')]),
                      Component.text(userProfile.phoneNumber ?? 'N/A'),
                    ]),
                    div([
                      span(classes: 'text-zinc-400 font-bold block text-[10px]', [Component.text('Trust Level')]),
                      Component.text('Level ${userProfile.verificationLevel}'),
                    ]),
                  ],
                ),
              ]),

              // ID Verification Section
              if (submission.hasIdVerification)
                div(classes: 'flex flex-col gap-3', [
                  div(classes: 'flex items-center justify-between', [
                    h4(
                      classes:
                          'text-xs font-black text-zinc-900 uppercase tracking-wide border-l-2 border-indigo-500 pl-2',
                      [Component.text('Government ID Verification')],
                    ),
                    div(classes: 'flex items-center gap-2', [
                      span(
                        classes:
                            'text-[9px] font-extrabold px-2 py-0.5 rounded-full border '
                            '${submission.idStatus == 'Approved' ? "bg-emerald-50 text-emerald-600 border-emerald-200" : submission.idStatus == 'Rejected' ? "bg-red-50 text-red-500 border-red-200" : "bg-amber-50 text-amber-600 border-amber-200"}',
                        [Component.text('Status: ${submission.idStatus}')],
                      ),
                      if (submission.idStatus == 'Pending') ...[
                        button(
                          onClick: () async {
                            if (_isProcessing) return;
                            await _updateIdStatus(submission.uid, 'Rejected', isApprove: false);
                          },
                          classes:
                              'px-2.5 py-1 rounded-lg border border-red-200 bg-red-50 text-red-500 text-[10px] font-bold cursor-pointer',
                          [Component.text('Reject ID')],
                        ),
                        button(
                          onClick: () async {
                            if (_isProcessing) return;
                            await _updateIdStatus(submission.uid, 'Approved', isApprove: true);
                          },
                          classes:
                              'px-2.5 py-1 rounded-lg bg-indigo-600 text-white text-[10px] font-bold cursor-pointer border-0',
                          [Component.text('Approve ID')],
                        ),
                      ] else if (submission.idStatus == 'Approved') ...[
                        button(
                          onClick: () async {
                            if (_isProcessing) return;
                            await _updateIdStatus(submission.uid, 'Rejected', isApprove: false);
                          },
                          classes:
                              'px-2 py-0.5 rounded border border-zinc-200 text-zinc-500 hover:text-red-500 text-[9px] font-bold cursor-pointer',
                          [Component.text('Revoke ID')],
                        ),
                      ],
                    ]),
                  ]),
                  div(
                    classes: 'grid grid-cols-2 gap-2 text-xs bg-zinc-50 p-3 rounded-xl border border-zinc-200/50',
                    [
                      div([
                        span(classes: 'text-zinc-400 font-bold', [Component.text('ID Type: ')]),
                        Component.text(submission.idType),
                      ]),
                      div([
                        span(classes: 'text-zinc-400 font-bold', [Component.text('ID Number: ')]),
                        Component.text(submission.idNumber),
                      ]),
                    ],
                  ),
                  if (submission.frontUrl != null || submission.backUrl != null || submission.selfieUrl != null)
                    div(classes: 'grid grid-cols-1 sm:grid-cols-3 gap-4 mt-2', [
                      if (submission.frontUrl != null)
                        div(classes: 'flex flex-col gap-1.5', [
                          span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                            Component.text('ID Front'),
                          ]),
                          a(
                            href: submission.frontUrl!,
                            target: Target.blank,
                            classes:
                                'block border border-zinc-200 rounded-xl overflow-hidden bg-zinc-50 hover:opacity-95 transition-opacity shadow-sm',
                            [
                              img(
                                src: submission.frontUrl!,
                                classes: 'w-full h-32 object-cover bg-zinc-100',
                              ),
                            ],
                          ),
                        ]),
                      if (submission.backUrl != null)
                        div(classes: 'flex flex-col gap-1.5', [
                          span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                            Component.text('ID Back'),
                          ]),
                          a(
                            href: submission.backUrl!,
                            target: Target.blank,
                            classes:
                                'block border border-zinc-200 rounded-xl overflow-hidden bg-zinc-50 hover:opacity-95 transition-opacity shadow-sm',
                            [
                              img(
                                src: submission.backUrl!,
                                classes: 'w-full h-32 object-cover bg-zinc-100',
                              ),
                            ],
                          ),
                        ]),
                      if (submission.selfieUrl != null)
                        div(classes: 'flex flex-col gap-1.5', [
                          span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                            Component.text('Selfie Verification'),
                          ]),
                          a(
                            href: submission.selfieUrl!,
                            target: Target.blank,
                            classes:
                                'block border border-zinc-200 rounded-xl overflow-hidden bg-zinc-50 hover:opacity-95 transition-opacity shadow-sm',
                            [
                              img(
                                src: submission.selfieUrl!,
                                classes: 'w-full h-32 object-cover bg-zinc-100',
                              ),
                            ],
                          ),
                        ]),
                    ]),
                ]),

              // Background Check Section
              if (submission.hasBackgroundCheck)
                div(classes: 'flex flex-col gap-3', [
                  div(classes: 'flex items-center justify-between', [
                    h4(
                      classes:
                          'text-xs font-black text-zinc-900 uppercase tracking-wide border-l-2 border-emerald-500 pl-2',
                      [Component.text('Background Check Clearance')],
                    ),
                    div(classes: 'flex items-center gap-2', [
                      span(
                        classes:
                            'text-[9px] font-extrabold px-2 py-0.5 rounded-full border '
                            '${submission.bgStatus == 'Approved' ? "bg-emerald-50 text-emerald-600 border-emerald-200" : submission.bgStatus == 'Rejected' ? "bg-red-50 text-red-500 border-red-200" : "bg-emerald-50 text-emerald-700 border-emerald-300"}',
                        [Component.text('Status: ${submission.bgStatus}')],
                      ),
                      button(
                        onClick: () => setState(() {
                          _selectedBgCheckSubmission = submission;
                          _selectedSubmission = null;
                        }),
                        classes:
                            'px-2.5 py-1 rounded-lg bg-emerald-600 hover:bg-emerald-700 text-white text-[10px] font-bold cursor-pointer border-0 flex items-center gap-1',
                        [
                          span(classes: 'text-xs', [Component.text('🛡️')]),
                          Component.text('Open BG Approval Window'),
                        ],
                      ),
                    ]),
                  ]),
                  div(
                    classes: 'grid grid-cols-3 gap-2 text-xs bg-zinc-50 p-3 rounded-xl border border-zinc-200/50',
                    [
                      div([
                        span(classes: 'text-zinc-400 font-bold', [Component.text('Type: ')]),
                        Component.text(submission.clearanceType ?? 'N/A'),
                      ]),
                      div([
                        span(classes: 'text-zinc-400 font-bold', [Component.text('Clearance No: ')]),
                        Component.text(submission.clearanceNumber ?? 'N/A'),
                      ]),
                      div([
                        span(classes: 'text-zinc-400 font-bold', [Component.text('Expiry: ')]),
                        Component.text(submission.expiryDate ?? 'N/A'),
                      ]),
                    ],
                  ),
                  if (submission.documentUrl != null)
                    div(classes: 'flex flex-col gap-1.5 mt-2', [
                      span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                        Component.text('Clearance Document'),
                      ]),
                      submission.documentUrl!.toLowerCase().contains('.pdf')
                          ? a(
                              href: submission.documentUrl!,
                              target: Target.blank,
                              classes:
                                  'inline-flex items-center gap-2 p-3 border border-zinc-200 rounded-xl bg-zinc-50 hover:bg-zinc-100 text-xs font-bold text-indigo-650 transition-all no-underline w-fit',
                              [
                                span(classes: 'text-lg', [Component.text('📄')]),
                                Component.text('View Clearance Document (PDF) ↗'),
                              ],
                            )
                          : a(
                              href: submission.documentUrl!,
                              target: Target.blank,
                              classes:
                                  'block border border-zinc-200 rounded-xl overflow-hidden bg-zinc-50 hover:opacity-95 transition-opacity max-w-sm shadow-sm',
                              [
                                img(
                                  src: submission.documentUrl!,
                                  classes: 'w-full h-48 object-contain bg-zinc-100',
                                ),
                              ],
                            ),
                    ]),
                ]),
            ]),

            // Modal Actions / Footer
            div(classes: 'p-6 border-t border-zinc-150/60 bg-zinc-50 flex justify-between items-center gap-3', [
              div(classes: 'text-left', [
                if (submission.isAnyPending)
                  span(classes: 'text-[11px] text-zinc-400 font-medium', [
                    Component.text(
                      submission.isIdPending && submission.isBgPending
                          ? 'Both ID and Background check are pending review.'
                          : submission.isBgPending
                          ? 'Background check requires clearance approval.'
                          : 'ID verification is pending review.',
                    ),
                  ]),
              ]),
              div(classes: 'flex items-center gap-3', [
                if (submission.isAnyPending) ...[
                  button(
                    onClick: () async {
                      if (_isProcessing) return;
                      await _updateBothStatus(submission.uid, 'Rejected', isApprove: false);
                      setState(() => _selectedSubmission = null);
                    },
                    classes:
                        'px-4 py-2.5 rounded-xl border border-red-200 bg-red-50/50 hover:bg-red-100/50 text-red-500 text-xs font-bold transition-all cursor-pointer outline-none',
                    [Component.text('Reject Submission')],
                  ),
                  if (submission.isIdPending && submission.isBgPending)
                    button(
                      onClick: () async {
                        if (_isProcessing) return;
                        await _updateBothStatus(submission.uid, 'Approved', isApprove: true);
                        setState(() => _selectedSubmission = null);
                      },
                      classes:
                          'px-5 py-2.5 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-bold transition-all shadow-md shadow-black/10 cursor-pointer border-0 outline-none flex items-center gap-1.5',
                      [
                        span(classes: 'text-xs', [Component.text('✓')]),
                        Component.text('Approve Both (Level 2)'),
                      ],
                    )
                  else if (submission.isBgPending)
                    button(
                      onClick: () async {
                        if (_isProcessing) return;
                        await _updateBgCheckStatus(submission.uid, 'Approved', isApprove: true);
                        setState(() => _selectedSubmission = null);
                      },
                      classes:
                          'px-5 py-2.5 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-bold transition-all shadow-md shadow-emerald-600/20 cursor-pointer border-0 outline-none flex items-center gap-1.5',
                      [
                        span(classes: 'text-xs', [Component.text('🛡️')]),
                        Component.text('Approve Background Check'),
                      ],
                    )
                  else
                    button(
                      onClick: () async {
                        if (_isProcessing) return;
                        await _updateIdStatus(submission.uid, 'Approved', isApprove: true);
                        setState(() => _selectedSubmission = null);
                      },
                      classes:
                          'px-5 py-2.5 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-bold transition-all shadow-md shadow-black/10 cursor-pointer border-0 outline-none flex items-center gap-1.5',
                      [Component.text('Approve ID Verification')],
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
            ]),
          ],
        ),
      ],
    );
  }
}
