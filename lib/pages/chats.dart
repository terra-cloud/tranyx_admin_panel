import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:riverpod/legacy.dart';

import '../app.dart';
import '../core/providers/environment_provider.dart';
import '../core/services/presence_service.dart';
import '../core/services/request_lock_service.dart';

// ── Constants ──────────────────────────────────────────────────
/// Seconds before an assigned-but-silent chat is returned to pending
const _kReassignTimeoutSec = 180;

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
  final int? claimDeadline;
  final List<String> rejectedBy;
  final int reassignCount;
  final String? userName;
  final String? userEmail;

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
    this.claimDeadline,
    this.rejectedBy = const [],
    required this.reassignCount,
    this.userName,
    this.userEmail,
  });

  bool get isPending {
    final s = status.toLowerCase().trim();
    return s == 'pending' || s == 'open' || s == 'waiting' || s == 'requested' || s == 'new' || s == 'unassigned' || s.isEmpty;
  }
  bool get isAssigned => status.toLowerCase().trim() == 'assigned';
  bool get isActive => status.toLowerCase().trim() == 'active' || status.toLowerCase().trim() == 'in_progress';
  bool get isResolved => status.toLowerCase().trim() == 'resolved' || status.toLowerCase().trim() == 'closed';

  /// True if assigned but claim window expired
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

    final rawRejected = map['rejectedBy'];
    final List<String> rejected = [];
    if (rawRejected is List) {
      for (final item in rawRejected) {
        if (item != null) rejected.add(item.toString());
      }
    }

    final reqAt = parseTs(map['requestedAt'] ?? map['createdAt'] ?? map['timestamp'] ?? map['submittedAt'] ?? map['updatedAt']);
    final upAt = parseTs(map['updatedAt'] ?? map['lastMessageAt'] ?? map['lastUpdated'] ?? reqAt);

    return SupportChat(
      id: id,
      lastMessage: map['lastMessage'] ?? map['message'] ?? map['content'] ?? 'New Support Request',
      updatedAt: upAt,
      requestedAt: reqAt,
      userIds: List<String>.from(map['userIds'] ?? (map['userId'] != null ? [map['userId']] : (map['uid'] != null ? [map['uid']] : []))),
      status: (map['status'] ?? 'pending').toString(),
      assignedAgentId: map['assignedAgentId'] ?? map['assignedTo'] ?? map['agentId'] ?? map['agentUid'],
      assignedAgentName: map['assignedAgentName'] ?? map['assignedToName'] ?? map['agentName'],
      assignedAgentEmail: map['assignedAgentEmail'] ?? map['assignedToEmail'] ?? map['agentEmail'],
      assignedAt: map['assignedAt'] != null ? parseTs(map['assignedAt']) : null,
      claimDeadline: map['claimDeadline'] != null ? parseTs(map['claimDeadline']) : null,
      rejectedBy: rejected,
      reassignCount: map['reassignCount'] ?? 0,
      userName: map['userName'] ?? map['customerName'] ?? map['name'] ?? map['userAccountName'],
      userEmail: map['userEmail'] ?? map['customerEmail'] ?? map['email'],
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
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(<UserProfileModel>[]);
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('users')
      .snapshots()
      .map(
        (snap) => snap.docs.map((doc) => UserProfileModel.fromMap(doc.id, doc.data())).where((userProfile) {
          final r = (userProfile.role ?? '').toLowerCase().trim();
          return r.isNotEmpty && r != 'admin' && r != 'user';
        }).toList(),
      )
      .handleError((_) => <UserProfileModel>[]);
});

final supportChatsStreamProvider = StreamProvider<List<SupportChat>>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(<SupportChat>[]);
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('support_chats')
      .snapshots()
      .map((snap) {
        final list = snap.docs.map((doc) => SupportChat.fromMap(doc.id, doc.data())).toList();
        list.sort((chatA, chatB) {
          final timeA = chatA.updatedAt > 0 ? chatA.updatedAt : chatA.requestedAt;
          final timeB = chatB.updatedAt > 0 ? chatB.updatedAt : chatB.requestedAt;
          return timeB.compareTo(timeA);
        });
        return list;
      })
      .handleError((err) {
        print('[Chats] Support chats stream error: $err');
        return <SupportChat>[];
      });
});

final activeChatRoomIdProvider = StateProvider<String?>((ref) => null);

final activeChatMessagesStreamProvider = StreamProvider<List<ChatMessage>>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(<ChatMessage>[]);
  }
  final firestore = ref.watch(firestoreProvider);
  final activeChatId = ref.watch(activeChatRoomIdProvider);
  if (activeChatId == null) return const Stream.empty();
  return firestore
      .collection('support_chats')
      .doc(activeChatId)
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
final newChatAlertProvider = StateProvider<List<String>>((ref) => []);

// ── Page ───────────────────────────────────────────────────────
class ChatsPage extends StatefulComponent {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  Timer? _reassignTimer;
  Timer? _heartbeatTimer;
  String? _chatActionFeedback;
  bool _chatFeedbackIsError = false;

  @override
  void initState() {
    super.initState();
    // Poll every 15s for timed-out chats and trigger reassignment
    _reassignTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkReassignments());
    // Heartbeat for active chat session every 25s
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) => _sendChatHeartbeat());
  }

  @override
  void dispose() {
    _reassignTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  void _showChatFeedback(String message, {bool isError = false}) {
    setState(() {
      _chatActionFeedback = message;
      _chatFeedbackIsError = isError;
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _chatActionFeedback = null);
      }
    });
  }

  Future<void> _sendChatHeartbeat() async {
    final activeId = context.read(activeChatRoomIdProvider);
    final currentUser = context.read(adminCurrentUserProvider).value;
    if (activeId == null || currentUser == null) return;

    try {
      final firestore = context.read(firestoreProvider);
      await RequestLockService.sendHeartbeat(
        firestore: firestore,
        collectionName: 'support_chats',
        requestId: activeId,
        currentAgentUid: currentUser.uid,
      );
    } catch (_) {}
  }

  Future<void> _checkReassignments() async {
    try {
      final firestore = context.read(firestoreProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      final configDoc = await firestore.collection('system_config').doc('settings').get();
      final timeoutSec = (configDoc.data()?['claimTimeoutSeconds'] as num?)?.toInt() ?? _kReassignTimeoutSec;
      final cutoff = now - (timeoutSec * 1000);

      final snap = await firestore.collection('support_chats').where('status', isEqualTo: 'assigned').get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final assignedAt = data['assignedAt'];
        int assignedAtMs = 0;
        if (assignedAt is num) assignedAtMs = assignedAt.toInt();
        if (assignedAt is Timestamp) assignedAtMs = assignedAt.millisecondsSinceEpoch;

        // If assigned but claim deadline passed, return to pending
        if (assignedAtMs > 0 && assignedAtMs < cutoff) {
          final currentCount = (data['reassignCount'] ?? 0) as int;
          final assignedAgentId = data['assignedAgentId'] ?? data['assignedTo'];
          await doc.reference.set({
            'status': 'pending',
            'assignedAgentId': null,
            'assignedAgentName': null,
            'assignedAgentEmail': null,
            'assignedTo': null,
            'assignedAt': null,
            'claimDeadline': null,
            'reassignCount': currentCount + 1,
            if (assignedAgentId != null) 'rejectedBy': FieldValue.arrayUnion([assignedAgentId]),
            'updatedAt': now,
          }, SetOptions(merge: true));
          print('[Chats] Chat ${doc.id} timed out, returned to pending.');
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

    final currentUserEmail = currentUser.email ?? '';
    final isAdmin = currentUserEmail.toLowerCase().contains('admin') || currentUserEmail == 'sarah.johnson@tranyx.com';

    try {
      final firestore = context.read(firestoreProvider);
      await RequestLockService.acceptOrPassRequest(
        firestore: firestore,
        collectionName: 'support_chats',
        requestId: chat.id,
        currentAgentUid: currentUser.uid,
        currentAgentName: agentName,
        currentAgentEmail: currentUser.email,
        isAdmin: isAdmin,
      );

      context.read(activeChatRoomIdProvider.notifier).state = chat.id;
      _showChatFeedback('Live chat claimed successfully. Active working session started.');
    } catch (e) {
      _showChatFeedback(e.toString().replaceAll('Exception:', '').trim(), isError: true);
    }
  }

  Future<void> _rejectOrPassChat(SupportChat chat) async {
    final currentUser = context.read(adminCurrentUserProvider).value;
    if (currentUser == null) return;

    try {
      final firestore = context.read(firestoreProvider);
      await RequestLockService.rejectOrPassRequest(
        firestore: firestore,
        collectionName: 'support_chats',
        requestId: chat.id,
        currentAgentUid: currentUser.uid,
      );
      if (context.read(activeChatRoomIdProvider) == chat.id) {
        context.read(activeChatRoomIdProvider.notifier).state = null;
      }
      _showChatFeedback('Chat passed to next available agent.');
    } catch (e) {
      _showChatFeedback(e.toString().replaceAll('Exception:', '').trim(), isError: true);
    }
  }

  Future<void> _forceReassign(SupportChat chat) async {
    final firestore = context.read(firestoreProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    await firestore.collection('support_chats').doc(chat.id).set({
      'status': 'pending',
      'assignedAgentId': null,
      'assignedAgentName': null,
      'assignedAgentEmail': null,
      'assignedTo': null,
      'assignedAt': null,
      'claimDeadline': null,
      'reassignCount': chat.reassignCount + 1,
      'updatedAt': now,
    }, SetOptions(merge: true));
    _showChatFeedback('Chat returned to general pending queue.');
  }

  Future<void> _resolveChat(SupportChat chat) async {
    final firestore = context.read(firestoreProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    await firestore.collection('support_chats').doc(chat.id).set({
      'status': 'resolved',
      'resolvedAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));
    if (context.read(activeChatRoomIdProvider) == chat.id) {
      context.read(activeChatRoomIdProvider.notifier).state = null;
    }
    _showChatFeedback('Support chat resolved successfully.');
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
    final onlineAgents = context.watch(onlineAgentsStreamProvider).value ?? [];
    final systemConfig = context.watch(systemConfigStreamProvider).value ?? const SystemConfigModel();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final userEmail = currentUser?.email ?? '';
    final isAdmin = userEmail.toLowerCase().contains('admin') || userEmail == 'sarah.johnson@tranyx.com';
    final currentUserId = currentUser?.uid ?? '';

    // Helper to resolve customer name
    String getCustomerName(List<String> userIds) {
      for (final uid in userIds) {
        final profile = users.where((prof) => prof.uid == uid).firstOrNull;
        if (profile != null && profile.name != 'Unknown User') {
          return profile.name;
        }
      }
      return userIds.isNotEmpty ? 'User ${userIds.first.substring(0, min(6, userIds.first.length))}' : 'Guest User';
    }

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0]', [
      // Top header with status counters
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [Component.text('Live Support Hub')]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text('Real-time single-agent customer chats, active sessions, and queue management.'),
          ]),
        ]),
        chatsAsync.when(
          data: (chats) {
            final pending = chats.where((c) => c.isPending).length;
            final assigned = chats.where((c) => c.isAssigned).length;
            final active = chats.where((c) => c.isActive).length;
            return div(classes: 'flex items-center gap-2 flex-wrap', [
              div(
                classes:
                    'px-3 py-1.5 rounded-xl text-xs font-bold ${pending > 0 ? "bg-amber-50 text-amber-700 border border-amber-200" : "bg-white text-zinc-500 border border-zinc-200/50"}',
                [
                  span(classes: 'w-2 h-2 rounded-full bg-amber-500 inline-block mr-1.5', []),
                  Component.text('$pending Pending'),
                ],
              ),
              div(
                classes:
                    'px-3 py-1.5 rounded-xl text-xs font-bold ${assigned > 0 ? "bg-indigo-50 text-indigo-700 border border-indigo-200" : "bg-white text-zinc-500 border border-zinc-200/50"}',
                [
                  span(classes: 'w-2 h-2 rounded-full bg-indigo-500 inline-block mr-1.5', []),
                  Component.text('$assigned Claiming'),
                ],
              ),
              div(classes: 'px-3 py-1.5 rounded-xl text-xs font-bold bg-emerald-50 text-[#0fa958] border border-emerald-200', [
                span(classes: 'w-2 h-2 rounded-full bg-[#0fa958] inline-block mr-1.5', []),
                Component.text('$active Active'),
              ]),
            ]);
          },
          loading: () => div(classes: 'text-xs text-zinc-400', [Component.text('Loading metrics...')]),
          error: (e, _) => div(classes: 'text-xs text-rose-500', [Component.text('Error')]),
        ),
      ]),

      // Feedback banner
      if (_chatActionFeedback != null)
        div(
          classes:
              'p-4 rounded-2xl border flex items-center justify-between gap-3 animate-fade-in '
              '${_chatFeedbackIsError ? "bg-rose-50 border-rose-200 text-rose-800" : "bg-emerald-50 border-emerald-200 text-emerald-800"}',
          [
            div(classes: 'flex items-center gap-2 text-xs font-bold', [
              span(classes: 'text-sm', [Component.text(_chatFeedbackIsError ? '⚠️' : '✅')]),
              Component.text(_chatActionFeedback!),
            ]),
            button(
              onClick: () => setState(() => _chatActionFeedback = null),
              classes: 'text-xs text-zinc-400 hover:text-zinc-700 font-bold bg-transparent border-0 cursor-pointer p-1',
              [Component.text('✕')],
            ),
          ],
        ),

      // Main chat split layout
      div(classes: 'grid grid-cols-1 lg:grid-cols-3 gap-6 flex-grow', [
        // Left Column: Chat Room List
        div(
          classes:
              'lg:col-span-1 rounded-[28px] border border-zinc-200/50 bg-white shadow-[0_8px_30px_rgba(0,0,0,0.015)] flex flex-col overflow-hidden h-[640px]',
          [
            div(classes: 'p-4 border-b border-zinc-100 flex items-center justify-between', [
              span(classes: 'text-xs font-black text-zinc-800', [Component.text('Conversations')]),
              span(classes: 'text-[10px] text-zinc-400 font-bold', [
                Component.text('${(chatsAsync.value ?? []).where((c) => !c.isResolved).length} open'),
              ]),
            ]),

            div(classes: 'flex-grow overflow-y-auto no-scrollbar flex flex-col divide-y divide-zinc-50', [
              chatsAsync.when(
                data: (chats) {
                  if (chats.isEmpty) {
                    return div(classes: 'p-8 text-center text-xs text-zinc-400', [
                      Component.text('No support chats found.'),
                    ]);
                  }

                  final sorted = [...chats];
                  sorted.sort((chatA, chatB) {
                    if (chatA.isPending && !chatB.isPending) return -1;
                    if (!chatA.isPending && chatB.isPending) return 1;
                    return chatB.updatedAt.compareTo(chatA.updatedAt);
                  });

                  return .fragment([
                    for (final chat in sorted)
                      () {
                        final isSelected = chat.id == activeChatId;
                        final isMyChat = chat.assignedAgentId == currentUserId;
                        final isExpired = chat.isClaimExpired(nowMs, systemConfig.claimTimeoutSeconds);
                        final assignedAgent = onlineAgents.where((ag) => ag.uid == chat.assignedAgentId).firstOrNull;
                        final agentOnline = assignedAgent != null || isMyChat;

                        return button(
                          onClick: () => context.read(activeChatRoomIdProvider.notifier).state = chat.id,
                          classes:
                              'p-4 text-left transition-all flex flex-col gap-1.5 cursor-pointer '
                              '${isSelected ? "bg-[#eff2f0]" : "hover:bg-[#fcfdfc]"} '
                              '${chat.isPending ? "border-l-4 border-l-amber-500" : (chat.isAssigned ? "border-l-4 border-l-indigo-500" : "")}',
                          [
                            div(classes: 'flex justify-between items-center gap-2', [
                              div(classes: 'flex items-center gap-1.5 min-w-0', [
                                span(
                                  classes:
                                      'w-2 h-2 rounded-full ${chat.isPending ? "bg-amber-500 animate-pulse" : (chat.isResolved ? "bg-zinc-300" : "bg-[#0fa958]")}',
                                  [],
                                ),
                                span(classes: 'text-xs font-black text-zinc-900 truncate', [
                                  Component.text(getCustomerName(chat.userIds)),
                                ]),
                              ]),
                              span(classes: 'text-[9px] text-zinc-400 font-bold', [
                                Component.text(_formatTime(chat.updatedAt)),
                              ]),
                            ]),

                            p(classes: 'text-[11px] text-zinc-500 font-medium truncate', [
                              Component.text(chat.lastMessage),
                            ]),

                            div(classes: 'flex justify-between items-center gap-2 mt-0.5', [
                              span(
                                classes:
                                    'text-[9px] font-extrabold uppercase px-2 py-0.5 rounded-full '
                                    '${chat.isPending ? "bg-amber-50 text-amber-700 border border-amber-200" : (chat.isAssigned ? "bg-indigo-50 text-indigo-700 border border-indigo-200" : (chat.isResolved ? "bg-zinc-100 text-zinc-500" : "bg-emerald-50 text-[#0fa958] border border-emerald-200"))}',
                                [
                                  Component.text(
                                    chat.isPending
                                        ? 'Pending'
                                        : (chat.isAssigned ? (isExpired ? 'Expired' : 'Claiming') : (chat.isResolved ? 'Resolved' : 'Active')),
                                  ),
                                ],
                              ),
                              if (chat.assignedAgentName != null)
                                span(classes: 'text-[10px] text-zinc-500 font-bold flex items-center gap-1', [
                                  span(classes: 'w-1.5 h-1.5 rounded-full ${agentOnline ? "bg-[#0fa958]" : "bg-zinc-300"}', []),
                                  Component.text(isMyChat ? 'You' : chat.assignedAgentName!),
                                ]),
                            ]),
                          ],
                        );
                      }(),
                  ]);
                },
                loading: () => div(classes: 'p-8 text-center text-xs text-zinc-400', [Component.text('Loading chats...')]),
                error: (e, _) => div(classes: 'p-8 text-center text-xs text-rose-500', [Component.text('Error loading')]),
              ),
            ]),
          ],
        ),

        // Right Column: Chat Room Window
        div(
          classes:
              'lg:col-span-2 rounded-[28px] border border-zinc-200/50 bg-white shadow-[0_8px_30px_rgba(0,0,0,0.015)] flex flex-col overflow-hidden h-[640px]',
          [
            if (activeChatId == null)
              div(classes: 'flex-grow flex flex-col items-center justify-center p-8 text-center gap-2', [
                div(classes: 'w-12 h-12 rounded-full bg-zinc-100 flex items-center justify-center text-xl mb-2', [
                  Component.text('💬'),
                ]),
                span(classes: 'text-sm font-black text-zinc-800', [Component.text('Select a Conversation')]),
                span(classes: 'text-xs text-zinc-400 max-w-sm', [
                  Component.text('Choose an active support session from the list on the left to attend to the customer.'),
                ]),
              ])
            else
              ...() {
                final chat = (chatsAsync.value ?? []).where((c) => c.id == activeChatId).firstOrNull;
                if (chat == null) {
                  return [
                    div(classes: 'flex-grow flex items-center justify-center', [Component.text('Loading conversation...')]),
                  ];
                }

                final isMyChat = chat.assignedAgentId == currentUserId;
                final isExpired = chat.isClaimExpired(nowMs, systemConfig.claimTimeoutSeconds);
                final assignedAgent = onlineAgents.where((ag) => ag.uid == chat.assignedAgentId).firstOrNull;
                final agentStatusLabel = assignedAgent != null
                    ? (assignedAgent.status == AgentPresenceState.away ? '🟡 Away' : (assignedAgent.status == AgentPresenceState.busy ? '🔵 Busy' : '🟢 Online'))
                    : (isMyChat ? '🟢 Online' : '⚪ Offline');
                final canReply = !chat.isResolved && (isAdmin || isMyChat);

                return [
                  // Top Conversation Header
                  div(
                    classes:
                        'bg-[#f8faf9] px-6 py-4 border-b border-zinc-200/60 flex flex-col md:flex-row justify-between items-start md:items-center gap-3',
                    [
                      div(classes: 'flex flex-col gap-0.5 min-w-0', [
                        div(classes: 'flex items-center gap-2', [
                          span(
                            classes:
                                'w-2 h-2 rounded-full ${chat.isPending ? "bg-amber-500 animate-pulse" : (chat.isResolved ? "bg-zinc-400" : "bg-[#0fa958]")}',
                            [],
                          ),
                          span(classes: 'text-sm font-black text-zinc-900 truncate', [
                            Component.text(getCustomerName(chat.userIds)),
                          ]),
                          span(classes: 'text-[10px] font-mono text-zinc-400 font-bold', [
                            Component.text('ID: #${chat.id.substring(0, min(8, chat.id.length))}'),
                          ]),
                        ]),
                        div(classes: 'flex items-center gap-2 text-xs font-semibold', [
                          if (chat.assignedAgentName != null)
                            span(classes: 'text-zinc-600 flex items-center gap-1.5', [
                              Component.text('Handled by ${chat.assignedAgentName!}'),
                              span(classes: 'text-[10px] font-bold text-zinc-400', [Component.text('($agentStatusLabel)')]),
                            ])
                          else
                            span(classes: 'text-amber-600 font-bold', [Component.text('Unassigned — Waiting for Agent')]),
                        ]),
                      ]),

                      div(classes: 'flex items-center gap-2 flex-wrap', [
                        // Pass to Queue button (for assigned agent)
                        if (isMyChat && !chat.isResolved)
                          button(
                            onClick: () => _rejectOrPassChat(chat),
                            classes: 'px-3 py-1.5 bg-red-50 hover:bg-red-100 text-red-600 text-xs font-bold rounded-xl border border-red-200 transition-colors cursor-pointer',
                            [Component.text('Pass to Queue')],
                          ),

                        // Force Reassign button (Admin only)
                        if (isAdmin && !chat.isPending && !chat.isResolved)
                          button(
                            onClick: () => _forceReassign(chat),
                            classes: 'px-3 py-1.5 bg-zinc-100 hover:bg-amber-100 hover:text-amber-800 text-zinc-600 text-xs font-bold rounded-xl transition-colors border border-zinc-200 cursor-pointer',
                            [Component.text('Force Reassign')],
                          ),

                        // Claim button (if not claimed by me)
                        if (!isMyChat && !chat.isResolved)
                          button(
                            onClick: () => _claimChat(chat),
                            classes: 'px-3.5 py-1.5 bg-black hover:bg-zinc-800 text-white text-xs font-black rounded-xl transition-colors shadow-sm cursor-pointer',
                            [Component.text(isExpired ? 'Override Lock' : (chat.isAssigned ? 'Take Over' : 'Claim Chat'))],
                          ),

                        // Resolve button
                        if (!chat.isResolved && (isAdmin || isMyChat))
                          button(
                            onClick: () => _resolveChat(chat),
                            classes: 'px-3.5 py-1.5 bg-emerald-50 hover:bg-emerald-100 text-[#0fa958] text-xs font-extrabold rounded-xl transition-colors border border-emerald-200 cursor-pointer',
                            [Component.text('✓ Resolve')],
                          ),
                      ]),
                    ],
                  ),

                  // Messages Area
                  div(classes: 'flex-grow p-6 flex flex-col gap-4 overflow-y-auto no-scrollbar bg-[#fafbfa]', [
                    messagesAsync.when(
                      data: (chatMessages) {
                        if (chatMessages.isEmpty) {
                          return div(classes: 'text-center p-8 text-xs text-zinc-400', [
                            Component.text('No messages yet. Waiting for customer inquiry.'),
                          ]);
                        }
                        return .fragment([
                          for (final msg in chatMessages)
                            div(
                              classes:
                                  'flex flex-col max-w-[80%] '
                                  '${msg.isStaff ? "self-end items-end" : "self-start items-start"}',
                              [
                                div(classes: 'text-[10px] text-zinc-400 font-bold px-1 mb-1', [
                                  Component.text(msg.senderName),
                                  if (msg.createdAt > 0)
                                    span(classes: 'ml-1.5 font-normal', [
                                      Component.text(_formatTime(msg.createdAt)),
                                    ]),
                                ]),
                                div(
                                  classes:
                                      'p-3.5 rounded-2xl text-xs font-medium leading-relaxed '
                                      '${msg.isStaff ? "bg-black text-white rounded-tr-none shadow-sm" : "bg-white text-zinc-800 border border-zinc-200/80 rounded-tl-none shadow-sm"}',
                                  [Component.text(msg.content)],
                                ),
                              ],
                            ),
                        ]);
                      },
                      loading: () => div(classes: 'text-center p-8 text-xs text-zinc-400', [Component.text('Loading messages...')]),
                      error: (e, _) => div(classes: 'text-center p-8 text-xs text-rose-500', [Component.text('Error: $e')]),
                    ),
                  ]),

                  // Reply Input Area
                  div(classes: 'p-4 border-t border-zinc-100 bg-white flex flex-col gap-2', [
                    if (!canReply)
                      div(classes: 'p-2.5 bg-amber-50 border border-amber-200 rounded-xl text-xs text-amber-800 font-semibold text-center', [
                        Component.text(
                          chat.isResolved
                              ? 'This support chat is resolved and closed.'
                              : 'Chat is locked by ${chat.assignedAgentName ?? "another agent"}. Click "Take Over" to claim.',
                        ),
                      ])
                    else
                      div(classes: 'flex gap-2 items-center', [
                        input(
                          value: replyText,
                          classes:
                              'flex-grow bg-[#eff2f0] border border-zinc-200/60 rounded-xl px-4 py-2.5 text-xs text-zinc-900 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                          attributes: {'type': 'text', 'placeholder': 'Type a reply to the customer...'},
                          onInput: (val) => context.read(chatReplyTextProvider.notifier).state = val as String,
                        ),
                        button(
                          onClick: () async {
                            final text = context.read(chatReplyTextProvider).trim();
                            if (text.isEmpty) return;

                            final agentName = (currentUser?.displayName?.isNotEmpty == true)
                                ? currentUser!.displayName!
                                : currentUser?.email?.split('@').first ?? 'Staff';

                            final firestore = context.read(firestoreProvider);
                            final now = DateTime.now().millisecondsSinceEpoch;

                            await firestore.collection('support_chats').doc(activeChatId).collection('messages').add({
                              'senderId': currentUserId,
                              'senderName': agentName,
                              'content': text,
                              'createdAt': now,
                              'isStaff': true,
                              'agentEmail': currentUser?.email,
                            });

                            await firestore.collection('support_chats').doc(activeChatId).set({
                              'status': 'active',
                              'lastMessage': text,
                              'updatedAt': now,
                              'assignedAgentId': currentUserId,
                              'assignedAgentName': agentName,
                            }, SetOptions(merge: true));

                            context.read(chatReplyTextProvider.notifier).state = '';
                          },
                          classes: 'px-5 py-2.5 bg-black hover:bg-zinc-800 text-white text-xs font-black rounded-xl transition-all shadow-sm cursor-pointer',
                          [Component.text('Send')],
                        ),
                      ]),
                  ]),
                ];
              }(),
          ],
        ),
      ]),
    ]);
  }
}
