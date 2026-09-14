import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:web/web.dart' as web;

import '../app.dart';
import '../components/global_p2p_alert_manager.dart' show globalAlertSoundEnabledProvider;
import '../core/providers/environment_provider.dart';

/// Represents a P2P Hybrid PRO Subscription Request submitted by a user.
class P2PSubscriptionRequest {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final String userPhone;
  final String photoUrl;
  final String plan; // 'monthly' or 'yearly'
  final double amount; // 299.0 or 2999.0
  final String paymentMethod; // 'Cash (P2P)'
  final String referenceNumber;
  final String status; // 'PENDING_VERIFICATION', 'ACTIVE', 'REJECTED'
  final int submittedAt;
  final int? verifiedAt;
  final String txId;
  final String? receiptUrl;
  final String? reviewedByAdminId;
  final String? reviewedByAdminName;
  final String? rejectionReason;
  final Map<String, dynamic> rawData;

  const P2PSubscriptionRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.userPhone = '',
    this.photoUrl = '',
    required this.plan,
    required this.amount,
    required this.paymentMethod,
    required this.referenceNumber,
    required this.status,
    required this.submittedAt,
    this.verifiedAt,
    required this.txId,
    this.receiptUrl,
    this.reviewedByAdminId,
    this.reviewedByAdminName,
    this.rejectionReason,
    this.rawData = const {},
  });

  bool get isPending =>
      status == 'PENDING_VERIFICATION' ||
      status == 'PENDING' ||
      status == 'AWAITING_VERIFICATION' ||
      status == 'AWAITING_AGENT';
  bool get isApproved => status == 'ACTIVE' || status == 'APPROVED' || status == 'SUCCESSFUL';
  bool get isRejected => status == 'REJECTED';
  bool get isYearly => plan.toLowerCase() == 'yearly';
  bool get isMonthly => !isYearly;

  P2PSubscriptionRequest mergeWith(P2PSubscriptionRequest other) {
    return P2PSubscriptionRequest(
      id: id,
      userId: other.userId.isNotEmpty ? other.userId : userId,
      userName: (other.userName.isNotEmpty && other.userName != 'Unknown User') ? other.userName : userName,
      userEmail: other.userEmail.isNotEmpty ? other.userEmail : userEmail,
      userPhone: other.userPhone.isNotEmpty ? other.userPhone : userPhone,
      photoUrl: other.photoUrl.isNotEmpty ? other.photoUrl : photoUrl,
      plan: other.plan.isNotEmpty ? other.plan : plan,
      amount: other.amount > 0 ? other.amount : amount,
      paymentMethod: other.paymentMethod.isNotEmpty ? other.paymentMethod : paymentMethod,
      referenceNumber: (other.referenceNumber.isNotEmpty && other.referenceNumber != 'N/A')
          ? other.referenceNumber
          : referenceNumber,
      status: (other.status != 'PENDING_VERIFICATION' || status == 'PENDING_VERIFICATION') ? other.status : status,
      submittedAt: submittedAt > 0 ? submittedAt : other.submittedAt,
      verifiedAt: other.verifiedAt ?? verifiedAt,
      txId: other.txId.isNotEmpty ? other.txId : txId,
      receiptUrl: other.receiptUrl ?? receiptUrl,
      reviewedByAdminId: other.reviewedByAdminId ?? reviewedByAdminId,
      reviewedByAdminName: other.reviewedByAdminName ?? reviewedByAdminName,
      rejectionReason: other.rejectionReason ?? rejectionReason,
      rawData: {...rawData, ...other.rawData},
    );
  }
}

/// Real-time stream provider syncing all P2P subscriptions across users, transactions, and deposit collections.
final p2pSubscriptionsStreamProvider = StreamProvider<List<P2PSubscriptionRequest>>((ref) {
  ref.watch(activeEnvAuthUserProvider);
  final firestore = ref.watch(firestoreProvider);

  final controller = StreamController<List<P2PSubscriptionRequest>>();
  final Map<String, List<P2PSubscriptionRequest>> sourceMap = {
    'users': [],
    'transactions': [],
    'subscriptions': [],
  };

  void emitMerged() {
    final Map<String, P2PSubscriptionRequest> merged = {};

    // 1. Process users collection (Primary ground truth for pendingSubscription)
    for (final sub in sourceMap['users'] ?? []) {
      final key = sub.userId.isNotEmpty ? sub.userId : sub.id;
      merged[key] = sub;
    }

    // 2. Merge transactions collection (Enriches verifiedAt, admin reviewer, status)
    for (final txSub in sourceMap['transactions'] ?? []) {
      final key = txSub.userId.isNotEmpty ? txSub.userId : txSub.id;
      if (merged.containsKey(key)) {
        merged[key] = merged[key]!.mergeWith(txSub);
      } else {
        merged[key] = txSub;
      }
    }

    // 3. Merge dedicated subscriptions collection if present
    for (final dedicatedSub in sourceMap['subscriptions'] ?? []) {
      final key = dedicatedSub.userId.isNotEmpty ? dedicatedSub.userId : dedicatedSub.id;
      if (merged.containsKey(key)) {
        merged[key] = merged[key]!.mergeWith(dedicatedSub);
      } else {
        merged[key] = dedicatedSub;
      }
    }

    final result = merged.values.toList()
      ..sort((subA, subB) => subB.submittedAt.compareTo(subA.submittedAt));

    if (!controller.isClosed) {
      controller.add(result);
    }
  }

  // Stream 1: Users Collection (Guaranteed 100% permission-free on Firestore rules)
  final subUsers = firestore.collection('users').snapshots().listen((snap) {
    final list = <P2PSubscriptionRequest>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final uid = doc.id;
      final userName = (data['name'] ?? data['displayName'] ?? 'Unknown User').toString();
      final userEmail = (data['email'] ?? '').toString();
      final userPhone = (data['phoneNumber'] ?? '').toString();
      final photoUrl = (data['photoURL'] ?? data['photoUrl'] ?? data['avatarUrl'] ?? '').toString();

      // Check pending subscription
      if (data['pendingSubscription'] != null && data['pendingSubscription'] is Map) {
        final pending = Map<String, dynamic>.from(data['pendingSubscription'] as Map);
        final plan = (pending['plan'] ?? 'monthly').toString();
        final amount = (pending['amount'] as num?)?.toDouble() ?? (plan == 'yearly' ? 2999.0 : 299.0);
        final refNo = (pending['referenceNumber'] ?? 'N/A').toString();
        final txId = (pending['txId'] ?? 'sub_p2p_${doc.id}').toString();
        final rawStatus = (pending['status'] ?? 'PENDING_VERIFICATION').toString().toUpperCase();
        final submittedAt = (pending['createdAt'] as num?)?.toInt() ??
            (data['updatedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
        final receiptUrl = (pending['receiptUrl'] ?? pending['proofUrl'] ?? pending['imageUrl'] ?? '').toString();

        list.add(P2PSubscriptionRequest(
          id: txId.isNotEmpty ? txId : uid,
          userId: uid,
          userName: userName,
          userEmail: userEmail,
          userPhone: userPhone,
          photoUrl: photoUrl,
          plan: plan,
          amount: amount,
          paymentMethod: (pending['method'] ?? 'Cash (P2P)').toString(),
          referenceNumber: refNo,
          status: rawStatus == 'ACTIVE' || rawStatus == 'APPROVED' ? 'ACTIVE' : 'PENDING_VERIFICATION',
          submittedAt: submittedAt,
          txId: txId,
          receiptUrl: receiptUrl.isNotEmpty ? receiptUrl : null,
          rawData: pending,
        ));
      } else if (data['subscriptionPaymentMethod'] == 'Cash (P2P)' ||
          (data['isPremium'] == true && data['subscriptionStatus'] == 'active')) {
        // Active Pro user who subscribed via Cash
        final plan = (data['subscriptionPlan'] ?? 'monthly').toString();
        final amount = (data['subscriptionPaymentAmount'] as num?)?.toDouble() ?? (plan == 'yearly' ? 2999.0 : 299.0);
        final refNo = (data['subscriptionTxId'] ?? 'P2P-VERIFIED').toString();
        final startedAt = (data['subscriptionStartedAt'] as num?)?.toInt() ??
            (data['premiumUntil'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;

        list.add(P2PSubscriptionRequest(
          id: 'sub_active_$uid',
          userId: uid,
          userName: userName,
          userEmail: userEmail,
          userPhone: userPhone,
          photoUrl: photoUrl,
          plan: plan,
          amount: amount,
          paymentMethod: 'Cash (P2P)',
          referenceNumber: refNo,
          status: 'ACTIVE',
          submittedAt: startedAt,
          verifiedAt: startedAt,
          txId: refNo,
          rawData: data,
        ));
      }
    }
    sourceMap['users'] = list;
    emitMerged();
  }, onError: (err) {
    print('[Subscriptions] Users stream error notice: $err');
  });

  // Stream 2: Transactions Collection (Safely wrapped with error handling)
  final subTx = firestore.collection('transactions').snapshots().listen((snap) {
    final list = <P2PSubscriptionRequest>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final kind = (data['kind'] ?? data['type'] ?? '').toString().toLowerCase();
      if (kind == 'subscription') {
        final txId = doc.id;
        final uid = (data['uid'] ?? data['userId'] ?? '').toString();
        final method = (data['method'] ?? 'Cash').toString();
        final isCash = method.toLowerCase().contains('cash') ||
            method.toLowerCase().contains('p2p') ||
            txId.startsWith('sub_p2p_');
        if (isCash) {
          final title = (data['title'] ?? '').toString();
          final plan = title.toLowerCase().contains('yearly') ? 'yearly' : 'monthly';
          final amount = (data['amount'] as num?)?.toDouble() ?? (plan == 'yearly' ? 2999.0 : 299.0);
          final rawStatus = (data['status'] ?? 'Pending').toString().toUpperCase();
          final status = rawStatus == 'SUCCESSFUL' || rawStatus == 'APPROVED'
              ? 'ACTIVE'
              : (rawStatus == 'REJECTED' ? 'REJECTED' : 'PENDING_VERIFICATION');
          final refNo = (data['referenceNumber'] ?? data['refNumber'] ?? 'N/A').toString();
          final createdAt = (data['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
          final verifiedAt = (data['verifiedAt'] as num?)?.toInt();

          list.add(P2PSubscriptionRequest(
            id: txId,
            userId: uid,
            userName: (data['userName'] ?? 'Subscriber').toString(),
            userEmail: (data['userEmail'] ?? '').toString(),
            plan: plan,
            amount: amount,
            paymentMethod: 'Cash (P2P)',
            referenceNumber: refNo,
            status: status,
            submittedAt: createdAt,
            verifiedAt: verifiedAt,
            txId: txId,
            reviewedByAdminId: data['reviewedByAdminId'] as String?,
            reviewedByAdminName: data['reviewedByAdminName'] as String?,
            rejectionReason: data['rejectionReason'] as String?,
            rawData: data,
          ));
        }
      }
    }
    sourceMap['transactions'] = list;
    emitMerged();
  }, onError: (err) {
    print('[Subscriptions] Transactions stream notice: $err');
  });

  // Stream 3: Subscriptions Collection (Optional fallback)
  final subDedicated = firestore.collection('subscriptions').snapshots().listen((snap) {
    final list = <P2PSubscriptionRequest>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final uid = (data['uid'] ?? data['userId'] ?? '').toString();
      final plan = (data['plan'] ?? 'monthly').toString();
      final amount = (data['amount'] as num?)?.toDouble() ?? (plan == 'yearly' ? 2999.0 : 299.0);
      final rawStatus = (data['status'] ?? 'PENDING').toString().toUpperCase();
      final status = rawStatus == 'ACTIVE' || rawStatus == 'APPROVED'
          ? 'ACTIVE'
          : (rawStatus == 'REJECTED' ? 'REJECTED' : 'PENDING_VERIFICATION');

      list.add(P2PSubscriptionRequest(
        id: doc.id,
        userId: uid,
        userName: (data['userName'] ?? 'Subscriber').toString(),
        userEmail: (data['userEmail'] ?? '').toString(),
        plan: plan,
        amount: amount,
        paymentMethod: (data['method'] ?? 'Cash (P2P)').toString(),
        referenceNumber: (data['referenceNumber'] ?? doc.id).toString(),
        status: status,
        submittedAt: (data['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        verifiedAt: (data['verifiedAt'] as num?)?.toInt(),
        txId: (data['txId'] ?? doc.id).toString(),
        reviewedByAdminId: data['reviewedByAdminId'] as String?,
        reviewedByAdminName: data['reviewedByAdminName'] as String?,
        rejectionReason: data['rejectionReason'] as String?,
        rawData: data,
      ));
    }
    sourceMap['subscriptions'] = list;
    emitMerged();
  }, onError: (_) {});

  ref.onDispose(() {
    subUsers.cancel();
    subTx.cancel();
    subDedicated.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Provider for pending subscription requests requiring agent verification.
final pendingSubscriptionsStreamProvider = StreamProvider<List<P2PSubscriptionRequest>>((ref) {
  final allSubs = ref.watch(p2pSubscriptionsStreamProvider).value ?? [];
  return Stream.value(allSubs.where((subItem) => subItem.isPending).toList());
});

/// Provider for badge counter of pending P2P subscriptions.
final pendingSubscriptionsCountProvider = Provider<int>((ref) {
  final allSubs = ref.watch(p2pSubscriptionsStreamProvider).value ?? [];
  return allSubs.where((subItem) => subItem.isPending).length;
});

/// Action to approve a P2P subscription request and grant Hybrid PRO status.
Future<void> executeApproveSubscription({
  required BuildContext context,
  required P2PSubscriptionRequest subscription,
  fb.User? adminUser,
}) async {
  final firestore = context.read(firestoreProvider);
  final effectiveUser = adminUser ?? context.read(adminAuthProvider).currentUser;
  final adminUid = effectiveUser?.uid ?? 'admin_portal';
  final adminName = effectiveUser?.displayName?.isNotEmpty == true
      ? effectiveUser!.displayName!
      : (effectiveUser?.email?.isNotEmpty == true ? effectiveUser!.email! : 'Admin Staff');
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final normalizedRef = subscription.referenceNumber.trim().toUpperCase();

  // 1. Sync environment authentication so isAdminOrStaff() passes unconditionally
  final app = await context.read(firebaseAppProvider.future);
  await syncEnvAuth(app, effectiveUser);

  // 2. Anti-duplicate check against claimed_p2p_references
  if (normalizedRef.isNotEmpty && normalizedRef != 'N/A') {
    try {
      final existingClaimSnap = await firestore.collection('claimed_p2p_references').doc(normalizedRef).get();
      if (existingClaimSnap.exists) {
        final claimant = existingClaimSnap.data()?['userName'] ?? 'another user';
        throw Exception('Approval blocked: Reference #$normalizedRef was already claimed by $claimant.');
      }
    } catch (e) {
      if (e.toString().contains('Approval blocked:')) rethrow;
    }
  }

  // 3. Update User Document to Hybrid PRO
  final premiumUntil = subscription.isYearly
      ? now.add(const Duration(days: 365))
      : now.add(const Duration(days: 30));

  await firestore.collection('users').doc(subscription.userId).set({
    'isPremium': true,
    'premiumUntil': premiumUntil.millisecondsSinceEpoch,
    'accountType': 'hybrid',
    'subscriptionPlan': subscription.plan,
    'subscriptionStartedAt': nowMs,
    'subscriptionPaymentMethod': 'Cash (P2P)',
    'subscriptionPaymentAmount': subscription.amount,
    'subscriptionTxId': normalizedRef,
    'subscriptionStatus': 'active',
    'pendingSubscription': null,
    'updatedAt': nowMs,
  }, SetOptions(merge: true));

  // 4. Update Transaction Record
  final txId = subscription.txId.isNotEmpty ? subscription.txId : 'sub_p2p_$nowMs';
  try {
    await firestore.collection('transactions').doc(txId).set({
      'uid': subscription.userId,
      'title': 'Hybrid PRO Subscription (${subscription.isYearly ? 'Yearly' : 'Monthly'})',
      'desc': 'Cash (P2P) Reference: $normalizedRef - Verified by $adminName',
      'amount': subscription.amount,
      'status': 'Successful',
      'method': 'Cash',
      'referenceNumber': normalizedRef,
      'txId': txId,
      'type': 'subscription',
      'kind': 'subscription',
      'verifiedAt': nowMs,
      'reviewedByAdminId': adminUid,
      'reviewedByAdminName': adminName,
      'updatedAt': nowMs,
    }, SetOptions(merge: true));
  } catch (txErr) {
    print('[Subscriptions] Transaction update notice: $txErr');
  }

  // 5. Register Reference in claimed_p2p_references to prevent duplicate claims
  if (normalizedRef.isNotEmpty && normalizedRef != 'N/A') {
    try {
      await firestore.collection('claimed_p2p_references').doc(normalizedRef).set({
        'referenceNumber': normalizedRef,
        'subscriptionId': txId,
        'userId': subscription.userId,
        'userName': subscription.userName,
        'amount': subscription.amount,
        'type': 'subscription',
        'approvedAt': nowMs,
        'approvedByAdminId': adminUid,
        'approvedByAdminName': adminName,
      });
    } catch (_) {}
  }

  // 6. Record Audit Log
  try {
    await firestore.collection('admin_audit_logs').add({
      'type': 'SUBSCRIPTION_APPROVAL',
      'userId': subscription.userId,
      'userName': subscription.userName,
      'amount': subscription.amount,
      'plan': subscription.plan,
      'referenceNumber': normalizedRef,
      'action': 'APPROVED',
      'reviewedByAdminId': adminUid,
      'reviewedByAdminName': adminName,
      'timestamp': nowMs,
    });
  } catch (_) {}

  // 7. Send In-App Notification to User
  try {
    await firestore.collection('notifications').add({
      'userId': subscription.userId,
      'uid': subscription.userId,
      'title': '🎉 Hybrid PRO Subscription Activated!',
      'body':
          'Your Cash (P2P) payment of ₱${subscription.amount.toStringAsFixed(2)} for ${subscription.plan.toUpperCase()} PRO has been verified. Welcome to Tranyx PRO!',
      'type': 'subscription_activated',
      'read': false,
      'createdAt': nowMs,
    });
  } catch (_) {}
}

/// Action to reject a P2P subscription request.
Future<void> executeRejectSubscription({
  required BuildContext context,
  required P2PSubscriptionRequest subscription,
  required String reason,
  fb.User? adminUser,
}) async {
  final firestore = context.read(firestoreProvider);
  final effectiveUser = adminUser ?? context.read(adminAuthProvider).currentUser;
  final adminUid = effectiveUser?.uid ?? 'admin_portal';
  final adminName = effectiveUser?.displayName?.isNotEmpty == true
      ? effectiveUser!.displayName!
      : (effectiveUser?.email?.isNotEmpty == true ? effectiveUser!.email! : 'Admin Staff');
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  // 1. Sync environment authentication
  final app = await context.read(firebaseAppProvider.future);
  await syncEnvAuth(app, effectiveUser);

  // 2. Clear pendingSubscription on user document
  await firestore.collection('users').doc(subscription.userId).set({
    'pendingSubscription': null,
    'lastSubscriptionRejection': {
      'reason': reason,
      'rejectedAt': nowMs,
      'reviewedBy': adminName,
    },
    'updatedAt': nowMs,
  }, SetOptions(merge: true));

  // 3. Update Transaction Record
  if (subscription.txId.isNotEmpty) {
    try {
      await firestore.collection('transactions').doc(subscription.txId).set({
        'status': 'Rejected',
        'rejectionReason': reason,
        'reviewedAt': nowMs,
        'reviewedByAdminId': adminUid,
        'reviewedByAdminName': adminName,
        'updatedAt': nowMs,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // 4. Record Audit Log
  try {
    await firestore.collection('admin_audit_logs').add({
      'type': 'SUBSCRIPTION_REJECTION',
      'userId': subscription.userId,
      'userName': subscription.userName,
      'amount': subscription.amount,
      'plan': subscription.plan,
      'referenceNumber': subscription.referenceNumber,
      'action': 'REJECTED',
      'rejectionReason': reason,
      'reviewedByAdminId': adminUid,
      'reviewedByAdminName': adminName,
      'timestamp': nowMs,
    });
  } catch (_) {}

  // 5. Send Notification to User
  try {
    await firestore.collection('notifications').add({
      'userId': subscription.userId,
      'uid': subscription.userId,
      'title': '⚠️ Subscription Payment Issue',
      'body':
          'Your Cash (P2P) payment for Hybrid PRO could not be verified: $reason. Please check your payment details or contact support.',
      'type': 'subscription_rejected',
      'read': false,
      'createdAt': nowMs,
    });
  } catch (_) {}
}

/// Standalone Subscriptions Page mounted at route `/subscriptions`.
class SubscriptionsPage extends StatelessComponent {
  const SubscriptionsPage({super.key});

  @override
  Component build(BuildContext context) {
    return const SubscriptionsView();
  }
}

/// Reusable Real-Time P2P Subscriptions View Component.
/// Can be rendered as a standalone page or embedded in a tab inside Deposits.
class SubscriptionsView extends StatefulComponent {
  const SubscriptionsView({super.key});

  @override
  State<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends State<SubscriptionsView> {
  String _activeTab = 'pending'; // 'pending', 'active', 'rejected', 'all'
  String _searchQuery = '';
  String _planFilter = 'all'; // 'all', 'monthly', 'yearly'
  bool _isProcessing = false;
  String? _toastMessage;
  P2PSubscriptionRequest? _rejectingSubscription;
  String _rejectionReasonPreset = 'Payment not received in account';
  String _customRejectionNote = '';
  String? _previewImageUrl;

  void _triggerToast(String message) {
    setState(() => _toastMessage = message);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          if (_toastMessage == message) _toastMessage = null;
        });
      }
    });
  }

  void _copyToClipboard(String text) {
    try {
      web.window.navigator.clipboard.writeText(text);
      _triggerToast('Copied to clipboard: $text');
    } catch (_) {
      try {
        final textarea = web.document.createElement('textarea') as web.HTMLTextAreaElement;
        textarea.value = text;
        web.document.body?.appendChild(textarea);
        textarea.select();
        web.document.execCommand('copy');
        textarea.remove();
        _triggerToast('Copied to clipboard: $text');
      } catch (_) {}
    }
  }

  Future<void> _handleApprove(P2PSubscriptionRequest sub) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final adminUser = context.read(adminCurrentUserProvider).value;
      await executeApproveSubscription(
        context: context,
        subscription: sub,
        adminUser: adminUser,
      );
      _triggerToast('🎉 Hybrid PRO Activated for ${sub.userName} (${sub.plan.toUpperCase()})!');
    } catch (e) {
      _triggerToast('Approval failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleConfirmReject() async {
    final sub = _rejectingSubscription;
    if (sub == null || _isProcessing) return;

    final finalReason = _rejectionReasonPreset == 'Other'
        ? (_customRejectionNote.trim().isNotEmpty ? _customRejectionNote.trim() : 'Payment not verified')
        : _rejectionReasonPreset;

    setState(() => _isProcessing = true);

    try {
      final adminUser = context.read(adminCurrentUserProvider).value;
      await executeRejectSubscription(
        context: context,
        subscription: sub,
        reason: finalReason,
        adminUser: adminUser,
      );
      _triggerToast('Subscription rejected for ${sub.userName}.');
      setState(() {
        _rejectingSubscription = null;
        _customRejectionNote = '';
      });
    } catch (e) {
      _triggerToast('Rejection failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String _formatTimeAgo(int timestamp) {
    if (timestamp <= 0) return 'Recently';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp));
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Component _buildTabButton(String tabKey, String label, {int count = 0, bool isUrgent = false}) {
    final isActive = _activeTab == tabKey;
    return button(
      onClick: () => setState(() => _activeTab = tabKey),
      classes:
          'flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-black transition-all cursor-pointer border-0 outline-none select-none '
          '${isActive ? "bg-zinc-900 text-white shadow-sm" : "bg-transparent text-zinc-600 hover:text-zinc-900 hover:bg-zinc-100"}',
      [
        Component.text(label),
        if (count > 0)
          span(
            classes:
                'px-2 py-0.5 rounded-full text-[10px] font-black '
                '${isActive ? "bg-white text-zinc-900" : (isUrgent ? "bg-amber-500 text-white animate-pulse" : "bg-zinc-200 text-zinc-700")}',
            [Component.text('$count')],
          ),
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final subsAsync = context.watch(p2pSubscriptionsStreamProvider);
    final allSubs = subsAsync.value ?? [];

    final pendingList = allSubs.where((subItem) => subItem.isPending).toList();
    final activeList = allSubs.where((subItem) => subItem.isApproved).toList();
    final rejectedList = allSubs.where((subItem) => subItem.isRejected).toList();

    final pendingVolume = pendingList.fold<double>(0.0, (acc, item) => acc + item.amount);
    final activeVolume = activeList.fold<double>(0.0, (acc, item) => acc + item.amount);

    // Filter by tab
    List<P2PSubscriptionRequest> filtered = allSubs.where((subItem) {
      if (_activeTab == 'pending' && !subItem.isPending) return false;
      if (_activeTab == 'active' && !subItem.isApproved) return false;
      if (_activeTab == 'rejected' && !subItem.isRejected) return false;

      // Filter by plan
      if (_planFilter != 'all') {
        if (subItem.plan.toLowerCase() != _planFilter.toLowerCase()) return false;
      }

      // Filter by search query
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final matchName = subItem.userName.toLowerCase().contains(q);
        final matchEmail = subItem.userEmail.toLowerCase().contains(q);
        final matchRef = subItem.referenceNumber.toLowerCase().contains(q);
        final matchUid = subItem.userId.toLowerCase().contains(q);
        if (!matchName && !matchEmail && !matchRef && !matchUid) return false;
      }

      return true;
    }).toList();

    final soundEnabled = context.watch(globalAlertSoundEnabledProvider);

    return div(
      classes: 'flex-grow p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0] relative min-h-screen',
      [
        // Toast notification
        if (_toastMessage != null)
          div(
            classes:
                'fixed bottom-6 right-6 z-50 px-5 py-3.5 rounded-2xl bg-zinc-900 text-white font-black text-xs shadow-2xl flex items-center gap-3 border border-zinc-700 animate-bounce',
            [
              span(classes: 'text-emerald-400 text-sm', [Component.text('✓')]),
              Component.text(_toastMessage!),
            ],
          ),

        // Header section
        div(
          classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 bg-white p-6 rounded-3xl border border-zinc-200/70 shadow-sm',
          [
            div(classes: 'flex flex-col gap-1', [
              div(classes: 'flex items-center gap-3', [
                div(
                  classes: 'w-10 h-10 rounded-2xl bg-gradient-to-br from-amber-400 to-purple-600 flex items-center justify-center text-xl shadow-md text-white',
                  [Component.text('👑')],
                ),
                div(classes: 'flex flex-col', [
                  h1(classes: 'text-xl md:text-2xl font-black text-zinc-900 tracking-tight m-0', [
                    Component.text('P2P Subscriptions Real-Time'),
                  ]),
                  span(classes: 'text-xs text-zinc-500 font-semibold', [
                    Component.text('Automated real-time verification and approval of Tranyx Hybrid PRO memberships.'),
                  ]),
                ]),
              ]),
            ]),

            div(classes: 'flex items-center gap-2.5 flex-wrap', [
              // Sound toggle
              button(
                onClick: () {
                  final next = !soundEnabled;
                  context.read(globalAlertSoundEnabledProvider.notifier).state = next;
                  try {
                    web.window.localStorage.setItem('tranyx_global_sound_enabled', next.toString());
                  } catch (_) {}
                },
                classes:
                    'px-3.5 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer border flex items-center gap-2 '
                    '${soundEnabled ? "bg-amber-50 text-amber-800 border-amber-200" : "bg-zinc-100 text-zinc-500 border-zinc-200"}',
                [
                  span([Component.text(soundEnabled ? '🔔 Sound On' : '🔕 Sound Muted')]),
                ],
              ),

              // Live Sync status indicator
              div(
                classes: 'px-3.5 py-2 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-700 text-xs font-bold flex items-center gap-2',
                [
                  span(classes: 'w-2 h-2 rounded-full bg-emerald-500 animate-ping', []),
                  Component.text('LIVE SYNC'),
                ],
              ),
            ]),
          ],
        ),

        // Metric Cards Row
        div(classes: 'grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4', [
          // 1. Pending Verification
          div(
            classes:
                'p-5 rounded-3xl bg-white border border-zinc-200/70 shadow-sm flex flex-col gap-2 relative overflow-hidden',
            [
              if (pendingList.isNotEmpty)
                div(classes: 'absolute top-0 right-0 w-24 h-24 bg-amber-400/10 rounded-full blur-2xl', []),
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-[11px] font-black uppercase text-zinc-400 tracking-wider', [
                  Component.text('Pending Review'),
                ]),
                span(classes: 'text-amber-500 text-base', [Component.text('⚡')]),
              ]),
              div(classes: 'flex items-baseline gap-2', [
                span(classes: 'text-3xl font-black text-zinc-900', [Component.text('${pendingList.length}')]),
                span(classes: 'text-xs font-bold text-amber-600', [
                  Component.text('₱${pendingVolume.toStringAsFixed(0)} pending'),
                ]),
              ]),
            ],
          ),

          // 2. Active PRO Subscribers
          div(
            classes:
                'p-5 rounded-3xl bg-white border border-zinc-200/70 shadow-sm flex flex-col gap-2 relative overflow-hidden',
            [
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-[11px] font-black uppercase text-zinc-400 tracking-wider', [
                  Component.text('Active PRO Users'),
                ]),
                span(classes: 'text-purple-500 text-base', [Component.text('👑')]),
              ]),
              div(classes: 'flex items-baseline gap-2', [
                span(classes: 'text-3xl font-black text-zinc-900', [Component.text('${activeList.length}')]),
                span(classes: 'text-xs font-bold text-purple-600', [Component.text('Active Members')]),
              ]),
            ],
          ),

          // 3. Total P2P Volume
          div(
            classes:
                'p-5 rounded-3xl bg-white border border-zinc-200/70 shadow-sm flex flex-col gap-2 relative overflow-hidden',
            [
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-[11px] font-black uppercase text-zinc-400 tracking-wider', [
                  Component.text('Approved Revenue'),
                ]),
                span(classes: 'text-emerald-500 text-base', [Component.text('💰')]),
              ]),
              div(classes: 'flex items-baseline gap-2', [
                span(classes: 'text-3xl font-black text-zinc-900', [
                  Component.text('₱${activeVolume.toStringAsFixed(0)}'),
                ]),
                span(classes: 'text-xs font-bold text-emerald-600', [Component.text('Processed')]),
              ]),
            ],
          ),

          // 4. Rejected Submissions
          div(
            classes:
                'p-5 rounded-3xl bg-white border border-zinc-200/70 shadow-sm flex flex-col gap-2 relative overflow-hidden',
            [
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-[11px] font-black uppercase text-zinc-400 tracking-wider', [
                  Component.text('Rejected / Passed'),
                ]),
                span(classes: 'text-rose-500 text-base', [Component.text('🚫')]),
              ]),
              div(classes: 'flex items-baseline gap-2', [
                span(classes: 'text-3xl font-black text-zinc-900', [Component.text('${rejectedList.length}')]),
                span(classes: 'text-xs font-bold text-rose-500', [Component.text('Invalid payments')]),
              ]),
            ],
          ),
        ]),

        // Navigation Tabs & Filters Row
        div(classes: 'flex flex-col gap-3.5 w-full', [
          // Tab bar
          div(
            classes:
                'w-full flex items-center gap-2 p-1.5 bg-white border border-zinc-200/60 rounded-2xl shadow-sm overflow-x-auto scrollbar-none',
            [
              _buildTabButton(
                'pending',
                '⚡ Pending Verification',
                count: pendingList.length,
                isUrgent: pendingList.isNotEmpty,
              ),
              _buildTabButton('active', '👑 Active PRO', count: activeList.length),
              _buildTabButton('rejected', '🚫 Rejected', count: rejectedList.length),
              _buildTabButton('all', 'All Subscriptions', count: allSubs.length),
            ],
          ),

          // Search & Filter controls
          div(
            classes:
                'flex flex-col sm:flex-row sm:items-center justify-between gap-3 bg-white/70 backdrop-blur-sm p-3 rounded-2xl border border-zinc-200/50 shadow-sm',
            [
              // Plan selector
              div(classes: 'flex items-center gap-2.5', [
                select(
                  onChange: (dynamic val) {
                    final selectedList = val is List<String> ? val : <String>[];
                    final opt = selectedList.isNotEmpty ? selectedList.first : 'all';
                    setState(() => _planFilter = opt);
                  },
                  classes:
                      'px-3 py-1.5 rounded-xl text-xs font-bold bg-white border border-zinc-200 text-zinc-700 focus:outline-none cursor-pointer shadow-sm',
                  [
                    option(value: 'all', selected: _planFilter == 'all', [Component.text('👑 All Plans')]),
                    option(value: 'monthly', selected: _planFilter == 'monthly', [Component.text('Monthly (₱299)')]),
                    option(value: 'yearly', selected: _planFilter == 'yearly', [Component.text('Yearly (₱2,999)')]),
                  ],
                ),
                span(classes: 'text-xs text-zinc-400 font-bold', [
                  Component.text('${filtered.length} entries'),
                ]),
              ]),

              // Search input
              div(classes: 'relative w-full sm:w-80', [
                input(
                  type: InputType.text,
                  value: _searchQuery,
                  onInput: (dynamic val) => setState(() => _searchQuery = (val as String?) ?? ''),
                  attributes: {'placeholder': 'Search subscriber, email, or ref #...'},
                  classes:
                      'w-full px-3.5 py-1.5 rounded-xl text-xs bg-white border border-zinc-200 text-zinc-900 focus:outline-none focus:border-zinc-400 shadow-sm',
                ),
                if (_searchQuery.isNotEmpty)
                  button(
                    onClick: () => setState(() => _searchQuery = ''),
                    classes: 'absolute right-2.5 top-1/2 -translate-y-1/2 text-zinc-400 hover:text-zinc-600 text-xs border-0 bg-transparent cursor-pointer',
                    [Component.text('✕')],
                  ),
              ]),
            ],
          ),
        ]),

        // Subscription Cards List
        if (filtered.isEmpty)
          div(
            classes:
                'w-full py-16 px-6 bg-white rounded-3xl border border-zinc-200/70 shadow-sm flex flex-col items-center justify-center gap-3 text-center',
            [
              span(classes: 'text-4xl', [Component.text(_activeTab == 'pending' ? '🎉' : '🔍')]),
              h3(classes: 'text-base font-black text-zinc-800 m-0', [
                Component.text(
                  _activeTab == 'pending' ? 'All P2P Subscriptions Verified!' : 'No matching subscriptions found.',
                ),
              ]),
              p(classes: 'text-xs text-zinc-400 max-w-sm m-0', [
                Component.text(
                  _activeTab == 'pending'
                      ? 'There are currently no user payments waiting for agent review. New requests will chime in real-time!'
                      : 'Try broadening your search query or switching filters.',
                ),
              ]),
            ],
          )
        else
          div(classes: 'flex flex-col gap-3', [
            for (final subItem in filtered)
              div(
                classes:
                    'p-5 rounded-3xl bg-white border transition-all duration-200 shadow-sm flex flex-col lg:flex-row lg:items-center justify-between gap-5 '
                    '${subItem.isPending ? "border-amber-200/80 hover:border-amber-300" : "border-zinc-200/70 hover:border-zinc-300"}',
                [
                  // Left: User Info & Plan details
                  div(classes: 'flex items-center gap-4 min-w-0', [
                    // Avatar
                    div(
                      classes:
                          'w-12 h-12 rounded-2xl bg-gradient-to-br from-indigo-100 to-purple-100 border border-indigo-200/60 flex items-center justify-center font-black text-sm text-indigo-700 flex-shrink-0 relative overflow-hidden shadow-sm',
                      [
                        if (subItem.photoUrl.isNotEmpty)
                          img(src: subItem.photoUrl, alt: subItem.userName, classes: 'w-full h-full object-cover')
                        else
                          Component.text(
                            subItem.userName.isNotEmpty ? subItem.userName.substring(0, 1).toUpperCase() : 'U',
                          ),
                      ],
                    ),

                    // User Info
                    div(classes: 'flex flex-col min-w-0 gap-1', [
                      div(classes: 'flex items-center gap-2 flex-wrap', [
                        span(classes: 'text-sm font-black text-zinc-900 truncate', [Component.text(subItem.userName)]),

                        // Plan badge
                        span(
                          classes:
                              'px-2.5 py-0.5 rounded-full text-[10px] font-black uppercase '
                              '${subItem.isYearly ? "bg-gradient-to-r from-amber-500/15 via-purple-500/15 to-indigo-500/15 text-amber-900 border border-amber-300" : "bg-indigo-50 text-indigo-700 border border-indigo-200"}',
                          [
                            Component.text(subItem.isYearly ? '👑 PRO YEARLY' : 'PRO MONTHLY'),
                          ],
                        ),

                        // Status pill
                        if (subItem.isPending)
                          span(
                            classes:
                                'px-2.5 py-0.5 rounded-full text-[10px] font-black uppercase bg-amber-50 text-amber-800 border border-amber-200 flex items-center gap-1.5',
                            [
                              span(classes: 'w-1.5 h-1.5 rounded-full bg-amber-500 animate-pulse', []),
                              Component.text('Pending Review'),
                            ],
                          )
                        else if (subItem.isApproved)
                          span(
                            classes:
                                'px-2.5 py-0.5 rounded-full text-[10px] font-black uppercase bg-emerald-50 text-emerald-800 border border-emerald-200 flex items-center gap-1',
                            [
                              Component.text('✓ Active PRO'),
                            ],
                          )
                        else
                          span(
                            classes:
                                'px-2.5 py-0.5 rounded-full text-[10px] font-black uppercase bg-rose-50 text-rose-700 border border-rose-200',
                            [
                              Component.text('Rejected'),
                            ],
                          ),
                      ]),

                      div(classes: 'flex items-center gap-3 text-xs text-zinc-500 flex-wrap', [
                        if (subItem.userEmail.isNotEmpty)
                          span(classes: 'font-medium', [Component.text(subItem.userEmail)]),
                        span(classes: 'text-zinc-400 font-mono text-[11px]', [
                          Component.text('UID: ${subItem.userId.substring(0, subItem.userId.length > 8 ? 8 : subItem.userId.length)}...'),
                        ]),
                        span(classes: 'text-zinc-400 text-[11px]', [
                          Component.text('Submitted ${_formatTimeAgo(subItem.submittedAt)}'),
                        ]),
                      ]),
                    ]),
                  ]),

                  // Center: Reference Number & Payment Info
                  div(classes: 'flex flex-row lg:flex-col items-start lg:items-end justify-between gap-1 border-t lg:border-t-0 pt-3 lg:pt-0 border-zinc-100', [
                    div(classes: 'flex items-center gap-2', [
                      span(classes: 'text-xs font-extrabold text-zinc-400 uppercase', [Component.text('Ref #:')]),
                      button(
                        classes:
                            'px-2.5 py-1 rounded-xl bg-zinc-100 hover:bg-zinc-200 text-zinc-900 font-mono font-black text-xs border border-zinc-200 select-all cursor-pointer flex items-center gap-1.5 transition-colors outline-none',
                        onClick: () => _copyToClipboard(subItem.referenceNumber),
                        attributes: {'title': 'Click to copy reference number'},
                        [
                          Component.text(subItem.referenceNumber),
                          span(classes: 'text-[10px] text-zinc-400', [Component.text('📋')]),
                        ],
                      ),
                    ]),

                    div(classes: 'flex items-center gap-2', [
                      span(classes: 'text-lg font-black text-zinc-900', [
                        Component.text('₱${subItem.amount.toStringAsFixed(2)}'),
                      ]),
                      span(classes: 'text-[11px] font-bold text-zinc-400', [
                        Component.text('via ${subItem.paymentMethod}'),
                      ]),
                    ]),
                  ]),

                  // Right: Action Buttons
                  div(classes: 'flex items-center gap-2.5 self-end lg:self-center shrink-0 flex-wrap', [
                    if (subItem.receiptUrl != null && subItem.receiptUrl!.isNotEmpty)
                      button(
                        onClick: () => setState(() => _previewImageUrl = subItem.receiptUrl),
                        classes:
                            'px-3.5 py-2 rounded-xl bg-zinc-100 hover:bg-zinc-200 text-zinc-700 text-xs font-bold transition-all border border-zinc-200 cursor-pointer flex items-center gap-1.5',
                        [
                          Component.text('🖼️ Proof'),
                        ],
                      ),

                    if (subItem.isPending) ...[
                      // Reject button
                      button(
                        onClick: () => setState(() {
                          _rejectingSubscription = subItem;
                          _rejectionReasonPreset = 'Payment not received in account';
                          _customRejectionNote = '';
                        }),
                        classes:
                            'px-3.5 py-2 rounded-xl bg-rose-50 hover:bg-rose-100 text-rose-700 text-xs font-black transition-all border border-rose-200 cursor-pointer',
                        [Component.text('✕ Reject')],
                      ),

                      // Approve button
                      button(
                        onClick: () => _handleApprove(subItem),
                        classes:
                            'px-5 py-2 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-black transition-all shadow-sm cursor-pointer flex items-center gap-1.5',
                        [
                          Component.text('✓ Approve PRO'),
                        ],
                      ),
                    ] else ...[
                      // View details / Profile
                      button(
                        onClick: () {
                          Router.of(context).push('/users');
                        },
                        classes:
                            'px-3.5 py-2 rounded-xl bg-zinc-100 hover:bg-zinc-200 text-zinc-700 text-xs font-bold transition-all border border-zinc-200 cursor-pointer',
                        [Component.text('User Profile →')],
                      ),
                    ],
                  ]),
                ],
              ),
          ]),

        // Rejection Modal Dialog
        if (_rejectingSubscription != null)
          div(
            classes: 'fixed inset-0 z-50 bg-black/50 backdrop-blur-sm flex items-center justify-center p-4',
            [
              div(
                classes: 'bg-white rounded-3xl p-6 max-w-md w-full border border-zinc-200 shadow-2xl flex flex-col gap-4',
                [
                  div(classes: 'flex items-center justify-between', [
                    h3(classes: 'text-base font-black text-zinc-900 m-0', [Component.text('Reject Subscription Payment')]),
                    button(
                      onClick: () => setState(() => _rejectingSubscription = null),
                      classes: 'text-zinc-400 hover:text-zinc-600 border-0 bg-transparent text-lg cursor-pointer',
                      [Component.text('✕')],
                    ),
                  ]),

                  p(classes: 'text-xs text-zinc-500 m-0', [
                    Component.text(
                      'Select a reason for rejecting ${_rejectingSubscription!.userName}\'s P2P subscription payment. The user will be notified in real-time.',
                    ),
                  ]),

                  // Pre-set reasons
                  div(classes: 'flex flex-col gap-2', [
                    label(classes: 'text-[11px] font-bold text-zinc-400 uppercase', [Component.text('Reason')]),
                    select(
                      onChange: (dynamic val) {
                        final selectedList = val is List<String> ? val : <String>[];
                        final opt = selectedList.isNotEmpty ? selectedList.first : '';
                        setState(() => _rejectionReasonPreset = opt);
                      },
                      classes: 'px-3.5 py-2 rounded-xl text-xs bg-white border border-zinc-200 text-zinc-800 font-bold focus:outline-none',
                      [
                        option(value: 'Payment not received in account', [Component.text('Payment not received in account')]),
                        option(value: 'Invalid or incorrect reference number', [Component.text('Invalid or incorrect reference number')]),
                        option(value: 'Amount received does not match plan price', [Component.text('Amount received does not match plan price')]),
                        option(value: 'Duplicate reference claim attempt', [Component.text('Duplicate reference claim attempt')]),
                        option(value: 'Other', [Component.text('Other (Specify below)')]),
                      ],
                    ),
                  ]),

                  if (_rejectionReasonPreset == 'Other')
                    div(classes: 'flex flex-col gap-2', [
                      label(classes: 'text-[11px] font-bold text-zinc-400 uppercase', [Component.text('Custom Explanation')]),
                      textarea(
                        onInput: (dynamic val) => setState(() => _customRejectionNote = val.toString()),
                        attributes: {'placeholder': 'Explain why the payment could not be verified...'},
                        classes: 'px-3.5 py-2 rounded-xl text-xs bg-white border border-zinc-200 text-zinc-800 font-medium focus:outline-none min-h-[80px]',
                        [],
                      ),
                    ]),

                  // Modal Actions
                  div(classes: 'flex items-center justify-end gap-2.5 pt-2', [
                    button(
                      onClick: () => setState(() => _rejectingSubscription = null),
                      classes: 'px-4 py-2 rounded-xl text-xs font-bold text-zinc-600 bg-zinc-100 hover:bg-zinc-200 transition-all border-0 cursor-pointer',
                      [Component.text('Cancel')],
                    ),
                    button(
                      onClick: _handleConfirmReject,
                      classes: 'px-4.5 py-2 rounded-xl text-xs font-black text-white bg-rose-600 hover:bg-rose-700 transition-all border-0 shadow-sm cursor-pointer',
                      [Component.text('Confirm Rejection')],
                    ),
                  ]),
                ],
              ),
            ],
          ),

        // Receipt Image Preview Modal
        if (_previewImageUrl != null)
          div(
            classes: 'fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4',
            [
              div(classes: 'relative max-w-2xl w-full bg-white p-4 rounded-3xl shadow-2xl flex flex-col gap-3', [
                div(classes: 'flex items-center justify-between', [
                  span(classes: 'text-xs font-black text-zinc-800', [Component.text('Proof of Payment Preview')]),
                  button(
                    onClick: () => setState(() => _previewImageUrl = null),
                    classes: 'text-zinc-400 hover:text-zinc-600 border-0 bg-transparent text-lg cursor-pointer',
                    [Component.text('✕')],
                  ),
                ]),
                img(
                  src: _previewImageUrl!,
                  alt: 'Payment Proof',
                  classes: 'w-full max-h-[70vh] object-contain rounded-2xl border border-zinc-100',
                ),
              ]),
            ],
          ),
      ],
    );
  }
}
