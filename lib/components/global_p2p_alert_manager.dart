import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:riverpod/legacy.dart';
import 'package:web/web.dart' as web;

import '../app.dart';
import '../core/providers/environment_provider.dart';
import '../core/services/presence_service.dart';
import '../core/services/request_lock_service.dart';
import '../core/services/ticket_email_service.dart';
import '../pages/chats.dart' show supportChatsStreamProvider, activeChatRoomIdProvider;
import '../pages/deposits.dart' show depositRequestsStreamProvider;
import '../pages/tickets.dart' show ticketsStreamProvider, selectedTicketIdProvider;
import '../pages/withdrawals.dart' show withdrawalRequestsStreamProvider;

/// Global sound notification state provider
final globalAlertSoundEnabledProvider = StateProvider<bool>((ref) {
  try {
    final saved = web.window.localStorage.getItem('tranyx_global_sound_enabled');
    if (saved != null) {
      return saved == 'true';
    }
  } catch (_) {}
  return true;
});

/// Unified model representing an active unhandled P2P, Support Ticket, or Live Support interrupt event.
class P2PInterruptItem {
  final String id;
  final String type; // 'deposit', 'withdrawal', 'ticket', 'chat'
  final String? referenceNumber;
  final String userName;
  final String? userEmail;
  final String userId;
  final double amount;
  final String paymentMethod; // Or category / type for tickets & chats
  final String? subject;
  final String? description;
  final String status;
  final String? assignedTo;
  final String? assignedToName;
  final int? assignedAt;
  final int? claimDeadline;
  final List<String> rejectedBy;
  final DateTime createdAt;

  const P2PInterruptItem({
    required this.id,
    required this.type,
    this.referenceNumber,
    required this.userName,
    this.userEmail,
    required this.userId,
    required this.amount,
    required this.paymentMethod,
    this.subject,
    this.description,
    required this.status,
    this.assignedTo,
    this.assignedToName,
    this.assignedAt,
    this.claimDeadline,
    this.rejectedBy = const [],
    required this.createdAt,
  });

  bool get isAssigned => status.toUpperCase() == 'ASSIGNED';
  bool get isDeposit => type == 'deposit';
  bool get isWithdrawal => type == 'withdrawal';
  bool get isTicket => type == 'ticket';
  bool get isChat => type == 'chat';

  bool isClaimExpired(int nowMs, int timeoutSec) {
    if (!isAssigned) return false;
    if (claimDeadline != null && claimDeadline! > 0) {
      return nowMs > claimDeadline!;
    }
    if (assignedAt != null && assignedAt! > 0) {
      return (nowMs - assignedAt!) > (timeoutSec * 1000);
    }
    return false;
  }
}

/// Global Alert Manager Component.
/// Stays permanently mounted in the AppShell so audio chimes, 3-minute claim
/// timeouts, and single-agent interrupt modals trigger ONLY on ONE assigned agent's device.
class GlobalP2PAlertManager extends StatefulComponent {
  const GlobalP2PAlertManager({super.key});

  @override
  State<GlobalP2PAlertManager> createState() => _GlobalP2PAlertManagerState();
}

class _GlobalP2PAlertManagerState extends State<GlobalP2PAlertManager> {
  final Set<String> _seenRequestIds = {};
  final Set<String> _acknowledgedInterruptIds = {};
  P2PInterruptItem? _activeInterruptItem;
  String? _claimErrorNotice;
  Timer? _sweepTimer;

  @override
  void initState() {
    super.initState();
    // Fast periodic sweep to release timed-out or offline claims every 10 seconds
    _sweepTimer = Timer.periodic(const Duration(seconds: 10), (_) => _runSweepRoutine());
  }

  @override
  void dispose() {
    _sweepTimer?.cancel();
    super.dispose();
  }

  Future<void> _runSweepRoutine() async {
    try {
      final firestore = context.read(firestoreProvider);
      final config = context.read(systemConfigStreamProvider).value ?? const SystemConfigModel();

      // 1. Release expired support tickets
      await RequestLockService.checkAndReleaseTimeouts(
        firestore: firestore,
        collectionName: 'supportTickets',
        claimTimeoutSec: config.claimTimeoutSeconds,
        heartbeatTimeoutSec: config.heartbeatTimeoutSeconds,
      );

      // 2. Release expired live support chats
      await RequestLockService.checkAndReleaseTimeouts(
        firestore: firestore,
        collectionName: 'support_chats',
        claimTimeoutSec: config.claimTimeoutSeconds,
        heartbeatTimeoutSec: config.heartbeatTimeoutSeconds,
      );
    } catch (_) {}
  }

  void _playAlertChime() {
    final soundEnabled = context.read(globalAlertSoundEnabledProvider);
    if (!soundEnabled) return;

    try {
      final audio = web.HTMLAudioElement();
      audio.src = 'https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3';
      audio.play();
    } catch (_) {}
  }

  /// Manually Accept & Attend Ticket
  Future<void> _handleAcceptTicket(P2PInterruptItem item) async {
    final currentUser = context.read(adminCurrentUserProvider).value;
    if (currentUser == null) return;

    final agentName = (currentUser.displayName?.isNotEmpty == true)
        ? currentUser.displayName!
        : (currentUser.email?.split('@').first ?? 'Agent');

    final currentUserEmail = currentUser.email ?? '';
    final isAdmin = currentUserEmail.toLowerCase().contains('admin') || currentUserEmail == 'sarah.johnson@tranyx.com';
    final firestore = context.read(firestoreProvider);

    try {
      await RequestLockService.acceptOrPassRequest(
        firestore: firestore,
        collectionName: 'supportTickets',
        requestId: item.id,
        currentAgentUid: currentUser.uid,
        currentAgentName: agentName,
        currentAgentEmail: currentUser.email,
        isAdmin: isAdmin,
      );

      // Dispatch notification email to customer
      final recipientEmail = item.userEmail ?? '';
      if (recipientEmail.isNotEmpty && recipientEmail.contains('@')) {
        await TicketEmailService.sendTicketStatusUpdateEmail(
          firestore: firestore,
          ticketId: item.id,
          referenceNumber: item.referenceNumber ?? item.id,
          recipientEmail: recipientEmail,
          recipientName: item.userName,
          uid: item.userId,
          subject: item.subject ?? 'Support Ticket',
          description: item.description ?? '',
          category: item.paymentMethod,
          oldStatus: item.status,
          newStatus: 'In Progress',
          agentName: agentName,
          agentResponse: 'Support Agent $agentName has accepted your ticket and is actively handling your request.',
          submittedAt: item.createdAt.millisecondsSinceEpoch,
        );
      }

      setState(() {
        _acknowledgedInterruptIds.add(item.id);
        _activeInterruptItem = null;
        _claimErrorNotice = null;
      });
      context.read(selectedTicketIdProvider.notifier).state = item.id;
      Router.of(context).push('/tickets');
    } catch (e) {
      setState(() => _claimErrorNotice = e.toString().replaceAll('Exception:', '').trim());
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => _claimErrorNotice = null);
      });
    }
  }

  /// Manually Reject or Pass Ticket to Next Candidate
  Future<void> _handleRejectTicket(P2PInterruptItem item) async {
    final currentUser = context.read(adminCurrentUserProvider).value;
    if (currentUser == null) return;

    try {
      final firestore = context.read(firestoreProvider);
      await RequestLockService.rejectOrPassRequest(
        firestore: firestore,
        collectionName: 'supportTickets',
        requestId: item.id,
        currentAgentUid: currentUser.uid,
      );

      setState(() {
        _acknowledgedInterruptIds.add(item.id);
        _activeInterruptItem = null;
        _claimErrorNotice = null;
      });
    } catch (e) {
      setState(() => _claimErrorNotice = e.toString().replaceAll('Exception:', '').trim());
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) setState(() => _claimErrorNotice = null);
      });
    }
  }

  /// Manually Accept & Open Live Chat
  Future<void> _handleAcceptChat(P2PInterruptItem item) async {
    final currentUser = context.read(adminCurrentUserProvider).value;
    if (currentUser == null) return;

    final agentName = (currentUser.displayName?.isNotEmpty == true)
        ? currentUser.displayName!
        : (currentUser.email?.split('@').first ?? 'Agent');

    final currentUserEmail = currentUser.email ?? '';
    final isAdmin = currentUserEmail.toLowerCase().contains('admin') || currentUserEmail == 'sarah.johnson@tranyx.com';
    final firestore = context.read(firestoreProvider);

    try {
      await RequestLockService.acceptOrPassRequest(
        firestore: firestore,
        collectionName: 'support_chats',
        requestId: item.id,
        currentAgentUid: currentUser.uid,
        currentAgentName: agentName,
        currentAgentEmail: currentUser.email,
        isAdmin: isAdmin,
      );

      setState(() {
        _acknowledgedInterruptIds.add(item.id);
        _activeInterruptItem = null;
        _claimErrorNotice = null;
      });
      context.read(activeChatRoomIdProvider.notifier).state = item.id;
      Router.of(context).push('/chats');
    } catch (e) {
      setState(() => _claimErrorNotice = e.toString().replaceAll('Exception:', '').trim());
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => _claimErrorNotice = null);
      });
    }
  }

  /// Manually Reject or Pass Live Chat to Next Candidate
  Future<void> _handleRejectChat(P2PInterruptItem item) async {
    final currentUser = context.read(adminCurrentUserProvider).value;
    if (currentUser == null) return;

    try {
      final firestore = context.read(firestoreProvider);
      await RequestLockService.rejectOrPassRequest(
        firestore: firestore,
        collectionName: 'support_chats',
        requestId: item.id,
        currentAgentUid: currentUser.uid,
      );

      setState(() {
        _acknowledgedInterruptIds.add(item.id);
        _activeInterruptItem = null;
        _claimErrorNotice = null;
      });
    } catch (e) {
      setState(() => _claimErrorNotice = e.toString().replaceAll('Exception:', '').trim());
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) setState(() => _claimErrorNotice = null);
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final depositsAsync = context.watch(depositRequestsStreamProvider);
    final withdrawalsAsync = context.watch(withdrawalRequestsStreamProvider);
    final ticketsAsync = context.watch(ticketsStreamProvider);
    final chatsAsync = context.watch(supportChatsStreamProvider);
    final configAsync = context.watch(systemConfigStreamProvider);
    final onlineAgentsAsync = context.watch(onlineAgentsStreamProvider);
    final currentUser = context.watch(adminCurrentUserProvider).value;
    final currentUid = currentUser?.uid ?? '';
    final currentUserEmail = currentUser?.email ?? '';
    final isAdmin = currentUserEmail.toLowerCase().contains('admin') || currentUserEmail == 'sarah.johnson@tranyx.com';

    final deposits = depositsAsync.value ?? [];
    final withdrawals = withdrawalsAsync.value ?? [];
    final tickets = ticketsAsync.value ?? [];
    final chats = chatsAsync.value ?? [];
    final config = configAsync.value ?? const SystemConfigModel();
    final onlineAgents = onlineAgentsAsync.value ?? [];
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    bool isOnChainCrypto(String method) {
      final m = method.toLowerCase();
      return m.contains('usdt') ||
          m.contains('crypto') ||
          m.contains('onchain') ||
          m.contains('trc20') ||
          m.contains('erc20') ||
          m.contains('bep20') ||
          m.contains('polygon') ||
          m.contains('sol') ||
          m.contains('btc') ||
          m.contains('eth') ||
          m.contains('blockchain');
    }

    // 1. Gather unassigned deposit requests (Excluding On-Chain Crypto/USDT)
    final unhandledDeposits = deposits.where((d) {
      if (isOnChainCrypto(d.paymentMethod)) return false;
      final isUnassigned = d.assignedAgentId == null || d.assignedAgentId!.isEmpty;
      final isWaitingStatus = d.status == 'PENDING_AGENT' ||
          d.status == 'AWAITING_QR' ||
          d.status == 'WAITING_FOR_QR' ||
          d.status == 'REQUESTED' ||
          d.status == 'OPEN' ||
          d.status == 'PENDING';
      final isResolved = d.status == 'APPROVED' ||
          d.status == 'REJECTED' ||
          d.status == 'CANCELLED' ||
          d.status == 'AWAITING_PAYMENT';
      return isUnassigned && isWaitingStatus && !isResolved && !_acknowledgedInterruptIds.contains(d.id);
    }).toList();

    // 2. Gather unassigned cashout requests (Excluding On-Chain Crypto/USDT)
    final unhandledWithdrawals = withdrawals.where((w) {
      if (isOnChainCrypto(w.paymentMethod)) return false;
      final isUnassigned = w.agentId == null || w.agentId!.isEmpty;
      final isWaitingStatus = w.status == 'WAITING_FOR_AGENT' ||
          w.status == 'PENDING_AGENT' ||
          w.status == 'REQUESTED' ||
          w.status == 'OPEN' ||
          w.status == 'PENDING';
      final isResolved = w.status == 'APPROVED' ||
          w.status == 'REJECTED' ||
          w.status == 'CANCELLED' ||
          w.status == 'AWAITING_AGENT_PAYMENT' ||
          w.status == 'PENDING_CONFIRMATION';
      return isUnassigned && isWaitingStatus && !isResolved && !_acknowledgedInterruptIds.contains(w.id);
    }).toList();

    // 3. Gather actionable support tickets (Strict Single-Agent Lock)
    final unhandledTickets = tickets.where((t) {
      if (t.isResolved || t.isInProgress) return false;
      if (_acknowledgedInterruptIds.contains(t.id)) return false;

      final rawRejected = t.emailLogs.where((l) => l is Map && l['type'] == 'REJECTED').map((l) => l['agentUid']?.toString()).toList();
      final allRejected = [...t.rejectedBy, ...rawRejected];
      final isAssignedToMe = t.assignedAgentId == currentUid;
      final isClaimExpired = t.isClaimExpired(nowMs, config.claimTimeoutSeconds);
      final isUnassigned = t.assignedAgentId == null || t.assignedAgentId!.isEmpty;

      // CASE A: Already assigned or designated to current agent within claim window
      if (isAssignedToMe && (t.isAssigned || t.isPending) && !isClaimExpired) {
        return true;
      }

      // CASE B: Unassigned OR Claim Expired -> Deterministically assign to 1 single online candidate!
      if (isUnassigned || isClaimExpired) {
        if (allRejected.contains(currentUid) && !isAdmin && onlineAgents.length > 1) return false;

        final eligible = onlineAgents.where((ag) => !allRejected.contains(ag.uid)).toList();
        String? designatedCandidateUid;
        String? designatedCandidateName;
        String? designatedCandidateEmail;

        if (eligible.isNotEmpty) {
          eligible.sort((ag1, ag2) => ag1.uid.compareTo(ag2.uid));
          final chosen = eligible[t.id.hashCode.abs() % eligible.length];
          designatedCandidateUid = chosen.uid;
          designatedCandidateName = chosen.name;
          designatedCandidateEmail = chosen.email;
        } else if (currentUid.isNotEmpty) {
          designatedCandidateUid = currentUid;
          designatedCandidateName = currentUser?.displayName ?? 'Agent';
          designatedCandidateEmail = currentUser?.email ?? '';
        }

        if (designatedCandidateUid != null) {
          final firestore = context.read(firestoreProvider);
          firestore.collection('supportTickets').doc(t.id).set({
            'status': 'ASSIGNED',
            'assignedTo': designatedCandidateUid,
            'assignedToName': designatedCandidateName,
            'assignedToEmail': designatedCandidateEmail,
            'assignedAgentId': designatedCandidateUid,
            'assignedAgentName': designatedCandidateName,
            'assignedAgentEmail': designatedCandidateEmail,
            'assignedAt': nowMs,
            'claimDeadline': nowMs + (config.claimTimeoutSeconds * 1000),
            'updatedAt': nowMs,
          }, SetOptions(merge: true));

          if (designatedCandidateUid == currentUid) {
            return true;
          }
        }
        return false;
      }

      return false;
    }).toList();

    // 4. Gather actionable Live Support chats (Strict Single-Agent Lock)
    final unhandledChats = chats.where((c) {
      if (c.isResolved || c.isActive) return false;
      if (_acknowledgedInterruptIds.contains(c.id)) return false;

      final allRejected = c.rejectedBy;
      final isAssignedToMe = c.assignedAgentId == currentUid;
      final isClaimExpired = c.isClaimExpired(nowMs, config.claimTimeoutSeconds);
      final isUnassigned = c.assignedAgentId == null || c.assignedAgentId!.isEmpty;

      // CASE A: Already assigned or designated to current agent within claim window
      if (isAssignedToMe && (c.isAssigned || c.isPending) && !isClaimExpired) {
        return true;
      }

      // CASE B: Unassigned OR Claim Expired -> Deterministically assign to 1 single online candidate!
      if (isUnassigned || isClaimExpired) {
        if (allRejected.contains(currentUid) && !isAdmin && onlineAgents.length > 1) return false;

        final eligible = onlineAgents.where((ag) => !allRejected.contains(ag.uid)).toList();
        String? designatedCandidateUid;
        String? designatedCandidateName;
        String? designatedCandidateEmail;

        if (eligible.isNotEmpty) {
          eligible.sort((ag1, ag2) => ag1.uid.compareTo(ag2.uid));
          final chosen = eligible[c.id.hashCode.abs() % eligible.length];
          designatedCandidateUid = chosen.uid;
          designatedCandidateName = chosen.name;
          designatedCandidateEmail = chosen.email;
        } else if (currentUid.isNotEmpty) {
          designatedCandidateUid = currentUid;
          designatedCandidateName = currentUser?.displayName ?? 'Agent';
          designatedCandidateEmail = currentUser?.email ?? '';
        }

        if (designatedCandidateUid != null) {
          final firestore = context.read(firestoreProvider);
          firestore.collection('support_chats').doc(c.id).set({
            'status': 'assigned',
            'assignedTo': designatedCandidateUid,
            'assignedToName': designatedCandidateName,
            'assignedToEmail': designatedCandidateEmail,
            'assignedAgentId': designatedCandidateUid,
            'assignedAgentName': designatedCandidateName,
            'assignedAgentEmail': designatedCandidateEmail,
            'assignedAt': nowMs,
            'claimDeadline': nowMs + (config.claimTimeoutSeconds * 1000),
            'updatedAt': nowMs,
          }, SetOptions(merge: true));

          if (designatedCandidateUid == currentUid) {
            return true;
          }
        }
        return false;
      }

      return false;
    }).toList();

    // Combine all actionable items
    final List<P2PInterruptItem> actionableItems = [
      ...unhandledChats.map((c) {
        final assignedAtMs = c.assignedAt;
        final claimDeadlineMs = assignedAtMs != null ? assignedAtMs + (config.claimTimeoutSeconds * 1000) : null;
        final customerName = c.userName ?? (c.userIds.isNotEmpty ? 'Customer #${c.userIds.first.substring(0, min(6, c.userIds.first.length))}' : 'Customer');
        return P2PInterruptItem(
          id: c.id,
          type: 'chat',
          userName: customerName,
          userEmail: c.userEmail,
          userId: c.userIds.isNotEmpty ? c.userIds.first : c.id,
          amount: 0.0,
          paymentMethod: 'Live Support',
          subject: 'Live Support Request',
          description: c.lastMessage,
          status: c.status,
          assignedTo: c.assignedAgentId ?? currentUid,
          assignedToName: c.assignedAgentName ?? (currentUser?.displayName ?? 'Agent'),
          assignedAt: assignedAtMs,
          claimDeadline: claimDeadlineMs,
          rejectedBy: c.rejectedBy,
          createdAt: DateTime.fromMillisecondsSinceEpoch(c.requestedAt > 0 ? c.requestedAt : nowMs),
        );
      }),
      ...unhandledTickets.map((t) {
        final assignedAtMs = t.assignedAt;
        final claimDeadlineMs = assignedAtMs != null ? assignedAtMs + (config.claimTimeoutSeconds * 1000) : null;
        return P2PInterruptItem(
          id: t.id,
          type: 'ticket',
          referenceNumber: t.ticketNumber,
          userName: t.userName ?? 'Customer',
          userEmail: t.userEmail,
          userId: t.uid,
          amount: 0.0,
          paymentMethod: t.category,
          subject: t.subject,
          description: t.description,
          status: t.status,
          assignedTo: t.assignedAgentId ?? currentUid,
          assignedToName: t.assignedAgentName ?? (currentUser?.displayName ?? 'Agent'),
          assignedAt: assignedAtMs,
          claimDeadline: claimDeadlineMs,
          rejectedBy: t.rejectedBy,
          createdAt: DateTime.fromMillisecondsSinceEpoch(t.createdAt > 0 ? t.createdAt : nowMs),
        );
      }),
      ...unhandledDeposits.map((d) => P2PInterruptItem(
            id: d.id,
            type: 'deposit',
            userName: d.userName,
            userId: d.userId,
            amount: d.amount,
            paymentMethod: d.paymentMethod,
            status: d.status,
            createdAt: DateTime.fromMillisecondsSinceEpoch(d.submittedAt),
          )),
      ...unhandledWithdrawals.map((w) => P2PInterruptItem(
            id: w.id,
            type: 'withdrawal',
            userName: w.userAccountName.isNotEmpty ? w.userAccountName : w.userName,
            userId: w.uid,
            amount: w.amount,
            paymentMethod: w.paymentMethod,
            status: w.status,
            createdAt: DateTime.fromMillisecondsSinceEpoch(w.createdAt),
          )),
    ];

    // Detect brand-new items to trigger audio chime
    for (final item in actionableItems) {
      if (!_seenRequestIds.contains(item.id)) {
        _seenRequestIds.add(item.id);
        _playAlertChime();
      }
    }

    // Set active interrupt item if not currently displaying or current is resolved/claimed
    if (actionableItems.isNotEmpty) {
      if (_activeInterruptItem == null ||
          !actionableItems.any((item) => item.id == _activeInterruptItem!.id)) {
        _activeInterruptItem = actionableItems.first;
      }
    } else {
      _activeInterruptItem = null;
    }

    if (_activeInterruptItem == null) {
      return const Component.empty();
    }

    return _buildInterruptModal(_activeInterruptItem!, actionableItems.length, config.claimTimeoutSeconds);
  }

  Component _buildInterruptModal(P2PInterruptItem item, int totalActionableCount, int claimTimeoutSec) {
    final isTicket = item.type == 'ticket';
    final isChat = item.type == 'chat';
    final isDeposit = item.type == 'deposit';
    final isGcash = item.paymentMethod.toLowerCase().contains('gcash');
    final isMaya = item.paymentMethod.toLowerCase().contains('maya');
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    String formatTimeAgo(DateTime dt) {
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 45) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    }

    String getTimeoutRemainingStr() {
      final assignedAt = item.assignedAt;
      if (assignedAt == null) return 'Claim Timeout: ${claimTimeoutSec}s';
      final deadline = item.claimDeadline ?? (assignedAt + (claimTimeoutSec * 1000));
      final remainingMs = deadline - nowMs;
      if (remainingMs <= 0) return 'Claim Timed Out';
      final remSec = (remainingMs / 1000).ceil();
      final min = remSec ~/ 60;
      final sec = remSec % 60;
      return '⏱️ Claim Window: ${min > 0 ? "$min m " : ""}${sec}s remaining';
    }

    final initialLetter = item.userName.isNotEmpty ? item.userName[0].toUpperCase() : 'U';

    return div(
      attributes: {
        'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; width: 100vw; height: 100vh; z-index: 999999 !important;',
      },
      classes:
          'fixed inset-0 bg-black/65 backdrop-blur-md z-[9999] flex items-center justify-center p-4 md:p-6 animate-fade-in pointer-events-auto',
      [
        div(
          classes:
              'bg-white text-zinc-900 rounded-[28px] border border-zinc-200 shadow-2xl w-full max-w-lg overflow-hidden flex flex-col animate-scale-up',
          [
            // Header Bar
            div(
              classes:
                  'px-7 py-5.5 md:px-8 md:py-6 bg-[#f8faf9] border-b border-zinc-200/80 flex items-center justify-between gap-4',
              [
                div(classes: 'flex items-center gap-3.5', [
                  div(
                    classes:
                        'w-11 h-11 rounded-2xl flex items-center justify-center text-lg shadow-sm '
                        '${isChat ? "bg-purple-500 text-white shadow-purple-500/20" : isTicket ? "bg-indigo-600 text-white shadow-indigo-600/20" : isDeposit ? "bg-[#0fa958] text-white shadow-[#0fa958]/20" : "bg-amber-500 text-white shadow-amber-500/20"}',
                    [Component.text(isChat ? '💬' : isTicket ? '🎫' : isDeposit ? '📥' : '📤')],
                  ),
                  div(classes: 'flex flex-col gap-0.5', [
                    div(classes: 'flex items-center gap-2 flex-wrap', [
                      h2(classes: 'text-sm font-black tracking-tight text-zinc-900', [
                        Component.text(
                          isChat
                              ? 'Live Support Request'
                              : isTicket
                              ? 'New Support Ticket Raised'
                              : isDeposit
                              ? 'New Deposit Request'
                              : 'New Cashout Request',
                        ),
                      ]),
                      span(
                        classes:
                            'inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[10px] font-extrabold '
                            '${isChat ? "bg-purple-50 text-purple-700 border border-purple-200/60" : isTicket ? "bg-indigo-50 text-indigo-700 border border-indigo-200/60" : isDeposit ? "bg-emerald-50 text-[#0fa958] border border-emerald-200/60" : "bg-amber-50 text-amber-700 border border-amber-200/60"}',
                        [
                          span(classes: 'w-1.5 h-1.5 rounded-full ${isChat ? "bg-purple-600 animate-pulse" : isTicket ? "bg-indigo-600 animate-pulse" : isDeposit ? "bg-[#0fa958] animate-pulse" : "bg-amber-500 animate-pulse"}', []),
                          Component.text('Action Needed'),
                        ],
                      ),
                    ]),
                    span(classes: 'text-[11px] text-zinc-400 font-medium leading-relaxed', [
                      Component.text(
                        isChat
                            ? 'Assigned to you — Accept live chat within 3-minute window'
                            : isTicket
                            ? 'Assigned to you — Accept within 3-minute window'
                            : isDeposit
                            ? 'Customer waiting for payment QR / verification'
                            : 'Customer waiting for agent payout disbursement',
                      ),
                    ]),
                  ]),
                ]),

                button(
                  onClick: () {
                    setState(() {
                      _acknowledgedInterruptIds.add(item.id);
                      _activeInterruptItem = null;
                      _claimErrorNotice = null;
                    });
                  },
                  classes:
                      'w-8 h-8 rounded-full bg-zinc-100 hover:bg-zinc-200/80 text-zinc-400 hover:text-zinc-700 transition-all flex items-center justify-center text-xs font-bold cursor-pointer border-0 outline-none shrink-0 ml-2',
                  attributes: {'title': 'Dismiss modal'},
                  [Component.text('✕')],
                ),
              ],
            ),

            // Error notice banner
            if (_claimErrorNotice != null)
              div(classes: 'p-3.5 bg-rose-50 border-b border-rose-200 text-rose-700 text-xs font-bold flex items-center gap-2 animate-fade-in', [
                span([Component.text('⚠️')]),
                span(classes: 'flex-1 leading-snug', [Component.text(_claimErrorNotice!)]),
              ]),

            // Content Body
            div(classes: 'p-7 md:p-8 flex flex-col gap-4.5', [
              // Ticket, Chat or Amount Display
              if (isTicket || isChat)
                div(classes: 'p-5 rounded-2xl bg-white border border-zinc-200/80 shadow-sm flex flex-col gap-2.5', [
                  div(classes: 'flex items-center justify-between gap-2', [
                    span(classes: 'text-[11px] font-mono font-black text-zinc-900 bg-[#eff2f0] px-2.5 py-1 rounded-lg', [
                      Component.text(item.referenceNumber ?? (isChat ? '#CHAT-${item.id.substring(0, min(8, item.id.length))}' : item.id)),
                    ]),
                    span(classes: 'text-[10px] font-extrabold uppercase px-2.5 py-0.5 rounded-full ${isChat ? "bg-purple-50 text-purple-700 border border-purple-200" : "bg-indigo-50 text-indigo-700 border border-indigo-200"}', [
                      Component.text(item.paymentMethod),
                    ]),
                  ]),

                  // Timeout Badge
                  div(classes: 'flex items-center justify-between bg-amber-50/80 border border-amber-200/80 px-3 py-1.5 rounded-xl', [
                    span(classes: 'text-[10px] font-extrabold text-amber-800', [
                      Component.text(getTimeoutRemainingStr()),
                    ]),
                    if (item.assignedToName != null)
                      span(classes: 'text-[10px] text-amber-700 font-bold', [
                        Component.text('Assigned: ${item.assignedToName}'),
                      ]),
                  ]),

                  span(classes: 'text-sm font-extrabold text-zinc-900 leading-snug', [
                    Component.text(item.subject ?? (isChat ? 'Customer Support Message' : 'Customer Support Request')),
                  ]),
                  if (item.description != null && item.description!.isNotEmpty)
                    p(classes: 'text-xs text-zinc-600 font-medium line-clamp-3 leading-relaxed bg-[#fbfcfb] p-3.5 rounded-xl border border-zinc-100 italic', [
                      Component.text('"${item.description!}"'),
                    ]),
                ])
              else
                div(
                  classes:
                      'p-5 rounded-2xl bg-white border border-zinc-200/80 shadow-sm flex items-center justify-between gap-4',
                  [
                    div(classes: 'flex flex-col gap-0.5', [
                      span(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                        Component.text(isDeposit ? 'Deposit Amount' : 'Disbursement Amount'),
                      ]),
                      span(classes: 'text-2xl font-black text-zinc-900 tracking-tight', [
                        Component.text('₱${item.amount.toStringAsFixed(2)}'),
                      ]),
                    ]),

                    div(classes: 'flex flex-col items-end gap-1.5', [
                      span(
                        classes:
                            'px-3 py-1 rounded-full text-[11px] font-extrabold flex items-center gap-1.5 '
                            '${isGcash ? "bg-blue-50 text-[#007DFE] border border-blue-200/60" : (isMaya ? "bg-emerald-50 text-[#0fa958] border border-emerald-200/60" : "bg-zinc-100 text-zinc-700 border border-zinc-200")}',
                        [
                          span([Component.text(isGcash ? '🔵' : (isMaya ? '🟢' : '💳'))]),
                          Component.text(item.paymentMethod),
                        ],
                      ),
                      span(classes: 'text-[10px] text-zinc-400 font-medium', [
                        Component.text(formatTimeAgo(item.createdAt)),
                      ]),
                    ]),
                  ],
                ),

              // Customer Details Inset
              div(classes: 'p-4 rounded-2xl bg-[#eff2f0]/60 border border-zinc-200/50 flex flex-col gap-2', [
                div(classes: 'flex items-center justify-between gap-2', [
                  div(classes: 'flex items-center gap-2.5 min-w-0', [
                    div(
                      classes:
                          'w-7.5 h-7.5 rounded-full bg-zinc-200 border border-zinc-300 flex items-center justify-center text-xs font-bold text-zinc-700 shrink-0',
                      [Component.text(initialLetter)],
                    ),
                    div(classes: 'flex flex-col min-w-0', [
                      span(classes: 'text-xs font-bold text-zinc-800 truncate', [Component.text(item.userName)]),
                      span(classes: 'text-[10px] font-mono text-zinc-400 truncate', [
                        Component.text(
                          item.userEmail != null && item.userEmail!.isNotEmpty
                              ? item.userEmail!
                              : 'UID: ${item.userId.substring(0, item.userId.length > 10 ? 10 : item.userId.length)}...',
                        ),
                      ]),
                    ]),
                  ]),

                  if (totalActionableCount > 1)
                    span(
                      classes: 'px-2.5 py-1 rounded-full bg-zinc-200 text-zinc-600 text-[10px] font-bold shrink-0',
                      [Component.text('+${totalActionableCount - 1} more in queue')],
                    ),
                ]),
              ]),
            ]),

            // Minimal Footer Actions
            div(
              classes:
                  'px-7 py-4.5 md:px-8 md:py-5 border-t border-zinc-100 bg-[#eff2f0]/40 flex items-center justify-between gap-3',
              [
                if (isTicket)
                  button(
                    onClick: () => _handleRejectTicket(item),
                    classes:
                        'px-4 py-2.5 rounded-xl bg-red-50 hover:bg-red-100 text-red-600 text-xs font-bold transition-all cursor-pointer border border-red-200 outline-none',
                    [Component.text('Pass / Reject')],
                  )
                else if (isChat)
                  button(
                    onClick: () => _handleRejectChat(item),
                    classes:
                        'px-4 py-2.5 rounded-xl bg-red-50 hover:bg-red-100 text-red-600 text-xs font-bold transition-all cursor-pointer border border-red-200 outline-none',
                    [Component.text('Pass / Reject')],
                  )
                else
                  button(
                    onClick: () {
                      setState(() {
                        _acknowledgedInterruptIds.add(item.id);
                        _activeInterruptItem = null;
                        _claimErrorNotice = null;
                      });
                    },
                    classes:
                        'px-4.5 py-2.5 rounded-xl bg-zinc-100 hover:bg-zinc-200/80 text-zinc-600 hover:text-zinc-900 text-xs font-bold transition-all cursor-pointer border-0 outline-none',
                    [Component.text('Snooze')],
                  ),

                if (isTicket)
                  button(
                    onClick: () => _handleAcceptTicket(item),
                    classes:
                        'px-5.5 py-2.5 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-black transition-all shadow-sm cursor-pointer border-0 outline-none flex items-center gap-2',
                    [
                      Component.text('Accept & Attend Ticket'),
                      span(classes: 'text-xs font-bold', [Component.text('→')]),
                    ],
                  )
                else if (isChat)
                  button(
                    onClick: () => _handleAcceptChat(item),
                    classes:
                        'px-5.5 py-2.5 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-black transition-all shadow-sm cursor-pointer border-0 outline-none flex items-center gap-2',
                    [
                      Component.text('Accept & Open Chat'),
                      span(classes: 'text-xs font-bold', [Component.text('→')]),
                    ],
                  )
                else
                  button(
                    onClick: () {
                      setState(() {
                        _acknowledgedInterruptIds.add(item.id);
                        _activeInterruptItem = null;
                        _claimErrorNotice = null;
                      });
                      if (isDeposit) {
                        Router.of(context).push('/deposits');
                      } else {
                        Router.of(context).push('/withdrawals');
                      }
                    },
                    classes:
                        'px-5.5 py-2.5 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-black transition-all shadow-sm cursor-pointer border-0 outline-none flex items-center gap-2',
                    [
                      Component.text(isDeposit ? 'Open Deposit Queue' : 'Open Cashout Queue'),
                      span(classes: 'text-xs font-bold', [Component.text('→')]),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
