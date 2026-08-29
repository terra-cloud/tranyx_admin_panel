import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:riverpod/legacy.dart';

import '../app.dart';
import '../core/providers/environment_provider.dart';
import '../core/services/presence_service.dart';
import '../core/services/request_lock_service.dart';
import '../core/services/ticket_email_service.dart';
import 'users.dart';

// ── Models ─────────────────────────────────────────────────────

class TicketResponseItem {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderEmail;
  final String message;
  final int createdAt;
  final bool isStaff;
  final String? statusChange;

  TicketResponseItem({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderEmail,
    required this.message,
    required this.createdAt,
    required this.isStaff,
    this.statusChange,
  });

  factory TicketResponseItem.fromMap(String id, Map<String, dynamic> map) {
    int parseTs(dynamic val) {
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    return TicketResponseItem(
      id: id,
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? 'Support Staff',
      senderEmail: map['senderEmail'],
      message: map['message'] ?? map['content'] ?? '',
      createdAt: parseTs(map['createdAt']),
      isStaff: map['isStaff'] ?? true,
      statusChange: map['statusChange'],
    );
  }
}

class TicketModel {
  final String id;
  final String ticketNumber;
  final String uid;
  final String? userEmail;
  final String? userName;
  final String subject;
  final String description;
  final String category;
  final String status;
  final String priority;
  final String? assignedAgentId;
  final String? assignedAgentName;
  final String? assignedAgentEmail;
  final int? assignedAt;
  final int? claimDeadline;
  final int? lastHeartbeat;
  final List<String> rejectedBy;
  final int createdAt;
  final int updatedAt;
  final int? resolvedAt;
  final bool emailConfirmationSent;
  final List<dynamic> emailLogs;
  final List<TicketResponseItem> responses;

  TicketModel({
    required this.id,
    required this.ticketNumber,
    required this.uid,
    this.userEmail,
    this.userName,
    required this.subject,
    required this.description,
    required this.category,
    required this.status,
    required this.priority,
    this.assignedAgentId,
    this.assignedAgentName,
    this.assignedAgentEmail,
    this.assignedAt,
    this.claimDeadline,
    this.lastHeartbeat,
    this.rejectedBy = const [],
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
    required this.emailConfirmationSent,
    required this.emailLogs,
    required this.responses,
  });

  bool get isPending => status.toLowerCase() == 'open' || status.toLowerCase() == 'pending';
  bool get isAssigned => status.toLowerCase() == 'assigned';
  bool get isInProgress => status.toLowerCase() == 'in progress' || status.toLowerCase() == 'in_progress';
  bool get isResolved => status.toLowerCase() == 'resolved' || status.toLowerCase() == 'closed';

  bool isClaimExpired(int nowMs, int claimTimeoutSec) {
    if (!isAssigned) return false;
    if (claimDeadline != null && claimDeadline! > 0) {
      return nowMs > claimDeadline!;
    }
    if (assignedAt != null && assignedAt! > 0) {
      return (nowMs - assignedAt!) > (claimTimeoutSec * 1000);
    }
    return false;
  }

  factory TicketModel.fromMap(String id, Map<String, dynamic> map) {
    int parseDateTime(dynamic val) {
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    final created = parseDateTime(map['createdAt'] ?? map['submittedAt'] ?? map['timestamp']);
    final refNum =
        map['ticketNumber'] ??
        map['referenceNumber'] ??
        map['ticketRef'] ??
        TicketEmailService.generateReferenceNumber(id, created > 0 ? created : null);

    final rawResponses = map['responses'];
    final List<TicketResponseItem> respList = [];
    if (rawResponses is List) {
      for (var i = 0; i < rawResponses.length; i++) {
        final item = rawResponses[i];
        if (item is Map<String, dynamic>) {
          respList.add(TicketResponseItem.fromMap('resp_$i', item));
        }
      }
    }

    final rawRejected = map['rejectedBy'];
    final List<String> rejectedList = [];
    if (rawRejected is List) {
      for (final r in rawRejected) {
        if (r != null) rejectedList.add(r.toString());
      }
    }

    final assignedAtVal = map['assignedAt'] != null ? parseDateTime(map['assignedAt']) : null;
    final claimDeadlineVal = map['claimDeadline'] != null
        ? parseDateTime(map['claimDeadline'])
        : (assignedAtVal != null ? assignedAtVal + (180 * 1000) : null);

    return TicketModel(
      id: id,
      ticketNumber: refNum,
      uid: map['uid'] ?? map['userId'] ?? 'unknown',
      userEmail: map['userEmail'] ?? map['email'],
      userName: map['userName'] ?? map['name'],
      subject: map['subject'] ?? map['title'] ?? 'No Subject',
      description: map['description'] ?? map['details'] ?? map['message'] ?? 'No Description provided.',
      category: map['category'] ?? map['type'] ?? 'General',
      status: map['status'] ?? 'Open',
      priority: map['priority'] ?? 'Medium',
      assignedAgentId: map['assignedAgentId'] ?? map['assignedTo'] ?? map['agentId'],
      assignedAgentName: map['assignedAgentName'] ?? map['assignedToName'] ?? map['agentName'],
      assignedAgentEmail: map['assignedAgentEmail'] ?? map['assignedToEmail'] ?? map['agentEmail'],
      assignedAt: assignedAtVal,
      claimDeadline: claimDeadlineVal,
      lastHeartbeat: map['lastHeartbeat'] != null ? parseDateTime(map['lastHeartbeat']) : null,
      rejectedBy: rejectedList,
      createdAt: created,
      updatedAt: parseDateTime(map['updatedAt'] ?? map['lastUpdated'] ?? created),
      resolvedAt: map['resolvedAt'] != null ? parseDateTime(map['resolvedAt']) : null,
      emailConfirmationSent: map['emailConfirmationSent'] ?? false,
      emailLogs: List<dynamic>.from(map['emailLogs'] ?? []),
      responses: respList,
    );
  }
}

// ── Providers ──────────────────────────────────────────────────

final ticketsStreamProvider = StreamProvider<List<TicketModel>>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(<TicketModel>[]);
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('supportTickets')
      .snapshots()
      .map((snap) {
        final list = snap.docs.map((doc) => TicketModel.fromMap(doc.id, doc.data())).toList();
        list.sort((ticketA, ticketB) => ticketB.createdAt.compareTo(ticketA.createdAt));
        return list;
      })
      .handleError((err) {
        print('[Tickets] Stream failed: $err');
        return <TicketModel>[];
      });
});

final ticketSearchQueryProvider = StateProvider<String>((ref) => '');
final ticketStatusFilterProvider = StateProvider<String>((ref) => 'all');
final ticketCategoryFilterProvider = StateProvider<String>((ref) => 'all');
final selectedTicketIdProvider = StateProvider<String?>((ref) => null);

// ── Page Component ─────────────────────────────────────────────

class TicketsPage extends StatefulComponent {
  const TicketsPage({super.key});

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  String _replyMessage = '';
  String _targetStatus = '';
  bool _sendEmailOnReply = true;
  bool _isSubmitting = false;
  String? _actionFeedback;
  bool _feedbackIsError = false;
  Timer? _heartbeatTimer;

  // New manual ticket form state
  bool _showCreateModal = false;
  String _newTicketEmail = '';
  String _newTicketName = '';
  String _newTicketSubject = '';
  String _newTicketCategory = 'General';
  String _newTicketDescription = '';

  @override
  void initState() {
    super.initState();
    // Heartbeat timer every 30s while working on a ticket
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) => _sendWorkingHeartbeat());
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendWorkingHeartbeat() async {
    final selectedId = context.read(selectedTicketIdProvider);
    final currentUser = context.read(adminCurrentUserProvider).value;
    if (selectedId == null || currentUser == null) return;

    try {
      final firestore = context.read(firestoreProvider);
      await RequestLockService.sendHeartbeat(
        firestore: firestore,
        collectionName: 'supportTickets',
        requestId: selectedId,
        currentAgentUid: currentUser.uid,
      );
    } catch (_) {}
  }

  void _showFeedback(String message, {bool isError = false}) {
    setState(() {
      _actionFeedback = message;
      _feedbackIsError = isError;
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _actionFeedback = null;
        });
      }
    });
  }

  /// Atomic Claim Action with Single-Agent Request Lock Protocol
  Future<void> _claimTicket(TicketModel ticket, String userEmail) async {
    final currentUser = context.read(adminCurrentUserProvider).value;
    if (currentUser == null) return;

    final agentName = (currentUser.displayName?.isNotEmpty == true)
        ? currentUser.displayName!
        : (currentUser.email?.split('@').first ?? 'Agent');

    final profile = context.read(currentAdminProfileProvider).value;
    final currentUserEmail = currentUser.email ?? 'admin@tranyx.app';
    final role = profile?.role.toLowerCase() ?? '';
    final isAdmin =
        role.contains('admin') || currentUserEmail == 'admin@tranyx.app' || currentUserEmail == 'admin@tranyx.com';

    final firestore = context.read(firestoreProvider);

    try {
      await RequestLockService.acceptOrPassRequest(
        firestore: firestore,
        collectionName: 'supportTickets',
        requestId: ticket.id,
        currentAgentUid: currentUser.uid,
        currentAgentName: agentName,
        currentAgentEmail: currentUser.email,
        isAdmin: isAdmin,
      );

      // Send automated email to user notifying them an agent is attending to the ticket
      if (userEmail.isNotEmpty && userEmail.contains('@')) {
        await TicketEmailService.sendTicketStatusUpdateEmail(
          firestore: firestore,
          ticketId: ticket.id,
          referenceNumber: ticket.ticketNumber,
          recipientEmail: userEmail,
          recipientName: ticket.userName ?? 'Valued Customer',
          uid: ticket.uid,
          subject: ticket.subject,
          description: ticket.description,
          category: ticket.category,
          oldStatus: ticket.status,
          newStatus: 'In Progress',
          agentName: agentName,
          agentResponse: 'Support Agent $agentName has accepted your ticket and is actively working on your request.',
          submittedAt: ticket.createdAt,
        );
      }

      _showFeedback('✅ Ticket #${ticket.ticketNumber} locked & claimed. Status updated to In Progress.');
    } catch (e) {
      _showFeedback(e.toString().replaceAll('Exception:', '').trim(), isError: true);
    }
  }

  /// Reject / Pass Ticket back to PENDING queue
  Future<void> _rejectTicket(TicketModel ticket) async {
    final currentUser = context.read(adminCurrentUserProvider).value;
    if (currentUser == null) return;

    try {
      final firestore = context.read(firestoreProvider);
      await RequestLockService.rejectOrPassRequest(
        firestore: firestore,
        collectionName: 'supportTickets',
        requestId: ticket.id,
        currentAgentUid: currentUser.uid,
      );
      context.read(selectedTicketIdProvider.notifier).state = null;
      _showFeedback('Ticket #${ticket.ticketNumber} passed to next candidate in queue.');
    } catch (e) {
      _showFeedback(e.toString().replaceAll('Exception:', '').trim(), isError: true);
    }
  }

  /// Resend Initial Confirmation Email
  Future<void> _resendConfirmationEmail(TicketModel ticket, String userEmail, String userName) async {
    if (userEmail.isEmpty || !userEmail.contains('@')) {
      _showFeedback('Cannot send confirmation: No valid email address found for this user.', isError: true);
      return;
    }

    try {
      final firestore = context.read(firestoreProvider);
      await TicketEmailService.sendTicketConfirmationEmail(
        firestore: firestore,
        ticketId: ticket.id,
        referenceNumber: ticket.ticketNumber,
        recipientEmail: userEmail,
        recipientName: userName,
        uid: ticket.uid,
        subject: ticket.subject,
        description: ticket.description,
        category: ticket.category,
        status: ticket.status,
        createdAt: ticket.createdAt > 0 ? ticket.createdAt : DateTime.now().millisecondsSinceEpoch,
      );
      _showFeedback('📧 Confirmation email resent to $userEmail with reference #${ticket.ticketNumber}.');
    } catch (e) {
      _showFeedback('Failed to resend confirmation email: $e', isError: true);
    }
  }

  /// Send Response / Status Update to Customer
  Future<void> _submitResponse(TicketModel ticket, String userEmail, String userName) async {
    final msg = _replyMessage.trim();
    final newStatus = _targetStatus.isNotEmpty ? _targetStatus : ticket.status;

    if (msg.isEmpty && newStatus == ticket.status) {
      _showFeedback('Please write a message or select a new status.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final currentUser = context.read(adminCurrentUserProvider).value;
      final agentName = (currentUser?.displayName?.isNotEmpty == true)
          ? currentUser!.displayName!
          : (currentUser?.email?.split('@').first ?? 'Staff Agent');

      final firestore = context.read(firestoreProvider);
      final now = DateTime.now().millisecondsSinceEpoch;

      final newResponseMap = {
        'senderId': currentUser?.uid ?? 'agent',
        'senderName': agentName,
        'senderEmail': currentUser?.email,
        'message': msg,
        'createdAt': now,
        'isStaff': true,
        'statusChange': newStatus != ticket.status ? newStatus : null,
      };

      final isResolved = newStatus.toLowerCase() == 'resolved' || newStatus.toLowerCase() == 'closed';

      await firestore.collection('supportTickets').doc(ticket.id).set({
        'status': newStatus,
        'lastHeartbeat': now,
        'updatedAt': now,
        if (isResolved) 'resolvedAt': now,
        'responses': FieldValue.arrayUnion([newResponseMap]),
      }, SetOptions(merge: true));

      // Also append to subcollection for full compatibility
      await firestore.collection('supportTickets').doc(ticket.id).collection('responses').add(newResponseMap);

      // Dispatch Email Notification
      if (_sendEmailOnReply && userEmail.isNotEmpty && userEmail.contains('@')) {
        await TicketEmailService.sendTicketStatusUpdateEmail(
          firestore: firestore,
          ticketId: ticket.id,
          referenceNumber: ticket.ticketNumber,
          recipientEmail: userEmail,
          recipientName: userName,
          uid: ticket.uid,
          subject: ticket.subject,
          description: ticket.description,
          category: ticket.category,
          oldStatus: ticket.status,
          newStatus: newStatus,
          agentName: agentName,
          agentResponse: msg.isNotEmpty ? msg : null,
          submittedAt: ticket.createdAt,
        );
      }

      setState(() {
        _replyMessage = '';
        _targetStatus = '';
        _isSubmitting = false;
      });

      _showFeedback('✅ Ticket response recorded${_sendEmailOnReply ? " and email sent to $userEmail" : ""}.');
    } catch (e) {
      setState(() => _isSubmitting = false);
      _showFeedback('Failed to post update: $e', isError: true);
    }
  }

  /// Create Manual Ticket
  Future<void> _createManualTicket() async {
    if (_newTicketSubject.trim().isEmpty || _newTicketDescription.trim().isEmpty) {
      _showFeedback('Subject and description are required.', isError: true);
      return;
    }

    try {
      final firestore = context.read(firestoreProvider);
      final currentUser = context.read(adminCurrentUserProvider).value;
      final now = DateTime.now().millisecondsSinceEpoch;

      final docRef = firestore.collection('supportTickets').doc();
      final refNum = TicketEmailService.generateReferenceNumber(docRef.id, now);

      await docRef.set({
        'ticketNumber': refNum,
        'uid': 'manual_admin_${currentUser?.uid ?? "staff"}',
        'userEmail': _newTicketEmail.trim(),
        'userName': _newTicketName.trim().isNotEmpty ? _newTicketName.trim() : 'Customer',
        'subject': _newTicketSubject.trim(),
        'category': _newTicketCategory,
        'description': _newTicketDescription.trim(),
        'status': 'Open',
        'priority': 'Medium',
        'createdAt': now,
        'updatedAt': now,
        'emailConfirmationSent': false,
        'rejectedBy': [],
        'responses': [],
      });

      if (_newTicketEmail.trim().isNotEmpty && _newTicketEmail.contains('@')) {
        await TicketEmailService.sendTicketConfirmationEmail(
          firestore: firestore,
          ticketId: docRef.id,
          referenceNumber: refNum,
          recipientEmail: _newTicketEmail.trim(),
          recipientName: _newTicketName.trim().isNotEmpty ? _newTicketName.trim() : 'Customer',
          uid: 'manual_${docRef.id}',
          subject: _newTicketSubject.trim(),
          description: _newTicketDescription.trim(),
          category: _newTicketCategory,
          status: 'Open',
          createdAt: now,
        );
      }

      setState(() {
        _showCreateModal = false;
        _newTicketEmail = '';
        _newTicketName = '';
        _newTicketSubject = '';
        _newTicketDescription = '';
      });

      _showFeedback('🎟️ Ticket #$refNum created successfully & confirmation email dispatched.');
    } catch (e) {
      _showFeedback('Failed to create ticket: $e', isError: true);
    }
  }

  @override
  Component build(BuildContext context) {
    final ticketsAsync = context.watch(ticketsStreamProvider);
    final users = context.watch(usersStreamProvider).value ?? [];
    final currentUser = context.watch(adminCurrentUserProvider).value;
    final currentUserEmail = currentUser?.email ?? '';
    final isAdmin = currentUserEmail.toLowerCase().contains('admin') || currentUserEmail == 'admin@tranyx.app';
    final currentUserId = currentUser?.uid ?? '';
    final config = context.watch(systemConfigStreamProvider).value ?? const SystemConfigModel();
    final onlineAgents = context.watch(onlineAgentsStreamProvider).value ?? [];

    final searchQuery = context.watch(ticketSearchQueryProvider).toLowerCase().trim();
    final statusFilter = context.watch(ticketStatusFilterProvider);
    final categoryFilter = context.watch(ticketCategoryFilterProvider);
    final selectedTicketId = context.watch(selectedTicketIdProvider);

    String getUserName(String uid, String? fallbackName) {
      if (fallbackName != null && fallbackName.isNotEmpty && fallbackName != 'Unknown User') {
        return fallbackName;
      }
      final match = users.firstWhere(
        (usr) => usr.uid == uid,
        orElse: () => UserProfileModel(
          uid: '',
          name: 'Unknown User',
          email: '',
          idVerified: false,
          bgChecked: false,
          verificationLevel: 0,
          banned: false,
        ),
      );
      return match.name.isNotEmpty ? match.name : 'Customer';
    }

    String getUserEmail(String uid, String? fallbackEmail) {
      if (fallbackEmail != null && fallbackEmail.isNotEmpty && fallbackEmail != 'N/A') {
        return fallbackEmail;
      }
      final match = users.firstWhere(
        (usr) => usr.uid == uid,
        orElse: () => UserProfileModel(
          uid: '',
          name: '',
          email: 'N/A',
          idVerified: false,
          bgChecked: false,
          verificationLevel: 0,
          banned: false,
        ),
      );
      return match.email;
    }

    final allTickets = ticketsAsync.value ?? [];

    // Filter tickets
    final filteredTickets = allTickets.where((t) {
      // 1. Status Filter
      if (statusFilter == 'open' && !t.isPending) return false;
      if (statusFilter == 'in_progress' && !t.isInProgress) return false;
      if (statusFilter == 'resolved' && !t.isResolved) return false;
      if (statusFilter == 'my_assigned' && t.assignedAgentId != currentUserId) return false;

      // 2. Category Filter
      if (categoryFilter != 'all' && t.category.toLowerCase() != categoryFilter.toLowerCase()) return false;

      // 3. Search Query (Ticket #, Ref #, Email, Name, UID, Subject, Description)
      if (searchQuery.isNotEmpty) {
        final email = getUserEmail(t.uid, t.userEmail).toLowerCase();
        final name = getUserName(t.uid, t.userName).toLowerCase();
        final refNum = t.ticketNumber.toLowerCase();
        final id = t.id.toLowerCase();
        final subject = t.subject.toLowerCase();
        final desc = t.description.toLowerCase();
        final uid = t.uid.toLowerCase();

        final matches =
            refNum.contains(searchQuery) ||
            id.contains(searchQuery) ||
            email.contains(searchQuery) ||
            name.contains(searchQuery) ||
            subject.contains(searchQuery) ||
            desc.contains(searchQuery) ||
            uid.contains(searchQuery);
        if (!matches) return false;
      }

      return true;
    }).toList();

    // Find active selected ticket
    final selectedTicket = allTickets.where((t) => t.id == selectedTicketId).firstOrNull;

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0]', [
      // Top Notification / Feedback Banner
      if (_actionFeedback != null)
        div(
          classes:
              'w-full p-4 rounded-2xl border flex items-center justify-between gap-3 animate-fade-in shadow-sm '
              '${_feedbackIsError ? "bg-red-50 border-red-200 text-red-700" : "bg-emerald-50 border-emerald-200 text-emerald-800"}',
          [
            div(classes: 'flex items-center gap-2.5 text-xs font-bold', [
              span(classes: 'text-sm', [Component.text(_feedbackIsError ? '⚠️' : '✨')]),
              Component.text(_actionFeedback!),
            ]),
            button(
              onClick: () => setState(() => _actionFeedback = null),
              classes: 'text-xs font-bold px-2 py-1 rounded-lg hover:bg-black/5 transition-colors',
              [Component.text('✕')],
            ),
          ],
        ),

      // Header Block
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          div(classes: 'flex items-center gap-2.5', [
            h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [Component.text('Support Tickets Center')]),
            span(
              classes: 'px-2.5 py-0.5 rounded-full text-[10px] font-extrabold bg-zinc-200 text-zinc-700',
              [Component.text('${allTickets.length} Total')],
            ),
            span(
              classes: 'px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-indigo-50 text-indigo-700 border border-indigo-200/60',
              [Component.text('Lock Timeout: ${config.claimTimeoutSeconds}s')],
            ),
          ]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text(
              'Review customer concerns, track reference numbers, dispatch email updates, and resolve tickets.',
            ),
          ]),
        ]),
        div(classes: 'flex items-center gap-3', [
          button(
            onClick: () => setState(() => _showCreateModal = true),
            classes: 'px-4 py-2.5 bg-black hover:bg-zinc-800 text-white rounded-xl text-xs font-black transition-all shadow-sm flex items-center gap-2',
            [
              span(classes: 'text-sm font-bold', [Component.text('+')]),
              Component.text('New Manual Ticket'),
            ],
          ),
        ]),
      ]),

      // Search and Filter Bar
      div(
        classes: 'flex flex-col md:flex-row gap-3 items-stretch md:items-center justify-between bg-white p-3.5 rounded-2xl border border-zinc-200/60 shadow-sm',
        [
          // Search Input
          div(classes: 'relative flex-1 min-w-[260px]', [
            input(
              value: searchQuery,
              onInput: (v) => context.read(ticketSearchQueryProvider.notifier).state = v as String,
              classes: 'w-full bg-[#f4f6f5] border border-zinc-200/80 rounded-xl pl-9 pr-4 py-2.5 text-xs text-zinc-900 placeholder:text-zinc-400 focus:outline-none focus:ring-1 focus:ring-black',
              attributes: {'placeholder': 'Search by Ticket #, Ref #, Email, Name, Subject, UID...'},
            ),
            span(classes: 'absolute left-3 top-2.5 text-zinc-400 text-xs', [Component.text('🔍')]),
            if (searchQuery.isNotEmpty)
              button(
                onClick: () => context.read(ticketSearchQueryProvider.notifier).state = '',
                classes: 'absolute right-2.5 top-2 text-zinc-400 hover:text-zinc-700 text-xs px-1',
                [Component.text('✕')],
              ),
          ]),

          // Status Tabs
          div(classes: 'flex items-center gap-1 bg-[#eff2f0] p-1 rounded-xl overflow-x-auto no-scrollbar', [
            _buildFilterTab(context, 'All', 'all', statusFilter),
            _buildFilterTab(context, 'Open', 'open', statusFilter),
            _buildFilterTab(context, 'In Progress', 'in_progress', statusFilter),
            _buildFilterTab(context, 'My Assigned', 'my_assigned', statusFilter),
            _buildFilterTab(context, 'Resolved', 'resolved', statusFilter),
          ]),

          // Category Select
          select(
            classes: 'bg-[#f4f6f5] border border-zinc-200/80 rounded-xl px-3 py-2 text-xs font-bold text-zinc-700 focus:outline-none cursor-pointer',
            onChange: (val) {
              final sel = val.isNotEmpty ? val.first : 'all';
              context.read(ticketCategoryFilterProvider.notifier).state = sel;
            },
            [
              option(value: 'all', selected: categoryFilter == 'all', [Component.text('All Categories')]),
              option(value: 'General', selected: categoryFilter == 'General', [Component.text('General')]),
              option(value: 'Payment / P2P', selected: categoryFilter == 'Payment / P2P', [
                Component.text('Payment / P2P'),
              ]),
              option(value: 'Account', selected: categoryFilter == 'Account', [Component.text('Account')]),
              option(value: 'KYC Verification', selected: categoryFilter == 'KYC Verification', [
                Component.text('KYC Verification'),
              ]),
              option(value: 'Booking / Rental', selected: categoryFilter == 'Booking / Rental', [
                Component.text('Booking / Rental'),
              ]),
              option(value: 'Technical', selected: categoryFilter == 'Technical', [Component.text('Technical')]),
              option(value: 'Security', selected: categoryFilter == 'Security', [Component.text('Security')]),
            ],
          ),
        ],
      ),

      // Main Table / Content List
      ticketsAsync.when(
        data: (tickets) {
          if (filteredTickets.isEmpty) {
            return div(
              classes: 'flex-grow flex flex-col items-center justify-center text-center p-16 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
              [
                span(classes: 'text-4xl mb-3', [Component.text('🎟️')]),
                h3(classes: 'text-sm font-bold text-zinc-900', [
                  Component.text(allTickets.isEmpty ? 'No support tickets recorded' : 'No matching tickets found'),
                ]),
                p(classes: 'text-xs text-zinc-400 mt-1 max-w-sm leading-relaxed', [
                  Component.text(
                    allTickets.isEmpty
                        ? 'Customer tickets submitted from the mobile/web app will automatically appear here with full email confirmations and reference numbers.'
                        : 'Try adjusting your search criteria or filter tabs to find the desired ticket.',
                  ),
                ]),
              ],
            );
          }

          return div(
            classes: 'overflow-x-auto w-full rounded-[28px] border border-zinc-200/50 bg-white shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
            [
              table(classes: 'w-full text-left text-xs border-collapse', [
                thead(
                  classes: 'bg-[#f8faf9] text-zinc-500 font-bold border-b border-zinc-100 text-[10px] uppercase tracking-wider',
                  [
                    tr([
                      th(classes: 'p-4.5', [Component.text('Reference #')]),
                      th(classes: 'p-4.5', [Component.text('User / Reporter')]),
                      th(classes: 'p-4.5', [Component.text('Subject & Category')]),
                      th(classes: 'p-4.5', [Component.text('Concern Details')]),
                      th(classes: 'p-4.5 text-center', [Component.text('Status')]),
                      th(classes: 'p-4.5 text-center', [Component.text('Assigned Agent')]),
                      th(classes: 'p-4.5 text-center', [Component.text('Submitted')]),
                      th(classes: 'p-4.5 text-right', [Component.text('Actions')]),
                    ]),
                  ],
                ),
                tbody(classes: 'divide-y divide-zinc-50', [
                  for (final ticket in filteredTickets)
                    _buildTicketRow(
                      ticket: ticket,
                      userName: getUserName(ticket.uid, ticket.userName),
                      userEmail: getUserEmail(ticket.uid, ticket.userEmail),
                      isAdmin: isAdmin,
                      currentUserId: currentUserId,
                      claimTimeoutSec: config.claimTimeoutSeconds,
                      onlineAgents: onlineAgents,
                    ),
                ]),
              ]),
            ],
          );
        },
        loading: () => div(
          classes: 'flex-grow flex justify-center items-center py-24 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
          [div(classes: 'animate-spin h-7 w-7 border-2 border-zinc-200 border-t-indigo-500 rounded-full', [])],
        ),
        error: (err, _) => div(
          classes: 'p-6 bg-red-50/5 border border-red-500/10 text-red-500 text-xs rounded-[20px] font-mono shadow-sm',
          [Component.text('Error loading tickets: $err')],
        ),
      ),

      // Ticket Detail & Conversation Modal
      if (selectedTicket != null)
        _buildTicketDetailModal(
          ticket: selectedTicket,
          userName: getUserName(selectedTicket.uid, selectedTicket.userName),
          userEmail: getUserEmail(selectedTicket.uid, selectedTicket.userEmail),
          isAdmin: isAdmin,
          currentUserId: currentUserId,
          claimTimeoutSec: config.claimTimeoutSeconds,
          onlineAgents: onlineAgents,
        ),

      // Create Manual Ticket Modal
      if (_showCreateModal) _buildCreateTicketModal(),
    ]);
  }

  Component _buildFilterTab(BuildContext context, String label, String value, String current) {
    final isSelected = current == value;
    return button(
      onClick: () => context.read(ticketStatusFilterProvider.notifier).state = value,
      classes:
          'px-3 py-1.5 rounded-lg text-[11px] font-extrabold transition-all whitespace-nowrap '
          '${isSelected ? "bg-black text-white shadow-sm" : "text-zinc-600 hover:text-black hover:bg-white/60"}',
      [Component.text(label)],
    );
  }

  Component _buildTicketRow({
    required TicketModel ticket,
    required String userName,
    required String userEmail,
    required bool isAdmin,
    required String currentUserId,
    required int claimTimeoutSec,
    required List<AgentPresenceModel> onlineAgents,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final isClaimedByMe = ticket.assignedAgentId == currentUserId;
    final isClaimExpired = ticket.isClaimExpired(nowMs, claimTimeoutSec);
    final isClaimedByOther =
        ticket.assignedAgentId != null && ticket.assignedAgentId!.isNotEmpty && !isClaimedByMe && !isClaimExpired;
    final canClaim =
        !ticket.isResolved && (ticket.assignedAgentId == null || isClaimExpired || isClaimedByMe || isAdmin);
    final assignedAgent = onlineAgents.where((agent) => agent.uid == ticket.assignedAgentId).firstOrNull;
    final isAgentOnline = assignedAgent != null || isClaimedByMe;

    String statusBadgeStyle(String st) {
      final s = st.toLowerCase();
      if (s == 'open' || s == 'pending') return 'bg-amber-50 text-amber-700 border-amber-200';
      if (s == 'assigned') return 'bg-indigo-50 text-indigo-700 border-indigo-200';
      if (s == 'in progress' || s == 'in_progress') return 'bg-blue-50 text-blue-700 border-blue-200';
      if (s == 'resolved') return 'bg-emerald-50 text-[#0fa958] border-emerald-200';
      return 'bg-zinc-100 text-zinc-600 border-zinc-200';
    }

    return tr(classes: 'hover:bg-[#fcfdfc] transition-colors', [
      // Reference Number
      td(classes: 'p-4.5 font-mono text-[11px] font-black text-zinc-800', [
        div(classes: 'flex flex-col gap-0.5', [
          span(classes: 'text-zinc-900', [Component.text(ticket.ticketNumber)]),
          if (ticket.emailConfirmationSent)
            span(classes: 'text-[9px] text-emerald-600 font-semibold flex items-center gap-1', [
              Component.text('✓ Email Confirmed'),
            ]),
        ]),
      ]),

      // User / Reporter
      td(classes: 'p-4.5 font-bold text-zinc-900', [
        div(classes: 'flex flex-col gap-0.5 max-w-[180px]', [
          span(classes: 'truncate', [Component.text(userName)]),
          span(classes: 'text-[10px] text-zinc-400 font-mono font-medium truncate', [Component.text(userEmail)]),
        ]),
      ]),

      // Subject & Category
      td(classes: 'p-4.5 text-zinc-700', [
        div(classes: 'flex flex-col gap-1 max-w-[200px]', [
          span(classes: 'font-extrabold text-zinc-900 truncate', [Component.text(ticket.subject)]),
          span(
            classes: 'text-[9px] font-extrabold uppercase tracking-wider text-indigo-600 bg-indigo-50 border border-indigo-500/10 px-2 py-0.5 rounded-md w-max',
            [Component.text(ticket.category)],
          ),
        ]),
      ]),

      // Description Snippet
      td(classes: 'p-4.5 text-zinc-500 font-medium max-w-xs leading-relaxed', [
        p(classes: 'line-clamp-2 text-[11px]', [Component.text(ticket.description)]),
      ]),

      // Status
      td(classes: 'p-4.5 text-center', [
        span(
          classes:
              'px-2.5 py-1 text-[10px] font-extrabold uppercase tracking-wider rounded-full border ${statusBadgeStyle(ticket.status)}',
          [Component.text(ticket.status)],
        ),
      ]),

      // Assigned Agent & Lock status
      td(classes: 'p-4.5 text-center', [
        if (ticket.assignedAgentName != null && ticket.assignedAgentName!.isNotEmpty)
          div(classes: 'flex flex-col items-center gap-0.5', [
            div(classes: 'flex items-center gap-1.5', [
              span(
                classes: 'w-1.5 h-1.5 rounded-full ${isAgentOnline ? "bg-[#0fa958] animate-pulse" : "bg-zinc-300"}',
                attributes: {'title': isAgentOnline ? 'Agent is Online' : 'Agent is Offline'},
                [],
              ),
              span(
                classes:
                    'px-2 py-0.5 text-[10px] font-bold rounded-md '
                    '${isClaimedByMe
                        ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                        : isClaimExpired
                        ? "bg-rose-50 text-rose-700 border border-rose-200"
                        : "bg-zinc-100 text-zinc-700 border border-zinc-200"}',
                [
                  Component.text(
                    isClaimedByMe
                        ? '👤 You'
                        : isClaimExpired
                        ? '⚠️ Expired (${ticket.assignedAgentName})'
                        : '🔒 ${ticket.assignedAgentName}',
                  ),
                ],
              ),
            ]),
            if (isClaimExpired)
              span(classes: 'text-[9px] text-rose-500 font-semibold', [Component.text('Claim Timed Out')])
            else if (!isAgentOnline && !isClaimedByMe)
              span(classes: 'text-[9px] text-zinc-400 font-medium', [Component.text('Offline (Auto-Releasing)')]),
          ])
        else
          span(
            classes:
                'text-[10px] text-amber-600 font-bold bg-amber-50 px-2 py-0.5 rounded-md border border-amber-200/60',
            [
              Component.text('Unassigned'),
            ],
          ),
      ]),

      // Created Date
      td(classes: 'p-4.5 text-center text-zinc-400 font-medium text-[10px]', [
        Component.text(
          ticket.createdAt > 0
              ? '${DateTime.fromMillisecondsSinceEpoch(ticket.createdAt).year}-${DateTime.fromMillisecondsSinceEpoch(ticket.createdAt).month.toString().padLeft(2, "0")}-${DateTime.fromMillisecondsSinceEpoch(ticket.createdAt).day.toString().padLeft(2, "0")}'
              : 'N/A',
        ),
      ]),

      // Actions
      td(classes: 'p-4.5 text-right', [
        div(classes: 'flex items-center justify-end gap-2', [
          if (canClaim && !isClaimedByMe)
            button(
              onClick: () => _claimTicket(ticket, userEmail),
              classes: 'px-2.5 py-1.5 bg-black hover:bg-zinc-800 text-white text-[10px] font-black rounded-lg transition-colors shadow-sm',
              [Component.text(isClaimExpired ? 'Override Lock' : 'Accept')],
            )
          else if (isClaimedByOther && !isAdmin)
            span(classes: 'text-[10px] text-zinc-400 font-bold px-2 py-1 bg-zinc-100 rounded-lg', [
              Component.text('Locked'),
            ]),

          // Open Detail Modal
          button(
            onClick: () => context.read(selectedTicketIdProvider.notifier).state = ticket.id,
            classes: 'px-3 py-1.5 bg-zinc-100 hover:bg-zinc-200 text-zinc-800 text-[10px] font-black rounded-lg transition-colors border border-zinc-200',
            [Component.text('View & Reply')],
          ),
        ]),
      ]),
    ]);
  }

  Component _buildTicketDetailModal({
    required TicketModel ticket,
    required String userName,
    required String userEmail,
    required bool isAdmin,
    required String currentUserId,
    required int claimTimeoutSec,
    required List<AgentPresenceModel> onlineAgents,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final isClaimedByMe = ticket.assignedAgentId == currentUserId;
    final isClaimExpired = ticket.isClaimExpired(nowMs, claimTimeoutSec);
    final isClaimedByOther =
        ticket.assignedAgentId != null && ticket.assignedAgentId!.isNotEmpty && !isClaimedByMe && !isClaimExpired;
    final canRespond = isAdmin || isClaimedByMe || ticket.assignedAgentId == null || isClaimExpired;
    final assignedAgent = onlineAgents.where((agent) => agent.uid == ticket.assignedAgentId).firstOrNull;
    final agentPresenceLabel = assignedAgent != null
        ? (assignedAgent.status == AgentPresenceState.away
              ? '🟡 Away'
              : (assignedAgent.status == AgentPresenceState.busy ? '🔵 Busy' : '🟢 Online'))
        : (isClaimedByMe ? '🟢 Online' : '⚪ Offline');

    final formattedSubmitDate = TicketEmailService.formatTimestamp(ticket.createdAt);

    return div(
      classes: 'fixed inset-0 bg-black/50 backdrop-blur-sm z-[9999] flex items-center justify-center p-4 md:p-6 animate-fade-in',
      [
        div(
          classes: 'bg-white text-zinc-900 rounded-[28px] border border-zinc-200 shadow-2xl w-full max-w-3xl max-h-[90vh] overflow-hidden flex flex-col animate-scale-up',
          [
            // Modal Top Header
            div(classes: 'px-7 py-5 bg-[#f8faf9] border-b border-zinc-200 flex items-center justify-between gap-4', [
              div(classes: 'flex flex-col gap-1', [
                div(classes: 'flex items-center gap-2.5', [
                  span(classes: 'text-xs font-mono font-black px-2.5 py-1 rounded-lg bg-black text-white', [
                    Component.text(ticket.ticketNumber),
                  ]),
                  span(
                    classes: 'text-xs font-extrabold text-indigo-600 bg-indigo-50 px-2.5 py-0.5 rounded-full border border-indigo-200',
                    [
                      Component.text(ticket.category),
                    ],
                  ),
                  span(
                    classes: 'text-xs font-bold text-amber-700 bg-amber-50 px-2.5 py-0.5 rounded-full border border-amber-200',
                    [
                      Component.text('Status: ${ticket.status}'),
                    ],
                  ),
                ]),
                h2(classes: 'text-base font-black text-zinc-900 mt-1', [Component.text(ticket.subject)]),
              ]),

              button(
                onClick: () => context.read(selectedTicketIdProvider.notifier).state = null,
                classes: 'w-8 h-8 rounded-full bg-zinc-200/70 hover:bg-zinc-300 text-zinc-600 flex items-center justify-center text-xs font-bold cursor-pointer transition-colors',
                [Component.text('✕')],
              ),
            ]),

            // Scrollable Content
            div(classes: 'p-7 overflow-y-auto flex flex-col gap-6 flex-1 bg-[#eff2f0]/30', [
              // Reporter Card
              div(
                classes: 'bg-white p-5 rounded-2xl border border-zinc-200/80 shadow-sm flex flex-col md:flex-row justify-between gap-4',
                [
                  div(classes: 'flex flex-col gap-1', [
                    span(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                      Component.text('Customer Information'),
                    ]),
                    div(classes: 'flex items-center gap-2', [
                      span(classes: 'text-sm font-extrabold text-zinc-900', [Component.text(userName)]),
                      span(classes: 'text-xs text-zinc-400 font-mono', [Component.text('($userEmail)')]),
                    ]),
                    span(classes: 'text-[10px] text-zinc-400 font-mono', [Component.text('User UID: ${ticket.uid}')]),
                  ]),

                  div(classes: 'flex flex-col md:items-end gap-1.5', [
                    span(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                      Component.text('Submission Time'),
                    ]),
                    span(classes: 'text-xs font-bold text-zinc-800', [Component.text(formattedSubmitDate)]),
                    button(
                      onClick: () => _resendConfirmationEmail(ticket, userEmail, userName),
                      classes: 'mt-1 px-3 py-1 bg-zinc-100 hover:bg-zinc-200 text-zinc-700 text-[10px] font-extrabold rounded-lg transition-colors border border-zinc-200 flex items-center gap-1.5',
                      [
                        span([Component.text('📧')]),
                        Component.text('Resend Confirmation Email'),
                      ],
                    ),
                  ]),
                ],
              ),

              // Concern Details
              div(classes: 'bg-white p-5 rounded-2xl border border-zinc-200/80 shadow-sm flex flex-col gap-2', [
                span(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                  Component.text('User Concern & Submitted Details'),
                ]),
                div(
                  classes: 'p-4 rounded-xl bg-[#fafafa] border border-zinc-200 text-xs text-zinc-800 leading-relaxed font-medium whitespace-pre-wrap',
                  [
                    Component.text(ticket.description),
                  ],
                ),
              ]),

              // Action Feedback Notice inside modal
              if (_actionFeedback != null)
                div(
                  classes:
                      'p-4 rounded-2xl border flex items-center justify-between gap-3 animate-fade-in '
                      '${_feedbackIsError ? "bg-rose-50 border-rose-200 text-rose-800" : "bg-emerald-50 border-emerald-200 text-emerald-800"}',
                  [
                    div(classes: 'flex items-center gap-2 text-xs font-bold', [
                      span(classes: 'text-sm', [Component.text(_feedbackIsError ? '⚠️' : '✅')]),
                      Component.text(_actionFeedback!),
                    ]),
                    button(
                      onClick: () => setState(() => _actionFeedback = null),
                      classes: 'text-xs text-zinc-400 hover:text-zinc-700 font-bold bg-transparent border-0 cursor-pointer p-1',
                      [Component.text('✕')],
                    ),
                  ],
                ),

              // Single-Agent Lock & Concurrency Status Banner
              div(
                classes:
                    'p-4 rounded-2xl border flex items-center justify-between gap-3 '
                    '${isClaimedByMe
                        ? "bg-emerald-50 border-emerald-200"
                        : isClaimExpired
                        ? "bg-rose-50 border-rose-200"
                        : isClaimedByOther
                        ? "bg-amber-50 border-amber-200"
                        : "bg-blue-50 border-blue-200"}',
                [
                  div(classes: 'flex items-center gap-2.5', [
                    span(classes: 'text-lg', [
                      Component.text(
                        isClaimedByMe
                            ? '👤'
                            : isClaimExpired
                            ? '⏱️'
                            : isClaimedByOther
                            ? '🔒'
                            : '🔔',
                      ),
                    ]),
                    div(classes: 'flex flex-col', [
                      span(classes: 'text-xs font-black text-zinc-900', [
                        Component.text(
                          isClaimedByMe
                              ? 'Active Working Session (You)'
                              : isClaimExpired
                              ? '3-Minute Claim Window Expired — Available for takeover'
                              : isClaimedByOther
                              ? 'Handled by ${ticket.assignedAgentName} ($agentPresenceLabel)'
                              : 'This ticket is unassigned and waiting for an agent.',
                        ),
                      ]),
                      span(classes: 'text-[10px] text-zinc-500 font-medium', [
                        Component.text(
                          isClaimedByOther
                              ? 'Only the assigned agent or an admin can reply or update this ticket.'
                              : 'Heartbeat and single-agent lock active. Responses dispatch confirmation emails.',
                        ),
                      ]),
                    ]),
                  ]),

                  div(classes: 'flex items-center gap-2', [
                    if (isClaimedByMe && !ticket.isResolved)
                      button(
                        onClick: () => _rejectTicket(ticket),
                        classes: 'px-3.5 py-2 bg-red-50 hover:bg-red-100 text-red-600 text-xs font-bold rounded-xl border border-red-200 transition-colors shadow-sm cursor-pointer',
                        [Component.text('Pass to Queue')],
                      ),

                    if (!isClaimedByMe && !ticket.isResolved)
                      button(
                        onClick: () => _claimTicket(ticket, userEmail),
                        classes: 'px-4 py-2 bg-black hover:bg-zinc-800 text-white text-xs font-black rounded-xl transition-colors shrink-0 shadow-sm cursor-pointer',
                        [
                          Component.text(
                            isClaimExpired
                                ? 'Override Lock'
                                : (isClaimedByOther ? 'Take Over (Admin)' : 'Claim Ticket'),
                          ),
                        ],
                      ),
                  ]),
                ],
              ),

              // Conversation & Update History
              if (ticket.responses.isNotEmpty)
                div(classes: 'flex flex-col gap-3', [
                  span(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                    Component.text('Update & Response History'),
                  ]),
                  for (final resp in ticket.responses)
                    div(classes: 'bg-white p-4 rounded-2xl border border-zinc-200/80 shadow-sm flex flex-col gap-1.5', [
                      div(classes: 'flex items-center justify-between gap-2', [
                        div(classes: 'flex items-center gap-2', [
                          span(classes: 'text-xs font-extrabold text-zinc-900', [Component.text(resp.senderName)]),
                          if (resp.statusChange != null)
                            span(
                              classes: 'text-[10px] font-extrabold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200',
                              [
                                Component.text('Status → ${resp.statusChange}'),
                              ],
                            ),
                        ]),
                        span(classes: 'text-[10px] text-zinc-400 font-medium', [
                          Component.text(TicketEmailService.formatTimestamp(resp.createdAt)),
                        ]),
                      ]),
                      if (resp.message.isNotEmpty)
                        p(classes: 'text-xs text-zinc-700 font-medium leading-relaxed mt-1', [
                          Component.text(resp.message),
                        ]),
                    ]),
                ]),

              // Response Composer (Locked if claimed by other and not admin)
              if (!canRespond)
                div(
                  classes: 'p-5 bg-zinc-100 border border-zinc-200 rounded-2xl text-center text-xs font-bold text-zinc-500 flex items-center justify-center gap-2',
                  [
                    span([Component.text('🔒')]),
                    Component.text(
                      'Ticket locked: Only ${ticket.assignedAgentName ?? "the assigned agent"} or Admin can send replies.',
                    ),
                  ],
                )
              else
                div(classes: 'bg-white p-5 rounded-2xl border border-zinc-200/80 shadow-sm flex flex-col gap-3', [
                  span(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                    Component.text('Post Agent Update / Response'),
                  ]),

                  textarea(
                    placeholder: 'Type official response or resolution notes to customer...',
                    classes: 'w-full bg-[#f8faf9] border border-zinc-200 rounded-xl p-3.5 text-xs text-zinc-900 placeholder:text-zinc-400 focus:outline-none focus:ring-1 focus:ring-black min-h-[90px]',
                    onInput: (v) => setState(() => _replyMessage = v),
                    [_replyMessage.isNotEmpty ? Component.text(_replyMessage) : Component.text('')],
                  ),

                  div(classes: 'flex flex-col md:flex-row items-stretch md:items-center justify-between gap-3 pt-2', [
                    div(classes: 'flex items-center gap-3', [
                      select(
                        classes: 'bg-[#f4f6f5] border border-zinc-200 rounded-xl px-3 py-2 text-xs font-bold text-zinc-700 focus:outline-none cursor-pointer',
                        onChange: (val) => setState(() => _targetStatus = val.isNotEmpty ? val.first : ''),
                        [
                          option(value: '', selected: _targetStatus.isEmpty, [
                            Component.text('Keep Status (${ticket.status})'),
                          ]),
                          option(value: 'In Progress', selected: _targetStatus == 'In Progress', [
                            Component.text('Set to IN PROGRESS'),
                          ]),
                          option(value: 'Resolved', selected: _targetStatus == 'Resolved', [
                            Component.text('Set to RESOLVED'),
                          ]),
                          option(value: 'Closed', selected: _targetStatus == 'Closed', [
                            Component.text('Set to CLOSED'),
                          ]),
                        ],
                      ),

                      label(classes: 'flex items-center gap-2 text-xs font-bold text-zinc-700 cursor-pointer', [
                        input(
                          type: InputType.checkbox,
                          checked: _sendEmailOnReply,
                          onChange: (v) => setState(() => _sendEmailOnReply = !_sendEmailOnReply),
                          classes: 'rounded text-black focus:ring-0 cursor-pointer',
                        ),
                        Component.text('Send Email to Customer ($userEmail)'),
                      ]),
                    ]),

                    button(
                      onClick: () => _submitResponse(ticket, userEmail, userName),
                      classes:
                          'px-5 py-2.5 bg-black hover:bg-zinc-800 text-white text-xs font-black rounded-xl transition-all shadow-sm flex items-center justify-center gap-2 '
                          '${_isSubmitting ? "opacity-50 cursor-not-allowed" : ""}',
                      [
                        if (_isSubmitting)
                          span(
                            classes: 'animate-spin w-3.5 h-3.5 border-2 border-white border-t-transparent rounded-full',
                            [],
                          )
                        else
                          span([Component.text('✉️')]),
                        Component.text(_isSubmitting ? 'Sending...' : 'Post Update & Email'),
                      ],
                    ),
                  ]),
                ]),
            ]),

            // Modal Footer
            div(classes: 'px-7 py-4 bg-[#f8faf9] border-t border-zinc-200 flex items-center justify-between gap-3', [
              if (isAdmin)
                button(
                  onClick: () async {
                    final firestore = context.read(firestoreProvider);
                    await firestore.collection('supportTickets').doc(ticket.id).delete();
                    context.read(selectedTicketIdProvider.notifier).state = null;
                    _showFeedback('Ticket #${ticket.ticketNumber} deleted.');
                  },
                  classes: 'px-3 py-1.5 bg-red-50 hover:bg-red-100 text-red-600 text-xs font-bold rounded-xl border border-red-200 transition-colors',
                  [Component.text('Delete Ticket (Admin)')],
                )
              else
                div(classes: '', []),

              button(
                onClick: () => context.read(selectedTicketIdProvider.notifier).state = null,
                classes: 'px-5 py-2 bg-zinc-200 hover:bg-zinc-300 text-zinc-800 text-xs font-black rounded-xl transition-colors',
                [Component.text('Close')],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  Component _buildCreateTicketModal() {
    return div(
      classes: 'fixed inset-0 bg-black/50 backdrop-blur-sm z-[9999] flex items-center justify-center p-4 md:p-6 animate-fade-in',
      [
        div(
          classes: 'bg-white text-zinc-900 rounded-[28px] border border-zinc-200 shadow-2xl w-full max-w-lg overflow-hidden flex flex-col animate-scale-up',
          [
            div(classes: 'px-7 py-5 bg-[#f8faf9] border-b border-zinc-200 flex items-center justify-between', [
              div(classes: 'flex flex-col', [
                h2(classes: 'text-base font-black text-zinc-900', [Component.text('Create Manual Support Ticket')]),
                p(classes: 'text-xs text-zinc-400', [
                  Component.text('Log an inbound customer phone or email support request.'),
                ]),
              ]),
              button(
                onClick: () => setState(() => _showCreateModal = false),
                classes: 'w-7 h-7 rounded-full bg-zinc-200/70 hover:bg-zinc-300 text-zinc-600 flex items-center justify-center text-xs font-bold',
                [Component.text('✕')],
              ),
            ]),

            div(classes: 'p-7 flex flex-col gap-4', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Customer Email Address *'),
                ]),
                input(
                  value: _newTicketEmail,
                  onInput: (v) => setState(() => _newTicketEmail = v as String),
                  classes: 'bg-[#f4f6f5] border border-zinc-200 rounded-xl px-3.5 py-2.5 text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black',
                  attributes: {'placeholder': 'customer@example.com'},
                ),
              ]),

              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Customer Name'),
                ]),
                input(
                  value: _newTicketName,
                  onInput: (v) => setState(() => _newTicketName = v as String),
                  classes: 'bg-[#f4f6f5] border border-zinc-200 rounded-xl px-3.5 py-2.5 text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black',
                  attributes: {'placeholder': 'Juan Dela Cruz'},
                ),
              ]),

              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Ticket Category'),
                ]),
                select(
                  classes: 'bg-[#f4f6f5] border border-zinc-200 rounded-xl px-3 py-2.5 text-xs font-bold text-zinc-800 focus:outline-none cursor-pointer',
                  onChange: (val) => setState(() => _newTicketCategory = val.isNotEmpty ? val.first : 'General'),
                  [
                    option(value: 'General', selected: _newTicketCategory == 'General', [
                      Component.text('General Concern'),
                    ]),
                    option(value: 'Payment / P2P', selected: _newTicketCategory == 'Payment / P2P', [
                      Component.text('Payment / P2P'),
                    ]),
                    option(value: 'Account', selected: _newTicketCategory == 'Account', [
                      Component.text('Account Management'),
                    ]),
                    option(value: 'KYC Verification', selected: _newTicketCategory == 'KYC Verification', [
                      Component.text('KYC Verification'),
                    ]),
                    option(value: 'Booking / Rental', selected: _newTicketCategory == 'Booking / Rental', [
                      Component.text('Booking / Rental'),
                    ]),
                    option(value: 'Technical', selected: _newTicketCategory == 'Technical', [
                      Component.text('Technical Issue'),
                    ]),
                    option(value: 'Security', selected: _newTicketCategory == 'Security', [
                      Component.text('Security / Fraud'),
                    ]),
                  ],
                ),
              ]),

              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Subject / Concern Title *'),
                ]),
                input(
                  value: _newTicketSubject,
                  onInput: (v) => setState(() => _newTicketSubject = v as String),
                  classes: 'bg-[#f4f6f5] border border-zinc-200 rounded-xl px-3.5 py-2.5 text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black',
                  attributes: {'placeholder': 'Brief description of issue'},
                ),
              ]),

              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Full Concern Details *'),
                ]),
                textarea(
                  placeholder: 'Provide complete details of the customer concern...',
                  classes: 'bg-[#f4f6f5] border border-zinc-200 rounded-xl p-3 text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black min-h-[90px]',
                  onInput: (v) => setState(() => _newTicketDescription = v),
                  [_newTicketDescription.isNotEmpty ? Component.text(_newTicketDescription) : Component.text('')],
                ),
              ]),
            ]),

            div(classes: 'px-7 py-4 bg-[#f8faf9] border-t border-zinc-200 flex items-center justify-between gap-3', [
              button(
                onClick: () => setState(() => _showCreateModal = false),
                classes: 'px-4 py-2 bg-zinc-100 hover:bg-zinc-200 text-zinc-700 text-xs font-bold rounded-xl',
                [Component.text('Cancel')],
              ),
              button(
                onClick: _createManualTicket,
                classes: 'px-5 py-2.5 bg-black hover:bg-zinc-800 text-white text-xs font-black rounded-xl shadow-sm',
                [Component.text('Create & Dispatch Confirmation')],
              ),
            ]),
          ],
        ),
      ],
    );
  }
}
