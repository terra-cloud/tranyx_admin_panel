import 'dart:async';
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:web/web.dart' as web;

import '../providers/environment_provider.dart';

/// Agent Presence Status
enum AgentPresenceState {
  online,
  busy,
  away,
  offline;

  static AgentPresenceState fromString(String? val) {
    if (val == null) return AgentPresenceState.offline;
    switch (val.toLowerCase()) {
      case 'online':
        return AgentPresenceState.online;
      case 'busy':
        return AgentPresenceState.busy;
      case 'away':
        return AgentPresenceState.away;
      case 'offline':
      default:
        return AgentPresenceState.offline;
    }
  }
}

/// Model representing an Agent's real-time presence data in Firestore `users/{uid}`
class AgentPresenceModel {
  final String uid;
  final String name;
  final String email;
  final String role;
  final bool isOnline;
  final AgentPresenceState status;
  final int lastSeenAt;
  final String? activeRequestId;

  const AgentPresenceModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.isOnline,
    required this.status,
    required this.lastSeenAt,
    this.activeRequestId,
  });

  /// Check if agent is actively online (within threshold seconds of last ping, accounting for clock skew)
  bool isActivelyOnline(int nowMs, {int thresholdSec = 180}) {
    if (!isOnline && status == AgentPresenceState.offline) return false;
    if (lastSeenAt == 0) return isOnline; // Newly connected
    return (nowMs - lastSeenAt).abs() < (thresholdSec * 1000);
  }

  factory AgentPresenceModel.fromMap(String uid, Map<String, dynamic> map) {
    int parseTs(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    final isOnlineVal = map['isOnline'] == true;
    final statusStr = map['presenceStatus'] as String?;
    final lastSeen = parseTs(map['lastSeenAt'] ?? map['lastActiveAt']);

    return AgentPresenceModel(
      uid: uid,
      name: map['name'] ?? map['displayName'] ?? (map['email']?.toString().split('@').first ?? 'Agent'),
      email: map['email'] ?? '',
      role: map['role'] ?? 'staff',
      isOnline: isOnlineVal,
      status: AgentPresenceState.fromString(statusStr ?? (isOnlineVal ? 'online' : 'offline')),
      lastSeenAt: lastSeen,
      activeRequestId: map['activeRequestId'] as String?,
    );
  }
}

/// Stream provider for all online agents & staff
final onlineAgentsStreamProvider = StreamProvider<List<AgentPresenceModel>>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(<AgentPresenceModel>[]);
  }

  final firestore = ref.watch(firestoreProvider);

  return firestore.collection('users').snapshots().map((snap) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final list = <AgentPresenceModel>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final role = (data['role'] as String? ?? '').toLowerCase();
      final email = (data['email'] as String? ?? '').toLowerCase();
      final isOnline = data['isOnline'] == true;
      final isStaff = role == 'staff' || role == 'agent' || role == 'admin' || role == 'superadmin' || email.contains('admin') || email.contains('@tranyx') || isOnline;
      if (isStaff) {
        final agent = AgentPresenceModel.fromMap(doc.id, data);
        if (agent.isActivelyOnline(nowMs, thresholdSec: 180)) {
          list.add(agent);
        }
      }
    }
    return list;
  }).handleError((err) {
    print('[PresenceService] Stream error: $err');
    return <AgentPresenceModel>[];
  });
});

/// Agent Presence Management Service
class PresenceService {
  static Timer? _presenceTimer;
  static String? _currentAgentUid;
  static bool _listenersAttached = false;
  static int _lastActivityPing = 0;

  /// Starts periodic presence heartbeat for currently authenticated staff agent
  static void startPresenceHeartbeat({
    required FirebaseFirestore firestore,
    required String agentUid,
    required String agentName,
    String? email,
    String? role,
  }) {
    if (_currentAgentUid == agentUid && _presenceTimer != null && _presenceTimer!.isActive) {
      return;
    }

    _currentAgentUid = agentUid;

    // Immediately send initial online ping
    _pingPresence(
      firestore: firestore,
      agentUid: agentUid,
      email: email,
      role: role,
      status: AgentPresenceState.online,
    );

    // Cancel existing timer if any
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final isHidden = web.document.visibilityState == 'hidden';
      _pingPresence(
        firestore: firestore,
        agentUid: agentUid,
        email: email,
        role: role,
        status: isHidden ? AgentPresenceState.away : AgentPresenceState.online,
      );
    });

    if (!_listenersAttached) {
      _attachLifecycleListeners(firestore, agentUid, email, role);
      _listenersAttached = true;
    }
  }

  static void _attachLifecycleListeners(
    FirebaseFirestore firestore,
    String agentUid,
    String? email,
    String? role,
  ) {
    // Window beforeunload / page close listener
    web.window.addEventListener(
      'beforeunload',
      ((web.Event e) {
        markOffline(firestore: firestore, agentUid: agentUid);
      }).toJS,
    );

    // Window focus listener
    web.window.addEventListener(
      'focus',
      ((web.Event e) {
        if (_currentAgentUid != null) {
          _pingPresence(
            firestore: firestore,
            agentUid: _currentAgentUid!,
            email: email,
            role: role,
            status: AgentPresenceState.online,
          );
        }
      }).toJS,
    );

    // User activity listener with 5s debounce
    void onUserActivity() {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastActivityPing > 5000 && _currentAgentUid != null) {
        _lastActivityPing = now;
        _pingPresence(
          firestore: firestore,
          agentUid: _currentAgentUid!,
          email: email,
          role: role,
          status: AgentPresenceState.online,
        );
      }
    }

    web.document.addEventListener('click', ((web.Event e) => onUserActivity()).toJS);
    web.document.addEventListener('keydown', ((web.Event e) => onUserActivity()).toJS);

    // Visibility change listener (tab switched / minimized)
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event e) {
        if (_currentAgentUid != null) {
          final isHidden = web.document.visibilityState == 'hidden';
          _pingPresence(
            firestore: firestore,
            agentUid: _currentAgentUid!,
            email: email,
            role: role,
            status: isHidden ? AgentPresenceState.away : AgentPresenceState.online,
          );
        }
      }).toJS,
    );
  }

  static Future<void> _pingPresence({
    required FirebaseFirestore firestore,
    required String agentUid,
    String? email,
    String? role,
    required AgentPresenceState status,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await firestore.collection('users').doc(agentUid).set({
        'isOnline': status != AgentPresenceState.offline,
        'presenceStatus': status.name,
        'lastSeenAt': now,
        'lastActiveAt': now,
        if (email != null && email.isNotEmpty) 'email': email,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Sets custom presence state (e.g. busy when taking a ticket)
  static Future<void> setPresenceState({
    required FirebaseFirestore firestore,
    required String agentUid,
    required AgentPresenceState state,
    String? activeRequestId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await firestore.collection('users').doc(agentUid).set({
        'isOnline': state != AgentPresenceState.offline,
        'presenceStatus': state.name,
        'lastSeenAt': now,
        'lastActiveAt': now,
        'activeRequestId': activeRequestId,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Immediately marks the agent as offline
  static Future<void> markOffline({
    required FirebaseFirestore firestore,
    required String agentUid,
  }) async {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await firestore.collection('users').doc(agentUid).set({
        'isOnline': false,
        'presenceStatus': 'offline',
        'lastSeenAt': now,
        'lastActiveAt': now,
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
