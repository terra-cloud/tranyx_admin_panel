import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:riverpod/legacy.dart';

import '../app.dart';
import '../core/providers/environment_provider.dart';

// ── Constants ──────────────────────────────────────────────────
/// Seconds before an assigned-but-silent chat is returned to pending
const _kReassignTimeoutSec = 90;

// ── Data Models ────────────────────────────────────────────────
class UserProfileModel {
  final String uid;
  final String name;
  final String email;
  final String? role;

  UserProfileModel({
    required this.uid,
    required this.name,
    required this.email,
    this.role,
  });

  factory UserProfileModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserProfileModel(
      uid: uid,
      name: map['name'] ?? 'Unknown User',
      email: map['email'] ?? 'No Email',
      role: map['role'],
    );
  }
}

/// Status flow: pending → assigned → active → resolved
class SupportChat {
  final String id;
  final String lastMessage;
  final int updatedAt;
  final int requestedAt;
  final List<String> userIds;
  final String status; // 'pending' | 'assigned' | 'active' | 'resolved'
  final String? assignedAgentId;
  final String? assignedAgentName;
  final String? assignedAgentEmail;
  final int? assignedAt;
  final int reassignCount;

  SupportChat({
    required this.id,
    required this.lastMessage,
    required this.updatedAt,
    required this.requestedAt,
    required this.userIds,
    required this.status,
    this.assignedAgentId,
    this.assignedAgentName,
    this.assignedAgentEmail,
    this.assignedAt,
    required this.reassignCount,
  });

  bool get isPending => status == 'pending';
  bool get isAssigned => status == 'assigned';
  bool get isActive => status == 'active';
  bool get isResolved => status == 'resolved';

  /// True if assigned but agent hasn't replied within timeout
  bool get isTimedOut {
    if (!isAssigned || assignedAt == null) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - assignedAt!;
    return elapsed > _kReassignTimeoutSec * 1000;
  }

  Duration get waitingTime {
    final since = requestedAt > 0 ? requestedAt : updatedAt;
    return Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - since);
  }

  factory SupportChat.fromMap(String id, Map<String, dynamic> map) {
    int parseTs(dynamic val) {
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    return SupportChat(
      id: id,
      lastMessage: map['lastMessage'] ?? 'No messages yet',
      updatedAt: parseTs(map['updatedAt']),
      requestedAt: parseTs(map['requestedAt'] ?? map['createdAt'] ?? map['updatedAt']),
      userIds: List<String>.from(map['userIds'] ?? []),
      status: map['status'] ?? 'pending',
      assignedAgentId: map['assignedAgentId'],
      assignedAgentName: map['assignedAgentName'],
      assignedAgentEmail: map['assignedAgentEmail'],
      assignedAt: map['assignedAt'] != null ? parseTs(map['assignedAt']) : null,
      reassignCount: map['reassignCount'] ?? 0,
    );
  }
}

class ChatMessage {
  final String senderId;
  final String senderName;
  final String content;
  final int createdAt;
  final bool isStaff;
  final String? agentEmail;

  ChatMessage({
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.createdAt,
    required this.isStaff,
    this.agentEmail,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? 'Unknown',
      content: map['content'] ?? '',
      createdAt: map['createdAt'] ?? 0,
      isStaff: map['isStaff'] ?? map['isAgent'] ?? (map['senderName']?.toString().contains('Admin') ?? false),
      agentEmail: map['agentEmail'],
    );
  }
}

// ── Providers ──────────────────────────────────────────────────
final chatUsersStreamProvider = StreamProvider<List<UserProfileModel>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return firestore.collection('users').snapshots().map((snap) {
    return snap.docs.map((doc) => UserProfileModel.fromMap(doc.id, doc.data())).toList();
  }).handleError((err) {
    print('[Chats] Users stream error: $err');
    return <UserProfileModel>[];
  });
});

/// Streams all support agents: anyone who is NOT admin and NOT a plain platform user
final supportAgentsProvider = StreamProvider<List<UserProfileModel>>((ref) {
  final firestore = ref.watch(adminFirestoreProvider);
  return firestore
      .collection('users')
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => UserProfileModel.fromMap(doc.id, doc.data()))
          .where((u) {
            final r = (u.role ?? '').toLowerCase().trim();
            return r.isNotEmpty && r != 'admin' && r != 'user';
          })
          .toList())
      .handleError((_) => <UserProfileModel>[]);
});

final supportChatsStreamProvider = StreamProvider<List<SupportChat>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('support_chats')
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((doc) => SupportChat.fromMap(doc.id, doc.data())).toList())
      .handleError((err) {
    print('[Chats] Support chats stream error: $err');
    return <SupportChat>[];
  });
});

final activeChatRoomIdProvider = StateProvider<String?>((ref) => null);

final activeChatMessagesStreamProvider = StreamProvider<List<ChatMessage>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final activeChatId = ref.watch(activeChatRoomIdProvider);
  if (activeChatId == null) return const Stream.empty();
  return firestore
      .collection('support_chats')
      .doc(activeChatId!)
      .collection('messages')
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map((snap) => snap.docs.map((doc) => ChatMessage.fromMap(doc.data())).toList())
      .handleError((err) {
    print('[Chats] Active messages stream error: $err');
    return <ChatMessage>[];
  });
});

final chatReplyTextProvider = StateProvider<String>((ref) => '');

/// Tracks previously seen pending chat IDs to detect new arrivals
final _seenPendingIdsProvider = StateProvider<Set<String>>((ref) => {});
final newChatAlertProvider = StateProvider<List<String>>((ref) => []);

// ── Page ───────────────────────────────────────────────────────
class ChatsPage extends StatefulComponent {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  Timer? _reassignTimer;

  @override
  void initState() {
    super.initState();
    // Poll every 15s for timed-out chats and trigger reassignment
    _reassignTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkReassignments());
  }

  @override
  void dispose() {
    _reassignTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkReassignments() async {
    try {
      final firestore = context.read(firestoreProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = now - (_kReassignTimeoutSec * 1000);

      final snap = await firestore
          .collection('support_chats')
          .where('status', isEqualTo: 'assigned')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final assignedAt = data['assignedAt'];
        int assignedAtMs = 0;
        if (assignedAt is num) assignedAtMs = assignedAt.toInt();
        if (assignedAt is Timestamp) assignedAtMs = assignedAt.millisecondsSinceEpoch;

        // If assigned but no agent response within timeout, return to pending
        if (assignedAtMs > 0 && assignedAtMs < cutoff) {
          final currentCount = (data['reassignCount'] ?? 0) as int;
          await doc.reference.update({
            'status': 'pending',
            'assignedAgentId': null,
            'assignedAgentName': null,
            'assignedAgentEmail': null,
            'assignedAt': null,
            'reassignCount': currentCount + 1,
          });
          print('[Chats] Chat ${doc.id} timed out, returned to pending. Reassign count: ${currentCount + 1}');
        }
      }
    } catch (e) {
      print('[Chats] Reassignment check error: $e');
    }
  }

  Future<void> _claimChat(SupportChat chat) async {
    final currentUser = context.read(adminCurrentUserProvider).value;
    if (currentUser == null) return;

    final agentName = (currentUser.displayName?.isNotEmpty == true)
        ? currentUser.displayName!
        : currentUser.email?.split('@').first ?? 'Agent';

    final firestore = context.read(firestoreProvider);
    await firestore.collection('support_chats').doc(chat.id).update({
      'status': 'assigned',
      'assignedAgentId': currentUser.uid,
      'assignedAgentName': agentName,
      'assignedAgentEmail': currentUser.email,
      'assignedAt': DateTime.now().millisecondsSinceEpoch,
    });
    context.read(activeChatRoomIdProvider.notifier).state = chat.id;
  }

  Future<void> _forceReassign(SupportChat chat) async {
    final firestore = context.read(firestoreProvider);
    await firestore.collection('support_chats').doc(chat.id).update({
      'status': 'pending',
      'assignedAgentId': null,
      'assignedAgentName': null,
      'assignedAgentEmail': null,
      'assignedAt': null,
      'reassignCount': chat.reassignCount + 1,
    });
  }

  Future<void> _resolveChat(SupportChat chat) async {
    final firestore = context.read(firestoreProvider);
    await firestore.collection('support_chats').doc(chat.id).update({
      'status': 'resolved',
      'resolvedAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (context.read(activeChatRoomIdProvider) == chat.id) {
      context.read(activeChatRoomIdProvider.notifier).state = null;
    }
  }

  String _formatWaiting(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s waiting';
    if (d.inMinutes < 60) return '${d.inMinutes}m waiting';
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m waiting';
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '';
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal().toString().substring(11, 16);
  }

  @override
  Component build(BuildContext context) {
    final chatsAsync = context.watch(supportChatsStreamProvider);
    final users = context.watch(chatUsersStreamProvider).value ?? [];
    final activeChatId = context.watch(activeChatRoomIdProvider);
    final messagesAsync = context.watch(activeChatMessagesStreamProvider);
    final replyText = context.watch(chatReplyTextProvider);
    final currentUser = context.watch(adminCurrentUserProvider).value;
    final currentUserEmail = currentUser?.email ?? '';
    final isAdmin = currentUserEmail.toLowerCase().contains('admin') || currentUserEmail == 'sarah.johnson@tranyx.com';
    final currentUserId = currentUser?.uid ?? '';

    // Detect new pending chats and surface alerts
    final allChats = chatsAsync.value ?? [];
    final pendingNow = allChats.where((c) => c.isPending).map((c) => c.id).toSet();
    final seenIds = context.read(_seenPendingIdsProvider);
    final freshAlerts = pendingNow.difference(seenIds).toList();
    if (freshAlerts.isNotEmpty) {
      Future.microtask(() {
        context.read(_seenPendingIdsProvider.notifier).state = {...seenIds, ...freshAlerts};
        final existing = context.read(newChatAlertProvider);
        context.read(newChatAlertProvider.notifier).state = [...existing, ...freshAlerts];
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted) context.read(newChatAlertProvider.notifier).state = [];
        });
      });
    }
    final alerts = context.watch(newChatAlertProvider);

    String getCustomerName(List<String> uIds) {
      for (final id in uIds) {
        final match = users.firstWhere((u) => u.uid == id, orElse: () => UserProfileModel(uid: '', name: '', email: ''));
        if (match.uid.isNotEmpty && (match.role == null || match.role == 'user')) return match.name;
      }
      return uIds.isNotEmpty ? '${uIds.first.substring(0, min(6, uIds.first.length))}...' : 'Unknown';
    }

    Component buildStatusBadge(SupportChat chat) {
      if (chat.isPending) {
        return span(classes: 'px-2 py-0.5 text-[9px] font-extrabold uppercase tracking-wider rounded-full bg-amber-100 text-amber-700 border border-amber-200', [text('Pending')]);
      }
      if (chat.isAssigned) {
        return span(classes: 'px-2 py-0.5 text-[9px] font-extrabold uppercase tracking-wider rounded-full bg-blue-100 text-blue-700 border border-blue-200', [text('Assigned')]);
      }
      if (chat.isActive) {
        return span(classes: 'px-2 py-0.5 text-[9px] font-extrabold uppercase tracking-wider rounded-full bg-[#e6f7ef] text-[#0fa958] border border-[#b7e6d0]', [text('Active')]);
      }
      return span(classes: 'px-2 py-0.5 text-[9px] font-extrabold uppercase tracking-wider rounded-full bg-zinc-100 text-zinc-500 border border-zinc-200', [text('Resolved')]);
    }

    Component buildChatItem(SupportChat chat) {
      final isSelected = activeChatId == chat.id;
      final isMyChat = chat.assignedAgentId == currentUserId;
      final waiting = _formatWaiting(chat.waitingTime);
      final isHighPriority = chat.waitingTime.inMinutes >= 5 || chat.reassignCount >= 2;

      return button(
        onClick: () {
          context.read(activeChatRoomIdProvider.notifier).state = chat.id;
        },
        classes: 'w-full text-left p-3.5 rounded-xl border text-xs transition-all flex flex-col gap-1.5 '
            '${isSelected ? 'bg-zinc-150 border-zinc-300 shadow-sm' : 'bg-zinc-50/50 border-transparent hover:bg-zinc-100/50'}'
            '${isHighPriority && !isSelected ? ' border-amber-200/80 bg-amber-50/50' : ''}',
        [
          div(classes: 'flex justify-between items-start gap-1', [
            span(classes: 'font-bold text-zinc-800 truncate flex-1', [text(getCustomerName(chat.userIds))]),
            buildStatusBadge(chat),
          ]),
          div(classes: 'flex items-center justify-between gap-1', [
            p(classes: 'text-[10px] text-zinc-500 truncate flex-1', [text(chat.lastMessage)]),
            span(classes: 'text-[9px] text-zinc-400 flex-shrink-0', [text(_formatTime(chat.updatedAt))]),
          ]),
          // Waiting + agent info row
          div(classes: 'flex items-center justify-between mt-0.5', [
            span(classes: 'text-[9px] font-bold '
                '${isHighPriority ? "text-amber-600" : "text-zinc-400"}', [
              text(isHighPriority ? '⚠ $waiting' : waiting)
            ]),
            if (chat.assignedAgentName != null)
              span(classes: 'text-[9px] text-zinc-400 font-semibold truncate max-w-[100px]', [
                text('→ ${chat.assignedAgentName!}')
              ])
            else if (chat.reassignCount > 0)
              span(classes: 'text-[9px] text-rose-500 font-bold', [
                text('↺ ${chat.reassignCount}× reassigned')
              ])
          ]),
        ],
      );
    }

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-4 max-w-7xl mx-auto w-full h-[calc(100vh-80px)] bg-[#eff2f0]', [

      // Header
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [text('Live Customer Service')]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            text('Manage support chats, agent assignments, and escalations.')
          ]),
        ]),
        // Summary badges
        chatsAsync.when(
          data: (chats) {
            final pending = chats.where((c) => c.isPending).length;
            final assigned = chats.where((c) => c.isAssigned).length;
            final active = chats.where((c) => c.isActive).length;
            return div(classes: 'flex items-center gap-2', [
              if (pending > 0)
                div(classes: 'flex items-center gap-1.5 px-3 py-1.5 bg-amber-100 border border-amber-200 rounded-full text-[10px] font-extrabold text-amber-700', [
                  span(classes: 'w-1.5 h-1.5 rounded-full bg-amber-500 animate-pulse', []),
                  text('$pending Pending')
                ]),
              if (assigned > 0)
                div(classes: 'flex items-center gap-1.5 px-3 py-1.5 bg-blue-100 border border-blue-200 rounded-full text-[10px] font-extrabold text-blue-700', [
                  text('$assigned Assigned')
                ]),
              if (active > 0)
                div(classes: 'flex items-center gap-1.5 px-3 py-1.5 bg-[#e6f7ef] border border-[#b7e6d0] rounded-full text-[10px] font-extrabold text-[#0fa958]', [
                  text('$active Active')
                ]),
            ]);
          },
          loading: () => div(classes: '', []),
          error: (_, __) => div(classes: '', []),
        ),
      ]),

      // New request alert banner
      if (alerts.isNotEmpty)
        div(classes: 'w-full p-3 bg-amber-50 border border-amber-300 rounded-2xl flex items-center gap-3 animate-pulse shadow-sm', [
          span(classes: 'text-xl flex-shrink-0', [text('🔔')]),
          div(classes: 'flex flex-col gap-0.5 flex-1', [
            span(classes: 'text-xs font-extrabold text-amber-800', [text('New support request${alerts.length > 1 ? "s" : ""} incoming!')]),
            span(classes: 'text-[10px] text-amber-700 font-medium', [
              text('${alerts.length} customer${alerts.length > 1 ? "s" : ""} waiting for an agent. Claim a chat to assist.')
            ]),
          ]),
          button(
            onClick: () => context.read(newChatAlertProvider.notifier).state = [],
            classes: 'text-amber-500 hover:text-amber-800 font-bold text-xs px-2 py-1 rounded-lg hover:bg-amber-100 transition-colors flex-shrink-0',
            [text('Dismiss')]
          )
        ]),

      // Main chat layout
      div(classes: 'flex-grow flex gap-5 overflow-hidden min-h-0', [

        // Left: Chat Room List
        div(classes: 'w-80 flex flex-col gap-2 bg-white border border-zinc-200/50 rounded-[24px] p-4 overflow-y-auto no-scrollbar shadow-[0_8px_30px_rgba(0,0,0,0.01)]', [
          span(classes: 'text-[9px] font-bold text-zinc-400 uppercase tracking-wider px-2 mb-1', [text('Support Queue')]),
          chatsAsync.when(
            data: (chats) {
              if (chats.isEmpty) {
                return div(classes: 'text-center p-8 text-xs text-zinc-450', [text('No support chats found.')]);
              }
              // Sort: pending first, then by priority (reassign count + wait time), then updated desc
              final sorted = [...chats];
              sorted.sort((a, b) {
                // Resolved go last
                if (a.isResolved && !b.isResolved) return 1;
                if (!a.isResolved && b.isResolved) return -1;
                // Pending goes first
                if (a.isPending && !b.isPending) return -1;
                if (!a.isPending && b.isPending) return 1;
                // Higher reassign count (escalated) goes higher
                final rDiff = b.reassignCount.compareTo(a.reassignCount);
                if (rDiff != 0) return rDiff;
                // Older wait time goes first
                return a.requestedAt.compareTo(b.requestedAt);
              });
              return .fragment([for (final chat in sorted) buildChatItem(chat)]);
            },
            loading: () => div(classes: 'flex justify-center items-center py-10', [
              div(classes: 'animate-spin h-5 w-5 border-2 border-zinc-200 border-t-indigo-500 rounded-full', [])
            ]),
            error: (err, _) => text('Error: $err'),
          ),
        ]),

        // Right: Chat Pane
        div(classes: 'flex-1 bg-white border border-zinc-200/50 rounded-[28px] overflow-hidden flex flex-col shadow-[0_8px_30px_rgba(0,0,0,0.015)]', [
          if (activeChatId == null)
            div(classes: 'flex-grow flex flex-col items-center justify-center text-center p-8 text-zinc-450', [
              span(classes: 'text-3xl mb-2', [text('💬')]),
              h3(classes: 'text-sm font-bold text-zinc-850', [text('Select a chat')]),
              p(classes: 'text-xs text-zinc-500 mt-1', [text('Choose a support request from the queue to view the conversation.')]),
            ])
          else
            // Find the selected chat
            ...() {
              final chat = (chatsAsync.value ?? []).where((c) => c.id == activeChatId).firstOrNull;
              if (chat == null) return [div(classes: 'flex-grow flex items-center justify-center', [text('Loading...')])];

              final isMyChat = chat.assignedAgentId == currentUserId;
              final canReply = !isAdmin && (chat.assignedAgentId == null || isMyChat);

              return [
                // Chat header with agent assignment info
                div(classes: 'bg-[#f8faf9] px-5 py-3.5 border-b border-zinc-100 flex justify-between items-center gap-3', [
                  div(classes: 'flex flex-col gap-0.5 min-w-0', [
                    div(classes: 'flex items-center gap-2', [
                      span(classes: 'w-2 h-2 rounded-full ${chat.isPending ? "bg-amber-500" : chat.isResolved ? "bg-zinc-400" : "bg-[#0fa958]"} ${chat.isPending ? "animate-pulse" : ""}', []),
                      span(classes: 'text-xs font-black text-zinc-800 truncate', [
                        text(getCustomerName(chat.userIds))
                      ]),
                    ]),
                    if (chat.assignedAgentName != null)
                      span(classes: 'text-[10px] text-zinc-400 font-medium truncate', [
                        text('Agent: ${chat.assignedAgentName!}${chat.assignedAgentEmail != null ? " (${chat.assignedAgentEmail})" : ""}')
                      ])
                    else
                      span(classes: 'text-[10px] text-amber-600 font-bold', [text('Unassigned — waiting for agent')])
                  ]),
                  div(classes: 'flex items-center gap-2 flex-shrink-0', [
                    // Waiting time chip
                    span(classes: 'text-[9px] px-2 py-1 rounded-full font-extrabold uppercase tracking-wide '
                        '${chat.waitingTime.inMinutes >= 5 ? "bg-amber-100 text-amber-700" : "bg-zinc-100 text-zinc-500"}', [
                      text(_formatWaiting(chat.waitingTime))
                    ]),
                    if (chat.reassignCount > 0)
                      span(classes: 'text-[9px] px-2 py-1 rounded-full font-extrabold bg-rose-100 text-rose-600', [
                        text('↺ ${chat.reassignCount}× reassigned')
                      ]),
                    // Claim button (for non-admin agents when chat is pending or timed out)
                    if (!isAdmin && !chat.isResolved && !isMyChat)
                      button(
                        onClick: () => _claimChat(chat),
                        classes: 'px-3 py-1.5 bg-black hover:bg-zinc-800 text-white text-[10px] font-extrabold rounded-lg transition-colors',
                        [text(chat.isPending ? 'Claim Chat' : 'Take Over')]
                      ),
                    // Force reassign (admin only)
                    if (isAdmin && !chat.isPending && !chat.isResolved)
                      button(
                        onClick: () => _forceReassign(chat),
                        classes: 'px-3 py-1.5 bg-zinc-100 hover:bg-amber-100 hover:text-amber-800 text-zinc-600 text-[10px] font-extrabold rounded-lg transition-colors border border-zinc-200',
                        [text('Force Reassign')]
                      ),
                    // Resolve button
                    if (!chat.isResolved && (isAdmin || isMyChat))
                      button(
                        onClick: () => _resolveChat(chat),
                        classes: 'px-3 py-1.5 bg-[#0fa958]/10 hover:bg-[#0fa958]/20 text-[#0fa958] text-[10px] font-extrabold rounded-lg transition-colors border border-[#0fa958]/20',
                        [text('Resolve')]
                      ),
                  ])
                ]),

                // Messages area
                div(classes: 'flex-grow p-5 flex flex-col gap-4 overflow-y-auto no-scrollbar bg-[#fafbfa]', [
                  messagesAsync.when(
                    data: (chatMessages) {
                      if (chatMessages.isEmpty) {
                        return div(classes: 'text-center p-8 text-xs text-zinc-500', [text('No messages yet. Waiting for conversation to begin.')]);
                      }
                      return .fragment([
                        for (final msg in chatMessages)
                          div(classes: 'flex flex-col max-w-[80%] '
                              '${msg.isStaff ? 'self-end items-end' : 'self-start items-start'}', [
                            div(classes: 'px-4 py-2.5 rounded-2xl text-xs '
                                '${msg.isStaff
                                    ? 'bg-black text-white rounded-tr-none shadow-md shadow-black/5'
                                    : 'bg-white border border-zinc-200 text-zinc-800 rounded-tl-none'}', [
                              text(msg.content)
                            ]),
                            span(classes: 'text-[8px] text-zinc-400 mt-1 px-1 font-bold', [
                              text(msg.isStaff
                                  ? '${msg.senderName.toUpperCase()}${msg.agentEmail != null ? " (${msg.agentEmail})" : ""} • ${msg.createdAt > 0 ? _formatTime(msg.createdAt) : ""}'
                                  : '${msg.senderName.toUpperCase()} • ${msg.createdAt > 0 ? _formatTime(msg.createdAt) : ""}')
                            ]),
                          ])
                      ]);
                    },
                    loading: () => div(classes: 'flex justify-center items-center py-10', [
                      div(classes: 'animate-spin h-5 w-5 border-2 border-zinc-200 border-t-indigo-500 rounded-full', [])
                    ]),
                    error: (err, _) => text('Error: $err'),
                  )
                ]),

                // Reply box — read-only for admin, locked for unassigned agent, active for assigned agent
                if (chat.isResolved)
                  div(classes: 'p-4 bg-zinc-50 border-t border-zinc-100 text-center text-xs text-zinc-400 font-bold', [
                    text('✅ This conversation has been resolved.')
                  ])
                else if (isAdmin)
                  div(classes: 'p-4 bg-zinc-50 border-t border-zinc-100 text-center text-xs text-zinc-500 font-bold flex items-center justify-center gap-2', [
                    span(classes: 'text-sm', [text('🔒')]),
                    text('Read-Only Mode: Only assigned support agents can send messages.')
                  ])
                else if (!canReply && chat.assignedAgentId != null)
                  div(classes: 'p-4 bg-zinc-50 border-t border-zinc-100 flex items-center justify-center gap-3', [
                    span(classes: 'text-[10px] text-zinc-400 font-semibold', [
                      text('Assigned to ${chat.assignedAgentName ?? "another agent"}. '),
                    ]),
                    button(
                      onClick: () => _claimChat(chat),
                      classes: 'px-3 py-1.5 bg-zinc-900 hover:bg-black text-white text-[10px] font-extrabold rounded-lg transition-colors',
                      [text('Take Over Chat')]
                    ),
                  ])
                else if (chat.isPending && !isAdmin)
                  div(classes: 'p-4 bg-amber-50 border-t border-amber-200 flex items-center justify-center gap-3', [
                    span(classes: 'text-[10px] text-amber-700 font-bold', [text('Claim this chat to start messaging.')]),
                    button(
                      onClick: () => _claimChat(chat),
                      classes: 'px-3 py-1.5 bg-black hover:bg-zinc-800 text-white text-[10px] font-extrabold rounded-lg transition-colors shadow-sm',
                      [text('Claim & Start')]
                    ),
                  ])
                else
                  div(classes: 'p-3 bg-white border-t border-zinc-100 flex gap-2', [
                    input(
                      value: replyText,
                      onInput: (v) => context.read(chatReplyTextProvider.notifier).state = v as String,
                      classes: 'flex-1 bg-[#f3f6f4] border border-zinc-200 rounded-lg px-4 py-2.5 text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black',
                      attributes: {'placeholder': 'Type support response...'},
                    ),
                    button(
                      onClick: () async {
                        final textVal = context.read(chatReplyTextProvider).trim();
                        if (textVal.isEmpty) return;

                        final firestore = context.read(firestoreProvider);
                        final u = context.read(adminCurrentUserProvider).value;
                        final senderName = (u?.displayName?.isNotEmpty == true)
                            ? u!.displayName!
                            : (u?.email != null ? u!.email!.split('@').first : 'Support Agent');

                        await firestore
                            .collection('support_chats')
                            .doc(activeChatId!)
                            .collection('messages')
                            .add({
                          'senderId': u?.uid ?? 'agent',
                          'senderName': senderName,
                          'content': textVal,
                          'createdAt': DateTime.now().millisecondsSinceEpoch,
                          'isStaff': true,
                          'agentEmail': u?.email,
                        });

                        await firestore
                            .collection('support_chats')
                            .doc(activeChatId!)
                            .set({
                          'lastMessage': textVal,
                          'updatedAt': DateTime.now().millisecondsSinceEpoch,
                          'status': 'active',
                          'lastSenderName': senderName,
                        }, SetOptions(merge: true));

                        context.read(chatReplyTextProvider.notifier).state = '';
                      },
                      classes: 'px-5 py-2.5 bg-black hover:bg-zinc-800 text-white text-xs font-bold rounded-lg transition-colors shadow-sm',
                      [text('Send')]
                    )
                  ])
              ];
            }(),
        ]),
      ]),
    ]);
  }
}
