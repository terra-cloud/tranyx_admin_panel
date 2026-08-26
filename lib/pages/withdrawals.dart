import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:web/web.dart' as web;

import '../app.dart';
import '../core/providers/environment_provider.dart';
import '../core/services/imgbb_service.dart';
import 'users.dart';
import 'deposits.dart' show depositRequestsStreamProvider;

/// Represents a P2P withdrawal request submitted by a user.
class WithdrawalRequest {
  final String id;
  final String uid;
  final String userName;
  final String userEmail;
  final double amount;
  final double feeAmount;
  final double netAmount;
  final String paymentMethod; // GCash, Maya, GrabPay, SeaBank, GoTyme, Bank
  final String userAccountName;
  final String userAccountNumber;
  final String userQrUrl;
  final String referenceNumber;
  final String proofImageUrl;
  final String status; // WAITING_FOR_AGENT, AWAITING_AGENT_PAYMENT, PENDING_CONFIRMATION, APPROVED, REJECTED, CANCELLED
  final String? rejectionReason;
  final String? rejectionNote;
  final String? notes;
  final String? category;
  final String? adminUid;
  final String? agentId;
  final String? agentName;
  final String? agentPhone;
  final int createdAt;
  final int? claimedAt;
  final int? proofSubmittedAt;
  final int? verifiedAt;
  final Map<String, dynamic> rawData;

  const WithdrawalRequest({
    required this.id,
    required this.uid,
    required this.userName,
    required this.userEmail,
    required this.amount,
    this.feeAmount = 0.0,
    this.netAmount = 0.0,
    required this.paymentMethod,
    required this.userAccountName,
    required this.userAccountNumber,
    this.userQrUrl = '',
    this.referenceNumber = '',
    this.proofImageUrl = '',
    required this.status,
    this.rejectionReason,
    this.rejectionNote,
    this.notes,
    this.category,
    this.adminUid,
    this.agentId,
    this.agentName,
    this.agentPhone,
    required this.createdAt,
    this.claimedAt,
    this.proofSubmittedAt,
    this.verifiedAt,
    this.rawData = const {},
  });

  bool get isOnChain =>
      paymentMethod.toLowerCase().contains('usdt') ||
      paymentMethod.toLowerCase().contains('crypto') ||
      paymentMethod.toLowerCase().contains('onchain') ||
      paymentMethod.toLowerCase().contains('trc20') ||
      paymentMethod.toLowerCase().contains('erc20') ||
      paymentMethod.toLowerCase().contains('polygon');

  factory WithdrawalRequest.fromMap(String id, Map<String, dynamic> map) {
    int parseDateTime(dynamic val) {
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is DateTime) return val.millisecondsSinceEpoch;
      if (val is String) {
        final parsedNum = int.tryParse(val);
        if (parsedNum != null) return parsedNum;
        final parsedDate = DateTime.tryParse(val);
        if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;
      }
      return DateTime.now().millisecondsSinceEpoch;
    }

    double parseAmount(dynamic val) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
      return 0.0;
    }

    final rawMethod = (map['payoutMethod'] ?? map['paymentMethod'] ?? map['method'] ?? map['type'] ?? 'GCash').toString();
    final lowerMethod = rawMethod.toLowerCase();
    String normalizedMethod = rawMethod;
    if (lowerMethod.contains('maya')) {
      normalizedMethod = 'Maya';
    } else if (lowerMethod.contains('gcash')) {
      normalizedMethod = 'GCash';
    } else if (lowerMethod.contains('grab')) {
      normalizedMethod = 'GrabPay';
    } else if (lowerMethod.contains('seabank')) {
      normalizedMethod = 'SeaBank';
    } else if (lowerMethod.contains('gotyme')) {
      normalizedMethod = 'GoTyme';
    } else if (lowerMethod.contains('bdo')) {
      normalizedMethod = 'BDO';
    } else if (lowerMethod.contains('bpi')) {
      normalizedMethod = 'BPI';
    } else if (lowerMethod.contains('unionbank')) {
      normalizedMethod = 'UnionBank';
    } else if (lowerMethod.contains('bank')) {
      normalizedMethod = 'Bank Transfer';
    }

    String extractUrlFromAny(dynamic val) {
      if (val == null) return '';
      if (val is String) {
        final s = val.trim();
        if (s.isNotEmpty && s != 'null') {
          if (s.startsWith('http://') || s.startsWith('https://') || s.startsWith('data:image/') || s.startsWith('blob:')) {
            return s;
          }
          if (s.length > 30 && (s.contains('firebasestorage') || s.contains('/o/') || s.contains('.jpg') || s.contains('.png') || s.contains('.jpeg') || s.contains('.webp'))) {
            return s;
          }
        }
      } else if (val is List) {
        for (final item in val) {
          final res = extractUrlFromAny(item);
          if (res.isNotEmpty) return res;
        }
      } else if (val is Map) {
        final m = val as Map<String, dynamic>;
        final directUrl = m['url'] ?? m['downloadUrl'] ?? m['download_url'] ?? m['imageUrl'] ?? m['image_url'] ?? m['src'] ?? m['path'] ?? m['proofUrl'] ?? m['attachmentUrl'];
        if (directUrl != null) {
          final res = extractUrlFromAny(directUrl);
          if (res.isNotEmpty) return res;
        }
        for (final v in m.values) {
          final res = extractUrlFromAny(v);
          if (res.isNotEmpty) return res;
        }
      }
      return '';
    }

    String extractProof(Map<String, dynamic> m) {
      final keys = [
        'proofImageUrl',
        'proof_image_url',
        'proofUrl',
        'proof_url',
        'receiptUrl',
        'receipt_url',
        'receiptImage',
        'receipt_image',
        'proofOfPayment',
        'proof_of_payment',
        'screenshotUrl',
        'screenshot',
        'imageUrl',
        'image_url',
      ];
      for (final k in keys) {
        if (m.containsKey(k)) {
          final res = extractUrlFromAny(m[k]);
          if (res.isNotEmpty) return res;
        }
      }
      return '';
    }

    String extractUserQr(Map<String, dynamic> m) {
      final keys = [
        'userQrUrl',
        'user_qr_url',
        'qrUrl',
        'qr_url',
        'qrImageUrl',
        'qr_image_url',
        'userQr',
        'recipientQrUrl',
      ];
      for (final k in keys) {
        if (m.containsKey(k)) {
          final res = extractUrlFromAny(m[k]);
          if (res.isNotEmpty) return res;
        }
      }
      return '';
    }

    final amount = parseAmount(map['amount']);
    final feeAmount = parseAmount(map['feeAmount']);
    final netAmount = parseAmount(map['netAmount']) > 0 ? parseAmount(map['netAmount']) : (amount - feeAmount);

    final rawStatus = (map['status'] ?? map['state'] ?? 'WAITING_FOR_AGENT').toString().toUpperCase();
    String normalizedStatus;
    if (rawStatus.contains('APPROV') || rawStatus.contains('SUCCESS') || rawStatus.contains('COMPLET')) {
      normalizedStatus = 'APPROVED';
    } else if (rawStatus.contains('REJECT') || rawStatus.contains('DECLIN')) {
      normalizedStatus = 'REJECTED';
    } else if (rawStatus.contains('CANCEL')) {
      normalizedStatus = 'CANCELLED';
    } else if (rawStatus.contains('CONFIRM') || rawStatus.contains('VERIF') || rawStatus.contains('PROOF')) {
      normalizedStatus = 'PENDING_CONFIRMATION';
    } else if (rawStatus.contains('PAY') || rawStatus.contains('CLAIM') || rawStatus.contains('PROGRESS')) {
      normalizedStatus = 'AWAITING_AGENT_PAYMENT';
    } else {
      normalizedStatus = 'WAITING_FOR_AGENT';
    }

    return WithdrawalRequest(
      id: id,
      uid: (map['userId'] ?? map['uid'] ?? map['renteeId'] ?? map['applicantId'] ?? '').toString(),
      userName: (map['userName'] ?? map['name'] ?? map['accountName'] ?? map['userAccountName'] ?? 'User').toString(),
      userEmail: (map['userEmail'] ?? map['email'] ?? '').toString(),
      amount: amount,
      feeAmount: feeAmount,
      netAmount: netAmount,
      paymentMethod: normalizedMethod,
      userAccountName: (map['accountName'] ?? map['userAccountName'] ?? map['recipientName'] ?? map['userName'] ?? '').toString(),
      userAccountNumber: (map['accountNumber'] ?? map['userAccountNumber'] ?? map['phoneNumber'] ?? map['phone'] ?? '').toString(),
      userQrUrl: extractUserQr(map),
      referenceNumber: (map['referenceNumber'] ?? map['refNumber'] ?? map['refNo'] ?? map['reference'] ?? '').toString(),
      proofImageUrl: extractProof(map),
      status: normalizedStatus,
      rejectionReason: (map['rejectionReason'] ?? map['reason']) as String?,
      rejectionNote: (map['rejectionNote'] ?? map['note']) as String?,
      notes: (map['notes'] ?? map['note'] ?? map['reason'] ?? map['memo'] ?? map['description']) as String?,
      category: (map['category'] ?? map['payoutCategory'] ?? map['payoutType'] ?? map['type']) as String?,
      adminUid: (map['adminUid'] ?? map['reviewedByAdminId']) as String?,
      agentId: (map['agentId'] ?? map['assignedAgentId']) as String?,
      agentName: (map['agentName'] ?? map['assignedAgentName']) as String?,
      agentPhone: (map['agentPhone'] ?? map['assignedAgentPhone']) as String?,
      createdAt: parseDateTime(map['createdAt'] ?? map['submittedAt'] ?? map['timestamp']),
      claimedAt: map['claimedAt'] != null ? parseDateTime(map['claimedAt']) : null,
      proofSubmittedAt: map['proofSubmittedAt'] != null ? parseDateTime(map['proofSubmittedAt']) : null,
      verifiedAt: map['verifiedAt'] != null ? parseDateTime(map['verifiedAt']) : (map['approvedAt'] != null ? parseDateTime(map['approvedAt']) : null),
      rawData: map,
    );
  }
}

/// Represents a unified real-time transaction across the entire system.
class PlatformTransaction {
  final String id;
  final String uid;
  final String type; // deposit, withdraw, escrow, platform_fee, transfer
  final double amount;
  final String status; // WAITING_FOR_AGENT, PENDING_VERIFICATION, PENDING_CONFIRMATION, COMPLETED, APPROVED, CANCELLED, REJECTED
  final String title;
  final String description;
  final String originRail;
  final String paymentMethod;
  final String referenceNumber;
  final String userAccountName;
  final String userAccountNumber;
  final String userQrUrl;
  final String proofImageUrl;
  final int createdAt;

  PlatformTransaction({
    required this.id,
    required this.uid,
    required this.type,
    required this.amount,
    required this.status,
    required this.title,
    required this.description,
    required this.originRail,
    required this.paymentMethod,
    required this.referenceNumber,
    required this.userAccountName,
    required this.userAccountNumber,
    required this.userQrUrl,
    required this.proofImageUrl,
    required this.createdAt,
  });

  factory PlatformTransaction.fromMap(String id, Map<String, dynamic> map) {
    int parseDateTime(dynamic val) {
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    double parseAmount(dynamic val) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val.replaceAll(RegExp(r'[^\d.-]'), '')) ?? 0.0;
      return 0.0;
    }

    return PlatformTransaction(
      id: id,
      uid: (map['uid'] ?? map['userId'] ?? '').toString(),
      type: (map['type'] ?? map['category'] ?? 'transaction').toString().toLowerCase(),
      amount: parseAmount(map['amount'] ?? map['netAmount']),
      status: (map['status'] ?? 'COMPLETED').toString().toUpperCase(),
      title: (map['title'] ?? map['name'] ?? map['type'] ?? 'Transaction').toString(),
      description: (map['desc'] ?? map['description'] ?? map['note'] ?? '').toString(),
      originRail: (map['originRail'] ?? map['rail'] ?? 'manual_p2p').toString(),
      paymentMethod: (map['method'] ?? map['paymentMethod'] ?? 'GCash').toString(),
      referenceNumber: (map['referenceNumber'] ?? map['refNumber'] ?? '').toString(),
      userAccountName: (map['userAccountName'] ?? map['accountName'] ?? '').toString(),
      userAccountNumber: (map['userAccountNumber'] ?? map['accountNumber'] ?? '').toString(),
      userQrUrl: (map['userQrUrl'] ?? map['qrUrl'] ?? '').toString(),
      proofImageUrl: (map['proofImageUrl'] ?? map['proofUrl'] ?? '').toString(),
      createdAt: parseDateTime(map['createdAt'] ?? map['timestamp'] ?? map['verifiedAt']),
    );
  }
}

/// Provider streaming P2P withdrawal requests in real time from all possible collections.
final withdrawalRequestsStreamProvider = StreamProvider<List<WithdrawalRequest>>((ref) {
  ref.watch(activeEnvAuthUserProvider);
  final firestore = ref.watch(firestoreProvider);

  final controller = StreamController<List<WithdrawalRequest>>();
  final Map<String, List<WithdrawalRequest>> sourceMap = {
    'withdrawal_requests': [],
    'withdrawals': [],
    'cashout_requests': [],
  };

  void emitMerged() {
    final Map<String, WithdrawalRequest> merged = {};
    for (final list in sourceMap.values) {
      for (final item in list) {
        merged[item.id] = item;
      }
    }
    final result = merged.values.toList()
      ..sort((reqA, reqB) => reqB.createdAt.compareTo(reqA.createdAt));
    if (!controller.isClosed) {
      controller.add(result);
    }
  }

  final sub1 = firestore.collection('withdrawal_requests').snapshots().listen((snap) {
    sourceMap['withdrawal_requests'] = snap.docs.map((doc) => WithdrawalRequest.fromMap(doc.id, doc.data())).toList();
    emitMerged();
  }, onError: (err) {
    print('[Withdrawals] withdrawal_requests stream notice: $err');
  });

  final sub2 = firestore.collection('withdrawals').snapshots().listen((snap) {
    sourceMap['withdrawals'] = snap.docs.map((doc) => WithdrawalRequest.fromMap(doc.id, doc.data())).toList();
    emitMerged();
  }, onError: (_) {});

  final sub3 = firestore.collection('cashout_requests').snapshots().listen((snap) {
    sourceMap['cashout_requests'] = snap.docs.map((doc) => WithdrawalRequest.fromMap(doc.id, doc.data())).toList();
    emitMerged();
  }, onError: (_) {});

  ref.onDispose(() {
    sub1.cancel();
    sub2.cancel();
    sub3.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Provider streaming all real-time platform transactions.
final platformTransactionsStreamProvider = StreamProvider<List<PlatformTransaction>>((ref) {
  ref.watch(activeEnvAuthUserProvider);
  final firestore = ref.watch(firestoreProvider);
  return firestore.collection('transactions').snapshots().map((snap) {
    final list = snap.docs.map((doc) => PlatformTransaction.fromMap(doc.id, doc.data())).toList();
    list.sort((txA, txB) => txB.createdAt.compareTo(txA.createdAt));
    return list;
  }).handleError((err) {
    print('[Transactions] Stream notice: $err');
    return <PlatformTransaction>[];
  });
});

class WithdrawalsPage extends StatefulComponent {
  const WithdrawalsPage({super.key});

  @override
  State<WithdrawalsPage> createState() => _WithdrawalsPageState();
}

class _WithdrawalsPageState extends State<WithdrawalsPage> {
  // Navigation tabs: 'awaiting_agent', 'in_progress', 'pending_proof', 'approved', 'rejected', 'all', 'realtime_tx', 'audit'
  String _activeTab = 'awaiting_agent';
  String _searchQuery = '';
  String _methodFilter = 'all'; // all, GCash, Maya, GrabPay, SeaBank, GoTyme, Bank

  // Multi-selection & Batch Operations
  final Set<String> _selectedWithdrawalIds = {};

  // Audio Chime & Interrupt Alert States
  bool _soundEnabled = true;
  final Set<String> _acknowledgedInterruptIds = {};
  WithdrawalRequest? _activeInterruptWithdrawal;

  // Inspection modal state
  WithdrawalRequest? _inspectingWithdrawal;
  PlatformTransaction? _inspectingTransaction;
  double _zoomLevel = 1.0;
  double _panX = 0.0;
  double _panY = 0.0;

  // Agent Fulfill & Proof Submission Modal States
  bool _showSubmitProofModal = false;
  WithdrawalRequest? _targetWithdrawalForProof;
  String _proofReferenceNumber = '';
  String _proofImageUrlInput = '';
  bool _isUploadingProof = false;

  // Manual / Ad-hoc P2P Cashout Modal States
  bool _showCreateCashoutModal = false;
  String _createUserId = '';
  String _createUserName = '';
  String _createUserEmail = '';
  String _createPaymentMethod = 'GCash';
  String _createAccountName = '';
  String _createAccountNumber = '';
  String _createAmountStr = '';
  String _createFeeStr = '0';
  String _createReasonCategory = 'Host Payout';
  String _createReasonNote = '';
  String _createUserQrUrl = '';
  String _userSearchQuery = '';
  bool _isUserDropdownOpen = false;

  // Receipt Modal State
  bool _showReceiptModal = false;
  WithdrawalRequest? _receiptWithdrawal;

  // Dialog workflow states
  bool _showApproveConfirmModal = false;
  bool _showRejectModal = false;
  bool _isProcessing = false;
  String? _toastMessage;

  // Rejection form states
  String _selectedRejectReason = 'Invalid GCash / Maya mobile number';
  String _customRejectNote = '';

  // Copy feedback state tracker
  final Map<String, bool> _copiedFields = {};

  final List<String> _predefinedRejectReasons = [
    'Invalid GCash / Maya mobile number',
    'Recipient account unverified / limit reached',
    'Recipient account name mismatch with bank/wallet',
    'Recipient account suspended or inactive',
    'Suspected unauthorized / fraudulent cashout',
    'User requested cancellation',
    'Other (Custom text required)',
  ];

  void _playAlertChime() {
    if (!_soundEnabled) return;
    try {
      final ctx = web.AudioContext();
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);

      // Play distinctive cashout chime (660Hz -> 1100Hz)
      osc.frequency.setValueAtTime(660, ctx.currentTime);
      osc.frequency.setValueAtTime(1100, ctx.currentTime + 0.14);
      gain.gain.setValueAtTime(0.35, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.45);

      osc.start(ctx.currentTime);
      osc.stop(ctx.currentTime + 0.45);
    } catch (_) {}
  }

  void _triggerToast(String message) {
    setState(() {
      _toastMessage = message;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          if (_toastMessage == message) _toastMessage = null;
        });
      }
    });
  }

  void _copyToClipboard(String fieldKey, String text) {
    try {
      web.window.navigator.clipboard.writeText(text);
    } catch (_) {
      try {
        final textarea = web.document.createElement('textarea') as web.HTMLTextAreaElement;
        textarea.value = text;
        web.document.body?.appendChild(textarea);
        textarea.select();
        web.document.execCommand('copy');
        textarea.remove();
      } catch (_) {}
    }

    setState(() {
      _copiedFields[fieldKey] = true;
    });
    _triggerToast('Copied to clipboard: $text');

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copiedFields[fieldKey] = false;
        });
      }
    });
  }

  void _openInspector(WithdrawalRequest item) {
    setState(() {
      _inspectingWithdrawal = item;
      _zoomLevel = 1.0;
      _panX = 0.0;
      _panY = 0.0;
      _showApproveConfirmModal = false;
      _showRejectModal = false;
      _showSubmitProofModal = false;
    });
  }

  void _closeInspector() {
    setState(() {
      _inspectingWithdrawal = null;
      _inspectingTransaction = null;
      _showApproveConfirmModal = false;
      _showRejectModal = false;
      _showSubmitProofModal = false;
    });
  }

  /// Step 1: Agent Claims P2P Cashout (Locks against agent conflicts)
  Future<void> _executeClaimCashout(WithdrawalRequest req, fb.User? adminUser) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    final firestore = context.read(firestoreProvider);
    final activeAuth = context.read(firebaseAuthProvider);
    final effectiveUser = activeAuth.currentUser ?? adminUser;
    final agentUid = effectiveUser?.uid ?? 'admin_agent';
    final agentName = effectiveUser?.displayName?.isNotEmpty == true
        ? effectiveUser!.displayName!
        : (effectiveUser?.email?.isNotEmpty == true ? effectiveUser!.email! : 'Admin Agent');
    final agentPhone = '0917-888-9999';
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    try {
      final docRef = firestore.collection('withdrawal_requests').doc(req.id);
      final currentSnap = await docRef.get();
      if (currentSnap.exists) {
        final data = currentSnap.data()!;
        final currentAgent = data['agentId'];
        if (currentAgent != null && currentAgent != agentUid && data['status'] == 'AWAITING_AGENT_PAYMENT') {
          final otherName = data['agentName'] ?? 'another agent';
          _triggerToast('Order already claimed by $otherName. Conflict prevented.');
          setState(() => _isProcessing = false);
          return;
        }
      }

      // Update withdrawal request
      await docRef.set({
        'status': 'AWAITING_AGENT_PAYMENT',
        'agentId': agentUid,
        'agentName': agentName,
        'agentPhone': agentPhone,
        'claimedAt': nowMs,
        'updatedAt': nowMs,
      }, SetOptions(merge: true));

      // Update linked transaction
      try {
        final txDocRef = firestore.collection('transactions').doc('p2p_with_${req.id}');
        await txDocRef.set({
          'status': 'AWAITING_AGENT_PAYMENT',
          'desc': 'Agent $agentName claimed your order and is transferring ₱${req.amount.toStringAsFixed(2)} to your ${req.paymentMethod}.',
          'agentId': agentUid,
          'agentName': agentName,
          'updatedAt': nowMs,
        }, SetOptions(merge: true));
      } catch (_) {}

      // Write notification to user
      try {
        await firestore.collection('notifications').doc().set({
          'uid': req.uid,
          'userId': req.uid,
          'title': 'Agent Claimed Cashout Request',
          'message': 'Agent $agentName is now sending ₱${req.amount.toStringAsFixed(2)} to your ${req.paymentMethod} account ($req.userAccountNumber).',
          'body': 'Agent $agentName claimed your ₱${req.amount.toStringAsFixed(2)} cashout.',
          'type': 'P2P_CASHOUT_CLAIMED',
          'category': 'wallet',
          'withdrawalRequestId': req.id,
          'isRead': false,
          'read': false,
          'createdAt': nowMs,
          'timestamp': nowMs,
        });
      } catch (_) {}

      // Log to admin audit
      try {
        await firestore.collection('admin_audit_logs').doc().set({
          'withdrawalRequestId': req.id,
          'userId': req.uid,
          'userName': req.userName,
          'amount': req.amount,
          'paymentMethod': req.paymentMethod,
          'action': 'CLAIMED_BY_AGENT',
          'reviewedByAdminId': agentUid,
          'reviewedByAdminName': agentName,
          'timestamp': nowMs,
          'type': 'WITHDRAWAL_CLAIM',
        });
      } catch (_) {}

      _triggerToast('Cashout claimed! You are now assigned to fulfill ₱${req.amount.toStringAsFixed(2)} to ${req.userAccountName}.');
      if (_activeInterruptWithdrawal?.id == req.id) {
        _activeInterruptWithdrawal = null;
      }
    } catch (e) {
      _triggerToast('Failed to claim cashout: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleProofImageFileSelected(web.Event event) {
    final input = event.target as web.HTMLInputElement;
    final files = input.files;
    if (files == null || files.length == 0) return;
    final file = files.item(0)!;

    final reader = web.FileReader();
    reader.readAsDataURL(file);
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result != null) {
        final img = web.HTMLImageElement();
        img.src = result.toString();
        img.onLoad.listen((_) async {
          final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
          const maxDim = 1200;
          var w = img.naturalWidth;
          var h = img.naturalHeight;
          if (w > maxDim || h > maxDim) {
            if (w > h) {
              h = (h * (maxDim / w)).round();
              w = maxDim;
            } else {
              w = (w * (maxDim / h)).round();
              h = maxDim;
            }
          }
          canvas.width = w;
          canvas.height = h;
          final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
          ctx.drawImage(img, 0, 0, w, h);
          final compressedDataUrl = canvas.toDataURL('image/png');

          setState(() {
            _proofImageUrlInput = compressedDataUrl;
            _isUploadingProof = true;
          });

          // Upload to ImgBB to get a hosted URL
          try {
            final firestore = context.read(firestoreProvider);
            final imgbbUrl = await ImgBBService.uploadFile(file, firestore: firestore);
            if (mounted) {
              setState(() {
                _proofImageUrlInput = imgbbUrl;
                _isUploadingProof = false;
              });
              _triggerToast('Receipt screenshot hosted on ImgBB.');
            }
          } catch (uploadErr) {
            print('[ImgBB] File upload failed ($uploadErr), trying base64 fallback...');
            try {
              final firestore = context.read(firestoreProvider);
              final imgbbUrl = await ImgBBService.uploadBase64(compressedDataUrl, firestore: firestore);
              if (mounted) {
                setState(() {
                  _proofImageUrlInput = imgbbUrl;
                  _isUploadingProof = false;
                });
                _triggerToast('Receipt screenshot hosted on ImgBB.');
              }
            } catch (fallbackErr) {
              print('[ImgBB] Base64 upload fallback error: $fallbackErr');
              if (mounted) {
                setState(() => _isUploadingProof = false);
              }
            }
          }
        });
      }
    });
  }

  /// Step 2: Agent Submits Payout Proof & Reference Number
  Future<void> _executeSubmitProof(WithdrawalRequest req, fb.User? adminUser) async {
    final refNum = _proofReferenceNumber.trim().toUpperCase();
    if (refNum.isEmpty) {
      _triggerToast('Please provide the transaction reference number from your receipt.');
      return;
    }
    if (_proofImageUrlInput.trim().isEmpty) {
      _triggerToast('Please select or upload a transfer proof screenshot file.');
      return;
    }

    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final firestore = context.read(firestoreProvider);
    final activeAuth = context.read(firebaseAuthProvider);
    final effectiveUser = activeAuth.currentUser ?? adminUser;
    final agentUid = effectiveUser?.uid ?? 'admin_agent';
    final agentName = effectiveUser?.displayName?.isNotEmpty == true
        ? effectiveUser!.displayName!
        : (effectiveUser?.email?.isNotEmpty == true ? effectiveUser!.email! : 'Admin Agent');
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Resolve final ImgBB public URL
    String finalProofUrl = _proofImageUrlInput.trim();
    if (!finalProofUrl.startsWith('http://') && !finalProofUrl.startsWith('https://')) {
      try {
        finalProofUrl = await ImgBBService.uploadBase64(finalProofUrl, firestore: firestore);
      } catch (err) {
        print('[SubmitProof] Upload to ImgBB before commit failed: $err');
      }
    }

    try {
      final docRef = firestore.collection('withdrawal_requests').doc(req.id);
      await docRef.set({
        'status': 'PENDING_CONFIRMATION',
        'referenceNumber': refNum,
        'proofImageUrl': finalProofUrl,
        'proofSubmittedAt': nowMs,
        'action': 'PROOF_SUBMITTED',
        'agentId': req.agentId ?? agentUid,
        'agentName': agentName,
        'updatedAt': nowMs,
      }, SetOptions(merge: true));

      // Update linked transactions
      try {
        final txDocData = {
          'status': 'PENDING_CONFIRMATION',
          'referenceNumber': refNum,
          'proofImageUrl': finalProofUrl,
          'desc': 'Agent transferred ₱${req.amount.toStringAsFixed(2)} via ${req.paymentMethod} (Ref: #$refNum). Awaiting final confirmation.',
          'updatedAt': nowMs,
        };
        await firestore.collection('transactions').doc(req.id).set(txDocData, SetOptions(merge: true));
        await firestore.collection('transactions').doc('p2p_with_${req.id}').set(txDocData, SetOptions(merge: true));

        // Update /wallets/{userId}/transactions/{requestId}
        await firestore.collection('wallets').doc(req.uid).collection('transactions').doc(req.id).set(txDocData, SetOptions(merge: true));
        await firestore.collection('wallets').doc(req.uid).collection('transactions').doc('p2p_with_${req.id}').set(txDocData, SetOptions(merge: true));
      } catch (_) {}

      // Write notification for user
      try {
        await firestore.collection('notifications').doc().set({
          'uid': req.uid,
          'userId': req.uid,
          'title': 'Payout Sent — Confirm Receipt',
          'message': 'Agent sent ₱${req.amount.toStringAsFixed(2)} to your ${req.paymentMethod} (Ref #$refNum). Please check your balance.',
          'body': 'Payout sent via ${req.paymentMethod}. Ref #$refNum.',
          'type': 'P2P_CASHOUT_PROOF_SUBMITTED',
          'category': 'wallet',
          'amount': req.amount,
          'referenceNumber': refNum,
          'withdrawalRequestId': req.id,
          'isRead': false,
          'read': false,
          'createdAt': nowMs,
          'timestamp': nowMs,
        });
      } catch (_) {}

      // Admin Audit
      try {
        await firestore.collection('admin_audit_logs').doc().set({
          'withdrawalRequestId': req.id,
          'userId': req.uid,
          'userName': req.userName,
          'amount': req.amount,
          'paymentMethod': req.paymentMethod,
          'referenceNumber': refNum,
          'action': 'PROOF_SUBMITTED',
          'reviewedByAdminId': agentUid,
          'reviewedByAdminName': agentName,
          'timestamp': nowMs,
          'type': 'WITHDRAWAL_PROOF',
        });
      } catch (_) {}

      _triggerToast('Transfer proof & Ref #$refNum submitted successfully.');
      setState(() {
        _showSubmitProofModal = false;
        _proofReferenceNumber = '';
        _proofImageUrlInput = '';
      });
      _closeInspector();
    } catch (e) {
      _triggerToast('Failed to submit proof: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Step 3: Approve & Finalize Cashout
  Future<void> _executeApproveWithdrawal(WithdrawalRequest req, fb.User? adminUser) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final firestore = context.read(firestoreProvider);
    final activeAuth = context.read(firebaseAuthProvider);
    final effectiveUser = activeAuth.currentUser ?? adminUser;
    final adminUid = effectiveUser?.uid ?? 'admin_portal';
    final adminName = effectiveUser?.displayName?.isNotEmpty == true
        ? effectiveUser!.displayName!
        : (effectiveUser?.email?.isNotEmpty == true ? effectiveUser!.email! : 'Admin Staff');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final refNum = req.referenceNumber.isNotEmpty ? req.referenceNumber : 'COMPLETED';

    try {
      final docRef = firestore.collection('withdrawal_requests').doc(req.id);
      await docRef.set({
        'status': 'APPROVED',
        'adminUid': adminUid,
        'reviewedByAdminId': adminUid,
        'reviewedByAdminName': adminName,
        'verifiedAt': nowMs,
        'action': 'APPROVED',
        'updatedAt': nowMs,
      }, SetOptions(merge: true));

      try {
        await firestore.collection('withdrawals').doc(req.id).set({
          'status': 'APPROVED',
          'adminUid': adminUid,
          'reviewedByAdminId': adminUid,
          'reviewedByAdminName': adminName,
          'verifiedAt': nowMs,
          'action': 'APPROVED',
          'updatedAt': nowMs,
        }, SetOptions(merge: true));
      } catch (_) {}

      // User Wallet Sub-collection Ledger: /wallets/{userId}/transactions/{requestId}
      try {
        final walletTxData = {
          'id': req.id,
          'type': 'WITHDRAWAL',
          'direction': 'DEBIT',
          'amount': req.amount,
          'payoutMethod': req.paymentMethod,
          'paymentMethod': req.paymentMethod,
          'referenceNumber': refNum,
          'status': 'COMPLETED',
          'isPending': false,
          'updatedAt': nowMs,
          'completedAt': nowMs,
        };
        await firestore.collection('wallets').doc(req.uid).collection('transactions').doc(req.id).set(walletTxData, SetOptions(merge: true));
        await firestore.collection('wallets').doc(req.uid).collection('transactions').doc('p2p_with_${req.id}').set(walletTxData, SetOptions(merge: true));
      } catch (_) {}

      // Global Transaction Status
      try {
        final globalTxData = {
          'status': 'COMPLETED',
          'desc': 'Cashout of ₱${req.amount.toStringAsFixed(2)} completed via ${req.paymentMethod} (Ref: #$refNum)',
          'verifiedAt': nowMs,
          'adminUid': adminUid,
          'updatedAt': nowMs,
        };
        await firestore.collection('transactions').doc(req.id).set(globalTxData, SetOptions(merge: true));
        await firestore.collection('transactions').doc('p2p_with_${req.id}').set(globalTxData, SetOptions(merge: true));
      } catch (_) {}

      // Write to user ledger & subcollection
      try {
        final primaryUserDocRef = firestore.collection('users').doc(req.uid);
        final userTxData = {
          'type': 'withdraw',
          'amount': -req.amount,
          'status': 'COMPLETED',
          'referenceNumber': refNum,
          'paymentMethod': req.paymentMethod,
          'createdAt': nowMs,
          'timestamp': nowMs,
          'updatedAt': nowMs,
        };
        await primaryUserDocRef.collection('transactions').doc(req.id).set(userTxData, SetOptions(merge: true));
        await primaryUserDocRef.collection('transactions').doc('p2p_with_${req.id}').set(userTxData, SetOptions(merge: true));

        await primaryUserDocRef.collection('ledger').doc().set({
          'type': 'DEBIT',
          'category': 'p2p_withdrawal',
          'amount': req.amount,
          'referenceNumber': refNum,
          'withdrawalRequestId': req.id,
          'createdAt': nowMs,
          'timestamp': nowMs,
        }, SetOptions(merge: true));
      } catch (_) {}

      // Push Notification
      try {
        await firestore.collection('notifications').doc().set({
          'uid': req.uid,
          'userId': req.uid,
          'title': 'Withdrawal Completed! ₱${req.amount.toStringAsFixed(2)} Sent',
          'message': 'Your cashout of ₱${req.amount.toStringAsFixed(2)} via ${req.paymentMethod} (Ref #$refNum) is verified and completed.',
          'body': 'Your ₱${req.amount.toStringAsFixed(2)} withdrawal has been completed.',
          'type': 'WITHDRAWAL_COMPLETED',
          'category': 'wallet',
          'amount': req.amount,
          'referenceNumber': refNum,
          'withdrawalRequestId': req.id,
          'isRead': false,
          'read': false,
          'createdAt': nowMs,
          'timestamp': nowMs,
        });
      } catch (_) {}

      // Admin Audit Log
      try {
        await firestore.collection('admin_audit_logs').doc().set({
          'withdrawalRequestId': req.id,
          'userId': req.uid,
          'userName': req.userName,
          'userEmail': req.userEmail,
          'amount': req.amount,
          'paymentMethod': req.paymentMethod,
          'referenceNumber': refNum,
          'action': 'APPROVED',
          'reviewedByAdminId': adminUid,
          'reviewedByAdminName': adminName,
          'reviewedAt': nowMs,
          'timestamp': nowMs,
          'type': 'WITHDRAWAL_APPROVAL',
        });
      } catch (_) {}

      _triggerToast('Cashout finalized & marked as COMPLETED.');
      _closeInspector();
    } catch (e) {
      _triggerToast('Finalization failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Step 4: Reject Cashout & 100% Refund User Balance
  Future<void> _executeRejectWithdrawal(WithdrawalRequest req, fb.User? adminUser) async {
    if (_isProcessing) return;

    final isOther = _selectedRejectReason == 'Other (Custom text required)';
    final finalReason = isOther
        ? (_customRejectNote.trim().isNotEmpty ? _customRejectNote.trim() : 'Unspecified custom rejection')
        : _selectedRejectReason;

    if (isOther && _customRejectNote.trim().isEmpty) {
      _triggerToast('Please provide a specific rejection note for "Other".');
      return;
    }

    setState(() => _isProcessing = true);

    final firestore = context.read(firestoreProvider);
    final activeAuth = context.read(firebaseAuthProvider);
    final effectiveUser = activeAuth.currentUser ?? adminUser;
    final adminUid = effectiveUser?.uid ?? 'admin_portal';
    final adminName = effectiveUser?.displayName?.isNotEmpty == true
        ? effectiveUser!.displayName!
        : (effectiveUser?.email?.isNotEmpty == true ? effectiveUser!.email! : 'Admin Staff');
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    try {
      // 1. Full 100% Refund to User across all user documents & wallet stores
      final targetUserDocRefs = <DocumentReference<Map<String, dynamic>>>[
        firestore.collection('users').doc(req.uid),
      ];

      try {
        if (req.uid.isNotEmpty) {
          final qSnap = await firestore.collection('users').where('uid', isEqualTo: req.uid).get();
          for (final d in qSnap.docs) {
            if (!targetUserDocRefs.any((r) => r.id == d.id)) targetUserDocRefs.add(d.reference);
          }
        }
        if (req.userEmail.isNotEmpty) {
          final qSnap2 = await firestore.collection('users').where('email', isEqualTo: req.userEmail).get();
          for (final d in qSnap2.docs) {
            if (!targetUserDocRefs.any((r) => r.id == d.id)) targetUserDocRefs.add(d.reference);
          }
        }
      } catch (_) {}

      double currentBalance = 0.0;
      for (final uRef in targetUserDocRefs) {
        try {
          final userDocSnap = await uRef.get();
          if (userDocSnap.exists) {
            final uData = userDocSnap.data()!;
            final b = (uData['tyxBalance'] as num?)?.toDouble() ??
                (uData['availableBalance'] as num?)?.toDouble() ??
                (uData['walletBalance'] as num?)?.toDouble() ??
                (uData['balance'] as num?)?.toDouble() ??
                (uData['fiatBalance'] as num?)?.toDouble() ??
                (uData['phpBalance'] as num?)?.toDouble() ??
                0.0;
            if (b > currentBalance) currentBalance = b;
          }
        } catch (_) {}
      }

      final restoredBalance = currentBalance + req.amount;

      // Update user balances
      for (final uRef in targetUserDocRefs) {
        try {
          await uRef.set({
            'uid': req.uid,
            'name': req.userName,
            'email': req.userEmail,
            'tyxBalance': restoredBalance,
            'availableBalance': restoredBalance,
            'walletBalance': restoredBalance,
            'balance': restoredBalance,
            'fiatBalance': restoredBalance,
            'phpBalance': restoredBalance,
            'totalBalance': restoredBalance,
            'updatedAt': nowMs,
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      // Update top-level wallets collection
      try {
        await firestore.collection('wallets').doc(req.uid).set({
          'userId': req.uid,
          'uid': req.uid,
          'tyxBalance': restoredBalance,
          'balance': restoredBalance,
          'availableBalance': restoredBalance,
          'walletBalance': restoredBalance,
          'fiatBalance': restoredBalance,
          'phpBalance': restoredBalance,
          'updatedAt': nowMs,
        }, SetOptions(merge: true));
      } catch (_) {}

      // 2. Mark withdrawal request as REJECTED in all target collections
      final docRef = firestore.collection('withdrawal_requests').doc(req.id);
      await docRef.set({
        'status': 'REJECTED',
        'adminUid': adminUid,
        'reviewedByAdminId': adminUid,
        'reviewedByAdminName': adminName,
        'reviewedAt': nowMs,
        'action': 'REJECTED',
        'rejectionReason': finalReason,
        'rejectionNote': _customRejectNote.trim(),
        'verifiedAt': nowMs,
        'updatedAt': nowMs,
      }, SetOptions(merge: true));

      try {
        await firestore.collection('withdrawals').doc(req.id).set({
          'status': 'REJECTED',
          'adminUid': adminUid,
          'reviewedByAdminId': adminUid,
          'reviewedByAdminName': adminName,
          'reviewedAt': nowMs,
          'action': 'REJECTED',
          'rejectionReason': finalReason,
          'rejectionNote': _customRejectNote.trim(),
          'verifiedAt': nowMs,
          'updatedAt': nowMs,
        }, SetOptions(merge: true));
      } catch (_) {}

      // Update User Wallet Sub-collection: /wallets/{userId}/transactions/{requestId}
      try {
        final walletRejectData = {
          'status': 'REJECTED',
          'rejectionReason': finalReason,
          'isPending': false,
          'updatedAt': nowMs,
        };
        await firestore.collection('wallets').doc(req.uid).collection('transactions').doc(req.id).set(walletRejectData, SetOptions(merge: true));
        await firestore.collection('wallets').doc(req.uid).collection('transactions').doc('p2p_with_${req.id}').set(walletRejectData, SetOptions(merge: true));
      } catch (_) {}

      // 3. Update transaction to CANCELLED / REJECTED
      try {
        final txDocData = {
          'status': 'CANCELLED',
          'rejectionReason': finalReason,
          'desc': 'Cashout rejected: $finalReason. ₱${req.amount.toStringAsFixed(2)} refunded to wallet.',
          'verifiedAt': nowMs,
          'updatedAt': nowMs,
        };
        await firestore.collection('transactions').doc(req.id).set(txDocData, SetOptions(merge: true));
        await firestore.collection('transactions').doc('p2p_with_${req.id}').set(txDocData, SetOptions(merge: true));
      } catch (_) {}

      // Update user transactions subcollection
      try {
        final userTxRejectData = {
          'status': 'REJECTED',
          'rejectionReason': finalReason,
          'updatedAt': nowMs,
        };
        await firestore.collection('users').doc(req.uid).collection('transactions').doc(req.id).set(userTxRejectData, SetOptions(merge: true));
        await firestore.collection('users').doc(req.uid).collection('transactions').doc('p2p_with_${req.id}').set(userTxRejectData, SetOptions(merge: true));
      } catch (_) {}

      // 4. Send notification with refund announcement
      try {
        await firestore.collection('notifications').doc().set({
          'uid': req.uid,
          'userId': req.uid,
          'title': 'Cashout Request Rejected — 100% Refunded',
          'message': 'Your ₱${req.amount.toStringAsFixed(2)} ${req.paymentMethod} cashout was rejected ($finalReason). The funds have been refunded to your wallet balance.',
          'body': 'Cashout rejected. ₱${req.amount.toStringAsFixed(2)} refunded.',
          'type': 'WITHDRAWAL_REJECTED',
          'category': 'wallet',
          'amount': req.amount,
          'newBalance': restoredBalance,
          'reason': finalReason,
          'withdrawalRequestId': req.id,
          'isRead': false,
          'read': false,
          'createdAt': nowMs,
          'timestamp': nowMs,
        });
      } catch (_) {}

      // 5. Immutable Admin Audit Log
      try {
        await firestore.collection('admin_audit_logs').doc().set({
          'withdrawalRequestId': req.id,
          'userId': req.uid,
          'userName': req.userName,
          'userEmail': req.userEmail,
          'amount': req.amount,
          'paymentMethod': req.paymentMethod,
          'action': 'REJECTED',
          'rejectionReason': finalReason,
          'rejectionNote': _customRejectNote.trim(),
          'refundedBalance': restoredBalance,
          'reviewedByAdminId': adminUid,
          'reviewedByAdminName': adminName,
          'reviewedAt': nowMs,
          'timestamp': nowMs,
          'type': 'WITHDRAWAL_REJECTION',
        });
      } catch (_) {}

      _triggerToast('Cashout rejected. ₱${req.amount.toStringAsFixed(2)} refunded 100% to ${req.userName}.');
      _closeInspector();
    } catch (e) {
      _triggerToast('Rejection failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Step 5: Unclaim / Release Order
  Future<void> _executeUnclaimCashout(WithdrawalRequest req) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final firestore = context.read(firestoreProvider);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    try {
      final docRef = firestore.collection('withdrawal_requests').doc(req.id);
      await docRef.set({
        'status': 'WAITING_FOR_AGENT',
        'agentId': FieldValue.delete(),
        'agentName': FieldValue.delete(),
        'agentPhone': FieldValue.delete(),
        'claimedAt': FieldValue.delete(),
        'updatedAt': nowMs,
      }, SetOptions(merge: true));

      try {
        final txDocRef = firestore.collection('transactions').doc('p2p_with_${req.id}');
        await txDocRef.set({
          'status': 'WAITING_FOR_AGENT',
          'desc': 'Awaiting Payment Agent fulfillment to ${req.userAccountNumber} (${req.userAccountName})',
          'updatedAt': nowMs,
        }, SetOptions(merge: true));
      } catch (_) {}

      _triggerToast('Order released back to public queue.');
      _closeInspector();
    } catch (e) {
      _triggerToast('Failed to release order: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Step 6: Create Manual / Ad-hoc P2P Cashout
  Future<void> _executeCreateCashout(fb.User? adminUser) async {
    final amount = double.tryParse(_createAmountStr.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
    if (amount <= 0) {
      _triggerToast('Please enter a valid cashout amount greater than 0.');
      return;
    }
    if (_createAccountName.trim().isEmpty) {
      _triggerToast('Please provide recipient account name.');
      return;
    }
    if (_createAccountNumber.trim().isEmpty) {
      _triggerToast('Please provide recipient mobile / account number.');
      return;
    }

    final fee = double.tryParse(_createFeeStr.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
    final netAmount = (amount - fee) > 0 ? (amount - fee) : amount;

    setState(() => _isProcessing = true);
    final firestore = context.read(firestoreProvider);
    final activeAuth = context.read(firebaseAuthProvider);
    final effectiveUser = activeAuth.currentUser ?? adminUser;
    final adminUid = effectiveUser?.uid ?? 'admin';
    final adminEmail = effectiveUser?.email ?? 'admin@tranyx.com';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final docId = 'with_${nowMs}_${math.Random().nextInt(9000) + 1000}';

    try {
      final finalUid = _createUserId.trim().isNotEmpty ? _createUserId.trim() : 'manual_user_$nowMs';
      final finalUserName = _createUserName.trim().isNotEmpty ? _createUserName.trim() : _createAccountName.trim();
      final finalUserEmail = _createUserEmail.trim().isNotEmpty ? _createUserEmail.trim() : 'user@tranyx.com';

      // 1. Create withdrawal_requests doc
      await firestore.collection('withdrawal_requests').doc(docId).set({
        'id': docId,
        'uid': finalUid,
        'userName': finalUserName,
        'userEmail': finalUserEmail,
        'amount': amount,
        'feeAmount': fee,
        'netAmount': netAmount,
        'paymentMethod': _createPaymentMethod,
        'userAccountName': _createAccountName.trim(),
        'userAccountNumber': _createAccountNumber.trim(),
        'userQrUrl': _createUserQrUrl.trim(),
        'status': 'WAITING_FOR_AGENT',
        'notes': _createReasonNote.trim().isNotEmpty ? _createReasonNote.trim() : _createReasonCategory,
        'category': _createReasonCategory,
        'originRail': 'manual_admin_p2p',
        'createdAt': nowMs,
        'createdByAdminId': adminUid,
        'createdByAdminEmail': adminEmail,
      });

      // 2. Create platform transaction
      try {
        await firestore.collection('transactions').doc('p2p_with_$docId').set({
          'id': 'p2p_with_$docId',
          'uid': finalUid,
          'type': 'withdrawal',
          'amount': amount,
          'netAmount': netAmount,
          'feeAmount': fee,
          'status': 'WAITING_FOR_AGENT',
          'title': 'P2P Cashout ($_createPaymentMethod)',
          'desc': 'Manual Cashout: $_createReasonCategory to ${_createAccountNumber.trim()} (${_createAccountName.trim()})',
          'method': _createPaymentMethod,
          'originRail': 'manual_p2p',
          'userAccountName': _createAccountName.trim(),
          'userAccountNumber': _createAccountNumber.trim(),
          'userQrUrl': _createUserQrUrl.trim(),
          'createdAt': nowMs,
          'createdByAdmin': adminEmail,
        });
      } catch (_) {}

      // 3. User subcollection transaction
      try {
        if (_createUserId.trim().isNotEmpty) {
          await firestore.collection('users').doc(_createUserId.trim()).collection('transactions').doc('p2p_with_$docId').set({
            'id': 'p2p_with_$docId',
            'amount': amount,
            'netAmount': netAmount,
            'feeAmount': fee,
            'type': 'withdrawal',
            'category': 'p2p_withdrawal',
            'status': 'WAITING_FOR_AGENT',
            'title': 'P2P Cashout via $_createPaymentMethod',
            'description': 'Manual P2P payout request created by admin support.',
            'timestamp': nowMs,
            'createdAt': nowMs,
          });
        }
      } catch (_) {}

      // 4. Admin audit log
      try {
        await firestore.collection('admin_audit_logs').doc().set({
          'withdrawalRequestId': docId,
          'userId': finalUid,
          'userName': finalUserName,
          'amount': amount,
          'paymentMethod': _createPaymentMethod,
          'action': 'MANUAL_CASHOUT_CREATED',
          'reviewedByAdminId': adminUid,
          'reviewedByAdminName': adminEmail,
          'timestamp': nowMs,
          'type': 'MANUAL_WITHDRAWAL',
        });
      } catch (_) {}

      _triggerToast('Manual P2P Cashout created for $finalUserName (₱${amount.toStringAsFixed(2)})!');
      setState(() {
        _showCreateCashoutModal = false;
        _createUserId = '';
        _createUserName = '';
        _createUserEmail = '';
        _createAccountName = '';
        _createAccountNumber = '';
        _createAmountStr = '';
        _createFeeStr = '0';
        _createReasonNote = '';
        _createUserQrUrl = '';
        _userSearchQuery = '';
        _isUserDropdownOpen = false;
      });
    } catch (e) {
      _triggerToast('Failed to create manual cashout: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Batch claim selected waiting cashouts
  Future<void> _executeBatchClaim(List<WithdrawalRequest> items, fb.User? adminUser) async {
    final waitingItems = items.where((reqItem) => _selectedWithdrawalIds.contains(reqItem.id) && reqItem.status == 'WAITING_FOR_AGENT').toList();
    if (waitingItems.isEmpty) {
      _triggerToast('No "Waiting for Agent" requests selected to claim.');
      return;
    }
    setState(() => _isProcessing = true);
    int claimedCount = 0;
    for (final it in waitingItems) {
      try {
        await _executeClaimCashout(it, adminUser);
        claimedCount++;
      } catch (_) {}
    }
    setState(() {
      _isProcessing = false;
      _selectedWithdrawalIds.clear();
    });
    _triggerToast('Successfully claimed $claimedCount cashout request(s)!');
  }

  /// Client-side CSV export
  void _downloadCsv(List<WithdrawalRequest> items) {
    try {
      final buffer = StringBuffer();
      buffer.writeln('ID,UID,User Name,User Email,Amount,Fee,Net Amount,Method,Account Name,Account Number,Reference Number,Status,Created At,Agent Name');
      for (final it in items) {
        final dateStr = DateTime.fromMillisecondsSinceEpoch(it.createdAt).toIso8601String();
        buffer.writeln(
          '"${it.id}","${it.uid}","${it.userName.replaceAll('"', '""')}","${it.userEmail.replaceAll('"', '""')}",'
          '${it.amount},${it.feeAmount},${it.netAmount},"${it.paymentMethod}","${it.userAccountName.replaceAll('"', '""')}",'
          '"${it.userAccountNumber}","${it.referenceNumber}","${it.status}","$dateStr","${it.agentName ?? ''}"',
        );
      }
      final encodedUri = 'data:text/csv;charset=utf-8,${Uri.encodeComponent(buffer.toString())}';
      final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
      anchor.href = encodedUri;
      anchor.download = 'tranyx_p2p_cashouts_${DateTime.now().millisecondsSinceEpoch}.csv';
      web.document.body?.appendChild(anchor);
      anchor.click();
      anchor.remove();
      _triggerToast('Exported ${items.length} cashout records to CSV.');
    } catch (e) {
      _triggerToast('Failed to export CSV: $e');
    }
  }

  /// Generate clean copyable receipt text for chat/SMS support
  String _generateReceiptText(WithdrawalRequest req) {
    final dt = DateTime.fromMillisecondsSinceEpoch(req.createdAt);
    final buffer = StringBuffer();
    buffer.writeln('========================================');
    buffer.writeln('TRANYX P2P CASHOUT OFFICIAL RECEIPT');
    buffer.writeln('========================================');
    buffer.writeln('Status: ${req.status}');
    buffer.writeln('Reference #: ${req.referenceNumber.isNotEmpty ? req.referenceNumber : req.id}');
    buffer.writeln('Date/Time: ${dt.toLocal().toString()}');
    buffer.writeln('----------------------------------------');
    buffer.writeln('Recipient Name: ${req.userAccountName.isNotEmpty ? req.userAccountName : req.userName}');
    buffer.writeln('Payment Rail: ${req.paymentMethod}');
    buffer.writeln('Account Number: ${req.userAccountNumber}');
    buffer.writeln('----------------------------------------');
    buffer.writeln('Gross Amount: PHP ${req.amount.toStringAsFixed(2)}');
    if (req.feeAmount > 0) {
      buffer.writeln('Platform Fee: PHP ${req.feeAmount.toStringAsFixed(2)}');
    }
    buffer.writeln('Net Disbursed: PHP ${req.netAmount.toStringAsFixed(2)}');
    if (req.agentName != null && req.agentName!.isNotEmpty) {
      buffer.writeln('Dispatched By: ${req.agentName}');
    }
    buffer.writeln('========================================');
    buffer.writeln('Verified by Tranyx Peer-to-Peer Settlement Network');
    return buffer.toString();
  }

  Component _buildMethodBadge(String method) {
    final m = method.toLowerCase();
    String label = method;
    String icon = '💳';
    String colorClass = 'bg-zinc-100 text-zinc-700 border-zinc-200';

    if (m.contains('gcash')) {
      label = 'GCash';
      icon = '🔵';
      colorClass = 'bg-blue-50 text-blue-700 border-blue-200';
    } else if (m.contains('maya')) {
      label = 'Maya';
      icon = '🟢';
      colorClass = 'bg-emerald-50 text-emerald-700 border-emerald-200';
    } else if (m.contains('grab')) {
      label = 'GrabPay';
      icon = '🟢';
      colorClass = 'bg-emerald-50 text-emerald-800 border-emerald-300';
    } else if (m.contains('seabank')) {
      label = 'SeaBank';
      icon = '🟠';
      colorClass = 'bg-orange-50 text-orange-700 border-orange-200';
    } else if (m.contains('gotyme')) {
      label = 'GoTyme';
      icon = '🟣';
      colorClass = 'bg-purple-50 text-purple-700 border-purple-200';
    } else if (m.contains('bdo')) {
      label = 'BDO';
      icon = '🔵';
      colorClass = 'bg-blue-50 text-blue-900 border-blue-300';
    } else if (m.contains('bpi')) {
      label = 'BPI';
      icon = '🔴';
      colorClass = 'bg-red-50 text-red-700 border-red-200';
    } else if (m.contains('unionbank')) {
      label = 'UnionBank';
      icon = '🟠';
      colorClass = 'bg-amber-50 text-amber-800 border-amber-300';
    } else if (m.contains('bank')) {
      label = 'Bank Transfer';
      icon = '🏛️';
      colorClass = 'bg-zinc-100 text-zinc-800 border-zinc-300';
    }

    return span(
      classes: 'px-2 py-0.5 rounded-lg text-[10px] font-black w-fit border inline-flex items-center gap-1 $colorClass',
      [
        span([Component.text(icon)]),
        Component.text(label),
      ],
    );
  }

  String _formatTimestamp(int ms) {
    if (ms <= 0) return 'Just now';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    final formattedDate = '${months[dt.month - 1]} ${dt.day}, ${dt.year} $hour:$min $ampm';

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago ($formattedDate)';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago ($formattedDate)';
    }
    return formattedDate;
  }

  @override
  Component build(BuildContext context) {
    final withdrawalsAsync = context.watch(withdrawalRequestsStreamProvider);
    final transactionsAsync = context.watch(platformTransactionsStreamProvider);
    final depositRequestsAsync = context.watch(depositRequestsStreamProvider);
    final usersAsync = context.watch(usersStreamProvider);
    final adminUser = context.watch(adminCurrentUserProvider).value;

    final allWithdrawals = withdrawalsAsync.value ?? [];
    final allTransactions = transactionsAsync.value ?? [];
    final allDeposits = depositRequestsAsync.value ?? [];
    final usersList = usersAsync.value ?? [];

    final pendingDepositsCount = allDeposits.where((d) => !d.isOnChain && (d.status == 'PENDING_AGENT' || d.status == 'PENDING_VERIFICATION')).length;

    // Check for NEW unhandled incoming requests to trigger Interrupt Popup (Excluding On-Chain Crypto)
    final unhandledNewRequests = allWithdrawals.where((w) {
      return !w.isOnChain && (w.status == 'WAITING_FOR_AGENT' && w.agentId == null) &&
          !_acknowledgedInterruptIds.contains(w.id);
    }).toList();

    if (unhandledNewRequests.isNotEmpty && _activeInterruptWithdrawal == null) {
      final newest = unhandledNewRequests.first;
      Future.microtask(() {
        if (mounted && _activeInterruptWithdrawal == null) {
          setState(() {
            _activeInterruptWithdrawal = newest;
          });
          _playAlertChime();
        }
      });
    }

    // Counts for tabs (P2P Fiat Queues)
    final awaitingAgentCount = allWithdrawals.where((w) => !w.isOnChain && w.status == 'WAITING_FOR_AGENT').length;
    final inProgressCount = allWithdrawals.where((w) => !w.isOnChain && w.status == 'AWAITING_AGENT_PAYMENT').length;
    final pendingProofCount = allWithdrawals.where((w) => !w.isOnChain && w.status == 'PENDING_CONFIRMATION').length;
    final approvedCount = allWithdrawals.where((w) => w.status == 'APPROVED').length;
    final rejectedCount = allWithdrawals.where((w) => w.status == 'REJECTED' || w.status == 'CANCELLED').length;

    final totalVolumeApproved = allWithdrawals
        .where((w) => w.status == 'APPROVED')
        .fold<double>(0.0, (acc, item) => acc + item.amount);

    final totalVolumePending = allWithdrawals
        .where((w) => w.status == 'WAITING_FOR_AGENT' || w.status == 'AWAITING_AGENT_PAYMENT' || w.status == 'PENDING_CONFIRMATION')
        .fold<double>(0.0, (acc, item) => acc + item.amount);

    // Filter withdrawals
    final filteredWithdrawals = allWithdrawals.where((w) {
      if (_activeTab == 'awaiting_agent' && w.status != 'WAITING_FOR_AGENT') return false;
      if (_activeTab == 'in_progress' && w.status != 'AWAITING_AGENT_PAYMENT') return false;
      if (_activeTab == 'pending_proof' && w.status != 'PENDING_CONFIRMATION') return false;
      if (_activeTab == 'approved' && w.status != 'APPROVED') return false;
      if (_activeTab == 'rejected' && w.status != 'REJECTED' && w.status != 'CANCELLED') return false;

      if (_methodFilter != 'all') {
        if (!w.paymentMethod.toLowerCase().contains(_methodFilter.toLowerCase())) return false;
      }

      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final matches = w.id.toLowerCase().contains(q) ||
            w.userName.toLowerCase().contains(q) ||
            w.userEmail.toLowerCase().contains(q) ||
            w.userAccountName.toLowerCase().contains(q) ||
            w.userAccountNumber.toLowerCase().contains(q) ||
            w.referenceNumber.toLowerCase().contains(q) ||
            (w.agentName != null && w.agentName!.toLowerCase().contains(q));
        if (!matches) return false;
      }
      return true;
    }).toList();

    // Filter Platform Transactions
    final filteredTransactions = allTransactions.where((tx) {
      if (_methodFilter != 'all') {
        if (!tx.paymentMethod.toLowerCase().contains(_methodFilter.toLowerCase())) return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final matches = tx.id.toLowerCase().contains(q) ||
            tx.uid.toLowerCase().contains(q) ||
            tx.title.toLowerCase().contains(q) ||
            tx.description.toLowerCase().contains(q) ||
            tx.referenceNumber.toLowerCase().contains(q) ||
            tx.userAccountName.toLowerCase().contains(q) ||
            tx.userAccountNumber.toLowerCase().contains(q);
        if (!matches) return false;
      }
      return true;
    }).toList();

    return div(
      classes: 'p-6 lg:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full relative min-h-screen',
      [
        // Top Global Notification Toast
        if (_toastMessage != null)
          div(
            classes:
                'fixed top-6 right-6 z-[9999] px-5 py-3.5 rounded-2xl bg-zinc-900/95 text-white text-xs font-bold shadow-2xl backdrop-blur-md border border-zinc-700 flex items-center gap-3 animate-fade-in transition-all',
            [
              span(classes: 'w-2.5 h-2.5 rounded-full bg-emerald-400 animate-ping', []),
              Component.text(_toastMessage!),
            ],
          ),

        // NEW INCOMING P2P CASHOUT INTERRUPT MODAL
        if (_activeInterruptWithdrawal != null)
          _buildInterruptAlertModal(_activeInterruptWithdrawal!, adminUser),

        // Top P2P Hub Switcher Bar (Seamless transition between Deposits and Withdrawals)
        div(
          classes: 'w-full bg-white p-2 rounded-2xl border border-zinc-200/60 shadow-sm flex items-center justify-between flex-wrap gap-3',
          [
            div(classes: 'flex items-center gap-2', [
              button(
                onClick: () => Router.of(context).push('/deposits'),
                classes:
                    'px-4 py-2 rounded-xl text-xs font-bold text-zinc-600 hover:text-zinc-900 hover:bg-zinc-100/70 transition-all flex items-center gap-2 cursor-pointer',
                [
                  span([Component.text('💳 P2P Deposits')]),
                  if (pendingDepositsCount > 0)
                    span(
                      classes: 'px-2 py-0.5 rounded-full bg-zinc-200 text-zinc-800 text-[10px] font-black',
                      [Component.text('$pendingDepositsCount')],
                    ),
                ],
              ),
              button(
                onClick: () => Router.of(context).push('/withdrawals'),
                classes:
                    'px-4 py-2 rounded-xl text-xs font-bold bg-black text-white shadow-sm flex items-center gap-2 cursor-pointer',
                [
                  span([Component.text('💸 P2P Cashouts')]),
                  if (awaitingAgentCount > 0)
                    span(
                      classes: 'px-2 py-0.5 rounded-full bg-rose-500 text-white text-[10px] font-black animate-pulse',
                      [Component.text('$awaitingAgentCount')],
                    ),
                ],
              ),
            ]),
            div(classes: 'flex items-center gap-2 text-xs text-zinc-400 font-semibold pr-2', [
              span(classes: 'w-2 h-2 rounded-full bg-emerald-500 animate-pulse', []),
              Component.text('Real-time Settlement Hub Active'),
            ]),
          ],
        ),

        // Header Section
        div(
          classes: 'flex flex-col lg:flex-row lg:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5',
          [
            div(classes: 'flex flex-col gap-1', [
              div(classes: 'flex items-center gap-3', [
                div(
                  classes:
                      'w-10 h-10 rounded-2xl bg-indigo-500/10 text-indigo-600 flex items-center justify-center font-black text-lg border border-indigo-500/20 shadow-sm',
                  [Component.text('💸')],
                ),
                div([
                  h1(
                    classes: 'text-xl font-black tracking-tight text-zinc-900 flex items-center gap-2.5',
                    [
                      Component.text('P2P Cashout & Withdrawal Queue'),
                      if (awaitingAgentCount > 0)
                        span(
                          classes:
                              'px-2.5 py-0.5 rounded-full bg-rose-500 text-white text-[10px] font-black animate-pulse shadow-sm',
                          [Component.text('$awaitingAgentCount PENDING AGENT')],
                        ),
                    ],
                  ),
                  p(classes: 'text-xs text-zinc-400 font-medium', [
                    Component.text(
                      'Real-time P2P Payout Dispatch: Claim cashout orders, transfer via GCash/Maya, submit receipts, and ensure 100% user safety.',
                    ),
                  ]),
                ]),
              ]),
            ]),

            // Controls & Metrics
            div(classes: 'flex items-center gap-3 flex-wrap', [
              // ➕ New P2P Cashout Creation Button
              button(
                onClick: () => setState(() => _showCreateCashoutModal = true),
                classes:
                    'px-4 py-2.5 rounded-2xl bg-black hover:bg-zinc-800 text-white text-xs font-black flex items-center gap-2 cursor-pointer shadow-md shadow-black/10 transition-all active:scale-95',
                [
                  span(classes: 'text-sm', [Component.text('➕')]),
                  Component.text('New P2P Cashout'),
                ],
              ),

              // Audio Toggle & Test Chime
              button(
                onClick: () {
                  setState(() => _soundEnabled = !_soundEnabled);
                  if (_soundEnabled) _playAlertChime();
                },
                classes:
                    'px-3.5 py-2 rounded-2xl border border-zinc-200/70 bg-white hover:bg-zinc-50 text-xs font-bold text-zinc-700 flex items-center gap-2 cursor-pointer shadow-sm transition-all',
                attributes: {'title': _soundEnabled ? 'Mute Cashout Alert Sound' : 'Enable Alert Sound'},
                [
                  span([Component.text(_soundEnabled ? '🔔 Sound ON' : '🔕 Sound OFF')]),
                ],
              ),

              // Pending Volume Badge
              div(
                classes:
                    'px-4 py-2 bg-white border border-zinc-200/50 rounded-2xl shadow-[0_2px_8px_rgba(0,0,0,0.02)] flex items-center gap-3',
                [
                  span(classes: 'w-2 h-2 rounded-full bg-amber-500', []),
                  div(classes: 'flex flex-col', [
                    span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Pending Volume'),
                    ]),
                    span(classes: 'text-xs font-extrabold text-amber-600', [
                      Component.text('₱${totalVolumePending.toStringAsFixed(2)}'),
                    ]),
                  ]),
                ],
              ),

              // Total Volume Paid Badge
              div(
                classes:
                    'px-4 py-2 bg-white border border-zinc-200/50 rounded-2xl shadow-[0_2px_8px_rgba(0,0,0,0.02)] flex items-center gap-3',
                [
                  span(classes: 'w-2 h-2 rounded-full bg-emerald-500', []),
                  div(classes: 'flex flex-col', [
                    span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Total Disbursed'),
                    ]),
                    span(classes: 'text-xs font-extrabold text-emerald-600', [
                      Component.text('₱${totalVolumeApproved.toStringAsFixed(2)}'),
                    ]),
                  ]),
                ],
              ),
            ]),
          ],
        ),

        // Navigation Tabs & Responsive Controls
        div(classes: 'flex flex-col gap-3.5 w-full', [
          // Horizontally Scrollable Tab Bar
          div(
            classes:
                'w-full flex items-center gap-2 p-1.5 bg-white border border-zinc-200/60 rounded-2xl shadow-sm overflow-x-auto scrollbar-none scroll-smooth',
            attributes: {'style': 'scrollbar-width: none; -ms-overflow-style: none; -webkit-overflow-scrolling: touch;'},
            [
              _buildTabButton('awaiting_agent', '⚡ Awaiting Agent', count: awaitingAgentCount, isUrgent: awaitingAgentCount > 0),
              _buildTabButton('in_progress', '⏳ In-Progress (Paying)', count: inProgressCount, isWarning: inProgressCount > 0),
              _buildTabButton('pending_proof', '🔍 Verify Proof', count: pendingProofCount),
              _buildTabButton('approved', 'Disbursed / Done', count: approvedCount),
              _buildTabButton('rejected', 'Rejected / Refunded', count: rejectedCount),
              _buildTabButton('all', 'All Cashouts', count: allWithdrawals.length),
              _buildTabButton('realtime_tx', '⚡ Live Transactions', count: allTransactions.length),
            ],
          ),

          // Filters & Search Row
          div(classes: 'flex flex-col sm:flex-row sm:items-center justify-between gap-3 bg-white/70 backdrop-blur-sm p-3 rounded-2xl border border-zinc-200/50 shadow-sm', [
            // Left: Method filter & Quick stats
            div(classes: 'flex items-center gap-2.5 flex-wrap', [
              div(classes: 'relative', [
                select(
                  onChange: (dynamic val) {
                    final selectedList = val is List<String> ? val : <String>[];
                    final opt = selectedList.isNotEmpty ? selectedList.first : 'all';
                    setState(() => _methodFilter = opt);
                  },
                  classes:
                      'px-3 py-1.5 rounded-xl text-xs font-bold bg-white border border-zinc-200 text-zinc-700 focus:outline-none focus:border-zinc-400 cursor-pointer shadow-sm',
                  [
                    option(value: 'all', selected: _methodFilter == 'all', [Component.text('💳 All Rails')]),
                    option(value: 'GCash', selected: _methodFilter == 'GCash', [Component.text('🔵 GCash')]),
                    option(value: 'Maya', selected: _methodFilter == 'Maya', [Component.text('🟢 Maya')]),
                    option(value: 'GrabPay', selected: _methodFilter == 'GrabPay', [Component.text('🟢 GrabPay')]),
                    option(value: 'SeaBank', selected: _methodFilter == 'SeaBank', [Component.text('🟠 SeaBank')]),
                    option(value: 'GoTyme', selected: _methodFilter == 'GoTyme', [Component.text('🟣 GoTyme')]),
                    option(value: 'Bank', selected: _methodFilter == 'Bank', [Component.text('🏛️ Bank Transfer')]),
                  ],
                ),
              ]),

              // Quick CSV Export for current tab
              button(
                onClick: () => _downloadCsv(filteredWithdrawals),
                classes:
                    'px-3 py-1.5 rounded-xl text-xs font-bold bg-zinc-100 hover:bg-zinc-200 text-zinc-700 border border-zinc-200 flex items-center gap-1.5 cursor-pointer shadow-sm transition-all',
                attributes: {'title': 'Export filtered cashouts to CSV'},
                [
                  span([Component.text('📥')]),
                  Component.text('Export CSV'),
                ],
              ),

              span(classes: 'text-xs text-zinc-400 font-semibold', [
                Component.text(_activeTab == 'realtime_tx'
                    ? 'Showing ${filteredTransactions.length} of ${allTransactions.length} platform transactions'
                    : 'Showing ${filteredWithdrawals.length} of ${allWithdrawals.length} cashout requests'),
              ]),
            ]),

            // Right: Search input
            div(classes: 'relative w-full sm:w-72', [
              input(
                type: InputType.text,
                value: _searchQuery,
                onInput: (dynamic val) => setState(() => _searchQuery = (val as String?) ?? ''),
                attributes: {'placeholder': 'Search user, recipient phone, or ref #...'},
                classes:
                    'w-full pl-9 pr-8 py-1.5 rounded-xl text-xs bg-white border border-zinc-200 text-zinc-800 placeholder-zinc-400 focus:outline-none focus:border-zinc-400 shadow-sm',
              ),
              span(classes: 'absolute left-3 top-2 text-xs text-zinc-400 pointer-events-none', [
                Component.text('🔍'),
              ]),
              if (_searchQuery.isNotEmpty)
                button(
                  onClick: () => setState(() => _searchQuery = ''),
                  classes:
                      'absolute right-2.5 top-1.5 text-[10px] text-zinc-400 hover:text-zinc-600 bg-transparent border-0 cursor-pointer',
                  [Component.text('✕')],
                ),
            ]),
          ]),
        ]),

        // Main Content Area
        if (_activeTab == 'realtime_tx')
          _buildRealtimeTransactionsView(filteredTransactions)
        else
          _buildWithdrawalsQueueView(filteredWithdrawals, adminUser),

        // Side/Modal Inspector
        if (_inspectingWithdrawal != null)
          _buildInspectorModal(_inspectingWithdrawal!, usersList, adminUser),

        if (_inspectingTransaction != null)
          _buildTransactionDetailModal(_inspectingTransaction!),

        // Step 2 Modal: Submit Transfer Proof
        if (_showSubmitProofModal && _targetWithdrawalForProof != null)
          _buildSubmitProofModal(_targetWithdrawalForProof!, adminUser),

        // Confirm Approve Modal
        if (_showApproveConfirmModal && _inspectingWithdrawal != null)
          _buildApproveConfirmModal(_inspectingWithdrawal!, adminUser),

        // Reject Modal
        if (_showRejectModal && _inspectingWithdrawal != null)
          _buildRejectModal(_inspectingWithdrawal!, adminUser),

        // Manual P2P Cashout Modal
        if (_showCreateCashoutModal)
          _buildCreateCashoutModal(usersList, adminUser),

        // Official Branded Receipt Modal
        if (_showReceiptModal && _receiptWithdrawal != null)
          _buildReceiptModal(_receiptWithdrawal!),
      ],
    );
  }

  Component _buildTabButton(String key, String label, {int count = 0, bool isUrgent = false, bool isWarning = false}) {
    final isActive = _activeTab == key;
    return button(
      onClick: () => setState(() => _activeTab = key),
      classes:
          'px-4 py-2 rounded-xl text-xs font-bold flex items-center gap-2 whitespace-nowrap transition-all duration-200 cursor-pointer '
          '${isActive ? "bg-black text-white shadow-sm" : "bg-transparent text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900"}',
      [
        Component.text(label),
        if (count > 0)
          span(
            classes:
                'px-1.5 py-0.5 rounded-full text-[10px] font-black leading-none flex items-center justify-center '
                '${isActive ? "bg-white/20 text-white" : (isUrgent ? "bg-rose-500 text-white animate-pulse" : (isWarning ? "bg-amber-500 text-white" : "bg-zinc-200 text-zinc-700"))}',
            [Component.text('$count')],
          ),
      ],
    );
  }

  /// UN-IGNORABLE INTERRUPT POPUP ALERT FOR NEW CASHOUTS
  Component _buildInterruptAlertModal(WithdrawalRequest req, fb.User? adminUser) {
    return div(
      classes:
          'fixed inset-0 z-[9990] flex items-center justify-center bg-black/70 backdrop-blur-md p-4 animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-lg bg-white rounded-3xl p-6 shadow-2xl border-2 border-rose-500 relative flex flex-col gap-5 overflow-hidden animate-scale-up',
          [
            // Top Urgency Banner
            div(classes: 'flex items-center justify-between pb-3 border-b border-zinc-100', [
              div(classes: 'flex items-center gap-2.5', [
                div(
                  classes: 'w-3 h-3 rounded-full bg-rose-500 animate-ping',
                  [],
                ),
                h2(classes: 'text-sm font-black text-rose-600 tracking-wide uppercase', [
                  Component.text('NEW P2P CASHOUT ALERT!'),
                ]),
              ]),
              span(classes: 'text-[11px] text-zinc-400 font-bold font-mono', [
                Component.text(_formatTimestamp(req.createdAt)),
              ]),
            ]),

            // Highlighted Amount Card
            div(
              classes:
                  'p-5 rounded-2xl bg-gradient-to-br from-indigo-50 to-purple-50 border border-indigo-200/60 flex items-center justify-between',
              [
                div(classes: 'flex flex-col', [
                  span(classes: 'text-xs text-indigo-600 font-bold uppercase tracking-wider', [
                    Component.text('Requested Payout Amount'),
                  ]),
                  span(classes: 'text-3xl font-black text-indigo-900 tracking-tight', [
                    Component.text('₱${req.amount.toStringAsFixed(2)}'),
                  ]),
                ]),
                span(
                  classes:
                      'px-3 py-1.5 rounded-xl font-black text-xs '
                      '${req.paymentMethod == "GCash" ? "bg-blue-500 text-white" : "bg-emerald-500 text-white"}',
                  [Component.text(req.paymentMethod)],
                ),
              ],
            ),

            // User Recipient Details
            div(classes: 'grid grid-cols-2 gap-3 p-4 rounded-2xl bg-zinc-50 border border-zinc-200/60 text-xs', [
              div([
                span(classes: 'text-zinc-400 font-bold block', [Component.text('Recipient Name')]),
                span(classes: 'text-zinc-900 font-extrabold text-sm', [Component.text(req.userAccountName)]),
              ]),
              div([
                span(classes: 'text-zinc-400 font-bold block', [Component.text('Recipient Phone / Account')]),
                span(classes: 'text-zinc-900 font-mono font-extrabold text-sm', [Component.text(req.userAccountNumber)]),
              ]),
              div([
                span(classes: 'text-zinc-400 font-bold block', [Component.text('User Profile')]),
                span(classes: 'text-zinc-700 font-bold truncate block', [Component.text(req.userName)]),
              ]),
              div([
                span(classes: 'text-zinc-400 font-bold block', [Component.text('User Email')]),
                span(classes: 'text-zinc-700 font-mono truncate block', [Component.text(req.userEmail)]),
              ]),
            ]),

            // Action Buttons
            div(classes: 'flex items-center gap-3 pt-2', [
              button(
                onClick: () {
                  setState(() {
                    _acknowledgedInterruptIds.add(req.id);
                    _activeInterruptWithdrawal = null;
                  });
                },
                classes:
                    'flex-1 py-3 rounded-2xl border border-zinc-200 text-zinc-600 font-bold text-xs hover:bg-zinc-100 cursor-pointer transition-all',
                [Component.text('Dismiss For Now')],
              ),
              button(
                onClick: () => _executeClaimCashout(req, adminUser),
                classes:
                    'flex-1 py-3 rounded-2xl bg-indigo-600 hover:bg-indigo-700 text-white font-black text-xs shadow-lg shadow-indigo-500/20 cursor-pointer transition-all flex items-center justify-center gap-2',
                [
                  span([Component.text('⚡ Claim & Fulfill Order')]),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  /// P2P WITHDRAWAL QUEUE LIST VIEW
  Component _buildWithdrawalsQueueView(List<WithdrawalRequest> items, fb.User? adminUser) {
    if (items.isEmpty) {
      String title = 'No Cashout Requests Found';
      String subtitle = 'All P2P cashouts have been processed.';
      if (_activeTab == 'awaiting_agent') {
        title = 'No P2P Cashouts Waiting 🎉';
        subtitle = 'All users requesting withdrawals have been assigned or fulfilled.';
      } else if (_activeTab == 'in_progress') {
        title = 'No Orders Currently In-Progress';
        subtitle = 'Claim an unassigned cashout from the "Awaiting Agent" tab to begin processing payouts.';
      }

      return div(
        classes: 'w-full py-20 bg-white rounded-3xl border border-zinc-200/50 flex flex-col items-center justify-center text-center p-8 shadow-sm',
        [
          div(
            classes: 'w-16 h-16 rounded-3xl bg-zinc-100 flex items-center justify-center text-3xl mb-4 shadow-inner',
            [Component.text('💸')],
          ),
          h3(classes: 'text-base font-black text-zinc-800', [Component.text(title)]),
          p(classes: 'text-xs text-zinc-400 mt-1 max-w-sm', [Component.text(subtitle)]),
        ],
      );
    }

    final allCurrentSelected = items.isNotEmpty && items.every((reqItem) => _selectedWithdrawalIds.contains(reqItem.id));

    return div(
      classes: 'w-full bg-white rounded-3xl border border-zinc-200/60 shadow-sm overflow-hidden flex flex-col relative',
      [
        div(classes: 'overflow-x-auto', [
          table(classes: 'w-full text-left border-collapse text-xs', [
            thead(classes: 'bg-zinc-50/80 border-b border-zinc-200/60 uppercase tracking-wider text-[10px] text-zinc-400 font-black', [
              tr([
                th(classes: 'py-3.5 px-4 w-10 text-center', [
                  input(
                    type: InputType.checkbox,
                    checked: allCurrentSelected,
                    onChange: (dynamic val) {
                      setState(() {
                        if (allCurrentSelected) {
                          for (final it in items) {
                            _selectedWithdrawalIds.remove(it.id);
                          }
                        } else {
                          for (final it in items) {
                            _selectedWithdrawalIds.add(it.id);
                          }
                        }
                      });
                    },
                    classes: 'rounded border-zinc-300 text-black cursor-pointer',
                  ),
                ]),
                th(classes: 'py-3.5 px-4', [Component.text('User / Recipient')]),
                th(classes: 'py-3.5 px-4', [Component.text('Method & Target')]),
                th(classes: 'py-3.5 px-4', [Component.text('Amount (₱)')]),
                th(classes: 'py-3.5 px-4', [Component.text('Status & Agent')]),
                th(classes: 'py-3.5 px-4', [Component.text('Submitted')]),
                th(classes: 'py-3.5 px-4 text-right', [Component.text('Actions')]),
              ]),
            ]),
            tbody(classes: 'divide-y divide-zinc-100 font-medium text-zinc-700', [
              for (final item in items)
                _buildWithdrawalTableRow(item, adminUser),
            ]),
          ]),
        ]),

        // Sticky Bottom Batch Action Toolbar
        if (_selectedWithdrawalIds.isNotEmpty)
          _buildBatchActionBar(items, adminUser),
      ],
    );
  }

  Component _buildWithdrawalTableRow(WithdrawalRequest item, fb.User? adminUser) {
    final activeAuth = context.read(firebaseAuthProvider);
    final myUid = activeAuth.currentUser?.uid ?? adminUser?.uid;
    final isClaimedByMe = item.agentId != null && item.agentId == myUid;
    final isSelected = _selectedWithdrawalIds.contains(item.id);

    return tr(
      classes: 'hover:bg-zinc-50/80 transition-colors group ${isSelected ? "bg-indigo-50/40" : ""}',
      [
        // Checkbox column
        td(classes: 'py-3.5 px-4 w-10 text-center', [
          input(
            type: InputType.checkbox,
            checked: isSelected,
            onChange: (dynamic val) {
              setState(() {
                if (_selectedWithdrawalIds.contains(item.id)) {
                  _selectedWithdrawalIds.remove(item.id);
                } else {
                  _selectedWithdrawalIds.add(item.id);
                }
              });
            },
            classes: 'rounded border-zinc-300 text-black cursor-pointer',
          ),
        ]),

        // User info
        td(classes: 'py-3.5 px-4', [
          div(classes: 'flex flex-col', [
            span(classes: 'font-bold text-zinc-900 text-xs flex items-center gap-1.5', [
              Component.text(item.userAccountName.isNotEmpty ? item.userAccountName : item.userName),
            ]),
            span(classes: 'text-[11px] text-zinc-400 truncate max-w-[180px]', [Component.text(item.userEmail)]),
            span(classes: 'text-[10px] font-mono text-zinc-400', [Component.text('UID: ${item.uid.substring(0, item.uid.length > 8 ? 8 : item.uid.length)}...')]),
          ]),
        ]),

        // Method & Target account
        td(classes: 'py-3.5 px-4', [
          div(classes: 'flex flex-col gap-1', [
            _buildMethodBadge(item.paymentMethod),
            div(classes: 'flex items-center gap-1.5', [
              span(classes: 'font-mono font-bold text-xs text-zinc-900', [Component.text(item.userAccountNumber)]),
              button(
                onClick: () => _copyToClipboard('phone_${item.id}', item.userAccountNumber),
                classes: 'p-1 text-zinc-400 hover:text-zinc-700 bg-transparent border-0 cursor-pointer',
                attributes: {'title': 'Copy Phone Number'},
                [Component.text(_copiedFields['phone_${item.id}'] == true ? '✓' : '📋')],
              ),
            ]),
          ]),
        ]),

        // Amount
        td(classes: 'py-3.5 px-4', [
          div(classes: 'flex flex-col', [
            span(classes: 'font-black text-sm text-zinc-900', [Component.text('₱${item.amount.toStringAsFixed(2)}')]),
            if (item.feeAmount > 0)
              span(classes: 'text-[10px] text-zinc-400', [Component.text('Fee: ₱${item.feeAmount.toStringAsFixed(2)}')]),
          ]),
        ]),

        // Status & Agent
        td(classes: 'py-3.5 px-4', [
          div(classes: 'flex flex-col gap-1', [
            _buildStatusBadge(item.status),
            if (item.agentName != null && item.agentName!.isNotEmpty)
              span(classes: 'text-[10px] text-zinc-500 font-bold', [
                Component.text('Agent: ${item.agentName}${isClaimedByMe ? " (You)" : ""}'),
              ]),
            if (item.referenceNumber.isNotEmpty)
              span(classes: 'text-[10px] font-mono text-zinc-400', [
                Component.text('Ref: #${item.referenceNumber}'),
              ]),
          ]),
        ]),

        // Submitted timestamp
        td(classes: 'py-3.5 px-4 text-zinc-400 font-mono text-[11px]', [
          Component.text(_formatTimestamp(item.createdAt)),
        ]),

        // Action buttons
        td(classes: 'py-3.5 px-4 text-right', [
          div(classes: 'flex items-center justify-end gap-1.5 flex-wrap', [
            // Quick action based on status
            if (item.status == 'WAITING_FOR_AGENT')
              button(
                onClick: () => _executeClaimCashout(item, adminUser),
                classes:
                    'px-3 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-xs cursor-pointer shadow-sm transition-all',
                [Component.text('⚡ Claim')],
              )
            else if (item.status == 'AWAITING_AGENT_PAYMENT')
              button(
                onClick: () {
                  setState(() {
                    _targetWithdrawalForProof = item;
                    _proofReferenceNumber = '';
                    _proofImageUrlInput = '';
                    _showSubmitProofModal = true;
                  });
                },
                classes:
                    'px-3 py-1.5 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white font-bold text-xs cursor-pointer shadow-sm transition-all',
                [Component.text('📤 Proof')],
              )
            else if (item.status == 'PENDING_CONFIRMATION')
              button(
                onClick: () => _executeApproveWithdrawal(item, adminUser),
                classes:
                    'px-3 py-1.5 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white font-bold text-xs cursor-pointer shadow-sm transition-all',
                [Component.text('✓ Finalize')],
              ),

            // Official Receipt Voucher Button
            button(
              onClick: () {
                setState(() {
                  _receiptWithdrawal = item;
                  _showReceiptModal = true;
                });
              },
              classes:
                  'px-2.5 py-1.5 rounded-xl bg-zinc-100 hover:bg-zinc-200 text-zinc-700 font-bold text-xs cursor-pointer transition-all flex items-center gap-1',
              attributes: {'title': 'View Official Payout Receipt'},
              [
                span([Component.text('🧾')]),
                Component.text('Receipt'),
              ],
            ),

            // Full Details & Inspector Button
            button(
              onClick: () => _openInspector(item),
              classes:
                  'px-2.5 py-1.5 rounded-xl border border-zinc-200 hover:bg-zinc-100 text-zinc-700 font-bold text-xs cursor-pointer transition-all',
              [Component.text('Inspect 🔎')],
            ),
          ]),
        ]),
      ],
    );
  }

  Component _buildStatusBadge(String status) {
    switch (status) {
      case 'WAITING_FOR_AGENT':
        return span(
          classes: 'px-2 py-0.5 rounded-full bg-rose-50 text-rose-600 border border-rose-200 text-[10px] font-black w-fit animate-pulse',
          [Component.text('⚡ WAITING AGENT')],
        );
      case 'AWAITING_AGENT_PAYMENT':
        return span(
          classes: 'px-2 py-0.5 rounded-full bg-amber-50 text-amber-600 border border-amber-200 text-[10px] font-black w-fit',
          [Component.text('⏳ AGENT PAYING')],
        );
      case 'PENDING_CONFIRMATION':
        return span(
          classes: 'px-2 py-0.5 rounded-full bg-blue-50 text-blue-600 border border-blue-200 text-[10px] font-black w-fit',
          [Component.text('🔍 PROOF SUBMITTED')],
        );
      case 'APPROVED':
        return span(
          classes: 'px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-600 border border-emerald-200 text-[10px] font-black w-fit',
          [Component.text('✅ DISBURSED')],
        );
      case 'REJECTED':
        return span(
          classes: 'px-2 py-0.5 rounded-full bg-rose-50 text-rose-600 border border-rose-200 text-[10px] font-black w-fit',
          [Component.text('❌ REJECTED')],
        );
      case 'CANCELLED':
        return span(
          classes: 'px-2 py-0.5 rounded-full bg-zinc-100 text-zinc-600 border border-zinc-200 text-[10px] font-black w-fit',
          [Component.text('🚫 CANCELLED')],
        );
      default:
        return span(
          classes: 'px-2 py-0.5 rounded-full bg-zinc-100 text-zinc-700 text-[10px] font-black w-fit',
          [Component.text(status)],
        );
    }
  }

  /// REAL-TIME PLATFORM TRANSACTIONS VIEW
  Component _buildRealtimeTransactionsView(List<PlatformTransaction> txList) {
    if (txList.isEmpty) {
      return div(
        classes: 'w-full py-20 bg-white rounded-3xl border border-zinc-200/50 flex flex-col items-center justify-center text-center p-8 shadow-sm',
        [
          div(
            classes: 'w-16 h-16 rounded-3xl bg-zinc-100 flex items-center justify-center text-3xl mb-4 shadow-inner',
            [Component.text('⚡')],
          ),
          h3(classes: 'text-base font-black text-zinc-800', [Component.text('No Platform Transactions Found')]),
          p(classes: 'text-xs text-zinc-400 mt-1 max-w-sm', [Component.text('All real-time deposits, withdrawals, and escrows will stream here live.')]),
        ],
      );
    }

    return div(
      classes: 'w-full bg-white rounded-3xl border border-zinc-200/60 shadow-sm overflow-hidden flex flex-col',
      [
        div(classes: 'overflow-x-auto', [
          table(classes: 'w-full text-left border-collapse text-xs', [
            thead(classes: 'bg-zinc-50/80 border-b border-zinc-200/60 uppercase tracking-wider text-[10px] text-zinc-400 font-black', [
              tr([
                th(classes: 'py-3.5 px-4', [Component.text('Transaction ID / Type')]),
                th(classes: 'py-3.5 px-4', [Component.text('Title & Details')]),
                th(classes: 'py-3.5 px-4', [Component.text('Amount')]),
                th(classes: 'py-3.5 px-4', [Component.text('Status')]),
                th(classes: 'py-3.5 px-4', [Component.text('Timestamp')]),
                th(classes: 'py-3.5 px-4 text-right', [Component.text('Action')]),
              ]),
            ]),
            tbody(classes: 'divide-y divide-zinc-100 font-medium text-zinc-700', [
              for (final tx in txList)
                tr(classes: 'hover:bg-zinc-50/80 transition-colors', [
                  // ID and Type
                  td(classes: 'py-3.5 px-4', [
                    div(classes: 'flex flex-col', [
                      span(classes: 'font-mono text-zinc-900 font-bold text-[11px]', [
                        Component.text(tx.id.length > 14 ? '${tx.id.substring(0, 14)}...' : tx.id),
                      ]),
                      span(
                        classes:
                            'px-1.5 py-0.5 rounded text-[9px] font-black uppercase w-fit '
                            '${tx.type.contains("deposit") ? "bg-emerald-50 text-emerald-600" : (tx.type.contains("withdraw") ? "bg-indigo-50 text-indigo-600" : "bg-purple-50 text-purple-600")}',
                        [Component.text(tx.type)],
                      ),
                    ]),
                  ]),

                  // Details
                  td(classes: 'py-3.5 px-4', [
                    div(classes: 'flex flex-col max-w-sm', [
                      span(classes: 'font-bold text-zinc-900 text-xs', [Component.text(tx.title)]),
                      if (tx.description.isNotEmpty)
                        span(classes: 'text-[11px] text-zinc-400 truncate', [Component.text(tx.description)]),
                      if (tx.referenceNumber.isNotEmpty)
                        span(classes: 'text-[10px] font-mono text-zinc-400', [Component.text('Ref: #${tx.referenceNumber}')]),
                    ]),
                  ]),

                  // Amount
                  td(classes: 'py-3.5 px-4', [
                    span(
                      classes:
                          'font-black text-sm '
                          '${tx.amount >= 0 ? "text-emerald-600" : "text-zinc-900"}',
                      [Component.text('${tx.amount >= 0 ? "+" : ""}₱${tx.amount.abs().toStringAsFixed(2)}')],
                    ),
                  ]),

                  // Status
                  td(classes: 'py-3.5 px-4', [
                    _buildStatusBadge(tx.status),
                  ]),

                  // Timestamp
                  td(classes: 'py-3.5 px-4 text-zinc-400 font-mono text-[11px]', [
                    Component.text(_formatTimestamp(tx.createdAt)),
                  ]),

                  // Action
                  td(classes: 'py-3.5 px-4 text-right', [
                    button(
                      onClick: () => setState(() => _inspectingTransaction = tx),
                      classes:
                          'px-2.5 py-1.5 rounded-xl border border-zinc-200 hover:bg-zinc-100 text-zinc-700 font-bold text-xs cursor-pointer',
                      [Component.text('View 🔎')],
                    ),
                  ]),
                ]),
            ]),
          ]),
        ]),
      ],
    );
  }

  /// MODAL: INSPECTOR FOR WITHDRAWAL REQUEST
  Component _buildInspectorModal(WithdrawalRequest req, List<UserProfileModel> usersList, fb.User? adminUser) {
    final activeAuth = context.read(firebaseAuthProvider);
    final myUid = activeAuth.currentUser?.uid ?? adminUser?.uid;
    final isClaimedByMe = req.agentId != null && req.agentId == myUid;

    UserProfileModel? matchedUser;
    try {
      matchedUser = usersList.firstWhere((userItem) => userItem.uid == req.uid || userItem.email == req.userEmail);
    } catch (_) {}

    return div(
      classes: 'fixed inset-0 z-[9900] flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-4xl bg-white rounded-3xl shadow-2xl border border-zinc-200 overflow-hidden flex flex-col max-h-[92vh]',
          [
            // Modal Top Header
            div(classes: 'px-6 py-4 border-b border-zinc-100 flex items-center justify-between bg-zinc-50/50', [
              div(classes: 'flex items-center gap-3', [
                span(classes: 'text-2xl', [Component.text('💸')]),
                div([
                  h2(classes: 'text-base font-black text-zinc-900 flex items-center gap-2', [
                    Component.text('P2P Cashout Inspection'),
                    _buildStatusBadge(req.status),
                  ]),
                  span(classes: 'text-[11px] text-zinc-400 font-mono', [
                    Component.text('Order ID: ${req.id} • Created ${_formatTimestamp(req.createdAt)}'),
                  ]),
                ]),
              ]),
              button(
                onClick: _closeInspector,
                classes:
                    'w-8 h-8 rounded-full bg-zinc-100 hover:bg-zinc-200 text-zinc-500 hover:text-zinc-800 flex items-center justify-center font-bold text-sm border-0 cursor-pointer transition-colors',
                [Component.text('✕')],
              ),
            ]),

            // Modal Body with 2 Columns: Proofs/QRs & Payment Info
            div(classes: 'p-6 overflow-y-auto flex flex-col md:flex-row gap-6', [
              // Left Column: Visual Proofs (User QR or Agent Transfer Receipt)
              div(classes: 'flex-1 flex flex-col gap-4', [
                span(classes: 'text-xs font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text(req.proofImageUrl.isNotEmpty ? 'Agent Payout Transfer Proof' : (req.userQrUrl.isNotEmpty ? 'Recipient Receiving QR' : 'Visual Credentials')),
                ]),

                if (req.proofImageUrl.isNotEmpty) ...[
                  div(
                    classes: 'relative w-full aspect-square rounded-2xl bg-zinc-900 border border-zinc-800 overflow-hidden flex items-center justify-center group',
                    [
                      img(
                        src: req.proofImageUrl,
                        alt: 'Agent Payout Proof',
                        classes: 'w-full h-full object-contain transition-transform duration-200',
                        attributes: {
                          'style': 'transform: scale($_zoomLevel) translate(${_panX}px, ${_panY}px);',
                        },
                      ),
                      // Zoom Overlay Controls
                      div(
                        classes: 'absolute bottom-3 right-3 flex items-center gap-1.5 bg-black/70 backdrop-blur-md p-1.5 rounded-xl border border-white/10 shadow-lg',
                        [
                          button(
                            onClick: () => setState(() => _zoomLevel = (_zoomLevel - 0.5).clamp(1.0, 3.0)),
                            classes: 'w-7 h-7 rounded-lg bg-white/10 hover:bg-white/20 text-white font-bold text-xs flex items-center justify-center cursor-pointer border-0',
                            [Component.text('−')],
                          ),
                          span(classes: 'text-[11px] font-mono font-bold text-white px-1', [
                            Component.text('${_zoomLevel.toStringAsFixed(1)}x'),
                          ]),
                          button(
                            onClick: () => setState(() => _zoomLevel = (_zoomLevel + 0.5).clamp(1.0, 3.0)),
                            classes: 'w-7 h-7 rounded-lg bg-white/10 hover:bg-white/20 text-white font-bold text-xs flex items-center justify-center cursor-pointer border-0',
                            [Component.text('+')],
                          ),
                          button(
                            onClick: () => web.window.open(req.proofImageUrl, '_blank'),
                            classes: 'w-7 h-7 rounded-lg bg-white/10 hover:bg-white/20 text-white font-bold text-xs flex items-center justify-center cursor-pointer border-0',
                            attributes: {'title': 'Open Image in Full Tab'},
                            [Component.text('↗')],
                          ),
                        ],
                      ),
                    ],
                  ),
                ] else if (req.userQrUrl.isNotEmpty) ...[
                  div(
                    classes: 'relative w-full aspect-square rounded-2xl bg-zinc-900 border border-zinc-800 overflow-hidden flex items-center justify-center',
                    [
                      img(
                        src: req.userQrUrl,
                        alt: 'User Receiving QR',
                        classes: 'w-full h-full object-contain',
                      ),
                      div(
                        classes: 'absolute bottom-3 right-3 flex items-center gap-1.5 bg-black/70 backdrop-blur-md p-1.5 rounded-xl',
                        [
                          button(
                            onClick: () => web.window.open(req.userQrUrl, '_blank'),
                            classes: 'px-2.5 py-1 rounded-lg bg-white/10 text-white text-xs font-bold border-0 cursor-pointer',
                            [Component.text('Open QR ↗')],
                          ),
                        ],
                      ),
                    ],
                  ),
                ] else ...[
                  div(
                    classes: 'w-full aspect-square rounded-2xl bg-zinc-50 border border-dashed border-zinc-300 flex flex-col items-center justify-center text-center p-6',
                    [
                      span(classes: 'text-3xl mb-2 text-zinc-400', [Component.text('📱')]),
                      h4(classes: 'text-xs font-bold text-zinc-600', [Component.text('Direct Mobile / Account Transfer')]),
                      p(classes: 'text-[11px] text-zinc-400 mt-1 max-w-[200px]', [
                        Component.text('No receipt image attached yet. Send payout directly to recipient mobile number below.'),
                      ]),
                    ],
                  ),
                ],
              ]),

              // Right Column: Full Recipient Details & Action Controls
              div(classes: 'flex-1 flex flex-col gap-4', [
                span(classes: 'text-xs font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Payout Details & Recipient'),
                ]),

                // Amount & Fee Box
                div(classes: 'p-4 rounded-2xl bg-zinc-50 border border-zinc-200/80 flex flex-col gap-3', [
                  div(classes: 'flex items-center justify-between', [
                    span(classes: 'text-xs text-zinc-500 font-bold', [Component.text('Gross Cashout Amount')]),
                    span(classes: 'text-xl font-black text-zinc-900', [Component.text('₱${req.amount.toStringAsFixed(2)}')]),
                  ]),
                  div(classes: 'flex items-center justify-between text-xs', [
                    span(classes: 'text-zinc-400 font-medium', [Component.text('Platform Fee (2%)')]),
                    span(classes: 'font-mono text-zinc-600 font-bold', [Component.text('₱${req.feeAmount.toStringAsFixed(2)}')]),
                  ]),
                  div(classes: 'border-t border-zinc-200 pt-2 flex items-center justify-between text-xs', [
                    span(classes: 'text-indigo-600 font-extrabold', [Component.text('Net Transfer To Recipient')]),
                    span(classes: 'font-mono font-black text-indigo-700 text-sm', [Component.text('₱${req.netAmount.toStringAsFixed(2)}')]),
                  ]),
                ]),

                // Recipient Credentials Card with Quick Copy
                div(classes: 'p-4 rounded-2xl border border-zinc-200 flex flex-col gap-3', [
                  div(classes: 'flex items-center justify-between', [
                    div(classes: 'flex flex-col', [
                      span(classes: 'text-[10px] text-zinc-400 uppercase font-black', [Component.text('Recipient Name')]),
                      span(classes: 'font-bold text-sm text-zinc-900', [Component.text(req.userAccountName)]),
                    ]),
                    button(
                      onClick: () => _copyToClipboard('insp_name_${req.id}', req.userAccountName),
                      classes: 'px-2.5 py-1 rounded-xl bg-zinc-100 hover:bg-zinc-200 text-xs font-bold text-zinc-700 border-0 cursor-pointer',
                      [Component.text(_copiedFields['insp_name_${req.id}'] == true ? 'Copied ✓' : 'Copy Name')],
                    ),
                  ]),

                  div(classes: 'flex items-center justify-between', [
                    div(classes: 'flex flex-col', [
                      span(classes: 'text-[10px] text-zinc-400 uppercase font-black', [Component.text('${req.paymentMethod} Mobile / Account')]),
                      span(classes: 'font-mono font-black text-sm text-zinc-900', [Component.text(req.userAccountNumber)]),
                    ]),
                    button(
                      onClick: () => _copyToClipboard('insp_phone_${req.id}', req.userAccountNumber),
                      classes: 'px-2.5 py-1 rounded-xl bg-indigo-50 hover:bg-indigo-100 text-xs font-bold text-indigo-700 border-0 cursor-pointer',
                      [Component.text(_copiedFields['insp_phone_${req.id}'] == true ? 'Copied ✓' : 'Copy Phone')],
                    ),
                  ]),

                  if (req.referenceNumber.isNotEmpty)
                    div(classes: 'flex items-center justify-between border-t border-zinc-100 pt-2', [
                      div(classes: 'flex flex-col', [
                        span(classes: 'text-[10px] text-zinc-400 uppercase font-black', [Component.text('Agent Transfer Ref #')]),
                        span(classes: 'font-mono font-bold text-xs text-zinc-900', [Component.text(req.referenceNumber)]),
                      ]),
                      button(
                        onClick: () => _copyToClipboard('insp_ref_${req.id}', req.referenceNumber),
                        classes: 'px-2.5 py-1 rounded-xl bg-zinc-100 hover:bg-zinc-200 text-xs font-bold text-zinc-700 border-0 cursor-pointer',
                        [Component.text(_copiedFields['insp_ref_${req.id}'] == true ? 'Copied ✓' : 'Copy Ref')],
                      ),
                    ]),
                ]),

                // User Profile & Security Details
                div(classes: 'p-3.5 rounded-2xl bg-zinc-50/70 border border-zinc-200 text-xs flex flex-col gap-2', [
                  span(classes: 'text-[10px] text-zinc-400 uppercase font-black', [Component.text('User Security & Balance Check')]),
                  div(classes: 'flex justify-between items-center', [
                    span(classes: 'text-zinc-500 font-medium', [Component.text('KYC Verification')]),
                    span(
                      classes:
                          'px-2 py-0.5 rounded-full text-[10px] font-black '
                          '${(matchedUser?.idVerified == true || (matchedUser?.verificationLevel ?? 0) >= 2) ? "bg-emerald-100 text-emerald-800" : "bg-amber-100 text-amber-800"}',
                      [Component.text((matchedUser?.idVerified == true || (matchedUser?.verificationLevel ?? 0) >= 2) ? "✓ KYC VERIFIED" : "UNVERIFIED")],
                    ),
                  ]),
                  div(classes: 'flex justify-between items-center', [
                    span(classes: 'text-zinc-500 font-medium', [Component.text('Current Wallet Balance')]),
                    span(classes: 'font-mono font-bold text-zinc-800', [
                      Component.text('₱${(matchedUser?.availableBalance ?? 0.0).toStringAsFixed(2)}'),
                    ]),
                  ]),
                  if (matchedUser != null && matchedUser.availableBalance < req.amount)
                    div(classes: 'p-2 rounded-xl bg-amber-50 border border-amber-200 text-[11px] text-amber-800 font-semibold flex items-center gap-1.5', [
                      span([Component.text('⚠️')]),
                      Component.text('Note: Requested ₱${req.amount.toStringAsFixed(2)} exceeds live user balance (₱${matchedUser.availableBalance.toStringAsFixed(2)}).'),
                    ]),
                ]),

                if (req.notes != null && req.notes!.isNotEmpty)
                  div(classes: 'p-3.5 rounded-2xl bg-zinc-50 border border-zinc-200 text-xs flex flex-col gap-1', [
                    span(classes: 'font-black text-zinc-500 text-[10px] uppercase', [Component.text('Order Note / Reason')]),
                    span(classes: 'font-semibold text-zinc-800', [Component.text(req.notes!)]),
                  ]),

                if (req.rejectionReason != null && req.rejectionReason!.isNotEmpty)
                  div(classes: 'p-3.5 rounded-2xl bg-rose-50 border border-rose-200 text-xs flex flex-col gap-1', [
                    span(classes: 'font-black text-rose-700 text-[10px] uppercase', [Component.text('Rejection Reason')]),
                    span(classes: 'font-bold text-rose-900', [Component.text(req.rejectionReason!)]),
                    if (req.rejectionNote != null && req.rejectionNote!.isNotEmpty)
                      span(classes: 'text-rose-700 text-[11px]', [Component.text('Note: ${req.rejectionNote!}')]),
                  ]),
              ]),
            ]),

            // Modal Bottom Actions
            div(classes: 'px-6 py-4 border-t border-zinc-100 bg-zinc-50 flex items-center justify-between gap-3 flex-wrap', [
              // Left: Secondary actions (Release, Reject, Receipt)
              div(classes: 'flex items-center gap-2 flex-wrap', [
                button(
                  onClick: () {
                    setState(() {
                      _receiptWithdrawal = req;
                      _showReceiptModal = true;
                    });
                  },
                  classes:
                      'px-3.5 py-2 rounded-2xl border border-zinc-200 bg-white hover:bg-zinc-100 text-zinc-700 font-bold text-xs cursor-pointer transition-all flex items-center gap-1.5',
                  [
                    span([Component.text('🧾')]),
                    Component.text('Receipt Voucher'),
                  ],
                ),

                if (req.status != 'APPROVED' && req.status != 'REJECTED' && req.status != 'CANCELLED')
                  button(
                    onClick: () => setState(() => _showRejectModal = true),
                    classes:
                        'px-4 py-2 rounded-2xl border border-rose-200 bg-white hover:bg-rose-50 text-rose-600 font-bold text-xs cursor-pointer transition-all',
                    [Component.text('Reject & Refund 100%')],
                  ),

                if (req.status == 'AWAITING_AGENT_PAYMENT' && isClaimedByMe)
                  button(
                    onClick: () => _executeUnclaimCashout(req),
                    classes:
                        'px-3.5 py-2 rounded-2xl border border-zinc-200 bg-white hover:bg-zinc-100 text-zinc-600 font-bold text-xs cursor-pointer transition-all',
                    [Component.text('Release Order')],
                  ),
              ]),

              // Right: Primary Step Progression Actions
              div(classes: 'flex items-center gap-2', [
                if (req.status == 'WAITING_FOR_AGENT')
                  button(
                    onClick: () => _executeClaimCashout(req, adminUser),
                    classes:
                        'px-5 py-2.5 rounded-2xl bg-indigo-600 hover:bg-indigo-700 text-white font-black text-xs cursor-pointer shadow-md shadow-indigo-500/20 transition-all',
                    [Component.text('⚡ Claim Cashout Request')],
                  )
                else if (req.status == 'AWAITING_AGENT_PAYMENT')
                  button(
                    onClick: () {
                      setState(() {
                        _targetWithdrawalForProof = req;
                        _proofReferenceNumber = '';
                        _proofImageUrlInput = '';
                        _showSubmitProofModal = true;
                      });
                    },
                    classes:
                        'px-5 py-2.5 rounded-2xl bg-emerald-600 hover:bg-emerald-700 text-white font-black text-xs cursor-pointer shadow-md shadow-emerald-500/20 transition-all',
                    [Component.text('📤 Submit Transfer Proof & Ref #')],
                  )
                else if (req.status == 'PENDING_CONFIRMATION')
                  button(
                    onClick: () => setState(() => _showApproveConfirmModal = true),
                    classes:
                        'px-5 py-2.5 rounded-2xl bg-emerald-600 hover:bg-emerald-700 text-white font-black text-xs cursor-pointer shadow-md shadow-emerald-500/20 transition-all',
                    [Component.text('✓ Confirm & Finalize Payout')],
                  ),
              ]),
            ]),
          ],
        ),
      ],
    );
  }

  /// MODAL: SUBMIT TRANSFER PROOF & REFERENCE NUMBER (AGENT DISBURSEMENT)
  Component _buildSubmitProofModal(WithdrawalRequest req, fb.User? adminUser) {
    return div(
      classes: 'fixed inset-0 z-[9950] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4 animate-fade-in',
      [
        div(
          classes: 'w-full max-w-lg bg-white rounded-3xl shadow-2xl border border-zinc-200 p-6 flex flex-col gap-5 animate-scale-up',
          [
            div(classes: 'flex items-center justify-between border-b border-zinc-100 pb-3', [
              h3(classes: 'text-sm font-black text-zinc-900', [Component.text('Submit Payout Receipt & Reference #')]),
              button(
                onClick: () => setState(() => _showSubmitProofModal = false),
                classes: 'w-7 h-7 rounded-full bg-zinc-100 text-zinc-500 flex items-center justify-center font-bold text-xs border-0 cursor-pointer',
                [Component.text('✕')],
              ),
            ]),

            // Payout Summary
            div(classes: 'p-4 rounded-2xl bg-indigo-50 border border-indigo-200 flex items-center justify-between text-xs', [
              div([
                span(classes: 'text-indigo-500 font-bold block', [Component.text('Disbursement Target')]),
                span(classes: 'text-indigo-950 font-black text-sm', [Component.text('${req.paymentMethod}: ${req.userAccountNumber}')]),
              ]),
              div(classes: 'text-right', [
                span(classes: 'text-indigo-500 font-bold block', [Component.text('Amount')]),
                span(classes: 'text-indigo-950 font-black text-base', [Component.text('₱${req.amount.toStringAsFixed(2)}')]),
              ]),
            ]),

            // Form Inputs
            div(classes: 'flex flex-col gap-4 text-xs', [
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'font-bold text-zinc-700', [
                  Component.text('GCash / Maya Reference Number *'),
                ]),
                input(
                  type: InputType.text,
                  value: _proofReferenceNumber,
                  onInput: (dynamic val) => setState(() => _proofReferenceNumber = (val as String?) ?? ''),
                  attributes: {'placeholder': 'e.g. 100293847561'},
                  classes: 'w-full px-4 py-2.5 rounded-2xl border border-zinc-300 font-mono font-bold text-xs focus:outline-none focus:border-indigo-500',
                ),
              ]),

              // Transfer Proof File Upload
              div(classes: 'flex flex-col gap-2', [
                div(classes: 'flex items-center justify-between', [
                  label(classes: 'font-bold text-zinc-700', [
                    Component.text('Transfer Proof Screenshot *'),
                  ]),
                  if (_isUploadingProof)
                    span(classes: 'inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-amber-50 text-amber-700 border border-amber-200/60 text-[10px] font-extrabold', [
                      span(classes: 'w-1.5 h-1.5 rounded-full bg-amber-500 animate-pulse', []),
                      Component.text('Uploading to ImgBB...'),
                    ])
                  else if (_proofImageUrlInput.isNotEmpty)
                    span(classes: 'inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-emerald-50 text-[#0fa958] border border-emerald-200/60 text-[10px] font-extrabold', [
                      span(classes: 'w-1.5 h-1.5 rounded-full bg-[#0fa958]', []),
                      Component.text(_proofImageUrlInput.startsWith('http') ? '✓ Hosted on ImgBB' : 'File Attached'),
                    ]),
                ]),

                // Hidden Native File Input
                input(
                  type: InputType.file,
                  id: 'withdrawalProofFileInput',
                  attributes: {'accept': 'image/png,image/jpeg,image/jpg,image/webp'},
                  events: {'change': _handleProofImageFileSelected},
                  classes: 'hidden',
                ),

                if (_proofImageUrlInput.isEmpty)
                  // Dropzone / File Picker Container
                  div(
                    events: {
                      'click': (_) {
                        final fileInput = web.document.getElementById('withdrawalProofFileInput') as web.HTMLInputElement?;
                        fileInput?.click();
                      }
                    },
                    classes:
                        'p-6 rounded-2xl border-2 border-dashed border-zinc-200 hover:border-emerald-500/80 bg-zinc-50/60 hover:bg-emerald-50/30 transition-all cursor-pointer flex flex-col items-center justify-center gap-2 text-center group',
                    [
                      div(
                        classes:
                            'w-11 h-11 rounded-2xl bg-white border border-zinc-200 shadow-sm flex items-center justify-center text-xl group-hover:scale-105 transition-all text-emerald-600',
                        [Component.text('📎')],
                      ),
                      div(classes: 'flex flex-col gap-0.5', [
                        span(classes: 'text-xs font-bold text-zinc-700 group-hover:text-emerald-700 transition-colors', [
                          Component.text('Click to browse or drop screenshot file'),
                        ]),
                        span(classes: 'text-[11px] text-zinc-400 font-medium', [
                          Component.text('PNG, JPG, or WEBP receipts'),
                        ]),
                      ]),
                    ],
                  )
                else
                  // Interactive Preview Card
                  div(
                    classes: 'p-3.5 rounded-2xl bg-zinc-50 border border-zinc-200 flex flex-col gap-3',
                    [
                      div(classes: 'relative rounded-xl overflow-hidden bg-black/5 border border-zinc-200/80 flex items-center justify-center max-h-48 p-2', [
                        img(
                          src: _proofImageUrlInput,
                          classes: 'max-h-44 w-auto object-contain rounded-lg shadow-sm',
                          attributes: {'alt': 'Transfer Proof Preview'},
                        ),
                      ]),
                      div(classes: 'flex items-center justify-between gap-2 pt-0.5', [
                        button(
                          onClick: () {
                            final fileInput = web.document.getElementById('withdrawalProofFileInput') as web.HTMLInputElement?;
                            fileInput?.click();
                          },
                          classes:
                              'px-3 py-1.5 rounded-xl bg-white hover:bg-zinc-100 text-zinc-700 border border-zinc-200 text-xs font-bold transition-all cursor-pointer flex items-center gap-1.5',
                          [
                            Component.text('🔄 Replace File'),
                          ],
                        ),
                        button(
                          onClick: () => setState(() => _proofImageUrlInput = ''),
                          classes:
                              'px-3 py-1.5 rounded-xl bg-red-50 hover:bg-red-100 text-red-600 border border-red-200/60 text-xs font-bold transition-all cursor-pointer flex items-center gap-1.5',
                          [
                            Component.text('✕ Remove'),
                          ],
                        ),
                      ]),
                    ],
                  ),
              ]),
            ]),

            // Modal Actions
            div(classes: 'flex items-center gap-3 pt-2', [
              button(
                onClick: () => setState(() => _showSubmitProofModal = false),
                classes: 'flex-1 py-3 rounded-2xl border border-zinc-200 text-zinc-600 font-bold text-xs hover:bg-zinc-100 cursor-pointer',
                [Component.text('Cancel')],
              ),
              button(
                onClick: () => _executeSubmitProof(req, adminUser),
                classes:
                    'flex-1 py-3 rounded-2xl bg-emerald-600 hover:bg-emerald-700 text-white font-black text-xs shadow-md shadow-emerald-500/20 cursor-pointer transition-all flex items-center justify-center gap-2',
                [
                  if (_isProcessing)
                    span(classes: 'animate-spin', [Component.text('⏳')])
                  else
                    Component.text('Confirm & Send Proof ✓'),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  /// MODAL: APPROVE CONFIRMATION
  Component _buildApproveConfirmModal(WithdrawalRequest req, fb.User? adminUser) {
    return div(
      classes: 'fixed inset-0 z-[9960] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4 animate-fade-in',
      [
        div(
          classes: 'w-full max-w-md bg-white rounded-3xl shadow-2xl border border-zinc-200 p-6 flex flex-col gap-4 animate-scale-up',
          [
            div(classes: 'w-12 h-12 rounded-2xl bg-emerald-100 text-emerald-600 flex items-center justify-center text-2xl mx-auto', [
              Component.text('✓'),
            ]),
            h3(classes: 'text-base font-black text-zinc-900 text-center', [Component.text('Finalize Cashout Payout?')]),
            p(classes: 'text-xs text-zinc-500 text-center leading-relaxed', [
              Component.text(
                'Are you sure you want to mark ₱${req.amount.toStringAsFixed(2)} to ${req.userAccountName} (${req.userAccountNumber}) as COMPLETED? User will receive a completion push notification.',
              ),
            ]),
            div(classes: 'flex items-center gap-3 pt-3', [
              button(
                onClick: () => setState(() => _showApproveConfirmModal = false),
                classes: 'flex-1 py-3 rounded-2xl border border-zinc-200 text-zinc-600 font-bold text-xs hover:bg-zinc-100 cursor-pointer',
                [Component.text('Cancel')],
              ),
              button(
                onClick: () => _executeApproveWithdrawal(req, adminUser),
                classes:
                    'flex-1 py-3 rounded-2xl bg-emerald-600 hover:bg-emerald-700 text-white font-black text-xs shadow-md shadow-emerald-500/20 cursor-pointer transition-all flex items-center justify-center gap-2',
                [
                  if (_isProcessing)
                    span(classes: 'animate-spin', [Component.text('⏳')])
                  else
                    Component.text('Yes, Finalize Payout ✓'),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  /// MODAL: REJECT WITH 100% REFUND SAFETY GUARANTEE
  Component _buildRejectModal(WithdrawalRequest req, fb.User? adminUser) {
    final isOther = _selectedRejectReason == 'Other (Custom text required)';

    return div(
      classes: 'fixed inset-0 z-[9960] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4 animate-fade-in',
      [
        div(
          classes: 'w-full max-w-md bg-white rounded-3xl shadow-2xl border border-rose-200 p-6 flex flex-col gap-4 animate-scale-up',
          [
            div(classes: 'w-12 h-12 rounded-2xl bg-rose-100 text-rose-600 flex items-center justify-center text-2xl mx-auto', [
              Component.text('⚠️'),
            ]),
            h3(classes: 'text-base font-black text-zinc-900 text-center', [Component.text('Reject Cashout Request')]),
            p(classes: 'text-xs text-zinc-500 text-center leading-relaxed', [
              Component.text(
                'Rejecting will immediately refund 100% of ₱${req.amount.toStringAsFixed(2)} back to ${req.userName}\'s wallet. Please select a clear reason.',
              ),
            ]),

            // Reason selector
            div(classes: 'flex flex-col gap-2 text-xs', [
              label(classes: 'font-bold text-zinc-700', [Component.text('Reason for Rejection *')]),
              select(
                onChange: (dynamic val) {
                  final selectedList = val is List<String> ? val : <String>[];
                  final opt = selectedList.isNotEmpty ? selectedList.first : _predefinedRejectReasons.first;
                  setState(() => _selectedRejectReason = opt);
                },
                classes: 'w-full px-3.5 py-2.5 rounded-xl border border-zinc-300 text-xs font-medium focus:outline-none focus:border-rose-500 bg-white',
                [
                  for (final reason in _predefinedRejectReasons)
                    option(value: reason, selected: _selectedRejectReason == reason, [Component.text(reason)]),
                ],
              ),

              if (isOther)
                div(classes: 'flex flex-col gap-1 mt-2', [
                  label(classes: 'font-bold text-zinc-700', [Component.text('Custom Rejection Note *')]),
                  textarea(
                    onInput: (dynamic val) => setState(() => _customRejectNote = (val as String?) ?? ''),
                    attributes: {'placeholder': 'Explain specific reason for refund...'},
                    classes: 'w-full px-3.5 py-2 rounded-xl border border-zinc-300 text-xs focus:outline-none focus:border-rose-500 h-20',
                    [],
                  ),
                ]),
            ]),

            // Action Buttons
            div(classes: 'flex items-center gap-3 pt-3', [
              button(
                onClick: () => setState(() => _showRejectModal = false),
                classes: 'flex-1 py-3 rounded-2xl border border-zinc-200 text-zinc-600 font-bold text-xs hover:bg-zinc-100 cursor-pointer',
                [Component.text('Cancel')],
              ),
              button(
                onClick: () => _executeRejectWithdrawal(req, adminUser),
                classes:
                    'flex-1 py-3 rounded-2xl bg-rose-600 hover:bg-rose-700 text-white font-black text-xs shadow-md shadow-rose-500/20 cursor-pointer transition-all flex items-center justify-center gap-2',
                [
                  if (_isProcessing)
                    span(classes: 'animate-spin', [Component.text('⏳')])
                  else
                    Component.text('Reject & Refund User ✓'),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  /// MODAL: PLATFORM TRANSACTION DETAIL
  Component _buildTransactionDetailModal(PlatformTransaction tx) {
    return div(
      classes: 'fixed inset-0 z-[9900] flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-fade-in',
      [
        div(
          classes: 'w-full max-w-lg bg-white rounded-3xl shadow-2xl border border-zinc-200 p-6 flex flex-col gap-4 animate-scale-up',
          [
            div(classes: 'flex items-center justify-between border-b border-zinc-100 pb-3', [
              div(classes: 'flex items-center gap-2.5', [
                span(classes: 'text-xl', [Component.text('⚡')]),
                h3(classes: 'text-sm font-black text-zinc-900', [Component.text('Transaction Details')]),
              ]),
              button(
                onClick: () => setState(() => _inspectingTransaction = null),
                classes: 'w-7 h-7 rounded-full bg-zinc-100 text-zinc-500 flex items-center justify-center font-bold text-xs border-0 cursor-pointer',
                [Component.text('✕')],
              ),
            ]),

            div(classes: 'grid grid-cols-2 gap-3 p-4 rounded-2xl bg-zinc-50 border border-zinc-200/80 text-xs', [
              div([
                span(classes: 'text-zinc-400 font-bold block', [Component.text('Transaction ID')]),
                span(classes: 'text-zinc-900 font-mono font-bold text-[11px]', [Component.text(tx.id)]),
              ]),
              div([
                span(classes: 'text-zinc-400 font-bold block', [Component.text('Status')]),
                _buildStatusBadge(tx.status),
              ]),
              div([
                span(classes: 'text-zinc-400 font-bold block', [Component.text('Amount')]),
                span(classes: 'text-zinc-900 font-black text-sm', [Component.text('₱${tx.amount.abs().toStringAsFixed(2)}')]),
              ]),
              div([
                span(classes: 'text-zinc-400 font-bold block', [Component.text('Category / Type')]),
                span(classes: 'text-zinc-900 font-bold uppercase', [Component.text(tx.type)]),
              ]),
              div([
                span(classes: 'text-zinc-400 font-bold block', [Component.text('Method / Rail')]),
                span(classes: 'text-zinc-900 font-bold', [Component.text('${tx.paymentMethod} (${tx.originRail})')]),
              ]),
              div([
                span(classes: 'text-zinc-400 font-bold block', [Component.text('Timestamp')]),
                span(classes: 'text-zinc-900 font-mono text-[11px]', [Component.text(_formatTimestamp(tx.createdAt))]),
              ]),
            ]),

            if (tx.description.isNotEmpty)
              div(classes: 'p-3 rounded-2xl bg-zinc-50 border border-zinc-200 text-xs', [
                span(classes: 'text-zinc-400 font-bold block mb-1', [Component.text('Description')]),
                span(classes: 'text-zinc-700 leading-relaxed', [Component.text(tx.description)]),
              ]),

            div(classes: 'flex justify-end pt-2', [
              button(
                onClick: () => setState(() => _inspectingTransaction = null),
                classes: 'px-5 py-2.5 rounded-2xl bg-zinc-900 hover:bg-black text-white font-bold text-xs cursor-pointer',
                [Component.text('Close')],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  /// BATCH ACTION TOOLBAR FOR SELECTED CASHOUT REQUESTS
  Component _buildBatchActionBar(List<WithdrawalRequest> items, fb.User? adminUser) {
    final selectedCount = _selectedWithdrawalIds.length;
    final selectedItems = items.where((reqItem) => _selectedWithdrawalIds.contains(reqItem.id)).toList();
    final waitingSelected = selectedItems.where((reqItem) => reqItem.status == 'WAITING_FOR_AGENT').length;
    final totalSelectedAmount = selectedItems.fold<double>(0.0, (acc, reqItem) => acc + reqItem.amount);

    return div(
      classes:
          'sticky bottom-4 mx-4 mt-3 z-40 bg-zinc-950 text-white p-4 rounded-3xl shadow-2xl border border-zinc-800 flex items-center justify-between flex-wrap gap-4 animate-fade-in',
      [
        div(classes: 'flex items-center gap-3', [
          div(
            classes: 'w-8 h-8 rounded-full bg-indigo-500/20 text-indigo-400 font-black text-xs flex items-center justify-center border border-indigo-500/40',
            [Component.text('$selectedCount')],
          ),
          div(classes: 'flex flex-col', [
            span(classes: 'font-black text-xs text-white', [
              Component.text('$selectedCount cashout request(s) selected'),
            ]),
            span(classes: 'text-[11px] text-zinc-400 font-mono font-bold', [
              Component.text('Total Volume: ₱${totalSelectedAmount.toStringAsFixed(2)}'),
            ]),
          ]),
        ]),

        div(classes: 'flex items-center gap-2 flex-wrap', [
          if (waitingSelected > 0)
            button(
              onClick: () => _executeBatchClaim(items, adminUser),
              classes:
                  'px-4 py-2 rounded-2xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-xs cursor-pointer shadow-md shadow-indigo-600/30 transition-all',
              [Component.text('⚡ Batch Claim ($waitingSelected)')],
            ),

          button(
            onClick: () => _downloadCsv(selectedItems),
            classes:
                'px-4 py-2 rounded-2xl bg-zinc-800 hover:bg-zinc-700 text-zinc-200 font-bold text-xs cursor-pointer border border-zinc-700 transition-all flex items-center gap-1.5',
            [
              span([Component.text('📥')]),
              Component.text('Export CSV'),
            ],
          ),

          button(
            onClick: () => setState(() => _selectedWithdrawalIds.clear()),
            classes:
                'px-3 py-2 rounded-2xl bg-zinc-900 hover:bg-zinc-800 text-zinc-400 hover:text-white font-bold text-xs cursor-pointer border border-zinc-800 transition-all',
            [Component.text('✕ Clear Selection')],
          ),
        ]),
      ],
    );
  }

  /// MODAL: CREATE MANUAL / AD-HOC P2P CASHOUT
  Component _buildCreateCashoutModal(List<UserProfileModel> usersList, fb.User? adminUser) {
    final filteredUsers = _userSearchQuery.trim().isEmpty
        ? usersList.take(6).toList()
        : usersList.where((userModel) {
            final q = _userSearchQuery.toLowerCase();
            return userModel.name.toLowerCase().contains(q) ||
                userModel.email.toLowerCase().contains(q) ||
                (userModel.phoneNumber?.toLowerCase().contains(q) ?? false) ||
                userModel.uid.toLowerCase().contains(q);
          }).take(8).toList();

    return div(
      classes: 'fixed inset-0 z-[9950] flex items-center justify-center bg-black/70 backdrop-blur-md p-4 animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-2xl bg-white rounded-3xl shadow-2xl border border-zinc-200 overflow-hidden flex flex-col max-h-[92vh] animate-scale-up',
          [
            // Header
            div(classes: 'px-6 py-4 bg-zinc-50 border-b border-zinc-100 flex items-center justify-between', [
              div(classes: 'flex items-center gap-3', [
                div(
                  classes: 'w-10 h-10 rounded-2xl bg-black text-white flex items-center justify-center text-lg font-black shadow-sm',
                  [Component.text('💸')],
                ),
                div([
                  h2(classes: 'text-base font-black text-zinc-900', [Component.text('Create Manual P2P Cashout')]),
                  p(classes: 'text-xs text-zinc-400 font-medium', [
                    Component.text('Initiate an ad-hoc withdrawal / payout order on behalf of a user.'),
                  ]),
                ]),
              ]),
              button(
                onClick: () => setState(() => _showCreateCashoutModal = false),
                classes:
                    'w-8 h-8 rounded-full bg-zinc-100 hover:bg-zinc-200 text-zinc-500 hover:text-zinc-800 flex items-center justify-center font-bold text-sm border-0 cursor-pointer transition-colors',
                [Component.text('✕')],
              ),
            ]),

            // Body Form
            div(classes: 'p-6 overflow-y-auto flex flex-col gap-4', [
              // User Search / Quick Autocomplete Section
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-xs font-bold text-zinc-700 flex items-center justify-between', [
                  span([Component.text('Beneficiary / Registered User (Optional Autocomplete)')]),
                  if (_createUserId.isNotEmpty)
                    span(classes: 'text-[10px] text-indigo-600 font-bold', [
                      Component.text('Selected: $_createUserName (UID: ${_createUserId.substring(0, _createUserId.length > 8 ? 8 : _createUserId.length)}...)'),
                    ]),
                ]),
                div(classes: 'relative', [
                  input(
                    type: InputType.text,
                    value: _userSearchQuery,
                    onInput: (dynamic val) {
                      setState(() {
                        _userSearchQuery = (val as String?) ?? '';
                        _isUserDropdownOpen = true;
                      });
                    },
                    attributes: {'placeholder': 'Search registered users by name, email, or phone...'},
                    classes:
                        'w-full px-3.5 py-2.5 rounded-2xl text-xs bg-zinc-50 border border-zinc-200 text-zinc-800 placeholder-zinc-400 focus:outline-none focus:border-zinc-500 focus:bg-white',
                  ),

                  if (_isUserDropdownOpen && filteredUsers.isNotEmpty)
                    div(
                      classes:
                          'absolute top-full left-0 right-0 mt-1.5 bg-white border border-zinc-200 rounded-2xl shadow-xl z-50 overflow-hidden max-h-48 overflow-y-auto divide-y divide-zinc-100',
                      [
                        for (final usr in filteredUsers)
                          button(
                            type: ButtonType.button,
                            onClick: () {
                              setState(() {
                                _createUserId = usr.uid;
                                _createUserName = usr.name;
                                _createUserEmail = usr.email;
                                _createAccountName = usr.name;
                                if (usr.phoneNumber != null && usr.phoneNumber!.isNotEmpty) {
                                  _createAccountNumber = usr.phoneNumber!;
                                }
                                _userSearchQuery = '${usr.name} (${usr.email})';
                                _isUserDropdownOpen = false;
                              });
                            },
                            classes:
                                'w-full px-4 py-2.5 text-left hover:bg-zinc-50 flex items-center justify-between text-xs cursor-pointer border-0 bg-transparent transition-colors',
                            [
                              div(classes: 'flex flex-col', [
                                span(classes: 'font-bold text-zinc-900', [Component.text(usr.name)]),
                                span(classes: 'text-[11px] text-zinc-400', [Component.text(usr.email)]),
                              ]),
                              div(classes: 'flex flex-col items-end', [
                                span(classes: 'text-[10px] font-mono text-zinc-500 font-bold', [
                                  Component.text('Bal: ₱${usr.availableBalance.toStringAsFixed(2)}'),
                                ]),
                                if (usr.phoneNumber != null && usr.phoneNumber!.isNotEmpty)
                                  span(classes: 'text-[10px] text-zinc-400 font-mono', [Component.text(usr.phoneNumber!)]),
                              ]),
                            ],
                          ),
                      ],
                    ),
                ]),
              ]),

              // Payment Rail & Payout Category
              div(classes: 'grid grid-cols-1 sm:grid-cols-2 gap-4', [
                div(classes: 'flex flex-col gap-1.5', [
                  label(classes: 'text-xs font-bold text-zinc-700', [Component.text('Payment Rail / Provider')]),
                  select(
                    onChange: (dynamic val) {
                      final selectedList = val is List<String> ? val : <String>[];
                      final opt = selectedList.isNotEmpty ? selectedList.first : 'GCash';
                      setState(() => _createPaymentMethod = opt);
                    },
                    classes:
                        'w-full px-3.5 py-2.5 rounded-2xl text-xs bg-zinc-50 border border-zinc-200 text-zinc-800 focus:outline-none focus:border-zinc-500 focus:bg-white cursor-pointer font-bold',
                    [
                      option(value: 'GCash', selected: _createPaymentMethod == 'GCash', [Component.text('🔵 GCash (e-Wallet)')]),
                      option(value: 'Maya', selected: _createPaymentMethod == 'Maya', [Component.text('🟢 Maya (e-Wallet)')]),
                      option(value: 'GrabPay', selected: _createPaymentMethod == 'GrabPay', [Component.text('🟢 GrabPay (e-Wallet)')]),
                      option(value: 'SeaBank', selected: _createPaymentMethod == 'SeaBank', [Component.text('🟠 SeaBank (Digital Bank)')]),
                      option(value: 'GoTyme', selected: _createPaymentMethod == 'GoTyme', [Component.text('🟣 GoTyme (Digital Bank)')]),
                      option(value: 'BDO', selected: _createPaymentMethod == 'BDO', [Component.text('🔵 BDO Unibank')]),
                      option(value: 'BPI', selected: _createPaymentMethod == 'BPI', [Component.text('🔴 Bank of the Philippine Islands (BPI)')]),
                      option(value: 'UnionBank', selected: _createPaymentMethod == 'UnionBank', [Component.text('🟠 UnionBank')]),
                      option(value: 'Bank Transfer', selected: _createPaymentMethod == 'Bank Transfer', [Component.text('🏛️ Other Commercial Bank')]),
                    ],
                  ),
                ]),

                div(classes: 'flex flex-col gap-1.5', [
                  label(classes: 'text-xs font-bold text-zinc-700', [Component.text('Payout Purpose / Category')]),
                  select(
                    onChange: (dynamic val) {
                      final selectedList = val is List<String> ? val : <String>[];
                      final opt = selectedList.isNotEmpty ? selectedList.first : 'Host Payout';
                      setState(() => _createReasonCategory = opt);
                    },
                    classes:
                        'w-full px-3.5 py-2.5 rounded-2xl text-xs bg-zinc-50 border border-zinc-200 text-zinc-800 focus:outline-none focus:border-zinc-500 focus:bg-white cursor-pointer font-bold',
                    [
                      option(value: 'Host Payout', selected: _createReasonCategory == 'Host Payout', [Component.text('🏠 Host Rental Earnings Payout')]),
                      option(value: 'Deposit Refund', selected: _createReasonCategory == 'Deposit Refund', [Component.text('🛡️ Security Deposit Refund')]),
                      option(value: 'Rewards Incentive', selected: _createReasonCategory == 'Rewards Incentive', [Component.text('🎁 Promotional / Reward Cashout')]),
                      option(value: 'Dispute Settlement', selected: _createReasonCategory == 'Dispute Settlement', [Component.text('⚖️ Dispute Resolution / Refund')]),
                      option(value: 'Manual Adjustment', selected: _createReasonCategory == 'Manual Adjustment', [Component.text('🔧 Manual Support Adjustment')]),
                    ],
                  ),
                ]),
              ]),

              // Recipient Name & Account Number
              div(classes: 'grid grid-cols-1 sm:grid-cols-2 gap-4', [
                div(classes: 'flex flex-col gap-1.5', [
                  label(classes: 'text-xs font-bold text-zinc-700', [Component.text('Recipient Account Name *')]),
                  input(
                    type: InputType.text,
                    value: _createAccountName,
                    onInput: (dynamic val) => setState(() => _createAccountName = (val as String?) ?? ''),
                    attributes: {'placeholder': 'e.g. Juan Dela Cruz'},
                    classes:
                        'w-full px-3.5 py-2.5 rounded-2xl text-xs bg-zinc-50 border border-zinc-200 text-zinc-800 placeholder-zinc-400 focus:outline-none focus:border-zinc-500 focus:bg-white font-bold',
                  ),
                ]),

                div(classes: 'flex flex-col gap-1.5', [
                  label(classes: 'text-xs font-bold text-zinc-700', [Component.text('Recipient Account / Mobile Number *')]),
                  input(
                    type: InputType.text,
                    value: _createAccountNumber,
                    onInput: (dynamic val) => setState(() => _createAccountNumber = (val as String?) ?? ''),
                    attributes: {'placeholder': 'e.g. 09171234567 or Account #'},
                    classes:
                        'w-full px-3.5 py-2.5 rounded-2xl text-xs bg-zinc-50 border border-zinc-200 text-zinc-800 placeholder-zinc-400 focus:outline-none focus:border-zinc-500 focus:bg-white font-mono font-bold',
                  ),
                ]),
              ]),

              // Amount & Fee Breakdown
              div(classes: 'grid grid-cols-1 sm:grid-cols-2 gap-4', [
                div(classes: 'flex flex-col gap-1.5', [
                  label(classes: 'text-xs font-bold text-zinc-700', [Component.text('Gross Amount (₱) *')]),
                  input(
                    type: InputType.number,
                    value: _createAmountStr,
                    onInput: (dynamic val) => setState(() => _createAmountStr = (val as String?) ?? ''),
                    attributes: {'placeholder': '0.00', 'step': 'any'},
                    classes:
                        'w-full px-3.5 py-2.5 rounded-2xl text-base font-black bg-zinc-50 border border-zinc-200 text-zinc-900 placeholder-zinc-400 focus:outline-none focus:border-zinc-500 focus:bg-white',
                  ),
                ]),

                div(classes: 'flex flex-col gap-1.5', [
                  label(classes: 'text-xs font-bold text-zinc-700', [Component.text('Fee Amount (₱)')]),
                  input(
                    type: InputType.number,
                    value: _createFeeStr,
                    onInput: (dynamic val) => setState(() => _createFeeStr = (val as String?) ?? ''),
                    attributes: {'placeholder': '0.00', 'step': 'any'},
                    classes:
                        'w-full px-3.5 py-2.5 rounded-2xl text-xs font-bold bg-zinc-50 border border-zinc-200 text-zinc-700 placeholder-zinc-400 focus:outline-none focus:border-zinc-500 focus:bg-white',
                  ),
                ]),
              ]),

              // Optional User QR and Notes
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-xs font-bold text-zinc-700', [Component.text('Recipient QR Image URL (Optional)')]),
                input(
                  type: InputType.text,
                  value: _createUserQrUrl,
                  onInput: (dynamic val) => setState(() => _createUserQrUrl = (val as String?) ?? ''),
                  attributes: {'placeholder': 'https://... QR code image link'},
                  classes:
                      'w-full px-3.5 py-2.5 rounded-2xl text-xs bg-zinc-50 border border-zinc-200 text-zinc-800 placeholder-zinc-400 focus:outline-none focus:border-zinc-500 focus:bg-white',
                ),
              ]),

              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-xs font-bold text-zinc-700', [Component.text('Internal Admin Note / Reference Reason')]),
                textarea(
                  onInput: (dynamic val) => setState(() => _createReasonNote = (val as String?) ?? ''),
                  attributes: {'placeholder': 'Details regarding why this manual cashout was issued...', 'rows': '2'},
                  classes:
                      'w-full px-3.5 py-2.5 rounded-2xl text-xs bg-zinc-50 border border-zinc-200 text-zinc-800 placeholder-zinc-400 focus:outline-none focus:border-zinc-500 focus:bg-white',
                  [Component.text(_createReasonNote)],
                ),
              ]),
            ]),

            // Footer Actions
            div(classes: 'px-6 py-4 bg-zinc-50 border-t border-zinc-100 flex items-center justify-between', [
              button(
                type: ButtonType.button,
                onClick: () => setState(() => _showCreateCashoutModal = false),
                classes:
                    'px-4 py-2.5 rounded-2xl border border-zinc-200 bg-white hover:bg-zinc-100 text-zinc-700 font-bold text-xs cursor-pointer transition-all',
                [Component.text('Cancel')],
              ),
              button(
                type: ButtonType.button,
                onClick: () => _executeCreateCashout(adminUser),
                classes:
                    'px-6 py-2.5 rounded-2xl bg-black hover:bg-zinc-800 text-white font-black text-xs cursor-pointer shadow-lg shadow-black/10 transition-all flex items-center gap-2',
                [
                  if (_isProcessing)
                    span(classes: 'w-3 h-3 border-2 border-white/20 border-t-white rounded-full animate-spin', []),
                  Component.text(_isProcessing ? 'Creating Cashout...' : 'Submit & Enqueue Cashout ⚡'),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  /// MODAL: OFFICIAL BRANDED RECEIPT VOUCHER
  Component _buildReceiptModal(WithdrawalRequest req) {
    final isApproved = req.status == 'APPROVED';
    final dt = DateTime.fromMillisecondsSinceEpoch(req.createdAt);

    return div(
      classes: 'fixed inset-0 z-[9960] flex items-center justify-center bg-black/70 backdrop-blur-md p-4 animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-md bg-white rounded-3xl shadow-2xl border border-zinc-200 overflow-hidden flex flex-col max-h-[92vh] animate-scale-up',
          [
            // Voucher Top Banner
            div(
              classes:
                  'px-6 py-5 bg-gradient-to-br from-zinc-950 via-zinc-900 to-zinc-800 text-white flex flex-col gap-2 relative overflow-hidden',
              [
                div(classes: 'flex items-center justify-between', [
                  div(classes: 'flex items-center gap-2', [
                    span(classes: 'text-lg', [Component.text('💸')]),
                    span(classes: 'font-black tracking-widest text-[11px] uppercase text-zinc-300', [
                      Component.text('Tranyx Settlement Hub'),
                    ]),
                  ]),
                  button(
                    onClick: () => setState(() => _showReceiptModal = false),
                    classes:
                        'w-7 h-7 rounded-full bg-white/10 hover:bg-white/20 text-white flex items-center justify-center font-bold text-xs border-0 cursor-pointer transition-colors',
                    [Component.text('✕')],
                  ),
                ]),
                h3(classes: 'text-lg font-black tracking-tight text-white mt-1', [
                  Component.text('P2P Payout Disbursement Voucher'),
                ]),
                div(classes: 'flex items-center justify-between text-[10px] text-zinc-400 font-mono', [
                  span([Component.text('Voucher #: ${req.referenceNumber.isNotEmpty ? req.referenceNumber : req.id}')]),
                  span([Component.text('${dt.month}/${dt.day}/${dt.year}')]),
                ]),
              ],
            ),

            // Receipt Content
            div(classes: 'p-6 overflow-y-auto flex flex-col gap-5 text-xs', [
              // Status & Amount Spotlight
              div(
                classes:
                    'p-4 rounded-2xl ${isApproved ? "bg-emerald-50/80 border-emerald-200" : "bg-amber-50/80 border-amber-200"} border flex flex-col items-center justify-center text-center gap-1.5',
                [
                  span(
                    classes:
                        'px-2.5 py-0.5 rounded-full text-[10px] font-black ${isApproved ? "bg-emerald-600 text-white" : "bg-amber-500 text-white"}',
                    [Component.text(isApproved ? '✓ DISBURSED & VERIFIED' : req.status)],
                  ),
                  span(classes: 'text-3xl font-black text-zinc-900 tracking-tight mt-1', [
                    Component.text('₱${req.netAmount.toStringAsFixed(2)}'),
                  ]),
                  span(classes: 'text-[11px] text-zinc-500 font-bold', [
                    Component.text('Net Transfer Amount to Beneficiary'),
                  ]),
                ],
              ),

              // Beneficiary & Rail Info
              div(classes: 'p-4 rounded-2xl bg-zinc-50 border border-zinc-200/70 flex flex-col gap-2.5', [
                span(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Beneficiary Account'),
                ]),
                div(classes: 'flex items-center justify-between', [
                  span(classes: 'text-zinc-500 font-medium', [Component.text('Recipient Name')]),
                  span(classes: 'font-bold text-zinc-900 text-right', [
                    Component.text(req.userAccountName.isNotEmpty ? req.userAccountName : req.userName),
                  ]),
                ]),
                div(classes: 'flex items-center justify-between', [
                  span(classes: 'text-zinc-500 font-medium', [Component.text('Payment Rail')]),
                  _buildMethodBadge(req.paymentMethod),
                ]),
                div(classes: 'flex items-center justify-between', [
                  span(classes: 'text-zinc-500 font-medium', [Component.text('Account Number')]),
                  span(classes: 'font-mono font-black text-zinc-900', [Component.text(req.userAccountNumber)]),
                ]),
              ]),

              // Financial Ledger Breakdown
              div(classes: 'p-4 rounded-2xl border border-zinc-200 flex flex-col gap-2', [
                span(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Transaction Breakdown'),
                ]),
                div(classes: 'flex items-center justify-between', [
                  span(classes: 'text-zinc-500', [Component.text('Gross Cashout Amount')]),
                  span(classes: 'font-bold text-zinc-800 font-mono', [Component.text('₱${req.amount.toStringAsFixed(2)}')]),
                ]),
                if (req.feeAmount > 0)
                  div(classes: 'flex items-center justify-between', [
                    span(classes: 'text-zinc-500', [Component.text('Processing / Platform Fee')]),
                    span(classes: 'font-bold text-zinc-600 font-mono', [Component.text('₱${req.feeAmount.toStringAsFixed(2)}')]),
                  ]),
                div(classes: 'border-t border-zinc-200 pt-2 flex items-center justify-between font-black', [
                  span(classes: 'text-zinc-900', [Component.text('Total Net Paid')]),
                  span(classes: 'text-zinc-900 font-mono text-sm', [Component.text('₱${req.netAmount.toStringAsFixed(2)}')]),
                ]),
              ]),

              // Dispatch Audit
              div(classes: 'text-[11px] text-zinc-400 flex flex-col gap-1 border-t border-zinc-100 pt-3', [
                if (req.agentName != null && req.agentName!.isNotEmpty)
                  span([Component.text('Dispatched by Agent: ${req.agentName}')]),
                span(classes: 'font-mono', [Component.text('Created: ${_formatTimestamp(req.createdAt)}')]),
                if (req.verifiedAt != null)
                  span(classes: 'font-mono', [Component.text('Settled: ${_formatTimestamp(req.verifiedAt!)}')]),
              ]),
            ]),

            // Footer Actions
            div(classes: 'px-6 py-4 bg-zinc-50 border-t border-zinc-100 flex items-center justify-between gap-3', [
              button(
                onClick: () => _copyToClipboard('receipt_${req.id}', _generateReceiptText(req)),
                classes:
                    'flex-1 py-2.5 rounded-2xl border border-zinc-200 bg-white hover:bg-zinc-100 text-zinc-800 font-bold text-xs cursor-pointer shadow-sm transition-all flex items-center justify-center gap-1.5',
                [
                  span([Component.text(_copiedFields['receipt_${req.id}'] == true ? '✓' : '📋')]),
                  Component.text(_copiedFields['receipt_${req.id}'] == true ? 'Copied to Clipboard!' : 'Copy For Chat'),
                ],
              ),
              button(
                onClick: () => web.window.print(),
                classes:
                    'px-5 py-2.5 rounded-2xl bg-black hover:bg-zinc-800 text-white font-bold text-xs cursor-pointer shadow-md transition-all flex items-center gap-1.5',
                [
                  span([Component.text('🖨️')]),
                  Component.text('Print'),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }
}
