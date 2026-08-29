import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../providers/environment_provider.dart';
import 'presence_service.dart';

/// System Config Settings Model
class SystemConfigModel {
  final int claimTimeoutSeconds; // Default 180s (3 minutes)
  final int heartbeatTimeoutSeconds; // Default 600s (10 minutes)
  final String resendApiKey;
  final String resendFromEmail;

  const SystemConfigModel({
    this.claimTimeoutSeconds = 180,
    this.heartbeatTimeoutSeconds = 600,
    this.resendApiKey = '',
    this.resendFromEmail = '',
  });

  factory SystemConfigModel.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SystemConfigModel();
    return SystemConfigModel(
      claimTimeoutSeconds: (map['claimTimeoutSeconds'] as num?)?.toInt() ?? 180,
      heartbeatTimeoutSeconds: (map['heartbeatTimeoutSeconds'] as num?)?.toInt() ?? 600,
      resendApiKey: (map['resendApiKey'] ?? map['resend_api_key'] ?? '').toString(),
      resendFromEmail: (map['resendFromEmail'] ?? map['senderEmail'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'claimTimeoutSeconds': claimTimeoutSeconds,
    'heartbeatTimeoutSeconds': heartbeatTimeoutSeconds,
    if (resendApiKey.isNotEmpty) 'resendApiKey': resendApiKey,
    if (resendFromEmail.isNotEmpty) 'resendFromEmail': resendFromEmail,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  };
}

/// Stream provider for system configuration
final systemConfigStreamProvider = StreamProvider<SystemConfigModel>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(const SystemConfigModel());
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('system_config')
      .doc('settings')
      .snapshots()
      .map((snap) => SystemConfigModel.fromMap(snap.data()))
      .handleError((e) {
        print('[SystemConfig] Error reading settings: $e');
        return const SystemConfigModel();
      });
});

/// Unified Request Model following System Instruction Protocol
class UnifiedRequestModel {
  final String id;
  final String category; // 'deposit' | 'withdrawal' | 'ticket' | 'bug_report' | 'user_report'
  final String status; // 'PENDING' | 'ASSIGNED' | 'IN_PROGRESS' | 'RESOLVED' | 'CLOSED'
  final String? assignedTo; // Firebase Auth UID
  final String? assignedToName;
  final String? assignedToEmail;
  final int? assignedAt;
  final int? claimDeadline;
  final int? lastHeartbeat;
  final List<String> rejectedBy;
  final String createdBy;
  final String? subject;
  final String? description;
  final double? amount;
  final String? paymentMethod;
  final int createdAt;

  UnifiedRequestModel({
    required this.id,
    required this.category,
    required this.status,
    this.assignedTo,
    this.assignedToName,
    this.assignedToEmail,
    this.assignedAt,
    this.claimDeadline,
    this.lastHeartbeat,
    required this.rejectedBy,
    required this.createdBy,
    this.subject,
    this.description,
    this.amount,
    this.paymentMethod,
    required this.createdAt,
  });

  bool get isPending => status == 'PENDING' || status == 'OPEN' || status == 'Open';
  bool get isAssigned => status == 'ASSIGNED';
  bool get isInProgress => status == 'IN_PROGRESS' || status == 'In Progress';
  bool get isResolved => status == 'RESOLVED' || status == 'Resolved' || status == 'CLOSED';

  /// True if assigned but claim deadline passed (> 3 min)
  bool isClaimExpired(int nowMs) {
    if (!isAssigned) return false;
    if (claimDeadline != null && claimDeadline! > 0) {
      return nowMs > claimDeadline!;
    }
    if (assignedAt != null && assignedAt! > 0) {
      return (nowMs - assignedAt!) > (180 * 1000);
    }
    return false;
  }

  /// True if in progress but heartbeat expired (> 10 min)
  bool isHeartbeatExpired(int nowMs, int heartbeatTimeoutSec) {
    if (!isInProgress) return false;
    if (lastHeartbeat == null || lastHeartbeat! <= 0) return false;
    return (nowMs - lastHeartbeat!) > (heartbeatTimeoutSec * 1000);
  }

  factory UnifiedRequestModel.fromMap(String id, Map<String, dynamic> map) {
    int? parseTs(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val);
      return null;
    }

    final rawRejected = map['rejectedBy'];
    final List<String> rejectedList = [];
    if (rawRejected is List) {
      for (final r in rawRejected) {
        if (r != null) rejectedList.add(r.toString());
      }
    }

    final assignedAtVal = parseTs(map['assignedAt']);
    final claimDeadlineVal = parseTs(map['claimDeadline']) ?? (assignedAtVal != null ? assignedAtVal + (180 * 1000) : null);

    return UnifiedRequestModel(
      id: id,
      category: map['category'] ?? 'ticket',
      status: map['status'] ?? 'PENDING',
      assignedTo: map['assignedTo'] ?? map['assignedAgentId'] ?? map['agentId'],
      assignedToName: map['assignedToName'] ?? map['assignedAgentName'] ?? map['agentName'],
      assignedToEmail: map['assignedToEmail'] ?? map['assignedAgentEmail'] ?? map['agentEmail'],
      assignedAt: assignedAtVal,
      claimDeadline: claimDeadlineVal,
      lastHeartbeat: parseTs(map['lastHeartbeat']),
      rejectedBy: rejectedList,
      createdBy: map['createdBy'] ?? map['uid'] ?? map['userId'] ?? 'unknown',
      subject: map['subject'] ?? map['title'],
      description: map['description'] ?? map['details'] ?? map['message'],
      amount: (map['amount'] as num?)?.toDouble(),
      paymentMethod: map['paymentMethod'] ?? map['category'],
      createdAt: parseTs(map['createdAt']) ?? parseTs(map['submittedAt']) ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Request Lock Service implementing Single-Agent Request Lock, Auto-Dispatcher, & Strict Sequential Failover
class RequestLockService {
  RequestLockService._();

  /// Accepts or claims a request with atomic transaction, enforcing 3-min timeout, presence, and locking rules.
  static Future<void> acceptOrPassRequest({
    required FirebaseFirestore firestore,
    required String collectionName,
    required String requestId,
    required String currentAgentUid,
    required String currentAgentName,
    String? currentAgentEmail,
    bool isAdmin = false,
  }) async {
    final requestRef = firestore.collection(collectionName).doc(requestId);
    final configRef = firestore.collection('system_config').doc('settings');

    final requestDoc = await requestRef.get();
    if (!requestDoc.exists) {
      throw Exception('Request not found.');
    }

    final configDoc = await configRef.get();
    final config = configDoc.data() ?? {};
    final timeoutSec = (config['claimTimeoutSeconds'] as num?)?.toInt() ?? 180;
    final timeoutMs = timeoutSec * 1000;
    final now = DateTime.now().millisecondsSinceEpoch;

    final req = requestDoc.data() ?? {};
    final status = (req['status'] as String? ?? 'PENDING').toUpperCase();
    final assignedTo = req['assignedTo'] as String? ?? req['assignedAgentId'] as String?;
    
    int assignedAtMs = 0;
    final assignedAtVal = req['assignedAt'];
    if (assignedAtVal is num) assignedAtMs = assignedAtVal.toInt();
    if (assignedAtVal is Timestamp) assignedAtMs = assignedAtVal.millisecondsSinceEpoch;

    int claimDeadlineMs = 0;
    final claimDeadlineVal = req['claimDeadline'];
    if (claimDeadlineVal is num) claimDeadlineMs = claimDeadlineVal.toInt();
    if (claimDeadlineVal is Timestamp) claimDeadlineMs = claimDeadlineVal.millisecondsSinceEpoch;
    if (claimDeadlineMs == 0 && assignedAtMs > 0) {
      claimDeadlineMs = assignedAtMs + timeoutMs;
    }

    final rawRejected = req['rejectedBy'];
    final List<String> rejectedList = [];
    if (rawRejected is List) {
      for (final item in rawRejected) {
        if (item != null) rejectedList.add(item.toString());
      }
    }

    // Check if current assignment has expired (> 3 mins or past claimDeadline)
    final isClaimExpired = status == 'ASSIGNED' && (claimDeadlineMs > 0 ? now > claimDeadlineMs : (now - assignedAtMs > timeoutMs));

    // CASE 1: Valid claim by the designated assigned agent within 3 minutes
    if (status == 'ASSIGNED' && assignedTo == currentAgentUid && !isClaimExpired) {
      await requestRef.set({
        'status': 'IN_PROGRESS',
        'lastHeartbeat': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      // Update agent presence to busy
      await PresenceService.setPresenceState(
        firestore: firestore,
        agentUid: currentAgentUid,
        state: AgentPresenceState.busy,
        activeRequestId: requestId,
      );
      return;
    }

    // CASE 2: Claim expired OR request is PENDING — Another eligible agent claims it
    if (status == 'PENDING' || status == 'OPEN' || isClaimExpired) {
      if (rejectedList.contains(currentAgentUid) && !isAdmin) {
        throw Exception('You previously rejected or passed this request.');
      }

      final Map<String, dynamic> updatePayload = {
        'status': 'IN_PROGRESS',
        'assignedTo': currentAgentUid,
        'assignedToName': currentAgentName,
        'assignedToEmail': currentAgentEmail,
        'assignedAgentId': currentAgentUid,
        'assignedAgentName': currentAgentName,
        'assignedAgentEmail': currentAgentEmail,
        'assignedAt': now,
        'claimDeadline': now + timeoutMs,
        'lastHeartbeat': now,
        'updatedAt': now,
      };

      // If overriding an expired agent, record them in rejectedBy so it isn't assigned to them again
      if (isClaimExpired && assignedTo != null && assignedTo.isNotEmpty && assignedTo != currentAgentUid) {
        updatePayload['rejectedBy'] = FieldValue.arrayUnion([assignedTo]);
      }

      await requestRef.set(updatePayload, SetOptions(merge: true));

      // Update agent presence to busy
      await PresenceService.setPresenceState(
        firestore: firestore,
        agentUid: currentAgentUid,
        state: AgentPresenceState.busy,
        activeRequestId: requestId,
      );
      return;
    }

    // CASE 3: If already claimed and in progress by someone else
    if ((status == 'IN_PROGRESS' || status == 'ASSIGNED') && assignedTo != currentAgentUid && !isClaimExpired) {
      final otherName = req['assignedToName'] ?? req['assignedAgentName'] ?? 'another active agent';
      throw Exception('Request is locked and currently being processed by $otherName.');
    }

    // Admin override fallback
    if (isAdmin) {
      await requestRef.set({
        'status': 'IN_PROGRESS',
        'assignedTo': currentAgentUid,
        'assignedToName': currentAgentName,
        'assignedToEmail': currentAgentEmail,
        'assignedAgentId': currentAgentUid,
        'assignedAgentName': currentAgentName,
        'assignedAgentEmail': currentAgentEmail,
        'assignedAt': now,
        'claimDeadline': now + timeoutMs,
        'lastHeartbeat': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      await PresenceService.setPresenceState(
        firestore: firestore,
        agentUid: currentAgentUid,
        state: AgentPresenceState.busy,
        activeRequestId: requestId,
      );
      return;
    }

    throw Exception('Request is locked or currently being processed by another active agent.');
  }

  /// Manually rejects or passes a request to the next candidate.
  /// Enforces single-agent candidate passing. Re-assigns the request to the NEXT best available online agent.
  /// If NO other agent is logged in / available, throws an Exception and prevents passing.
  static Future<void> rejectOrPassRequest({
    required FirebaseFirestore firestore,
    required String collectionName,
    required String requestId,
    required String currentAgentUid,
  }) async {
    final requestRef = firestore.collection(collectionName).doc(requestId);
    final configRef = firestore.collection('system_config').doc('settings');
    final now = DateTime.now().millisecondsSinceEpoch;

    final configDoc = await configRef.get();
    final config = configDoc.data() ?? {};
    final timeoutSec = (config['claimTimeoutSeconds'] as num?)?.toInt() ?? 180;
    final timeoutMs = timeoutSec * 1000;

    // 1. Fetch current document to inspect rejectedBy
    final docSnap = await requestRef.get();
    final docData = docSnap.data() ?? {};
    final rawRejected = docData['rejectedBy'];
    final List<String> rejectedList = [currentAgentUid];
    if (rawRejected is List) {
      for (final item in rawRejected) {
        if (item != null) rejectedList.add(item.toString());
      }
    }

    // 2. Fetch all online staff/agents
    final usersSnap = await firestore.collection('users').get();
    final allOtherOnlineAgents = <Map<String, dynamic>>[];
    for (final uDoc in usersSnap.docs) {
      if (uDoc.id == currentAgentUid) continue; // Exclude current passing agent

      final d = uDoc.data();
      final role = (d['role'] as String? ?? '').toLowerCase();
      final email = (d['email'] as String? ?? '').toLowerCase();
      final lastSeen = (d['lastSeenAt'] as num?)?.toInt() ?? 0;
      final isOnline = d['isOnline'] == true || (d['presenceStatus'] != 'offline' && lastSeen > 0 && (now - lastSeen) < 180000);
      final isStaff = role == 'staff' || role == 'agent' || role == 'admin' || role == 'superadmin' || email.contains('admin') || email.contains('@tranyx') || isOnline;

      if (isStaff && (isOnline || (lastSeen > 0 && (now - lastSeen) < 180000))) {
        allOtherOnlineAgents.add({
          'uid': uDoc.id,
          'name': d['name'] ?? d['displayName'] ?? 'Agent',
          'email': d['email'] ?? '',
          'status': d['presenceStatus'] ?? 'online',
        });
      }
    }

    // STRICT RULE: If NO other staff/agents are online on the platform
    if (allOtherOnlineAgents.isEmpty) {
      throw Exception('You cannot pass this request anymore because no other agents are currently online.');
    }

    // Filter by rejected history
    var otherEligibleAgents = allOtherOnlineAgents.where((ag) => !rejectedList.contains(ag['uid'])).toList();

    // If every other agent has already been offered once, cycle back to the other online agents
    if (otherEligibleAgents.isEmpty) {
      otherEligibleAgents = List.from(allOtherOnlineAgents);
    }

    // Prefer idle over busy agents
    otherEligibleAgents.sort((agA, agB) {
      final aBusy = agA['status'] == 'busy' ? 1 : 0;
      final bBusy = agB['status'] == 'busy' ? 1 : 0;
      return aBusy.compareTo(bBusy);
    });

    final nextAgent = otherEligibleAgents.first;
    final assignStatus = collectionName == 'support_chats' ? 'assigned' : 'ASSIGNED';

    await requestRef.set({
      'status': assignStatus,
      'assignedTo': nextAgent['uid'],
      'assignedToName': nextAgent['name'],
      'assignedToEmail': nextAgent['email'],
      'assignedAgentId': nextAgent['uid'],
      'assignedAgentName': nextAgent['name'],
      'assignedAgentEmail': nextAgent['email'],
      'assignedAt': now,
      'claimDeadline': now + timeoutMs,
      'rejectedBy': FieldValue.arrayUnion([currentAgentUid]),
      'updatedAt': now,
    }, SetOptions(merge: true));

    print('[$collectionName] Request $requestId passed by $currentAgentUid -> Assigned to next candidate ${nextAgent["name"]} (${nextAgent["uid"]}) with fresh 3m window.');

    // Restore passing agent's presence back to online
    await PresenceService.setPresenceState(
      firestore: firestore,
      agentUid: currentAgentUid,
      state: AgentPresenceState.online,
      activeRequestId: null,
    );
  }

  /// Updates heartbeat timestamp for active working sessions.
  static Future<void> sendHeartbeat({
    required FirebaseFirestore firestore,
    required String collectionName,
    required String requestId,
    required String currentAgentUid,
  }) async {
    final requestRef = firestore.collection(collectionName).doc(requestId);
    final now = DateTime.now().millisecondsSinceEpoch;

    await requestRef.update({
      'lastHeartbeat': now,
    }).catchError((_) {});
  }

  /// Automatically assigns unassigned PENDING requests to a single eligible online agent.
  static Future<void> autoAssignPendingRequests({
    required FirebaseFirestore firestore,
    required String collectionName,
    int claimTimeoutSec = 180,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeoutMs = claimTimeoutSec * 1000;

      // 1. Fetch unassigned PENDING / Open requests
      final snap = await firestore.collection(collectionName).get();
      final unassignedDocs = snap.docs.where((doc) {
        final data = doc.data();
        final status = (data['status'] as String? ?? 'OPEN').toUpperCase();
        if (status == 'RESOLVED' || status == 'CLOSED' || status == 'REJECTED') return false;
        final assigned = data['assignedTo'] ?? data['assignedAgentId'];
        return assigned == null || assigned.toString().trim().isEmpty;
      }).toList();

      if (unassignedDocs.isEmpty) return;

      // 2. Fetch online staff/agents
      final usersSnap = await firestore.collection('users').get();
      final onlineAgents = <Map<String, dynamic>>[];
      for (final doc in usersSnap.docs) {
        final d = doc.data();
        final role = (d['role'] as String? ?? '').toLowerCase();
        final email = (d['email'] as String? ?? '').toLowerCase();
        final isOnline = d['isOnline'] == true || (d['presenceStatus'] != 'offline');
        final lastSeen = (d['lastSeenAt'] as num?)?.toInt() ?? 0;
        final isStaff = role == 'staff' || role == 'agent' || role == 'admin' || role == 'superadmin' || email.contains('admin') || email.contains('@tranyx') || isOnline;

        if (isStaff && isOnline && (lastSeen == 0 || (now - lastSeen) < 180000)) {
          onlineAgents.add({
            'uid': doc.id,
            'name': d['name'] ?? d['displayName'] ?? 'Agent',
            'email': d['email'] ?? '',
            'status': d['presenceStatus'] ?? 'online',
            'activeRequestId': d['activeRequestId'],
          });
        }
      }

      if (onlineAgents.isEmpty) return;

      // 3. For each unassigned request, assign to a SINGLE best eligible agent
      for (final doc in unassignedDocs) {
        final data = doc.data();
        final rawRejected = data['rejectedBy'];
        final List<String> rejectedList = [];
        if (rawRejected is List) {
          for (final r in rawRejected) {
            if (r != null) rejectedList.add(r.toString());
          }
        }

        // Filter out agents who previously rejected or timed out
        var eligibleAgents = onlineAgents.where((ag) => !rejectedList.contains(ag['uid'])).toList();
        if (eligibleAgents.isEmpty) {
          eligibleAgents = List.from(onlineAgents);
        }

        // Prefer available/idle agents over busy ones
        eligibleAgents.sort((agA, agB) {
          final aBusy = agA['status'] == 'busy' ? 1 : 0;
          final bBusy = agB['status'] == 'busy' ? 1 : 0;
          return aBusy.compareTo(bBusy);
        });

        final chosenAgent = eligibleAgents.first;
        final assignStatus = collectionName == 'support_chats' ? 'assigned' : 'ASSIGNED';

        await doc.reference.set({
          'status': assignStatus,
          'assignedTo': chosenAgent['uid'],
          'assignedToName': chosenAgent['name'],
          'assignedToEmail': chosenAgent['email'],
          'assignedAgentId': chosenAgent['uid'],
          'assignedAgentName': chosenAgent['name'],
          'assignedAgentEmail': chosenAgent['email'],
          'assignedAt': now,
          'claimDeadline': now + timeoutMs,
          'updatedAt': now,
        }, SetOptions(merge: true));

        print('[$collectionName] Auto-assigned request ${doc.id} to single agent ${chosenAgent["name"]} (${chosenAgent["uid"]})');
      }
    } catch (e) {
      print('[RequestLockService] Auto-assign error for $collectionName: $e');
    }
  }

  /// Sweeps expired ASSIGNED (> 3 min or Agent Offline) or IN_PROGRESS (> 10 min without heartbeat) requests back to PENDING,
  /// then immediately auto-dispatches PENDING requests to single available online agents.
  static Future<void> checkAndReleaseTimeouts({
    required FirebaseFirestore firestore,
    required String collectionName,
    int claimTimeoutSec = 180,
    int heartbeatTimeoutSec = 600,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final claimCutoff = now - (claimTimeoutSec * 1000);
      final heartbeatCutoff = now - (heartbeatTimeoutSec * 1000);

      // 1. Release expired or Offline ASSIGNED requests
      final assignedSnap = await firestore
          .collection(collectionName)
          .where('status', whereIn: ['ASSIGNED', 'assigned', 'Assigned'])
          .get();

      for (final doc in assignedSnap.docs) {
        final data = doc.data();
        final assignedAt = data['assignedAt'];
        int assignedAtMs = 0;
        if (assignedAt is num) assignedAtMs = assignedAt.toInt();
        if (assignedAt is Timestamp) assignedAtMs = assignedAt.millisecondsSinceEpoch;

        final claimDeadline = data['claimDeadline'];
        int deadlineMs = 0;
        if (claimDeadline is num) deadlineMs = claimDeadline.toInt();
        if (claimDeadline is Timestamp) deadlineMs = claimDeadline.millisecondsSinceEpoch;

        bool isExpired = deadlineMs > 0 ? now > deadlineMs : (assignedAtMs > 0 && assignedAtMs < claimCutoff);

        // Presence Check: If assigned agent went offline after 30s grace period
        final previousAgent = data['assignedTo'] ?? data['assignedAgentId'];
        final assignedAgeMs = assignedAtMs > 0 ? (now - assignedAtMs) : 999999;
        if (!isExpired && previousAgent != null && previousAgent.toString().isNotEmpty && assignedAgeMs > 30000) {
          final userDoc = await firestore.collection('users').doc(previousAgent.toString()).get();
          if (userDoc.exists) {
            final uData = userDoc.data() ?? {};
            final isOnline = uData['isOnline'] == true;
            final lastSeen = (uData['lastSeenAt'] as num?)?.toInt() ?? 0;
            final isExplicitOffline = uData['presenceStatus'] == 'offline';
            if (isExplicitOffline || (!isOnline && lastSeen > 0 && (now - lastSeen) > 180000)) {
              isExpired = true;
              print('[$collectionName] Fast-failover: Assigned agent $previousAgent went offline for doc ${doc.id}');
            }
          }
        }

        if (isExpired) {
          final pendingStatus = collectionName == 'support_chats' ? 'pending' : 'PENDING';
          final updateData = <String, dynamic>{
            'status': pendingStatus,
            'assignedTo': null,
            'assignedToName': null,
            'assignedToEmail': null,
            'assignedAgentId': null,
            'assignedAgentName': null,
            'assignedAgentEmail': null,
            'assignedAt': null,
            'claimDeadline': null,
            'updatedAt': now,
          };
          if (previousAgent != null && previousAgent.toString().isNotEmpty) {
            updateData['rejectedBy'] = FieldValue.arrayUnion([previousAgent.toString()]);
          }
          await doc.reference.set(updateData, SetOptions(merge: true));
          print('[$collectionName] Released expired/offline assignment for ${doc.id}');
        }
      }

      // 2. Release abandoned IN_PROGRESS requests (heartbeat timeout)
      final inProgressSnap = await firestore
          .collection(collectionName)
          .where('status', isEqualTo: 'IN_PROGRESS')
          .get();

      for (final doc in inProgressSnap.docs) {
        final data = doc.data();
        final lastHeartbeat = data['lastHeartbeat'];
        int heartbeatMs = 0;
        if (lastHeartbeat is num) heartbeatMs = lastHeartbeat.toInt();
        if (lastHeartbeat is Timestamp) heartbeatMs = lastHeartbeat.millisecondsSinceEpoch;

        if (heartbeatMs > 0 && heartbeatMs < heartbeatCutoff) {
          final previousAgent = data['assignedTo'] ?? data['assignedAgentId'];
          final updateData = <String, dynamic>{
            'status': 'PENDING',
            'assignedTo': null,
            'assignedToName': null,
            'assignedToEmail': null,
            'assignedAgentId': null,
            'assignedAgentName': null,
            'assignedAgentEmail': null,
            'assignedAt': null,
            'claimDeadline': null,
            'lastHeartbeat': null,
            'updatedAt': now,
          };
          if (previousAgent != null && previousAgent.toString().isNotEmpty) {
            updateData['rejectedBy'] = FieldValue.arrayUnion([previousAgent.toString()]);
          }
          await doc.reference.set(updateData, SetOptions(merge: true));
          print('[$collectionName] Released abandoned IN_PROGRESS request ${doc.id} (Heartbeat timeout)');
        }
      }

      // 3. Immediately auto-dispatch PENDING requests to available single agents
      await autoAssignPendingRequests(
        firestore: firestore,
        collectionName: collectionName,
        claimTimeoutSec: claimTimeoutSec,
      );
    } catch (e) {
      print('[RequestLockService] Timeout sweep error for $collectionName: $e');
    }
  }
}
