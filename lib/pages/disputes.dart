import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../app.dart';
import '../core/providers/environment_provider.dart';

/// Represents a customer gig dispute submitted for admin arbitration.
class DisputeItem {
  final String id;
  final String jobId;
  final String jobTitle;
  final String employerId;
  final String acceptedNyxianId;
  final String openedBy;
  final String openedByRole;
  final String status; // 'OPEN', 'RESOLVED'
  final String category;
  final String reason;
  final double escrowAmount;
  final int createdAt;
  final int updatedAt;
  final int? resolvedAt;
  final String? resolvedBy;
  final String? resolutionType; // 'REFUND_EMPLOYER', 'PAY_NYXIAN', 'SPLIT_ESCROW'
  final String? resolutionNotes;
  final double? employerRefund;
  final double? nyxianPayout;
  final Map<String, dynamic> rawData;

  const DisputeItem({
    required this.id,
    required this.jobId,
    required this.jobTitle,
    required this.employerId,
    required this.acceptedNyxianId,
    required this.openedBy,
    required this.openedByRole,
    required this.status,
    required this.category,
    required this.reason,
    required this.escrowAmount,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
    this.resolvedBy,
    this.resolutionType,
    this.resolutionNotes,
    this.employerRefund,
    this.nyxianPayout,
    required this.rawData,
  });

  bool get isOpen => status.toUpperCase() == 'OPEN';

  factory DisputeItem.fromMap(String id, Map<String, dynamic> map) {
    int parseDateTime(dynamic val) {
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    double parseAmount(dynamic val) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
      return 0.0;
    }

    return DisputeItem(
      id: id,
      jobId: (map['jobId'] ?? '').toString(),
      jobTitle: (map['jobTitle'] ?? 'Gig').toString(),
      employerId: (map['employerId'] ?? '').toString(),
      acceptedNyxianId: (map['acceptedNyxianId'] ?? 'None').toString(),
      openedBy: (map['openedBy'] ?? '').toString(),
      openedByRole: (map['openedByRole'] ?? 'User').toString(),
      status: (map['status'] ?? 'OPEN').toString().toUpperCase(),
      category: (map['category'] ?? 'Dispute').toString(),
      reason: (map['reason'] ?? '').toString(),
      escrowAmount: parseAmount(map['escrowAmount']),
      createdAt: parseDateTime(map['createdAt']),
      updatedAt: parseDateTime(map['updatedAt']),
      resolvedAt: map['resolvedAt'] != null ? parseDateTime(map['resolvedAt']) : null,
      resolvedBy: map['resolvedBy'] as String?,
      resolutionType: map['resolutionType'] as String?,
      resolutionNotes: map['resolutionNotes'] as String?,
      employerRefund: map['employerRefund'] != null ? parseAmount(map['employerRefund']) : null,
      nyxianPayout: map['nyxianPayout'] != null ? parseAmount(map['nyxianPayout']) : null,
      rawData: map,
    );
  }
}

/// Provider streaming all disputes in real-time from the active environment.
final disputesStreamProvider = StreamProvider<List<DisputeItem>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return firestore.collection('disputes').snapshots().map((snapshot) {
    final list = snapshot.docs.map((doc) => DisputeItem.fromMap(doc.id, doc.data())).toList();
    list.sort((d1, d2) => d2.createdAt.compareTo(d1.createdAt));
    return list;
  });
});

class DisputesPage extends StatefulComponent {
  const DisputesPage({super.key});

  @override
  State<DisputesPage> createState() => _DisputesPageState();
}

class _DisputesPageState extends State<DisputesPage> {
  String _statusFilter = 'ALL'; // 'ALL', 'OPEN', 'RESOLVED'
  String _searchQuery = '';

  // Arbitration modal state
  DisputeItem? _selectedDispute;
  String _resolutionType = 'REFUND_EMPLOYER'; // 'REFUND_EMPLOYER', 'PAY_NYXIAN', 'SPLIT_ESCROW'
  String _notes = '';
  double _employerPercent = 50.0;
  double _nyxianPercent = 50.0;
  bool _isExecuting = false;
  String? _executionError;

  void _openArbitrationModal(DisputeItem dispute) {
    setState(() {
      _selectedDispute = dispute;
      _resolutionType = 'REFUND_EMPLOYER';
      _notes = '';
      _employerPercent = 50.0;
      _nyxianPercent = 50.0;
      _isExecuting = false;
      _executionError = null;
    });
  }

  void _closeArbitrationModal() {
    setState(() {
      _selectedDispute = null;
      _notes = '';
      _isExecuting = false;
      _executionError = null;
    });
  }

  Future<void> _executeArbitration(BuildContext context) async {
    final dispute = _selectedDispute;
    if (dispute == null) return;

    final user = context.read(adminCurrentUserProvider).value;
    final adminUid = user?.uid ?? 'admin';

    if (_notes.trim().length < 10) {
      setState(() => _executionError = 'Please enter at least 10 characters explaining your arbitration rationale.');
      return;
    }

    setState(() {
      _isExecuting = true;
      _executionError = null;
    });

    try {
      final activeFirestore = context.read(firestoreProvider);
      final adminFirestore = context.read(adminFirestoreProvider);
      final nowMillis = DateTime.now().millisecondsSinceEpoch;

      final jobId = dispute.jobId;
      final employerId = dispute.employerId;
      final nyxianId = dispute.acceptedNyxianId;
      final escrowAmount = dispute.escrowAmount;

      double refundToEmployer = 0.0;
      double payoutToNyxian = 0.0;

      if (_resolutionType == 'REFUND_EMPLOYER') {
        refundToEmployer = escrowAmount;
        payoutToNyxian = 0.0;
      } else if (_resolutionType == 'PAY_NYXIAN') {
        refundToEmployer = 0.0;
        payoutToNyxian = escrowAmount;
      } else {
        refundToEmployer = (escrowAmount * (_employerPercent / 100.0));
        payoutToNyxian = (escrowAmount * (_nyxianPercent / 100.0));
      }

      // 1. Credit Employer Wallet if refund > 0
      if (refundToEmployer > 0 && employerId.isNotEmpty) {
        final empDoc = await activeFirestore.collection('users').doc(employerId).get();
        final currentBal = (empDoc.data()?['tyxBalance'] as num?)?.toDouble() ?? 0.0;
        await activeFirestore.collection('users').doc(employerId).set({
          'tyxBalance': currentBal + refundToEmployer,
        }, SetOptions(merge: true));

        // Transaction log for employer
        await activeFirestore.collection('transactions').doc('refund_dispute_${dispute.id}').set({
          'id': 'refund_dispute_${dispute.id}',
          'uid': employerId,
          'jobId': jobId,
          'disputeId': dispute.id,
          'type': 'refund',
          'category': 'refund',
          'amount': refundToEmployer,
          'title': 'Dispute Arbitration Refund',
          'desc': 'Escrow refund of ₱${refundToEmployer.toStringAsFixed(2)} for gig "${dispute.jobTitle}" via admin arbitration.',
          'status': 'Completed',
          'method': 'Tranyx Escrow',
          'originRail': 'internal_balance',
          'createdAt': nowMillis,
        });
      }

      // 2. Credit Nyxian Wallet if payout > 0
      if (payoutToNyxian > 0 && nyxianId.isNotEmpty && nyxianId != 'None') {
        final nyxDoc = await activeFirestore.collection('users').doc(nyxianId).get();
        final currentBal = (nyxDoc.data()?['tyxBalance'] as num?)?.toDouble() ?? 0.0;
        await activeFirestore.collection('users').doc(nyxianId).set({
          'tyxBalance': currentBal + payoutToNyxian,
        }, SetOptions(merge: true));

        // Transaction log for Nyxian
        await activeFirestore.collection('transactions').doc('payout_dispute_${dispute.id}').set({
          'id': 'payout_dispute_${dispute.id}',
          'uid': nyxianId,
          'jobId': jobId,
          'disputeId': dispute.id,
          'type': 'payout',
          'category': 'earnings',
          'amount': payoutToNyxian,
          'title': 'Dispute Arbitration Payout',
          'desc': 'Escrow payout of ₱${payoutToNyxian.toStringAsFixed(2)} for gig "${dispute.jobTitle}" via admin arbitration.',
          'status': 'Completed',
          'method': 'Tranyx Escrow',
          'originRail': 'internal_balance',
          'createdAt': nowMillis,
        });
      }

      // 3. Update Escrow Document
      final escrowStatus = _resolutionType == 'REFUND_EMPLOYER'
          ? 'refunded'
          : (_resolutionType == 'PAY_NYXIAN' ? 'released' : 'split_resolved');
      await activeFirestore.collection('escrow').doc(jobId).set({
        'status': escrowStatus,
        'resolvedViaDispute': true,
        'disputeId': dispute.id,
        'employerRefund': refundToEmployer,
        'nyxianPayout': payoutToNyxian,
        'resolvedAt': nowMillis,
        'resolvedBy': adminUid,
      }, SetOptions(merge: true));

      // 4. Update Job Document Status
      final jobStatus = _resolutionType == 'REFUND_EMPLOYER' ? 'Cancelled' : 'Completed';
      await activeFirestore.collection('jobs').doc(jobId).set({
        'status': jobStatus,
        'resolvedDisputeId': dispute.id,
        'updatedAt': nowMillis,
      }, SetOptions(merge: true));

      // 5. In-chat system resolution notice
      try {
        final msgId = 'msg_res_$nowMillis';
        await activeFirestore.collection('chats').doc(jobId).collection('messages').doc(msgId).set({
          'senderId': 'system',
          'senderName': 'Tranyx Arbitration',
          'type': 'dispute_resolved',
          'disputeId': dispute.id,
          'resolutionType': _resolutionType,
          'text': 'Dispute resolved by Admin. Ruling: ${_resolutionType.replaceAll('_', ' ')}. Refund: ₱${refundToEmployer.toStringAsFixed(2)}, Payout: ₱${payoutToNyxian.toStringAsFixed(2)}. Notes: "${_notes.trim()}"',
          'createdAt': nowMillis,
        });
        await activeFirestore.collection('chats').doc(jobId).set({
          'updatedAt': nowMillis,
        }, SetOptions(merge: true));
      } catch (_) {}

      // 6. Update Dispute Document itself in both firestores
      final disputeUpdate = {
        'status': 'RESOLVED',
        'resolvedAt': nowMillis,
        'resolvedBy': adminUid,
        'resolutionType': _resolutionType,
        'resolutionNotes': _notes.trim(),
        'employerRefund': refundToEmployer,
        'nyxianPayout': payoutToNyxian,
        'updatedAt': nowMillis,
      };

      await activeFirestore.collection('disputes').doc(dispute.id).set(disputeUpdate, SetOptions(merge: true));
      await adminFirestore.collection('disputes').doc(dispute.id).set(disputeUpdate, SetOptions(merge: true)).catchError((_) {});

      _closeArbitrationModal();
    } catch (e) {
      print('[Disputes] Error resolving dispute: $e');
      setState(() {
        _isExecuting = false;
        _executionError = 'Arbitration failed: $e';
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final disputesAsync = context.watch(disputesStreamProvider);

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0]', [
      // Header block
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900 flex items-center gap-2.5', [
            span([Component.text('⚖️')]),
            Component.text('Gig Disputes & Arbitration Console'),
          ]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text(
              'Neutral platform tribunal for reviewing stalled, abandoned, or contested gigs and executing binding escrow settlements.',
            ),
          ]),
        ]),
      ]),

      disputesAsync.when(
        data: (allDisputes) {
          final pendingCount = allDisputes.where((d) => d.isOpen).length;

          // Filter
          var filtered = allDisputes;
          if (_statusFilter != 'ALL') {
            filtered = filtered.where((d) => d.status == _statusFilter).toList();
          }
          if (_searchQuery.trim().isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            filtered = filtered.where((d) {
              return d.jobTitle.toLowerCase().contains(q) ||
                  d.id.toLowerCase().contains(q) ||
                  d.reason.toLowerCase().contains(q) ||
                  d.category.toLowerCase().contains(q) ||
                  d.employerId.toLowerCase().contains(q) ||
                  d.acceptedNyxianId.toLowerCase().contains(q);
            }).toList();
          }

          return div(classes: 'flex flex-col gap-6', [
            // Controls Bar
            div(classes: 'flex flex-col md:flex-row items-stretch md:items-center justify-between gap-3 bg-white p-4 rounded-2xl border border-zinc-200/50 shadow-sm', [
              div(classes: 'flex items-center gap-1.5 overflow-x-auto pb-1 md:pb-0', [
                for (final opt in [
                  ('ALL', 'All Disputes (${allDisputes.length})'),
                  ('OPEN', 'Pending Review ($pendingCount)'),
                  ('RESOLVED', 'Resolved'),
                ])
                  button(
                    classes:
                        'px-3.5 py-1.5 rounded-xl text-xs font-semibold whitespace-nowrap transition cursor-pointer border-0 '
                        '${_statusFilter == opt.$1 ? "bg-black text-white font-bold" : "bg-zinc-100 text-zinc-600 hover:text-zinc-900"}',
                    onClick: () => setState(() => _statusFilter = opt.$1),
                    [Component.text(opt.$2)],
                  ),
              ]),
              div(classes: 'relative w-full md:w-80', [
                input(
                  value: _searchQuery,
                  classes: 'w-full pl-4 pr-4 py-2 bg-[#f8faf9] border border-zinc-200/50 rounded-xl text-xs text-zinc-800 placeholder:text-zinc-400 focus:outline-none focus:border-black transition',
                  attributes: {'type': 'text', 'placeholder': 'Search dispute, job title, reason...'},
                  onInput: (dynamic val) => setState(() => _searchQuery = (val as String?) ?? ''),
                ),
              ]),
            ]),

            // Disputes List
            if (filtered.isEmpty)
              div(classes: 'p-16 text-center rounded-3xl bg-white border border-dashed border-zinc-200 text-zinc-400 space-y-2', [
                span(classes: 'text-3xl block', [Component.text('⚖️')]),
                h4(classes: 'text-sm font-bold text-zinc-700', [Component.text('No disputes match the selected filter.')]),
                p(classes: 'text-xs text-zinc-400', [Component.text('Customer-submitted disputes will automatically appear here for arbitration.')]),
              ])
            else
              div(classes: 'flex flex-col gap-4', [
                for (final dispute in filtered)
                  _buildDisputeCard(dispute),
              ]),
          ]);
        },
        error: (err, _) => div(classes: 'p-8 text-center text-red-500 font-bold bg-white rounded-2xl', [
          Component.text('Error loading disputes: $err'),
        ]),
        loading: () => div(classes: 'py-20 flex justify-center', [
          span(classes: 'inline-block animate-spin h-8 w-8 border-4 border-zinc-200 border-t-black rounded-full', []),
        ]),
      ),

      // Arbitration Modal
      if (_selectedDispute != null)
        _buildArbitrationModal(context),
    ]);
  }

  Component _buildDisputeCard(DisputeItem dispute) {
    final isOpen = dispute.isOpen;
    final createdAt = dispute.createdAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(dispute.createdAt)
        : null;
    final dateStr = createdAt != null
        ? '${createdAt.month}/${createdAt.day} ${createdAt.hour.toString().padLeft(2, "0")}:${createdAt.minute.toString().padLeft(2, "0")}'
        : '';

    return div(classes: 'p-5 rounded-2xl bg-white border border-zinc-200/60 shadow-sm hover:border-zinc-300 transition flex flex-col gap-4', [
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-3', [
        div(classes: 'space-y-1', [
          div(classes: 'flex items-center gap-2 flex-wrap', [
            span(
              classes:
                  'px-2.5 py-0.5 rounded-full text-[10px] font-black uppercase tracking-wider ${isOpen ? "bg-amber-100 text-amber-800 border border-amber-200" : "bg-emerald-100 text-emerald-800 border border-emerald-200"}',
              [Component.text(isOpen ? 'Needs Arbitration' : 'Resolved')],
            ),
            span(classes: 'px-2 py-0.5 rounded-md text-[10px] font-bold bg-zinc-100 text-zinc-600', [
              Component.text(dispute.category),
            ]),
            if (dateStr.isNotEmpty)
              span(classes: 'text-[11px] text-zinc-400 font-mono', [Component.text(dateStr)]),
          ]),
          h4(classes: 'text-base font-bold text-zinc-900', [Component.text(dispute.jobTitle)]),
          p(classes: 'text-xs text-zinc-400 font-mono', [
            Component.text('Dispute ID: ${dispute.id} • Filed by: ${dispute.openedByRole.toUpperCase()} (${dispute.openedBy})'),
          ]),
        ]),

        div(classes: 'flex items-center justify-between md:justify-end gap-4 shrink-0', [
          div(classes: 'text-left md:text-right', [
            span(classes: 'text-[10px] uppercase font-bold text-zinc-400 block', [Component.text('Escrow at Stake')]),
            span(classes: 'text-lg font-black text-indigo-600 font-mono', [
              Component.text('₱${dispute.escrowAmount.toStringAsFixed(2)}'),
            ]),
          ]),
          if (isOpen)
            button(
              classes: 'px-4 py-2.5 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-bold transition shadow-md shadow-black/10 cursor-pointer border-0 flex items-center gap-1.5 active:scale-95',
              onClick: () => _openArbitrationModal(dispute),
              [
                span([Component.text('⚖️')]),
                Component.text('Review & Arbitrate'),
              ],
            ),
        ]),
      ]),

      // Grounds statement box
      div(classes: 'p-3.5 rounded-xl bg-zinc-50 border border-zinc-200/60 text-xs text-zinc-700 leading-relaxed', [
        p(classes: 'text-[10px] font-bold uppercase tracking-wider text-zinc-400 mb-1', [
          Component.text('Dispute Grounds / User Statement:'),
        ]),
        Component.text(dispute.reason),
      ]),

      // If resolved, show ruling details
      if (!isOpen)
        div(classes: 'p-3.5 rounded-xl bg-emerald-50/60 border border-emerald-200/60 text-xs text-emerald-900 leading-relaxed space-y-1.5', [
          div(classes: 'flex items-center justify-between flex-wrap gap-2', [
            span(classes: 'font-bold text-emerald-800', [
              Component.text('Resolution: ${(dispute.resolutionType ?? "").replaceAll('_', ' ')}'),
            ]),
            span(classes: 'font-mono text-xs text-emerald-700', [
              Component.text('Refund to Employer: ₱${(dispute.employerRefund ?? 0.0).toStringAsFixed(2)} | Payout to Nyxian: ₱${(dispute.nyxianPayout ?? 0.0).toStringAsFixed(2)}'),
            ]),
          ]),
          if (dispute.resolutionNotes?.isNotEmpty == true)
            p(classes: 'text-[11px] text-zinc-600', [
              Component.text('Admin Notes: ${dispute.resolutionNotes}'),
            ]),
        ]),
    ]);
  }

  Component _buildArbitrationModal(BuildContext context) {
    final dispute = _selectedDispute!;
    final escrow = dispute.escrowAmount;

    final empRefund = _resolutionType == 'REFUND_EMPLOYER'
        ? escrow
        : (_resolutionType == 'PAY_NYXIAN' ? 0.0 : escrow * (_employerPercent / 100.0));
    final nyxPayout = _resolutionType == 'PAY_NYXIAN'
        ? escrow
        : (_resolutionType == 'REFUND_EMPLOYER' ? 0.0 : escrow * (_nyxianPercent / 100.0));

    return div(classes: 'fixed inset-0 z-[250] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fadeIn', [
      div(classes: 'w-full max-w-xl bg-white border border-zinc-200 rounded-3xl p-6 shadow-2xl space-y-4 text-zinc-900 max-h-[90vh] overflow-y-auto no-scrollbar', [
        // Modal Header
        div(classes: 'flex items-center justify-between border-b border-zinc-100 pb-3', [
          div(classes: 'flex items-center gap-2.5', [
            div(classes: 'p-2 rounded-xl bg-indigo-50 text-indigo-600 border border-indigo-100', [
              span(classes: 'text-base', [Component.text('⚖️')]),
            ]),
            div([
              h3(classes: 'text-base font-black text-zinc-900', [Component.text('Admin Arbitration Desk')]),
              p(classes: 'text-xs text-zinc-400 font-mono', [Component.text('Dispute: ${dispute.id}')]),
            ]),
          ]),
          button(
            classes: 'w-8 h-8 rounded-full bg-zinc-100 hover:bg-zinc-200 text-zinc-500 flex items-center justify-center cursor-pointer border-0 font-bold',
            onClick: () => _closeArbitrationModal(),
            [Component.text('✕')],
          ),
        ]),

        // Summary Card
        div(classes: 'p-3.5 rounded-2xl bg-zinc-50 border border-zinc-200/60 space-y-2 text-xs', [
          div(classes: 'flex items-center justify-between', [
            span(classes: 'font-bold text-zinc-900', [Component.text(dispute.jobTitle)]),
            span(classes: 'font-black text-indigo-600 text-sm font-mono', [Component.text('₱${escrow.toStringAsFixed(2)} Escrow')]),
          ]),
          div(classes: 'flex items-center gap-2 text-zinc-400 font-mono text-[11px]', [
            span([Component.text('Employer: ${dispute.employerId}')]),
            span([Component.text('•')]),
            span([Component.text('Nyxian: ${dispute.acceptedNyxianId}')]),
          ]),
          div(classes: 'p-2.5 rounded-xl bg-white border border-zinc-200 text-zinc-600', [
            p(classes: 'text-[10px] font-bold uppercase tracking-wider text-amber-700 mb-0.5', [Component.text('Dispute: ${dispute.category}')]),
            Component.text(dispute.reason),
          ]),
        ]),

        // Pathways Selector
        div(classes: 'space-y-2 text-left', [
          label(classes: 'block text-xs font-bold uppercase tracking-wider text-zinc-500', [
            Component.text('Select Arbitration Settlement Pathway:'),
          ]),

          // Path 1
          div(
            classes:
                'p-3.5 rounded-2xl border transition cursor-pointer flex items-start gap-3 ${_resolutionType == "REFUND_EMPLOYER" ? "bg-indigo-50/70 border-indigo-300 ring-1 ring-indigo-300" : "bg-zinc-50/50 border-zinc-200 hover:border-zinc-300"}',
            events: {'click': (_) => setState(() => _resolutionType = 'REFUND_EMPLOYER')},
            [
              span(classes: 'text-xl', [Component.text('↩️')]),
              div(classes: 'flex-1', [
                div(classes: 'flex items-center justify-between', [
                  p(classes: 'font-bold text-xs text-zinc-900', [Component.text('Path 1: 100% Refund to Employer')]),
                  span(classes: 'text-xs font-black text-indigo-600 font-mono', [Component.text('₱${escrow.toStringAsFixed(2)}')]),
                ]),
                p(classes: 'text-[11px] text-zinc-500 mt-0.5', [
                  Component.text('Nyxian abandoned the task, exceeded SLA, or committed fraud. Full escrow returned to Employer.'),
                ]),
              ]),
            ],
          ),

          // Path 2
          div(
            classes:
                'p-3.5 rounded-2xl border transition cursor-pointer flex items-start gap-3 ${_resolutionType == "PAY_NYXIAN" ? "bg-emerald-50/70 border-emerald-300 ring-1 ring-emerald-300" : "bg-zinc-50/50 border-zinc-200 hover:border-zinc-300"}',
            events: {'click': (_) => setState(() => _resolutionType = 'PAY_NYXIAN')},
            [
              span(classes: 'text-xl', [Component.text('✅')]),
              div(classes: 'flex-1', [
                div(classes: 'flex items-center justify-between', [
                  p(classes: 'font-bold text-xs text-zinc-900', [Component.text('Path 2: 100% Payout to Nyxian')]),
                  span(classes: 'text-xs font-black text-emerald-600 font-mono', [Component.text('₱${escrow.toStringAsFixed(2)}')]),
                ]),
                p(classes: 'text-[11px] text-zinc-500 mt-0.5', [
                  Component.text('Work completed satisfactorily; employer was unresponsive or falsely refusing confirmation.'),
                ]),
              ]),
            ],
          ),

          // Path 3
          div(
            classes:
                'p-3.5 rounded-2xl border transition cursor-pointer flex flex-col gap-3 ${_resolutionType == "SPLIT_ESCROW" ? "bg-purple-50/70 border-purple-300 ring-1 ring-purple-300" : "bg-zinc-50/50 border-zinc-200 hover:border-zinc-300"}',
            events: {'click': (_) => setState(() => _resolutionType = 'SPLIT_ESCROW')},
            [
              div(classes: 'flex items-start gap-3', [
                span(classes: 'text-xl', [Component.text('⚖️')]),
                div(classes: 'flex-1', [
                  div(classes: 'flex items-center justify-between', [
                    p(classes: 'font-bold text-xs text-zinc-900', [Component.text('Path 3: Proportional Split Settlement')]),
                    span(classes: 'text-xs font-black text-purple-600 font-mono', [
                      Component.text('Emp: ₱${empRefund.toStringAsFixed(2)} | Nyx: ₱${nyxPayout.toStringAsFixed(2)}'),
                    ]),
                  ]),
                  p(classes: 'text-[11px] text-zinc-500 mt-0.5', [
                    Component.text('Partial task completed, or mutual fault. Custom distribution between Employer and Nyxian.'),
                  ]),
                ]),
              ]),

              if (_resolutionType == 'SPLIT_ESCROW')
                div(classes: 'pt-2 border-t border-zinc-200 space-y-2', [
                  div(classes: 'flex items-center justify-between text-xs', [
                    span(classes: 'text-zinc-500 font-semibold', [
                      Component.text('Employer Refund: ${_employerPercent.toStringAsFixed(0)}% (₱${empRefund.toStringAsFixed(2)})'),
                    ]),
                    span(classes: 'text-zinc-500 font-semibold', [
                      Component.text('Nyxian Payout: ${_nyxianPercent.toStringAsFixed(0)}% (₱${nyxPayout.toStringAsFixed(2)})'),
                    ]),
                  ]),
                  div(classes: 'flex items-center gap-3', [
                    span(classes: 'text-[11px] text-zinc-400 font-bold', [Component.text('Employer')]),
                    input(
                      value: _employerPercent.toStringAsFixed(0),
                      classes: 'flex-1 accent-purple-600 cursor-pointer',
                      attributes: {'type': 'range', 'min': '0', 'max': '100', 'step': '5'},
                      onInput: (dynamic val) {
                        final parsed = double.tryParse((val as String?) ?? '') ?? 50.0;
                        setState(() {
                          _employerPercent = parsed;
                          _nyxianPercent = (100.0 - parsed).clamp(0.0, 100.0);
                        });
                      },
                    ),
                    span(classes: 'text-[11px] text-zinc-400 font-bold', [Component.text('Nyxian')]),
                  ]),
                ]),
            ],
          ),
        ]),

        // Admin Justification Notes
        div(classes: 'space-y-1.5 text-left', [
          label(classes: 'block text-xs font-bold uppercase tracking-wider text-zinc-500', [
            Component.text('Admin Arbitration Rationale (Min 10 chars):'),
          ]),
          textarea(
            classes: 'w-full p-3 bg-zinc-50 border border-zinc-200 rounded-xl text-xs text-zinc-900 placeholder:text-zinc-400 focus:outline-none focus:border-black min-h-[80px] resize-none',
            attributes: {'placeholder': 'Document evidence reviewed (e.g. Chat review confirmed zero response for 3 days)...'},
            onInput: (dynamic val) => setState(() => _notes = (val as String?) ?? ''),
            [Component.text(_notes)],
          ),
        ]),

        if (_executionError != null)
          div(classes: 'p-3 rounded-xl bg-red-50 border border-red-200 text-red-600 text-xs font-semibold', [
            Component.text(_executionError!),
          ]),

        // Modal Actions
        div(classes: 'flex justify-end gap-2.5 pt-2 border-t border-zinc-100', [
          button(
            classes: 'px-4 py-2.5 rounded-xl text-xs font-semibold text-zinc-500 hover:bg-zinc-100 cursor-pointer border-0',
            onClick: () => _closeArbitrationModal(),
            [Component.text('Cancel')],
          ),
          button(
            classes:
                'px-6 py-2.5 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-bold transition shadow-lg shadow-black/10 cursor-pointer border-0 active:scale-95 flex items-center gap-2 ${_isExecuting || _notes.trim().length < 10 ? "opacity-50 cursor-not-allowed" : ""}',
            attributes: (_isExecuting || _notes.trim().length < 10) ? {'disabled': 'true'} : {},
            onClick: (_isExecuting || _notes.trim().length < 10) ? null : () => _executeArbitration(context),
            [
              if (_isExecuting)
                span(classes: 'inline-block animate-spin h-3.5 w-3.5 border-2 border-white/30 border-t-white rounded-full', []),
              Component.text(_isExecuting ? 'Executing Settlement...' : 'Execute Arbitration Settlement'),
            ],
          ),
        ]),
      ]),
    ]);
  }
}
