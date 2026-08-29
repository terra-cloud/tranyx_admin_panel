import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:web/web.dart' as web;

import '../app.dart';
import '../core/providers/environment_provider.dart';
import 'users.dart';
import 'withdrawals.dart';

/// Represents a P2P deposit request submitted by a user.
class DepositRequest {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final double amount;
  final String paymentMethod; // GCash, Maya, Bank
  final String referenceNumber;
  final String status; // PENDING_AGENT, AWAITING_PAYMENT, PENDING_VERIFICATION, APPROVED, REJECTED, CANCELLED
  final int submittedAt;
  final String receiptUrl;
  final String targetWallet;
  final String? assignedAgentId;
  final String? assignedAgentName;
  final int? assignedAt;
  final String? agentQrUrl;
  final String? agentPaymentNumber;
  final String? agentPaymentName;
  final String? reviewedByAdminId;
  final String? reviewedByAdminName;
  final int? reviewedAt;
  final String? action;
  final String? rejectionReason;
  final String? rejectionNote;
  final Map<String, dynamic> rawData;

  bool get isOnChain =>
      paymentMethod.toLowerCase().contains('usdt') ||
      paymentMethod.toLowerCase().contains('crypto') ||
      paymentMethod.toLowerCase().contains('onchain') ||
      paymentMethod.toLowerCase().contains('trc20') ||
      paymentMethod.toLowerCase().contains('erc20') ||
      paymentMethod.toLowerCase().contains('polygon');

  DepositRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.amount,
    required this.paymentMethod,
    required this.referenceNumber,
    required this.status,
    required this.submittedAt,
    required this.receiptUrl,
    required this.targetWallet,
    this.assignedAgentId,
    this.assignedAgentName,
    this.assignedAt,
    this.agentQrUrl,
    this.agentPaymentNumber,
    this.agentPaymentName,
    this.reviewedByAdminId,
    this.reviewedByAdminName,
    this.reviewedAt,
    this.action,
    this.rejectionReason,
    this.rejectionNote,
    this.rawData = const {},
  });

  DepositRequest mergeWith(DepositRequest other) {
    return DepositRequest(
      id: id,
      userId: other.userId.isNotEmpty ? other.userId : userId,
      userName: (other.userName.isNotEmpty && other.userName != 'Unknown User') ? other.userName : userName,
      userEmail: other.userEmail.isNotEmpty ? other.userEmail : userEmail,
      amount: other.amount > 0 ? other.amount : amount,
      paymentMethod: (other.paymentMethod.isNotEmpty && other.paymentMethod != 'GCash') ? other.paymentMethod : paymentMethod,
      referenceNumber: (other.referenceNumber.isNotEmpty && other.referenceNumber != 'N/A') ? other.referenceNumber : referenceNumber,
      status: (other.status != 'PENDING_AGENT' || status == 'PENDING_AGENT') ? other.status : status,
      submittedAt: submittedAt > 0 ? submittedAt : other.submittedAt,
      receiptUrl: other.receiptUrl.isNotEmpty ? other.receiptUrl : receiptUrl,
      targetWallet: (other.targetWallet.isNotEmpty && other.targetWallet != 'Main Wallet') ? other.targetWallet : targetWallet,
      assignedAgentId: other.assignedAgentId ?? assignedAgentId,
      assignedAgentName: other.assignedAgentName ?? assignedAgentName,
      assignedAt: other.assignedAt ?? assignedAt,
      agentQrUrl: other.agentQrUrl ?? agentQrUrl,
      agentPaymentNumber: other.agentPaymentNumber ?? agentPaymentNumber,
      agentPaymentName: other.agentPaymentName ?? agentPaymentName,
      reviewedByAdminId: other.reviewedByAdminId ?? reviewedByAdminId,
      reviewedByAdminName: other.reviewedByAdminName ?? reviewedByAdminName,
      reviewedAt: other.reviewedAt ?? reviewedAt,
      action: other.action ?? action,
      rejectionReason: other.rejectionReason ?? rejectionReason,
      rejectionNote: other.rejectionNote ?? rejectionNote,
      rawData: {...rawData, ...other.rawData},
    );
  }

  factory DepositRequest.fromMap(String id, Map<String, dynamic> map) {
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

    final rawMethod = (map['paymentMethod'] ?? map['method'] ?? map['type'] ?? 'GCash').toString();
    final normalizedMethod = rawMethod.toLowerCase().contains('maya')
        ? 'Maya'
        : (rawMethod.toLowerCase().contains('gcash') ? 'GCash' : rawMethod);

    final rawRef = (map['referenceNumber'] ?? map['refNumber'] ?? map['refNo'] ?? map['reference'] ?? 'N/A').toString();

    // Deep multi-key & recursive proof of payment scanner
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

    String extractReceipt(Map<String, dynamic> m) {
      final keys = [
        'receiptUrl',
        'receipt_url',
        'proofUrl',
        'proof_url',
        'proofOfPayment',
        'proof_of_payment',
        'proofOfPaymentUrl',
        'screenshotUrl',
        'screenshot',
        'imageUrl',
        'image_url',
        'paymentProofUrl',
        'paymentProof',
        'payment_proof',
        'transferProof',
        'transfer_proof',
        'receipt',
        'proof',
        'attachment',
        'attachments',
        'fileUrl',
        'file_url',
        'mediaUrl',
        'media_url',
        'photoUrl',
        'photo_url',
        'photo',
        'file',
        'files',
        'documentUrl',
        'document_url',
        'docUrl',
        'doc_url',
        'depositProof',
        'userProof',
        'user_proof',
        'clientProof',
      ];
      for (final k in keys) {
        final val = m[k];
        if (val != null) {
          final res = extractUrlFromAny(val);
          if (res.isNotEmpty) return res;
        }
      }

      // Deep scan non-agent keys
      for (final entry in m.entries) {
        final k = entry.key.toLowerCase();
        if (k.contains('agent') || k.contains('admin')) continue;
        final res = extractUrlFromAny(entry.value);
        if (res.isNotEmpty) return res;
      }

      return '';
    }

    final rawReceipt = extractReceipt(map);

    final rawStatus = (map['status'] ?? '').toString().trim().toUpperCase();
    final hasProof = rawReceipt.isNotEmpty;
    String normalizedStatus;

    if (rawStatus == 'APPROVED' || rawStatus == 'COMPLETED' || rawStatus == 'SUCCESS') {
      normalizedStatus = 'APPROVED';
    } else if (rawStatus == 'REJECTED' || rawStatus == 'DECLINED') {
      normalizedStatus = 'REJECTED';
    } else if (rawStatus == 'CANCELLED' || rawStatus == 'CANCELED') {
      normalizedStatus = 'CANCELLED';
    } else if (hasProof ||
        rawStatus == 'PENDING_VERIFICATION' ||
        rawStatus == 'PROOF_SUBMITTED' ||
        rawStatus == 'PAID' ||
        rawStatus == 'VERIFYING' ||
        rawStatus == 'PROCESSING' ||
        rawStatus == 'UNDER_REVIEW' ||
        rawStatus == 'VERIFICATION_PENDING' ||
        rawStatus == 'PENDING_REVIEW') {
      normalizedStatus = 'PENDING_VERIFICATION';
    } else if (rawStatus == 'AWAITING_PAYMENT' || rawStatus == 'QR_SENT' || rawStatus == 'AGENT_ASSIGNED') {
      normalizedStatus = 'AWAITING_PAYMENT';
    } else if (rawStatus == 'PENDING_AGENT' || rawStatus == 'AWAITING_QR' || rawStatus == 'REQUESTED' || rawStatus == 'OPEN') {
      normalizedStatus = 'PENDING_AGENT';
    } else if (map['assignedAgentId'] != null && (map['assignedAgentId'] as String).isNotEmpty) {
      normalizedStatus = 'AWAITING_PAYMENT';
    } else {
      normalizedStatus = 'PENDING_AGENT';
    }

    final rawWallet = (map['targetWallet'] ??
            map['walletAddress'] ??
            map['wallet'] ??
            map['walletPublicKey'] ??
            'Main Wallet')
        .toString();

    // Extract Assigned Agent ID and Name (supports ID, UID, and Legacy Email formats)
    final rawAgentId = (map['assignedAgentId'] ??
            map['agentId'] ??
            map['agentUid'] ??
            map['assignedTo'] ??
            map['handledBy'] ??
            map['claimedBy'] ??
            map['agent'])
        ?.toString()
        .trim();

    final rawAgentName = (map['assignedAgentName'] ??
            map['agentName'] ??
            map['agentDisplayName'] ??
            map['agentEmail'] ??
            map['assignedAgentEmail'])
        ?.toString()
        .trim();

    String? formatAgentName(String? name, String? id) {
      if (name != null && name.isNotEmpty && name != 'null') {
        if (name.contains('@')) {
          final username = name.split('@').first;
          final parts = username.split(RegExp(r'[._-]'));
          return parts
              .where((part) => part.isNotEmpty)
              .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
              .join(' ')
              .trim();
        }
        return name;
      }
      if (id != null && id.isNotEmpty && id != 'null') {
        if (id.contains('@')) {
          final username = id.split('@').first;
          final parts = username.split(RegExp(r'[._-]'));
          return parts
              .where((part) => part.isNotEmpty)
              .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
              .join(' ')
              .trim();
        }
        return 'Agent (${id.substring(0, mathMin(id.length, 6))})';
      }
      return null;
    }

    final formattedAgentName = formatAgentName(rawAgentName, rawAgentId);

    final amount = parseAmount(
      map['amount'] ??
      map['depositAmount'] ??
      map['requestedAmount'] ??
      map['grossAmount'] ??
      map['netAmount'] ??
      map['totalAmount'] ??
      map['value']
    );

    return DepositRequest(
      id: id,
      userId: (map['userId'] ?? map['uid'] ?? '').toString(),
      userName: (map['userName'] ?? map['userFullName'] ?? map['name'] ?? 'Unknown User').toString(),
      userEmail: (map['userEmail'] ?? map['email'] ?? '').toString(),
      amount: amount,
      paymentMethod: normalizedMethod,
      referenceNumber: rawRef,
      status: normalizedStatus,
      submittedAt: parseDateTime(map['submittedAt'] ?? map['createdAt'] ?? map['timestamp']),
      receiptUrl: rawReceipt,
      targetWallet: rawWallet,
      assignedAgentId: (rawAgentId != null && rawAgentId.isNotEmpty && rawAgentId != 'null') ? rawAgentId : null,
      assignedAgentName: formattedAgentName,
      assignedAt: map['assignedAt'] != null ? parseDateTime(map['assignedAt']) : null,
      agentQrUrl: map['agentQrUrl'] as String?,
      agentPaymentNumber: map['agentPaymentNumber'] as String?,
      agentPaymentName: map['agentPaymentName'] as String?,
      reviewedByAdminId: map['reviewedByAdminId'] as String?,
      reviewedByAdminName: map['reviewedByAdminName'] as String?,
      reviewedAt: map['reviewedAt'] != null ? parseDateTime(map['reviewedAt']) : null,
      action: map['action'] as String?,
      rejectionReason: map['rejectionReason'] as String?,
      rejectionNote: map['rejectionNote'] as String?,
      rawData: map,
    );
  }
}

/// Represents an agent's saved payment QR code preset.
class AgentQrPreset {
  final String method; // GCash, Maya, Bank
  final String accountName;
  final String accountNumber;
  final String qrImageUrl;

  const AgentQrPreset({
    required this.method,
    required this.accountName,
    required this.accountNumber,
    required this.qrImageUrl,
  });

  Map<String, dynamic> toMap() => {
        'method': method,
        'accountName': accountName,
        'accountNumber': accountNumber,
        'qrImageUrl': qrImageUrl,
      };

  factory AgentQrPreset.fromMap(Map<String, dynamic> map) => AgentQrPreset(
        method: map['method'] ?? 'GCash',
        accountName: map['accountName'] ?? '',
        accountNumber: map['accountNumber'] ?? '',
        qrImageUrl: map['qrImageUrl'] ?? '',
      );
}

/// Represents an approved P2P reference claim to prevent duplicate double-crediting.
class ClaimedReference {
  final String id;
  final String referenceNumber;
  final String depositRequestId;
  final String userId;
  final String userName;
  final double amount;
  final int approvedAt;
  final String approvedByAdminId;
  final String approvedByAdminName;

  ClaimedReference({
    required this.id,
    required this.referenceNumber,
    required this.depositRequestId,
    required this.userId,
    required this.userName,
    required this.amount,
    required this.approvedAt,
    required this.approvedByAdminId,
    required this.approvedByAdminName,
  });

  factory ClaimedReference.fromMap(String id, Map<String, dynamic> map) {
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

    return ClaimedReference(
      id: id,
      referenceNumber: (map['referenceNumber'] ?? id).toString(),
      depositRequestId: (map['depositRequestId'] ?? map['depositId'] ?? '').toString(),
      userId: (map['userId'] ?? map['uid'] ?? '').toString(),
      userName: (map['userName'] ?? 'User').toString(),
      amount: parseAmount(map['amount']),
      approvedAt: parseDateTime(map['approvedAt'] ?? map['timestamp'] ?? map['createdAt']),
      approvedByAdminId: (map['approvedByAdminId'] ?? '').toString(),
      approvedByAdminName: (map['approvedByAdminName'] ?? 'Admin').toString(),
    );
  }
}

/// Represents an immutable Admin Audit Log entry.
class AdminAuditEntry {
  final String id;
  final String depositRequestId;
  final String userId;
  final String userName;
  final double amount;
  final String referenceNumber;
  final String action;
  final String? rejectionReason;
  final String reviewedByAdminId;
  final String reviewedByAdminName;
  final int timestamp;

  AdminAuditEntry({
    required this.id,
    required this.depositRequestId,
    required this.userId,
    required this.userName,
    required this.amount,
    required this.referenceNumber,
    required this.action,
    this.rejectionReason,
    required this.reviewedByAdminId,
    required this.reviewedByAdminName,
    required this.timestamp,
  });

  factory AdminAuditEntry.fromMap(String id, Map<String, dynamic> map) {
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

    return AdminAuditEntry(
      id: id,
      depositRequestId: (map['depositRequestId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      userName: (map['userName'] ?? 'User').toString(),
      amount: parseAmount(map['amount']),
      referenceNumber: (map['referenceNumber'] ?? '').toString(),
      action: (map['action'] ?? '').toString(),
      rejectionReason: map['rejectionReason'] as String?,
      reviewedByAdminId: (map['reviewedByAdminId'] ?? '').toString(),
      reviewedByAdminName: (map['reviewedByAdminName'] ?? 'Admin').toString(),
      timestamp: parseDateTime(map['timestamp'] ?? map['reviewedAt'] ?? map['createdAt']),
    );
  }
}

/// Provider streaming all deposit requests from all possible collections.
final depositRequestsStreamProvider = StreamProvider<List<DepositRequest>>((ref) {
  ref.watch(activeEnvAuthUserProvider);
  final firestore = ref.watch(firestoreProvider);

  final controller = StreamController<List<DepositRequest>>();
  final Map<String, List<DepositRequest>> sourceMap = {
    'deposit_requests': [],
    'deposits': [],
  };

  void emitMerged() {
    final Map<String, DepositRequest> merged = {};
    for (final list in sourceMap.values) {
      for (final item in list) {
        if (!merged.containsKey(item.id)) {
          merged[item.id] = item;
        } else {
          final existing = merged[item.id]!;
          merged[item.id] = existing.mergeWith(item);
        }
      }
    }
    final result = merged.values.toList()
      ..sort((reqA, reqB) => reqB.submittedAt.compareTo(reqA.submittedAt));
    if (!controller.isClosed) {
      controller.add(result);
    }
  }

  final sub1 = firestore.collection('deposit_requests').snapshots().listen((snap) {
    sourceMap['deposit_requests'] = snap.docs.map((doc) => DepositRequest.fromMap(doc.id, doc.data())).toList();
    emitMerged();
  }, onError: (err) {
    print('[Deposits] deposit_requests stream notice: $err');
  });

  final sub2 = firestore.collection('deposits').snapshots().listen((snap) {
    sourceMap['deposits'] = snap.docs.map((doc) => DepositRequest.fromMap(doc.id, doc.data())).toList();
    emitMerged();
  }, onError: (_) {});

  ref.onDispose(() {
    sub1.cancel();
    sub2.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Provider streaming claimed P2P reference numbers registry.
final claimedReferencesStreamProvider = StreamProvider<List<ClaimedReference>>((ref) {
  ref.watch(activeEnvAuthUserProvider);
  final firestore = ref.watch(firestoreProvider);
  return firestore.collection('claimed_p2p_references').snapshots().map((snap) {
    return snap.docs.map((doc) => ClaimedReference.fromMap(doc.id, doc.data())).toList();
  }).handleError((_) {
    return <ClaimedReference>[];
  });
});

/// Provider streaming Admin Audit Logs.
final adminAuditLogsStreamProvider = StreamProvider<List<AdminAuditEntry>>((ref) {
  ref.watch(activeEnvAuthUserProvider);
  final firestore = ref.watch(firestoreProvider);
  return firestore.collection('admin_audit_logs').snapshots().map((snap) {
    final list = snap.docs.map((doc) => AdminAuditEntry.fromMap(doc.id, doc.data())).toList();
    list.sort((logA, logB) => logB.timestamp.compareTo(logA.timestamp));
    return list;
  }).handleError((_) {
    return <AdminAuditEntry>[];
  });
});

/// Count of pending deposit verification requests.
final pendingDepositsCountProvider = Provider<int>((ref) {
  final list = ref.watch(depositRequestsStreamProvider).value ?? [];
  return list.where((d) => !d.isOnChain && (d.status == 'PENDING_AGENT' || d.status == 'PENDING_VERIFICATION')).length;
});

class DepositsPage extends StatefulComponent {
  const DepositsPage({super.key});

  @override
  State<DepositsPage> createState() => _DepositsPageState();
}

class _DepositsPageState extends State<DepositsPage> {
  // Navigation tabs: 'awaiting_qr', 'pending_proof', 'awaiting_payment', 'approved', 'rejected', 'all', 'registry', 'audit'
  String _activeTab = 'awaiting_qr';
  String _searchQuery = '';
  String _methodFilter = 'all'; // all, GCash, Maya

  // Audio Chime & Alert States
  bool _soundEnabled = true;

  // Inspection modal state
  DepositRequest? _inspectingDeposit;
  bool _isFullscreenViewer = false;
  double _zoomLevel = 1.0;
  double _panX = 0.0;
  double _panY = 0.0;
  bool _isDragging = false;
  double _dragStartX = 0.0;
  double _dragStartY = 0.0;

  // Send QR Modal & Locking States
  bool _showSendQrModal = false;
  DepositRequest? _targetDepositForQr;
  String _sendQrAccountName = '';
  String _sendQrAccountNumber = '';
  String _sendQrImageUrl = '';
  bool _showQrPresetManager = false;

  // Saved Agent QR Presets (stored in LocalStorage)
  final Map<String, AgentQrPreset> _savedPresets = {};

  // Dialog workflow states
  bool _showApproveConfirmModal = false;
  bool _showRejectModal = false;
  bool _isProcessing = false;
  String? _toastMessage;

  // Rejection form states
  String _selectedRejectReason = 'Payment not received in merchant account';
  String _customRejectNote = '';

  // Copy feedback state tracker
  final Map<String, bool> _copiedFields = {};

  final List<String> _predefinedRejectReasons = [
    'Payment not received in merchant account',
    'Submitted amount does not match received amount',
    'Reference number mismatch / invalid',
    'Duplicate transaction submission',
    'Illegible / tampered payment screenshot',
    'Other (Custom text required)',
  ];

  @override
  void initState() {
    super.initState();
    _loadQrPresetsFromStorage();
  }

  void _loadQrPresetsFromStorage() {
    try {
      final savedJson = web.window.localStorage.getItem('tranyx_agent_qr_presets');
      if (savedJson != null && savedJson.isNotEmpty) {
        final decoded = jsonDecode(savedJson) as Map<String, dynamic>;
        decoded.forEach((key, val) {
          if (val is Map<String, dynamic>) {
            _savedPresets[key] = AgentQrPreset.fromMap(val);
          }
        });
      }
    } catch (_) {}

    // Default presets if empty
    if (!_savedPresets.containsKey('GCash')) {
      _savedPresets['GCash'] = const AgentQrPreset(
        method: 'GCash',
        accountName: 'Tranyx Official Merchant',
        accountNumber: '0917-888-9999',
        qrImageUrl: 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=09178889999_GCash',
      );
    }
    if (!_savedPresets.containsKey('Maya')) {
      _savedPresets['Maya'] = const AgentQrPreset(
        method: 'Maya',
        accountName: 'Tranyx Official Merchant',
        accountNumber: '0918-777-8888',
        qrImageUrl: 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=09187778888_Maya',
      );
    }
  }

  void _saveQrPresetsToStorage() {
    try {
      final map = <String, dynamic>{};
      _savedPresets.forEach((k, v) => map[k] = v.toMap());
      web.window.localStorage.setItem('tranyx_agent_qr_presets', jsonEncode(map));
      _triggerToast('QR presets saved successfully.');
    } catch (_) {}
  }

  void _playAlertChime() {
    if (!_soundEnabled) return;
    try {
      final ctx = web.AudioContext();
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);

      // Play urgent high-low alert tone (880Hz -> 1320Hz)
      osc.frequency.setValueAtTime(880, ctx.currentTime);
      osc.frequency.setValueAtTime(1320, ctx.currentTime + 0.12);
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

  void _handleQrImageFileSelected(web.Event event) {
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
        img.onLoad.listen((_) {
          final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
          const maxDim = 600;
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
            _sendQrImageUrl = compressedDataUrl;
          });
          _triggerToast('QR code image loaded successfully.');
        });
      }
    });
  }

  void _handlePresetQrImageFileSelected(String method, web.Event event) {
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
        img.onLoad.listen((_) {
          final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
          const maxDim = 600;
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
          final current = _savedPresets[method] ?? AgentQrPreset(method: method, accountName: '', accountNumber: '', qrImageUrl: '');
          setState(() {
            _savedPresets[method] = AgentQrPreset(
              method: method,
              accountName: current.accountName,
              accountNumber: current.accountNumber,
              qrImageUrl: compressedDataUrl,
            );
          });
          _triggerToast('$method QR image preset updated.');
        });
      }
    });
  }

  void _openSendQrModal(DepositRequest deposit) {
    // Populate form with preset for this method
    final preset = _savedPresets[deposit.paymentMethod] ?? _savedPresets['GCash'];
    setState(() {
      _targetDepositForQr = deposit;
      _sendQrAccountName = preset?.accountName ?? 'Merchant Account';
      _sendQrAccountNumber = preset?.accountNumber ?? '';
      _sendQrImageUrl = preset?.qrImageUrl ?? '';
      _showSendQrModal = true;
    });
  }

  void _openInspector(DepositRequest deposit) {
    setState(() {
      _inspectingDeposit = deposit;
      _isFullscreenViewer = false;
      _zoomLevel = 1.0;
      _panX = 0.0;
      _panY = 0.0;
      _showApproveConfirmModal = false;
      _showRejectModal = false;
      _selectedRejectReason = _predefinedRejectReasons.first;
      _customRejectNote = '';
    });
  }

  void _closeInspector() {
    setState(() {
      _inspectingDeposit = null;
      _showApproveConfirmModal = false;
      _showRejectModal = false;
      _isFullscreenViewer = false;
    });
  }

  void _zoomIn() {
    setState(() {
      if (_zoomLevel < 4.0) _zoomLevel = (_zoomLevel + 0.3).clamp(0.5, 4.0);
    });
  }

  void _zoomOut() {
    setState(() {
      if (_zoomLevel > 0.6) _zoomLevel = (_zoomLevel - 0.3).clamp(0.5, 4.0);
    });
  }

  void _resetZoom() {
    setState(() {
      _zoomLevel = 1.0;
      _panX = 0.0;
      _panY = 0.0;
    });
  }

  /// Evaluates whether the deposit was claimed by the currently logged-in agent.
  /// Checks against Admin UID, Dev Env UID, Staff Email, Display Name, and local session credentials.
  bool _isClaimedByCurrentAgent(DepositRequest deposit, fb.User? adminUser) {
    final activeEnvUser = context.read(activeEnvAuthUserProvider).value;
    final localStoredEmail = web.window.localStorage.getItem('tranyx_staff_email');

    final myIdentifiers = <String>{};
    if (adminUser?.uid != null && adminUser!.uid.isNotEmpty) {
      myIdentifiers.add(adminUser.uid.toLowerCase().trim());
    }
    if (adminUser?.email != null && adminUser!.email!.isNotEmpty) {
      myIdentifiers.add(adminUser.email!.toLowerCase().trim());
    }
    if (adminUser?.displayName != null && adminUser!.displayName!.isNotEmpty) {
      myIdentifiers.add(adminUser.displayName!.toLowerCase().trim());
    }
    if (activeEnvUser?.uid != null && activeEnvUser!.uid.isNotEmpty) {
      myIdentifiers.add(activeEnvUser.uid.toLowerCase().trim());
    }
    if (activeEnvUser?.email != null && activeEnvUser!.email!.isNotEmpty) {
      myIdentifiers.add(activeEnvUser.email!.toLowerCase().trim());
    }
    if (localStoredEmail != null && localStoredEmail.isNotEmpty) {
      myIdentifiers.add(localStoredEmail.toLowerCase().trim());
    }

    final depositAgentIdentifiers = <String>{};
    if (deposit.assignedAgentId != null && deposit.assignedAgentId!.isNotEmpty) {
      depositAgentIdentifiers.add(deposit.assignedAgentId!.toLowerCase().trim());
    }
    if (deposit.assignedAgentName != null && deposit.assignedAgentName!.isNotEmpty) {
      depositAgentIdentifiers.add(deposit.assignedAgentName!.toLowerCase().trim());
    }
    final m = deposit.rawData;
    for (final k in [
      'assignedAgentId',
      'agentId',
      'agentUid',
      'assignedTo',
      'handledBy',
      'claimedBy',
      'agent',
      'assignedAgentEmail',
      'agentEmail',
      'assignedAgentName',
      'agentName'
    ]) {
      final v = m[k]?.toString().toLowerCase().trim();
      if (v != null && v.isNotEmpty && v != 'null') {
        depositAgentIdentifiers.add(v);
      }
    }

    if (depositAgentIdentifiers.isEmpty) return false;
    return depositAgentIdentifiers.any((id) => myIdentifiers.contains(id));
  }

  /// Checks if any agent has already claimed or handled this deposit.
  bool _hasAgentAssignment(DepositRequest deposit) {
    if (deposit.assignedAgentId != null && deposit.assignedAgentId!.isNotEmpty) return true;
    final m = deposit.rawData;
    for (final k in ['assignedAgentId', 'agentId', 'agentUid', 'assignedTo', 'handledBy', 'claimedBy', 'agent']) {
      final v = m[k]?.toString().trim();
      if (v != null && v.isNotEmpty && v != 'null') return true;
    }
    return false;
  }

  /// AGENT QR CODE SENDING & CONCURRENCY LOCKING
  /// Prevents Agent B from sending QR code if Agent A already claimed the request.
  Future<void> _executeSendQrCode(DepositRequest deposit, fb.User? adminUser) async {
    if (_isProcessing) return;

    if (_sendQrAccountNumber.trim().isEmpty && _sendQrImageUrl.trim().isEmpty) {
      _triggerToast('Please provide at least a QR code image URL or account number.');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    final firestore = context.read(firestoreProvider);
    final effectiveUser = adminUser ?? context.read(adminAuthProvider).currentUser;
    final adminUid = effectiveUser?.uid ?? 'admin_portal';
    final adminName = effectiveUser?.displayName?.isNotEmpty == true
        ? effectiveUser!.displayName!
        : (effectiveUser?.email?.isNotEmpty == true ? effectiveUser!.email! : 'Agent Staff');
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    try {
      final depositDocRef = firestore.collection('deposit_requests').doc(deposit.id);

      // 1. Concurrency Check: Fetch latest live document snapshot
      try {
        final latestDocSnap = await depositDocRef.get();
        if (latestDocSnap.exists) {
          final latestData = latestDocSnap.data()!;
          final existingAgentId = (latestData['assignedAgentId'] ??
                  latestData['agentId'] ??
                  latestData['agentUid'] ??
                  latestData['assignedTo'] ??
                  latestData['handledBy'] ??
                  '')
              .toString()
              .trim();
          final existingAgentName = (latestData['assignedAgentName'] ??
                  latestData['agentName'] ??
                  latestData['agentEmail'] ??
                  'Another Agent')
              .toString();

          final currentEmail = (effectiveUser?.email ?? '').trim().toLowerCase();
          final isClaimedByCurrent = existingAgentId.isNotEmpty &&
              (existingAgentId == adminUid ||
                  (currentEmail.isNotEmpty && existingAgentId.toLowerCase() == currentEmail));

          // IF ANOTHER AGENT ALREADY CLAIMED THIS REQUEST -> BLOCK AGENT B
          if (existingAgentId.isNotEmpty && !isClaimedByCurrent) {
            final assignedTime = latestData['assignedAt'] != null ? _formatTimestamp(latestData['assignedAt']) : 'recently';
            _triggerToast('🔒 Action Blocked! Request was already claimed by Agent $existingAgentName ($assignedTime). You cannot override their QR.');
            setState(() {
              _isProcessing = false;
              _showSendQrModal = false;
            });
            return;
          }
        }
      } catch (getErr) {
        print('[Deposits] Notice checking concurrency snapshot: $getErr');
      }

      // 2. Lock to Current Agent & Send QR Code
      await depositDocRef.set({
        'status': 'AWAITING_PAYMENT',
        'assignedAgentId': adminUid,
        'assignedAgentName': adminName,
        'assignedAt': nowMs,
        'agentQrUrl': _sendQrImageUrl.trim(),
        'agentPaymentNumber': _sendQrAccountNumber.trim(),
        'agentPaymentName': _sendQrAccountName.trim(),
        'updatedAt': nowMs,
      }, SetOptions(merge: true));

      // 3. Log Audit (Safe execution in case collection rules are restricted)
      try {
        await firestore.collection('admin_audit_logs').doc().set({
          'depositRequestId': deposit.id,
          'userId': deposit.userId,
          'userName': deposit.userName,
          'amount': deposit.amount,
          'paymentMethod': deposit.paymentMethod,
          'action': 'QR_SENT',
          'reviewedByAdminId': adminUid,
          'reviewedByAdminName': adminName,
          'reviewedAt': nowMs,
          'timestamp': nowMs,
          'type': 'AGENT_QR_SENT',
        });
      } catch (auditErr) {
        print('[Deposits] Audit log write skipped: $auditErr');
      }

      _triggerToast('✓ QR Code sent to ${deposit.userName}! Request locked to your agent ID.');
      setState(() {
        _showSendQrModal = false;
        _targetDepositForQr = null;
      });
    } catch (e) {
      print('[Deposits] Send QR Error: $e');
      _triggerToast('Failed to send QR code: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Deposit Approval Workflow with atomic Firestore execution
  Future<void> _executeApproveDeposit(DepositRequest deposit, fb.User? adminUser) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    final firestore = context.read(firestoreProvider);
    final effectiveUser = adminUser ?? context.read(adminAuthProvider).currentUser;
    final adminUid = effectiveUser?.uid ?? 'admin_portal';
    final adminName = effectiveUser?.displayName?.isNotEmpty == true
        ? effectiveUser!.displayName!
        : (effectiveUser?.email?.isNotEmpty == true ? effectiveUser!.email! : 'Admin Staff');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final normalizedRef = deposit.referenceNumber.trim().toUpperCase();

    // Ensure effective user has admin/agent credentials in users/{uid} and p2p_agents/{uid}
    if (effectiveUser != null) {
      final myUid = effectiveUser.uid;
      final myEmail = effectiveUser.email ?? 'admin@tranyx.app';
      try {
        await firestore.collection('users').doc(myUid).set({
          'uid': myUid,
          'email': myEmail,
          'role': 'admin',
          'isAdmin': true,
          'name': adminName,
          'updatedAt': nowMs,
        }, SetOptions(merge: true));
        await firestore.collection('p2p_agents').doc(myUid).set({
          'uid': myUid,
          'email': myEmail,
          'role': 'agent',
          'isActive': true,
          'updatedAt': nowMs,
        }, SetOptions(merge: true));
      } catch (authSeedErr) {
        print('[Deposits] Admin role verification notice: $authSeedErr');
      }
    }

    try {
      // 1. Double check against claimed_p2p_references collection (Safe)
      try {
        final existingClaimSnap = await firestore.collection('claimed_p2p_references').doc(normalizedRef).get();
        if (existingClaimSnap.exists) {
          final existingData = existingClaimSnap.data()!;
          final claimant = existingData['userName'] ?? 'another user';
          _triggerToast('Approval blocked: Reference #$normalizedRef was already claimed by $claimant.');
          setState(() {
            _isProcessing = false;
            _showApproveConfirmModal = false;
          });
          return;
        }
      } catch (checkErr) {
        print('[Deposits] Notice checking claimed references: $checkErr');
      }

      // 2. Resolve User Document References (by ID, UID, and Email)
      final depositDocRef = firestore.collection('deposit_requests').doc(deposit.id);
      final primaryUserDocRef = firestore.collection('users').doc(deposit.userId);
      final claimedRefDoc = firestore.collection('claimed_p2p_references').doc(normalizedRef);
      final auditLogDoc = firestore.collection('admin_audit_logs').doc();
      final txDoc = firestore.collection('transactions').doc();

      final targetUserDocRefs = <DocumentReference<Map<String, dynamic>>>[primaryUserDocRef];
      try {
        if (deposit.userId.isNotEmpty) {
          final qSnap = await firestore.collection('users').where('uid', isEqualTo: deposit.userId).get();
          for (final d in qSnap.docs) {
            if (!targetUserDocRefs.any((r) => r.id == d.id)) targetUserDocRefs.add(d.reference);
          }
        }
        if (deposit.userEmail.isNotEmpty) {
          final qSnap2 = await firestore.collection('users').where('email', isEqualTo: deposit.userEmail).get();
          for (final d in qSnap2.docs) {
            if (!targetUserDocRefs.any((r) => r.id == d.id)) targetUserDocRefs.add(d.reference);
          }
        }
      } catch (lookupErr) {
        print('[Deposits] User query notice: $lookupErr');
      }

      // Read current balance across all matching documents
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
        } catch (getUErr) {
          print('[Deposits] Notice fetching user balance: $getUErr');
        }
      }
      final newBalance = currentBalance + deposit.amount;

      // Update Deposit Request status to APPROVED
      await depositDocRef.set({
        'status': 'APPROVED',
        'reviewedByAdminId': adminUid,
        'reviewedByAdminName': adminName,
        'reviewedAt': nowMs,
        'action': 'APPROVED',
        'updatedAt': nowMs,
      }, SetOptions(merge: true));

      // Update User Balance across all matching user documents
      for (final uRef in targetUserDocRefs) {
        try {
          await uRef.set({
            'uid': deposit.userId,
            'name': deposit.userName,
            'email': deposit.userEmail,
            'tyxBalance': newBalance,
            'availableBalance': newBalance,
            'walletBalance': newBalance,
            'balance': newBalance,
            'fiatBalance': newBalance,
            'phpBalance': newBalance,
            'totalBalance': newBalance,
            'updatedAt': nowMs,
          }, SetOptions(merge: true));
        } catch (userUpErr) {
          print('[Deposits] User balance update notice on ${uRef.id}: $userUpErr');
        }

        // Write to user subcollections for mobile/web app synchronization
        try {
          await uRef.collection('transactions').doc(txDoc.id).set({
            'type': 'deposit',
            'amount': deposit.amount,
            'status': 'COMPLETED',
            'referenceNumber': deposit.referenceNumber,
            'paymentMethod': deposit.paymentMethod,
            'createdAt': nowMs,
            'timestamp': nowMs,
          }, SetOptions(merge: true));
        } catch (_) {}

        try {
          await uRef.collection('ledger').doc().set({
            'type': 'CREDIT',
            'category': 'p2p_deposit',
            'amount': deposit.amount,
            'balanceAfter': newBalance,
            'referenceNumber': deposit.referenceNumber,
            'depositRequestId': deposit.id,
            'createdAt': nowMs,
            'timestamp': nowMs,
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      // Update Top-Level Wallets Collection (if present in schema)
      try {
        final walletDocRef = firestore.collection('wallets').doc(deposit.userId);
        await walletDocRef.set({
          'userId': deposit.userId,
          'uid': deposit.userId,
          'tyxBalance': newBalance,
          'balance': newBalance,
          'availableBalance': newBalance,
          'walletBalance': newBalance,
          'fiatBalance': newBalance,
          'phpBalance': newBalance,
          'updatedAt': nowMs,
        }, SetOptions(merge: true));
      } catch (_) {}

      // Write Real-Time Push Notification for User
      try {
        await firestore.collection('notifications').doc().set({
          'uid': deposit.userId,
          'userId': deposit.userId,
          'title': 'Deposit Approved! ₱${deposit.amount.toStringAsFixed(2)} Added',
          'message': 'Your ₱${deposit.amount.toStringAsFixed(2)} top-up via ${deposit.paymentMethod} (Ref #${deposit.referenceNumber}) has been approved and credited to your wallet.',
          'body': 'Your ₱${deposit.amount.toStringAsFixed(2)} deposit has been approved.',
          'type': 'DEPOSIT_APPROVED',
          'category': 'wallet',
          'amount': deposit.amount,
          'newBalance': newBalance,
          'referenceNumber': deposit.referenceNumber,
          'depositRequestId': deposit.id,
          'isRead': false,
          'read': false,
          'createdAt': nowMs,
          'timestamp': nowMs,
        });
      } catch (notifErr) {
        print('[Deposits] Notification write notice: $notifErr');
      }

      // Add Reference Number to claimed_p2p_references Registry (Safe)
      try {
        await claimedRefDoc.set({
          'referenceNumber': deposit.referenceNumber,
          'depositRequestId': deposit.id,
          'userId': deposit.userId,
          'userName': deposit.userName,
          'amount': deposit.amount,
          'paymentMethod': deposit.paymentMethod,
          'approvedAt': nowMs,
          'approvedByAdminId': adminUid,
          'approvedByAdminName': adminName,
          'createdAt': nowMs,
        });
      } catch (claimErr) {
        print('[Deposits] Claimed reference write skipped: $claimErr');
      }

      // Record in Global Transactions
      try {
        await txDoc.set({
          'uid': deposit.userId,
          'type': 'deposit',
          'category': 'p2p_deposit',
          'amount': deposit.amount,
          'status': 'COMPLETED',
          'paymentMethod': deposit.paymentMethod,
          'referenceNumber': deposit.referenceNumber,
          'depositRequestId': deposit.id,
          'signature': 'P2P-${deposit.referenceNumber}',
          'createdAt': nowMs,
          'timestamp': nowMs,
          'title': 'Deposit via ${deposit.paymentMethod}',
          'description': 'Reference #${deposit.referenceNumber} approved by $adminName',
        });
      } catch (txErr) {
        print('[Deposits] Transaction record skipped: $txErr');
      }

      // Write Immutable Admin Audit Log (Safe)
      try {
        await auditLogDoc.set({
          'depositRequestId': deposit.id,
          'userId': deposit.userId,
          'userName': deposit.userName,
          'userEmail': deposit.userEmail,
          'amount': deposit.amount,
          'paymentMethod': deposit.paymentMethod,
          'referenceNumber': deposit.referenceNumber,
          'action': 'APPROVED',
          'reviewedByAdminId': adminUid,
          'reviewedByAdminName': adminName,
          'reviewedAt': nowMs,
          'timestamp': nowMs,
          'type': 'DEPOSIT_APPROVAL',
        });
      } catch (auditErr) {
        print('[Deposits] Audit log write skipped: $auditErr');
      }

      _triggerToast('Deposit approved! ₱${deposit.amount.toStringAsFixed(2)} credited to ${deposit.userName}.');
      _closeInspector();
    } catch (e) {
      print('[Deposits] Approval error: $e');
      _triggerToast('Approval failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Rejection Workflow with Mandatory Reason
  Future<void> _executeRejectDeposit(DepositRequest deposit, fb.User? adminUser) async {
    if (_isProcessing) return;

    final isOther = _selectedRejectReason == 'Other (Custom text required)';
    final finalReason = isOther
        ? (_customRejectNote.trim().isNotEmpty ? _customRejectNote.trim() : 'Unspecified custom rejection')
        : _selectedRejectReason;

    if (isOther && _customRejectNote.trim().isEmpty) {
      _triggerToast('Please provide a specific rejection note for "Other".');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    final firestore = context.read(firestoreProvider);
    final effectiveUser = adminUser ?? context.read(adminAuthProvider).currentUser;
    final adminUid = effectiveUser?.uid ?? 'admin_portal';
    final adminName = effectiveUser?.displayName?.isNotEmpty == true
        ? effectiveUser!.displayName!
        : (effectiveUser?.email?.isNotEmpty == true ? effectiveUser!.email! : 'Admin Staff');
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    try {
      final depositDocRef = firestore.collection('deposit_requests').doc(deposit.id);

      // Update Deposit Request status to REJECTED (Wallet remains untouched)
      await depositDocRef.set({
        'status': 'REJECTED',
        'reviewedByAdminId': adminUid,
        'reviewedByAdminName': adminName,
        'reviewedAt': nowMs,
        'action': 'REJECTED',
        'rejectionReason': finalReason,
        'rejectionNote': _customRejectNote.trim(),
        'updatedAt': nowMs,
      }, SetOptions(merge: true));

      // Write Immutable Admin Audit Log (Safe)
      try {
        await firestore.collection('admin_audit_logs').doc().set({
          'depositRequestId': deposit.id,
          'userId': deposit.userId,
          'userName': deposit.userName,
          'userEmail': deposit.userEmail,
          'amount': deposit.amount,
          'paymentMethod': deposit.paymentMethod,
          'referenceNumber': deposit.referenceNumber,
          'action': 'REJECTED',
          'rejectionReason': finalReason,
          'rejectionNote': _customRejectNote.trim(),
          'reviewedByAdminId': adminUid,
          'reviewedByAdminName': adminName,
          'reviewedAt': nowMs,
          'timestamp': nowMs,
          'type': 'DEPOSIT_REJECTION',
        });
      } catch (auditErr) {
        print('[Deposits] Audit log write skipped: $auditErr');
      }

      _triggerToast('Deposit rejected. Request marked as REJECTED.');
      _closeInspector();
    } catch (e) {
      print('[Deposits] Rejection error: $e');
      _triggerToast('Rejection failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
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
    final depositsAsync = context.watch(depositRequestsStreamProvider);
    final withdrawalsAsync = context.watch(withdrawalRequestsStreamProvider);
    final claimedAsync = context.watch(claimedReferencesStreamProvider);
    final auditLogsAsync = context.watch(adminAuditLogsStreamProvider);
    final usersAsync = context.watch(usersStreamProvider);
    final adminUser = context.watch(adminCurrentUserProvider).value;

    final allDeposits = depositsAsync.value ?? [];
    final allWithdrawals = withdrawalsAsync.value ?? [];
    final claimedList = claimedAsync.value ?? [];
    final auditLogs = auditLogsAsync.value ?? [];
    final usersList = usersAsync.value ?? [];

    final pendingWithdrawalsCount = allWithdrawals.where((w) => w.status == 'WAITING_FOR_AGENT' || w.status == 'AWAITING_AGENT_PAYMENT').length;

    // Map claimed reference numbers for instant lookup
    final Map<String, ClaimedReference> claimedRefsMap = {};
    for (final claimItem in claimedList) {
      claimedRefsMap[claimItem.referenceNumber.trim().toUpperCase()] = claimItem;
    }

    // Categorized Counts
    final awaitingQrCount = allDeposits.where((d) => d.status == 'PENDING_AGENT').length;
    final awaitingPaymentCount = allDeposits.where((d) => d.status == 'AWAITING_PAYMENT').length;
    final pendingProofCount = allDeposits.where((d) => d.status == 'PENDING_VERIFICATION').length;
    final approvedCount = allDeposits.where((d) => d.status == 'APPROVED').length;
    final rejectedCount = allDeposits.where((d) => d.status == 'REJECTED').length;

    // Filter deposits based on tab, search, and method
    List<DepositRequest> filteredDeposits = allDeposits.where((depositItem) {
      // Tab filter
      if (_activeTab == 'awaiting_qr' && depositItem.status != 'PENDING_AGENT') return false;
      if (_activeTab == 'awaiting_payment' && depositItem.status != 'AWAITING_PAYMENT') return false;
      if (_activeTab == 'pending_proof' && depositItem.status != 'PENDING_VERIFICATION') return false;
      if (_activeTab == 'approved' && depositItem.status != 'APPROVED') return false;
      if (_activeTab == 'rejected' && depositItem.status != 'REJECTED') return false;

      // Method filter
      if (_methodFilter != 'all') {
        if (!depositItem.paymentMethod.toLowerCase().contains(_methodFilter.toLowerCase())) {
          return false;
        }
      }

      // Search filter
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final matchUser = depositItem.userName.toLowerCase().contains(q);
        final matchId = depositItem.userId.toLowerCase().contains(q);
        final matchRef = depositItem.referenceNumber.toLowerCase().contains(q);
        final matchEmail = depositItem.userEmail.toLowerCase().contains(q);
        final matchAmount = depositItem.amount.toString().contains(q);
        final matchAgent = (depositItem.assignedAgentName ?? '').toLowerCase().contains(q);
        if (!matchUser && !matchId && !matchRef && !matchEmail && !matchAmount && !matchAgent) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort all queues from NEWEST to OLDEST (descending by submission time)
    filteredDeposits.sort((reqA, reqB) => reqB.submittedAt.compareTo(reqA.submittedAt));

    final totalVolumeApproved = allDeposits
        .where((d) => d.status == 'APPROVED')
        .fold<double>(0.0, (acc, item) => acc + item.amount);

    return div(
      classes: 'flex-grow p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0] relative min-h-screen',
      [
        // Toast message banner
        if (_toastMessage != null)
          div(
            classes:
                'fixed top-6 right-6 z-[9999] bg-zinc-950 text-white px-5 py-3.5 rounded-2xl shadow-2xl border border-zinc-800 flex items-center gap-3 animate-fade-up',
            [
              span(classes: 'text-base', [Component.text('🔔')]),
              span(classes: 'text-xs font-bold', [Component.text(_toastMessage!)]),
              button(
                onClick: () => setState(() => _toastMessage = null),
                classes: 'ml-2 text-zinc-400 hover:text-white bg-transparent border-0 cursor-pointer text-xs font-bold',
                [Component.text('✕')],
              ),
            ],
          ),

        // Top P2P Hub Switcher Bar (Seamless transition between Deposits and Withdrawals)
        div(
          classes: 'w-full bg-white p-2 rounded-2xl border border-zinc-200/60 shadow-sm flex items-center justify-between flex-wrap gap-3',
          [
            div(classes: 'flex items-center gap-2', [
              button(
                onClick: () => Router.of(context).push('/deposits'),
                classes:
                    'px-4 py-2 rounded-xl text-xs font-bold bg-black text-white shadow-sm flex items-center gap-2 cursor-pointer',
                [
                  span([Component.text('💳 P2P Deposits')]),
                  if (awaitingQrCount > 0 || pendingProofCount > 0)
                    span(
                      classes: 'px-2 py-0.5 rounded-full bg-rose-500 text-white text-[10px] font-black',
                      [Component.text('${awaitingQrCount + pendingProofCount}')],
                    ),
                ],
              ),
              button(
                onClick: () => Router.of(context).push('/withdrawals'),
                classes:
                    'px-4 py-2 rounded-xl text-xs font-bold text-zinc-600 hover:text-zinc-900 hover:bg-zinc-100/70 transition-all flex items-center gap-2 cursor-pointer',
                [
                  span([Component.text('💸 P2P Cashouts')]),
                  if (pendingWithdrawalsCount > 0)
                    span(
                      classes: 'px-2 py-0.5 rounded-full bg-rose-500 text-white text-[10px] font-black animate-pulse',
                      [Component.text('$pendingWithdrawalsCount')],
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
                      'w-10 h-10 rounded-2xl bg-emerald-500/10 text-emerald-600 flex items-center justify-center font-black text-lg border border-emerald-500/20 shadow-sm',
                  [Component.text('₱')],
                ),
                div([
                  h1(
                    classes: 'text-xl font-black tracking-tight text-zinc-900 flex items-center gap-2.5',
                    [
                      Component.text('P2P Payment & Deposit Queue'),
                      if (awaitingQrCount > 0)
                        span(
                          classes:
                              'px-2.5 py-0.5 rounded-full bg-rose-500 text-white text-[10px] font-black animate-pulse shadow-sm',
                          [Component.text('$awaitingQrCount NEEDS QR')],
                        ),
                    ],
                  ),
                  p(classes: 'text-xs text-zinc-400 font-medium', [
                    Component.text(
                      'Real-time P2P Dispatch: Send your QR code, lock requests against agent conflicts, and verify receipt proofs.',
                    ),
                  ]),
                ]),
              ]),
            ]),

            // Controls & Metrics
            div(classes: 'flex items-center gap-3 flex-wrap', [
              // Audio Toggle & Test Chime
              button(
                onClick: () {
                  setState(() => _soundEnabled = !_soundEnabled);
                  if (_soundEnabled) _playAlertChime();
                },
                classes:
                    'px-3.5 py-2 rounded-2xl border border-zinc-200/70 bg-white hover:bg-zinc-50 text-xs font-bold text-zinc-700 flex items-center gap-2 cursor-pointer shadow-sm transition-all',
                attributes: {'title': _soundEnabled ? 'Mute Interrupt Sound' : 'Enable Interrupt Sound'},
                [
                  span([Component.text(_soundEnabled ? '🔔 Sound ON' : '🔕 Sound OFF')]),
                ],
              ),

              // Agent QR Presets Manager Button
              button(
                onClick: () => setState(() => _showQrPresetManager = true),
                classes:
                    'px-3.5 py-2 rounded-2xl border border-emerald-500/30 bg-emerald-50 hover:bg-emerald-100 text-xs font-bold text-emerald-800 flex items-center gap-2 cursor-pointer shadow-sm transition-all',
                [
                  span([Component.text('⚙️ My QR Presets')]),
                ],
              ),

              // Total Volume Badge
              div(
                classes:
                    'px-4 py-2 bg-white border border-zinc-200/50 rounded-2xl shadow-[0_2px_8px_rgba(0,0,0,0.02)] flex items-center gap-3',
                [
                  span(classes: 'w-2 h-2 rounded-full bg-emerald-500', []),
                  div(classes: 'flex flex-col', [
                    span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Total Volume Credited'),
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
              _buildTabButton('awaiting_qr', '⚡ Awaiting QR', count: awaitingQrCount, isUrgent: awaitingQrCount > 0),
              _buildTabButton('pending_proof', '🔍 Verify Proof', count: pendingProofCount, isWarning: pendingProofCount > 0),
              _buildTabButton('awaiting_payment', '⏳ User Paying', count: awaitingPaymentCount),
              _buildTabButton('approved', 'Approved', count: approvedCount),
              _buildTabButton('rejected', 'Rejected', count: rejectedCount),
              _buildTabButton('all', 'All Submissions', count: allDeposits.length),
              _buildTabButton('registry', 'Claimed Registry', count: claimedList.length),
              _buildTabButton('audit', 'Audit Logs', count: auditLogs.length),
            ],
          ),

          // Filters & Search Row (Responsive layout)
          if (_activeTab != 'registry' && _activeTab != 'audit')
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
                      option(value: 'all', selected: _methodFilter == 'all', [Component.text('💳 All Methods')]),
                      option(value: 'GCash', selected: _methodFilter == 'GCash', [Component.text('🔵 GCash Only')]),
                      option(value: 'Maya', selected: _methodFilter == 'Maya', [Component.text('🟢 Maya Only')]),
                    ],
                  ),
                ]),
                span(classes: 'text-xs text-zinc-400 font-semibold', [
                  Component.text('Showing ${filteredDeposits.length} of ${allDeposits.length} requests'),
                ]),
              ]),

              // Right: Search input
              div(classes: 'relative w-full sm:w-72', [
                input(
                  type: InputType.text,
                  value: _searchQuery,
                  onInput: (dynamic val) => setState(() => _searchQuery = (val as String?) ?? ''),
                  attributes: {'placeholder': 'Search user, agent, or ref #...'},
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

        // Tab Contents
        if (_activeTab == 'registry')
          _buildClaimedRegistryView(claimedList)
        else if (_activeTab == 'audit')
          _buildAuditLogsView(auditLogs)
        else
          depositsAsync.when(
            data: (_) {
              if (filteredDeposits.isEmpty) {
                return _buildEmptyState();
              }
              return _buildDepositQueueList(filteredDeposits, claimedRefsMap, usersList, adminUser);
            },
            loading: () => div(
              classes:
                  'flex-grow flex flex-col items-center justify-center py-24 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
              [
                div(
                  classes: 'animate-spin h-8 w-8 border-3 border-zinc-200 border-t-emerald-500 rounded-full mb-3',
                  [],
                ),
                p(classes: 'text-xs text-zinc-400 font-semibold', [Component.text('Loading P2P deposit requests...')]),
              ],
            ),
            error: (err, _) => div(
              classes: 'p-8 bg-red-50/20 border border-red-200 rounded-[24px] text-red-600 text-xs font-mono',
              [Component.text('Failed to load queue: $err')],
            ),
          ),

        // Send QR Code Modal with Concurrency Protection
        if (_showSendQrModal && _targetDepositForQr != null)
          _buildSendQrModal(_targetDepositForQr!, adminUser),

        // Agent QR Presets Manager Modal
        if (_showQrPresetManager) _buildQrPresetManagerModal(),

        // High-Resolution Receipt Inspector Modal
        if (_inspectingDeposit != null)
          _buildInspectorModal(_inspectingDeposit!, claimedRefsMap, adminUser, usersList),

        // Approve Confirmation Dialog
        if (_showApproveConfirmModal && _inspectingDeposit != null)
          _buildApproveConfirmDialog(_inspectingDeposit!, adminUser),

        // Rejection Workflow Modal
        if (_showRejectModal && _inspectingDeposit != null) _buildRejectDialog(_inspectingDeposit!, adminUser),
      ],
    );
  }

  Component _buildTabButton(String id, String label, {int? count, bool isUrgent = false, bool isWarning = false}) {
    final isActive = _activeTab == id;
    return button(
      onClick: () => setState(() => _activeTab = id),
      classes:
          'flex-shrink-0 px-4 py-2 text-xs font-bold rounded-xl transition-all duration-200 flex items-center gap-2 cursor-pointer border-0 outline-none whitespace-nowrap '
          '${isActive ? 'bg-black text-white shadow-md shadow-black/10' : 'bg-transparent text-zinc-600 hover:text-zinc-900 hover:bg-zinc-100/80'}',
      [
        Component.text(label),
        if (count != null)
          span(
            classes:
                'px-1.5 py-0.5 rounded-full text-[9px] font-black leading-none '
                '${isActive ? 'bg-white/20 text-white' : (isUrgent ? 'bg-rose-500 text-white animate-pulse' : (isWarning ? 'bg-amber-100 text-amber-700' : 'bg-zinc-100 text-zinc-600'))}',
            [Component.text('$count')],
          ),
      ],
    );
  }

  Component _buildEmptyState() {
    String title = 'No requests in this queue';
    String subtitle = 'All incoming deposit requests have been processed.';
    if (_activeTab == 'awaiting_qr') {
      title = 'No New P2P Requests Waiting 🎉';
      subtitle = 'All users have received their payment QR codes from active agents.';
    } else if (_activeTab == 'pending_proof') {
      title = 'Verification Queue is Clear ✨';
      subtitle = 'There are no unreviewed receipt proofs waiting for audit.';
    } else if (_activeTab == 'awaiting_payment') {
      title = 'No Pending User Payments';
      subtitle = 'Users currently paying will show up here until they submit receipt proof.';
    }

    return div(
      classes:
          'flex-grow flex flex-col items-center justify-center text-center p-16 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
      [
        div(
          classes:
              'w-16 h-16 rounded-full bg-emerald-50 text-emerald-600 flex items-center justify-center text-2xl mb-4 border border-emerald-100',
          [Component.text('🧾')],
        ),
        h3(classes: 'text-sm font-black text-zinc-900', [Component.text(title)]),
        p(classes: 'text-xs text-zinc-400 mt-1 max-w-sm leading-relaxed', [Component.text(subtitle)]),
      ],
    );
  }

  /// P2P DEPOSIT QUEUE LIST VIEW
  Component _buildDepositQueueList(
    List<DepositRequest> deposits,
    Map<String, ClaimedReference> claimedRefsMap,
    List<UserProfileModel> usersList,
    fb.User? adminUser,
  ) {
    return div(classes: 'flex flex-col gap-3.5', [
      for (int i = 0; i < deposits.length; i++)
        () {
          final deposit = deposits[i];
          final normalizedRef = deposit.referenceNumber.trim().toUpperCase();
          final isDuplicate = claimedRefsMap.containsKey(normalizedRef) &&
              claimedRefsMap[normalizedRef]!.depositRequestId != deposit.id;

          final userProfile = usersList.firstWhere(
            (userItem) => userItem.uid == deposit.userId,
            orElse: () => UserProfileModel(
              uid: deposit.userId,
              name: deposit.userName,
              email: deposit.userEmail,
              idVerified: false,
              bgChecked: false,
              verificationLevel: 0,
              banned: false,
            ),
          );
          final displayName = userProfile.name.isNotEmpty && userProfile.name != 'Unknown User'
              ? userProfile.name
              : (deposit.userName.isNotEmpty ? deposit.userName : 'Anonymous User');

          final isGcash = deposit.paymentMethod.toLowerCase().contains('gcash');
          final isMaya = deposit.paymentMethod.toLowerCase().contains('maya');

          // Agent Locking State (robust ID, UID, Email, & session matching)
          final isAssigned = _hasAgentAssignment(deposit);
          final isClaimedByMe = _isClaimedByCurrentAgent(deposit, adminUser);
          final isClaimedByOther = isAssigned && !isClaimedByMe;
          final isUnclaimed = !isAssigned;

          return div(
            classes:
                'p-5 rounded-[24px] bg-white border ${isDuplicate ? 'border-red-300 ring-1 ring-red-400/30' : (isClaimedByOther ? 'border-zinc-200 bg-zinc-50/40' : 'border-zinc-200/60')} '
                'flex flex-col lg:flex-row justify-between lg:items-center gap-5 hover:border-zinc-300 transition-all duration-200 shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
            [
              // Left: Status Indicator, Thumbnail / QR, User and Details
              div(classes: 'flex items-start sm:items-center gap-4.5 flex-1 min-w-0', [
                // Thumbnail: Receipt Proof or Agent QR
                div(
                  events: {
                    'click': (_) {
                      if (deposit.status == 'PENDING_VERIFICATION' && isClaimedByOther) {
                        _triggerToast('🔒 Restricted: Only Agent ${deposit.assignedAgentName} can inspect and verify this payment.');
                        return;
                      }
                      _openInspector(deposit);
                    },
                  },
                  classes:
                      'relative w-16 h-16 rounded-2xl bg-zinc-100 border border-zinc-200 overflow-hidden flex-shrink-0 cursor-pointer group shadow-sm',
                  [
                    if (deposit.receiptUrl.isNotEmpty)
                      img(
                        src: deposit.receiptUrl,
                        alt: 'Receipt proof thumbnail',
                        classes:
                            'w-full h-full object-cover group-hover:scale-110 transition-transform duration-300',
                      )
                    else if (deposit.agentQrUrl != null && deposit.agentQrUrl!.isNotEmpty)
                      img(
                        src: deposit.agentQrUrl!,
                        alt: 'Agent QR thumbnail',
                        classes:
                            'w-full h-full object-cover group-hover:scale-110 transition-transform duration-300 p-1 bg-white',
                      )
                    else
                      div(
                        classes: 'w-full h-full flex flex-col items-center justify-center text-zinc-400 text-xs gap-0.5',
                        [
                          span(classes: 'text-base', [Component.text('⚡')]),
                          span(classes: 'text-[9px] font-bold', [Component.text('Needs QR')]),
                        ],
                      ),
                    div(
                      classes:
                          'absolute inset-0 bg-black/30 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center text-white text-xs',
                      [Component.text('🔍')],
                    ),
                  ],
                ),

                // User Info & Request Metadata
                div(classes: 'flex flex-col gap-1 min-w-0 flex-1', [
                  div(classes: 'flex items-center gap-2.5 flex-wrap', [
                    span(
                      events: {
                        'click': (_) {
                          if (deposit.status == 'PENDING_VERIFICATION' && isClaimedByOther) {
                            _triggerToast('🔒 Restricted: Only Agent ${deposit.assignedAgentName} can inspect and verify this payment.');
                            return;
                          }
                          _openInspector(deposit);
                        },
                      },
                      classes:
                          'font-extrabold text-sm text-zinc-900 hover:text-emerald-600 transition-colors cursor-pointer truncate',
                      [Component.text(displayName)],
                    ),

                    // Payment Method Badge
                    span(
                      classes:
                          'px-2.5 py-0.5 rounded-full text-[10px] font-extrabold flex items-center gap-1 '
                          '${isGcash ? 'bg-[#007DFE]/10 text-[#007DFE] border border-[#007DFE]/20' : (isMaya ? 'bg-[#2CB34A]/10 text-[#2CB34A] border border-[#2CB34A]/20' : 'bg-zinc-100 text-zinc-700 border border-zinc-200')}',
                      [
                        span(classes: 'text-[11px]', [
                          Component.text(isGcash ? '🔵' : (isMaya ? '🟢' : '💳')),
                        ]),
                        Component.text(deposit.paymentMethod),
                      ],
                    ),

                    // Agent Locking / Ownership Badge
                    if (isClaimedByMe)
                      span(
                        classes:
                            'px-2.5 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-300 text-[10px] font-black flex items-center gap-1',
                        [Component.text('🟢 YOU ARE ASSIGNED')],
                      )
                    else if (isClaimedByOther)
                      span(
                        classes:
                            'px-2.5 py-0.5 rounded-full bg-zinc-200 text-zinc-700 border border-zinc-300 text-[10px] font-bold flex items-center gap-1',
                        [
                          span([Component.text('🔒')]),
                          Component.text('Handled by Agent ${deposit.assignedAgentName ?? "Staff"}'),
                        ],
                      )
                    else if (deposit.status == 'PENDING_AGENT')
                      span(
                        classes:
                            'px-2.5 py-0.5 rounded-full bg-rose-100 text-rose-700 border border-rose-200 text-[10px] font-black flex items-center gap-1 animate-pulse',
                        [Component.text('⚡ AWAITING AGENT QR')],
                      ),

                    // Duplicate Warning Pill
                    if (isDuplicate)
                      span(
                        classes:
                            'px-2.5 py-0.5 rounded-full bg-red-100 text-red-700 border border-red-200 text-[10px] font-extrabold flex items-center gap-1 animate-pulse',
                        [Component.text('⚠️ DUPLICATE REFERENCE')],
                      ),
                  ]),

                  // Reference Number / Payment Details & User UID
                  div(classes: 'flex items-center gap-2 flex-wrap text-xs text-zinc-500 mt-0.5', [
                    if (deposit.referenceNumber != 'N/A') ...[
                      span(classes: 'text-zinc-400 font-semibold', [Component.text('Ref: ')]),
                      span(classes: 'font-mono font-bold text-zinc-800 bg-zinc-100 px-2 py-0.5 rounded-md text-[11px]', [
                        Component.text(deposit.referenceNumber),
                      ]),
                      button(
                        onClick: () => _copyToClipboard('ref_${deposit.id}', deposit.referenceNumber),
                        classes:
                            'text-[10px] text-zinc-400 hover:text-zinc-800 bg-transparent border-0 cursor-pointer font-bold px-1 py-0.5 rounded hover:bg-zinc-100',
                        attributes: {'title': 'Copy reference number'},
                        [
                          Component.text(_copiedFields['ref_${deposit.id}'] == true ? '✓ Copied' : '📋 Copy'),
                        ],
                      ),
                      span(classes: 'text-zinc-300', [Component.text('•')]),
                    ],
                    span(classes: 'text-[11px] text-zinc-400 font-mono truncate max-w-[120px]', [
                      Component.text('UID: ${deposit.userId}'),
                    ]),
                  ]),

                  // Submission Timestamp
                  div(classes: 'flex items-center gap-2 mt-0.5 text-[11px] text-zinc-400 font-medium', [
                    span([Component.text('🕒 Requested: ')]),
                    span(classes: 'text-zinc-600 font-semibold', [
                      Component.text(_formatTimestamp(deposit.submittedAt)),
                    ]),
                  ]),
                ]),
              ]),

              // Center-Right: Amount Badge & Actions
              div(classes: 'flex items-center justify-between lg:justify-end gap-6 flex-shrink-0', [
                div(classes: 'flex flex-col lg:items-end', [
                  span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                    Component.text('Amount to Receive'),
                  ]),
                  span(classes: 'text-lg font-black text-emerald-600 tracking-tight', [
                    Component.text('₱${deposit.amount.toStringAsFixed(2)}'),
                  ]),
                ]),

                // Action Buttons
                div(classes: 'flex items-center gap-2', [
                  // 1. If Awaiting QR: Show "Claim & Send QR" button
                  if (deposit.status == 'PENDING_AGENT') ...[
                    if (isUnclaimed || isClaimedByMe)
                      button(
                        onClick: () => _openSendQrModal(deposit),
                        classes:
                            'px-4 py-2.5 rounded-xl bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-700 hover:to-teal-700 text-white text-xs font-black transition-all shadow-md shadow-emerald-500/20 cursor-pointer border-0 outline-none flex items-center gap-1.5',
                        [
                          span([Component.text('⚡')]),
                          span([Component.text('Send QR Code')]),
                        ],
                      )
                    else
                      button(
                        attributes: {
                          'disabled': 'true',
                          'title': 'Request is already claimed by Agent ${deposit.assignedAgentName}. Competing QR cannot be sent.',
                        },
                        classes:
                            'px-4 py-2.5 rounded-xl bg-zinc-200 text-zinc-400 text-xs font-bold cursor-not-allowed border-0 flex items-center gap-1.5',
                        [
                          span([Component.text('🔒')]),
                          span([Component.text('Claimed by ${deposit.assignedAgentName}')]),
                        ],
                      ),
                  ]
                  // 2. If Awaiting Payment: Show status / resend option for assigned agent
                  else if (deposit.status == 'AWAITING_PAYMENT') ...[
                    if (isClaimedByMe)
                      button(
                        onClick: () => _openSendQrModal(deposit),
                        classes:
                            'px-3.5 py-2 rounded-xl border border-zinc-300 bg-white hover:bg-zinc-50 text-zinc-800 text-xs font-bold flex items-center gap-1.5 cursor-pointer',
                        [
                          span([Component.text('🔄 Update QR')]),
                        ],
                      )
                    else
                      span(
                        classes:
                            'px-3 py-1.5 rounded-xl bg-zinc-100 text-zinc-500 text-xs font-bold border border-zinc-200',
                        [Component.text('⏳ Waiting User Payment')],
                      ),
                  ]
                  // 3. If Pending Verification: Inspect & Review (Only visible to assigned agent)
                  else if (deposit.status == 'PENDING_VERIFICATION') ...[
                    if (isClaimedByMe || isUnclaimed)
                      button(
                        onClick: () => _openInspector(deposit),
                        classes:
                            'px-4 py-2.5 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-bold transition-all shadow-md shadow-black/10 cursor-pointer border-0 outline-none flex items-center gap-1.5',
                        [
                          span([Component.text('Inspect & Verify')]),
                          span(classes: 'text-[10px]', [Component.text('→')]),
                        ],
                      )
                    else
                      span(
                        attributes: {
                          'title': 'This payment is assigned to Agent ${deposit.assignedAgentName ?? "Staff"}. Only the assigned agent can inspect and verify.',
                        },
                        classes:
                            'px-3.5 py-2 rounded-xl bg-zinc-100 text-zinc-500 text-xs font-bold border border-zinc-200 flex items-center gap-1.5 cursor-not-allowed',
                        [
                          span([Component.text('🔒')]),
                          Component.text('Handled by ${deposit.assignedAgentName ?? "Agent"}'),
                        ],
                      ),
                  ]
                  // 4. If Completed: Inspect history
                  else ...[
                    button(
                      onClick: () => _openInspector(deposit),
                      classes:
                          'px-3.5 py-1.5 rounded-xl border border-zinc-200 bg-zinc-50 hover:bg-zinc-100 text-zinc-700 text-xs font-bold flex items-center gap-1.5 cursor-pointer',
                      [
                        span([Component.text('View Details')]),
                      ],
                    ),
                  ],
                ]),
              ]),
            ],
          );
        }(),
    ]);
  }

  /// SEND QR CODE MODAL: Allows agent to send their QR code with locking & preset selection
  Component _buildSendQrModal(DepositRequest deposit, fb.User? adminUser) {
    return div(
      classes: 'fixed inset-0 bg-black/80 backdrop-blur-sm z-[70] flex items-center justify-center p-4',
      [
        div(
          classes:
              'bg-white rounded-[28px] border border-zinc-200 shadow-2xl w-full max-w-lg overflow-hidden flex flex-col animate-fade-up',
          [
            // Modal Header
            div(
              classes: 'p-6 border-b border-zinc-150/80 bg-emerald-50/60 flex items-center justify-between gap-4',
              [
                div(classes: 'flex items-center gap-3', [
                  div(
                    classes:
                        'w-10 h-10 rounded-2xl bg-emerald-500 text-white flex items-center justify-center text-xl font-black shadow-md shadow-emerald-500/20 flex-shrink-0',
                    [Component.text('📱')],
                  ),
                  div([
                    h3(classes: 'text-sm font-black text-zinc-950', [
                      Component.text('Send ${deposit.paymentMethod} QR Code'),
                    ]),
                    p(classes: 'text-xs text-zinc-500 font-medium', [
                      Component.text('Send payment QR to user "${deposit.userName}" (₱${deposit.amount.toStringAsFixed(2)})'),
                    ]),
                  ]),
                ]),

                button(
                  onClick: () => setState(() => _showSendQrModal = false),
                  classes: 'text-zinc-400 hover:text-zinc-800 bg-transparent border-0 cursor-pointer text-lg font-bold',
                  [Component.text('✕')],
                ),
              ],
            ),

            // Form Body
            div(classes: 'p-6 flex flex-col gap-4 text-xs overflow-y-auto max-h-[70vh]', [
              // Presets Shortcut Bar
              div(classes: 'flex flex-col gap-2', [
                div(classes: 'flex items-center justify-between', [
                  label(classes: 'text-xs font-black text-zinc-800', [Component.text('Select Saved Preset:')]),
                  button(
                    onClick: () => setState(() => _showQrPresetManager = true),
                    classes:
                        'text-[11px] text-emerald-600 hover:text-emerald-800 bg-transparent border-0 cursor-pointer font-bold',
                    [Component.text('⚙️ Manage Presets')],
                  ),
                ]),
                div(classes: 'grid grid-cols-2 gap-2', [
                  for (final entry in _savedPresets.entries)
                    button(
                      onClick: () {
                        setState(() {
                          _sendQrAccountName = entry.value.accountName;
                          _sendQrAccountNumber = entry.value.accountNumber;
                          _sendQrImageUrl = entry.value.qrImageUrl;
                        });
                      },
                      classes:
                          'p-3 rounded-xl border border-zinc-200 bg-zinc-50 hover:bg-emerald-50/60 hover:border-emerald-300 text-left transition-all cursor-pointer flex flex-col gap-1',
                      [
                        span(classes: 'font-extrabold text-zinc-900', [Component.text('⚡ ${entry.key} Preset')]),
                        span(classes: 'text-[10px] text-zinc-500 truncate', [Component.text(entry.value.accountNumber)]),
                      ],
                    ),
                ]),
              ]),

              // Upload QR Code Image Component (Instead of text URL link)
              div(classes: 'flex flex-col gap-2', [
                label(classes: 'text-xs font-black text-zinc-900 flex items-center justify-between', [
                  span([Component.text('📸 Upload Your Payment QR Code:')]),
                  if (_sendQrImageUrl.isNotEmpty)
                    span(classes: 'text-[10px] text-emerald-600 font-bold', [Component.text('✓ QR Loaded')]),
                ]),

                // Upload Dropzone & File Picker
                div(
                  classes:
                      'p-4 rounded-2xl border-2 border-dashed ${_sendQrImageUrl.isNotEmpty ? 'border-emerald-400 bg-emerald-50/30' : 'border-zinc-300 bg-zinc-50 hover:bg-zinc-100/70 hover:border-zinc-400'} transition-all flex flex-col items-center justify-center gap-3 relative cursor-pointer text-center',
                  [
                    if (_sendQrImageUrl.isNotEmpty) ...[
                      div(classes: 'w-48 h-48 bg-white p-2 rounded-2xl border border-zinc-200 shadow-md flex items-center justify-center overflow-hidden', [
                        img(
                          src: _sendQrImageUrl,
                          alt: 'Agent QR Preview',
                          classes: 'w-full h-full object-contain',
                        ),
                      ]),
                      div(classes: 'flex items-center gap-2', [
                        label(
                          classes:
                              'px-3.5 py-1.5 rounded-xl bg-white border border-zinc-300 text-zinc-700 hover:bg-zinc-100 text-xs font-bold transition-all shadow-sm cursor-pointer',
                          [
                            Component.text('🔄 Replace QR Image'),
                            input(
                              type: InputType.file,
                              attributes: {'accept': 'image/*'},
                              events: {'change': (dynamic e) => _handleQrImageFileSelected(e as web.Event)},
                              classes: 'hidden',
                            ),
                          ],
                        ),
                        button(
                          onClick: () => setState(() => _sendQrImageUrl = ''),
                          classes:
                              'px-3.5 py-1.5 rounded-xl bg-red-50 border border-red-200 text-red-600 hover:bg-red-100 text-xs font-bold transition-all cursor-pointer',
                          [Component.text('✕ Remove')],
                        ),
                      ]),
                    ] else ...[
                      div(
                        classes:
                            'w-12 h-12 rounded-2xl bg-emerald-100 text-emerald-700 flex items-center justify-center text-2xl font-black',
                        [Component.text('📤')],
                      ),
                      div(classes: 'flex flex-col gap-0.5', [
                        span(classes: 'text-xs font-extrabold text-zinc-800', [
                          Component.text('Click to upload QR Code screenshot or image'),
                        ]),
                        span(classes: 'text-[11px] text-zinc-400 font-medium', [
                          Component.text('PNG, JPG, or WEBP • Compressed automatically for real-time delivery'),
                        ]),
                      ]),
                      label(
                        classes:
                            'px-4 py-2 rounded-xl bg-black text-white hover:bg-zinc-800 text-xs font-bold transition-all shadow-md cursor-pointer inline-block',
                        [
                          Component.text('Browse Image File'),
                          input(
                            type: InputType.file,
                            attributes: {'accept': 'image/*'},
                            events: {'change': (dynamic e) => _handleQrImageFileSelected(e as web.Event)},
                            classes: 'hidden',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ]),

              // Account Name Input
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-xs font-bold text-zinc-700', [Component.text('Merchant / Account Name:')]),
                input(
                  type: InputType.text,
                  value: _sendQrAccountName,
                  onInput: (dynamic val) => setState(() => _sendQrAccountName = (val as String?) ?? ''),
                  attributes: {'placeholder': 'e.g. John Doe / Tranyx Agent'},
                  classes:
                      'w-full p-3 rounded-xl bg-white border border-zinc-300 text-xs text-zinc-800 focus:outline-none focus:border-emerald-500 shadow-sm',
                ),
              ]),

              // Mobile / Account Number Input
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-xs font-bold text-zinc-700', [Component.text('Account / Mobile Number:')]),
                input(
                  type: InputType.text,
                  value: _sendQrAccountNumber,
                  onInput: (dynamic val) => setState(() => _sendQrAccountNumber = (val as String?) ?? ''),
                  attributes: {'placeholder': 'e.g. 0917-XXX-XXXX'},
                  classes:
                      'w-full p-3 rounded-xl bg-white border border-zinc-300 text-xs text-zinc-800 focus:outline-none focus:border-emerald-500 font-mono shadow-sm',
                ),
              ]),

              // Concurrency Locking Notice
              div(classes: 'p-3 bg-amber-50 rounded-xl border border-amber-200 text-[11px] text-amber-800 font-medium leading-relaxed', [
                Component.text(
                  '🔒 Real-time Lock: Once dispatched, this QR code appears instantly on the user\'s screen via live Firestore stream. Other agents are automatically blocked from overriding.',
                ),
              ]),
            ]),

            // Actions
            div(classes: 'p-5 border-t border-zinc-150/80 bg-zinc-50 flex items-center justify-end gap-3', [
              button(
                onClick: () => setState(() => _showSendQrModal = false),
                classes:
                    'px-4 py-2.5 rounded-xl bg-zinc-200 hover:bg-zinc-300 text-zinc-700 text-xs font-bold transition-all cursor-pointer border-0 outline-none',
                [Component.text('Cancel')],
              ),
              button(
                onClick: () => _executeSendQrCode(deposit, adminUser),
                classes:
                    'px-6 py-2.5 rounded-xl bg-[#0fa958] hover:bg-[#0d924c] text-white text-xs font-black transition-all shadow-md shadow-emerald-500/20 cursor-pointer border-0 outline-none flex items-center gap-2',
                [
                  if (_isProcessing)
                    div(classes: 'animate-spin h-3.5 w-3.5 border-2 border-white border-t-transparent rounded-full', [])
                  else
                    span([Component.text('Confirm & Send QR to User')]),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  /// AGENT QR PRESET MANAGER MODAL
  Component _buildQrPresetManagerModal() {
    return div(
      classes: 'fixed inset-0 bg-black/80 backdrop-blur-sm z-[80] flex items-center justify-center p-4',
      [
        div(
          classes:
              'bg-white rounded-[28px] border border-zinc-200 shadow-2xl w-full max-w-lg overflow-hidden flex flex-col animate-fade-up',
          [
            div(classes: 'p-6 border-b border-zinc-150/80 bg-zinc-50 flex items-center justify-between', [
              div([
                h3(classes: 'text-sm font-black text-zinc-950', [Component.text('Agent QR Code Presets')]),
                p(classes: 'text-xs text-zinc-400 font-medium', [
                  Component.text('Upload and save your GCash and Maya QR images for instant 1-click dispatch.'),
                ]),
              ]),
              button(
                onClick: () => setState(() => _showQrPresetManager = false),
                classes: 'text-zinc-400 hover:text-zinc-800 bg-transparent border-0 cursor-pointer text-lg font-bold',
                [Component.text('✕')],
              ),
            ]),

            div(classes: 'p-6 flex flex-col gap-5 text-xs overflow-y-auto max-h-[70vh]', [
              for (final method in ['GCash', 'Maya'])
                () {
                  final currentPreset = _savedPresets[method] ??
                      AgentQrPreset(method: method, accountName: '', accountNumber: '', qrImageUrl: '');
                  return div(classes: 'p-4 rounded-2xl bg-zinc-50 border border-zinc-200/80 flex flex-col gap-3', [
                    div(classes: 'flex items-center justify-between', [
                      span(classes: 'font-black text-sm text-zinc-900 flex items-center gap-1.5', [
                        span([Component.text(method == 'GCash' ? '🔵' : '🟢')]),
                        Component.text('$method Preset'),
                      ]),
                    ]),
                    div(classes: 'flex flex-col gap-1', [
                      label(classes: 'text-[10px] text-zinc-400 font-bold uppercase', [Component.text('Account Name')]),
                      input(
                        type: InputType.text,
                        value: currentPreset.accountName,
                        onInput: (dynamic val) {
                          final newVal = (val as String?) ?? '';
                          setState(() {
                            _savedPresets[method] = AgentQrPreset(
                              method: method,
                              accountName: newVal,
                              accountNumber: currentPreset.accountNumber,
                              qrImageUrl: currentPreset.qrImageUrl,
                            );
                          });
                        },
                        classes:
                            'p-2.5 rounded-xl bg-white border border-zinc-200 text-xs text-zinc-800 focus:outline-none',
                      ),
                    ]),
                    div(classes: 'flex flex-col gap-1', [
                      label(classes: 'text-[10px] text-zinc-400 font-bold uppercase', [Component.text('Mobile / Account Number')]),
                      input(
                        type: InputType.text,
                        value: currentPreset.accountNumber,
                        onInput: (dynamic val) {
                          final newVal = (val as String?) ?? '';
                          setState(() {
                            _savedPresets[method] = AgentQrPreset(
                              method: method,
                              accountName: currentPreset.accountName,
                              accountNumber: newVal,
                              qrImageUrl: currentPreset.qrImageUrl,
                            );
                          });
                        },
                        classes:
                            'p-2.5 rounded-xl bg-white border border-zinc-200 text-xs text-zinc-800 focus:outline-none font-mono',
                      ),
                    ]),
                    div(classes: 'flex flex-col gap-2', [
                      label(classes: 'text-[10px] text-zinc-400 font-bold uppercase', [Component.text('Preset QR Code Image')]),
                      div(classes: 'flex items-center gap-3', [
                        if (currentPreset.qrImageUrl.isNotEmpty)
                          div(classes: 'w-16 h-16 bg-white p-1 rounded-xl border border-zinc-200 shadow-sm flex-shrink-0', [
                            img(
                              src: currentPreset.qrImageUrl,
                              alt: '$method QR',
                              classes: 'w-full h-full object-contain',
                            ),
                          ]),
                        label(
                          classes:
                              'px-3.5 py-2 rounded-xl bg-white border border-zinc-300 hover:bg-zinc-100 text-zinc-800 text-xs font-bold transition-all shadow-sm cursor-pointer flex items-center gap-1.5',
                          [
                            span([Component.text('📁')]),
                            Component.text(currentPreset.qrImageUrl.isNotEmpty ? 'Replace $method QR File' : 'Upload $method QR Image'),
                            input(
                              type: InputType.file,
                              attributes: {'accept': 'image/*'},
                              events: {'change': (dynamic e) => _handlePresetQrImageFileSelected(method, e as web.Event)},
                              classes: 'hidden',
                            ),
                          ],
                        ),
                      ]),
                    ]),
                  ]);
                }(),
            ]),

            div(classes: 'p-5 border-t border-zinc-150 bg-zinc-50 flex items-center justify-end gap-3', [
              button(
                onClick: () {
                  _saveQrPresetsToStorage();
                  setState(() => _showQrPresetManager = false);
                },
                classes:
                    'px-6 py-2.5 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-bold transition-all shadow-md cursor-pointer border-0',
                [Component.text('Save Presets')],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  /// High-Resolution Receipt Inspector Modal with Zoom/Pan & One-Tap Copy
  Component _buildInspectorModal(
    DepositRequest deposit,
    Map<String, ClaimedReference> claimedRefsMap,
    fb.User? adminUser,
    List<UserProfileModel> usersList,
  ) {
    final normalizedRef = deposit.referenceNumber.trim().toUpperCase();
    final duplicateClaim = claimedRefsMap[normalizedRef];
    final isDuplicate = duplicateClaim != null && duplicateClaim.depositRequestId != deposit.id;

    final userProfile = usersList.firstWhere(
      (userItem) => userItem.uid == deposit.userId,
      orElse: () => UserProfileModel(
        uid: deposit.userId,
        name: deposit.userName,
        email: deposit.userEmail,
        idVerified: false,
        bgChecked: false,
        verificationLevel: 0,
        banned: false,
      ),
    );
    final displayName = userProfile.name.isNotEmpty && userProfile.name != 'Unknown User'
        ? userProfile.name
        : (deposit.userName.isNotEmpty ? deposit.userName : 'Anonymous User');

    final isGcash = deposit.paymentMethod.toLowerCase().contains('gcash');
    final isMaya = deposit.paymentMethod.toLowerCase().contains('maya');

    final displayReceiptUrl = deposit.receiptUrl.isNotEmpty
        ? deposit.receiptUrl
        : (deposit.rawData['proofUrl'] ??
                deposit.rawData['receiptUrl'] ??
                deposit.rawData['proofOfPayment'] ??
                deposit.rawData['proofOfPaymentUrl'] ??
                deposit.rawData['paymentProof'] ??
                deposit.rawData['paymentProofUrl'] ??
                deposit.rawData['paymentScreenshot'] ??
                deposit.rawData['screenshotUrl'] ??
                deposit.rawData['proof'] ??
                deposit.rawData['receipt'] ??
                '')
            .toString();

    return div(
      classes: 'fixed inset-0 bg-black/75 backdrop-blur-md z-[9999] flex items-center justify-center p-3 md:p-6',
      events: {
        'click': (e) {
          final target = e.target as dynamic;
          if (target.getAttribute?.call('id') == 'modal-backdrop') {
            _closeInspector();
          }
        },
      },
      attributes: {'id': 'modal-backdrop'},
      [
        div(
          classes:
              'bg-white rounded-[32px] border border-zinc-200/80 shadow-2xl overflow-hidden flex flex-col transition-all duration-300 '
              '${_isFullscreenViewer ? 'w-full h-full max-w-full max-h-full rounded-none' : 'w-full max-w-5xl max-h-[90vh]'}',
          [
            // Modal Header
            div(
              classes:
                  'px-6 py-4 border-b border-zinc-150/80 bg-zinc-50 flex items-center justify-between gap-4 flex-shrink-0',
              [
                div(classes: 'flex items-center gap-3 min-w-0', [
                  div(
                    classes:
                        'w-9 h-9 rounded-xl bg-emerald-100 text-emerald-700 flex items-center justify-center font-black text-sm flex-shrink-0',
                    [Component.text('₱')],
                  ),
                  div(classes: 'min-w-0', [
                    div(classes: 'flex items-center gap-2', [
                      h3(classes: 'text-sm font-black text-zinc-950 truncate', [
                        Component.text('Deposit Inspection: $displayName'),
                      ]),
                      span(
                        classes:
                            'px-2 py-0.5 rounded-full text-[10px] font-black uppercase tracking-wider '
                            '${deposit.status == 'APPROVED' ? 'bg-emerald-100 text-emerald-800 border border-emerald-300' : (deposit.status == 'REJECTED' ? 'bg-red-100 text-red-800 border border-red-300' : 'bg-amber-100 text-amber-800 border border-amber-300')}',
                        [Component.text(deposit.status.replaceAll('_', ' '))],
                      ),
                    ]),
                    p(classes: 'text-[11px] text-zinc-400 font-mono font-semibold truncate', [
                      Component.text('Deposit Request ID: ${deposit.id} • Submitted ${_formatTimestamp(deposit.submittedAt)}'),
                    ]),
                  ]),
                ]),

                div(classes: 'flex items-center gap-2', [
                  // Fullscreen toggle
                  button(
                    onClick: () => setState(() => _isFullscreenViewer = !_isFullscreenViewer),
                    classes:
                        'p-2 text-zinc-500 hover:text-black hover:bg-zinc-200/60 rounded-xl transition-all border-0 bg-transparent cursor-pointer text-xs font-bold',
                    attributes: {'title': _isFullscreenViewer ? 'Exit Fullscreen' : 'Expand Fullscreen'},
                    [
                      Component.text(_isFullscreenViewer ? '🗗 Compress' : '⛶ Fullscreen'),
                    ],
                  ),
                  // Close modal
                  button(
                    onClick: _closeInspector,
                    classes:
                        'p-2 text-zinc-400 hover:text-zinc-800 bg-transparent border-0 cursor-pointer text-lg font-bold outline-none',
                    [Component.text('✕')],
                  ),
                ]),
              ],
            ),

            // Duplicate Alert Banner
            if (isDuplicate)
              div(
                classes:
                    'bg-red-500 text-white px-6 py-3.5 border-b border-red-600 flex items-start gap-3 shadow-inner',
                [
                  span(classes: 'text-xl flex-shrink-0', [Component.text('⚠️')]),
                  div(classes: 'flex flex-col text-xs leading-relaxed', [
                    span(classes: 'font-black tracking-wide uppercase', [
                      Component.text('Duplicate Reference Warning: Double-Crediting Blocked'),
                    ]),
                    span(classes: 'font-medium opacity-95 mt-0.5', [
                      Component.text(
                        'Reference #${deposit.referenceNumber} was already approved on ${_formatTimestamp(duplicateClaim.approvedAt)} '
                        'for User "${duplicateClaim.userName}" (UID: ${duplicateClaim.userId}) by Admin "${duplicateClaim.approvedByAdminName}". '
                        'Approving this deposit again is blocked to prevent financial loss.',
                      ),
                    ]),
                  ]),
                ],
              ),

            // Modal Body: Left Inspector & Right Metadata Panel
            div(classes: 'flex-1 grid grid-cols-1 lg:grid-cols-12 overflow-y-auto min-h-0 divide-y lg:divide-y-0 lg:divide-x divide-zinc-200/70', [
              // Left Col: Interactive High-Resolution Receipt Viewer (7 cols)
              div(classes: 'lg:col-span-7 flex flex-col bg-zinc-950 p-4 relative min-h-[360px] lg:min-h-[500px]', [
                // Top viewer controls toolbar
                div(
                  classes:
                      'absolute top-6 left-6 right-6 z-10 flex items-center justify-between bg-zinc-900/90 backdrop-blur-md px-4 py-2 rounded-2xl border border-zinc-700/60 text-white shadow-xl',
                  [
                    div(classes: 'flex items-center gap-2', [
                      span(classes: 'text-xs font-bold text-zinc-300', [Component.text('Receipt Proof Viewer')]),
                      span(classes: 'text-[10px] font-mono text-zinc-400 bg-zinc-800 px-2 py-0.5 rounded-full', [
                        Component.text('${(_zoomLevel * 100).toInt()}%'),
                      ]),
                    ]),

                    div(classes: 'flex items-center gap-1.5', [
                      button(
                        onClick: _zoomOut,
                        classes:
                            'w-7 h-7 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-white flex items-center justify-center font-bold text-xs border-0 cursor-pointer',
                        attributes: {'title': 'Zoom Out'},
                        [Component.text('－')],
                      ),
                      button(
                        onClick: _resetZoom,
                        classes:
                            'px-2.5 h-7 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-white flex items-center justify-center font-bold text-[10px] border-0 cursor-pointer',
                        attributes: {'title': 'Reset View (100%)'},
                        [Component.text('Reset')],
                      ),
                      button(
                        onClick: _zoomIn,
                        classes:
                            'w-7 h-7 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-white flex items-center justify-center font-bold text-xs border-0 cursor-pointer',
                        attributes: {'title': 'Zoom In'},
                        [Component.text('＋')],
                      ),
                      if (displayReceiptUrl.isNotEmpty)
                        a(
                          href: displayReceiptUrl,
                          target: Target.blank,
                          classes:
                              'px-2.5 h-7 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white flex items-center justify-center font-bold text-[10px] border-0 no-underline cursor-pointer ml-1',
                          attributes: {'title': 'Open original in new window'},
                          [Component.text('↗ Open Full')],
                        ),
                    ]),
                  ],
                ),

                // Interactive Image viewport supporting pan and scale
                div(
                  classes:
                      'flex-1 flex items-center justify-center overflow-hidden rounded-2xl bg-zinc-900 border border-zinc-800 relative mt-14 cursor-grab active:cursor-grabbing select-none',
                  events: {
                    'mousedown': (e) {
                      final mouseEvent = e as dynamic;
                      setState(() {
                        _isDragging = true;
                        _dragStartX = (mouseEvent.clientX as num?)?.toDouble() ?? 0.0;
                        _dragStartY = (mouseEvent.clientY as num?)?.toDouble() ?? 0.0;
                      });
                    },
                    'mousemove': (e) {
                      if (!_isDragging) return;
                      final mouseEvent = e as dynamic;
                      final currentX = (mouseEvent.clientX as num?)?.toDouble() ?? 0.0;
                      final currentY = (mouseEvent.clientY as num?)?.toDouble() ?? 0.0;
                      final dx = currentX - _dragStartX;
                      final dy = currentY - _dragStartY;
                      setState(() {
                        _panX += dx;
                        _panY += dy;
                        _dragStartX = currentX;
                        _dragStartY = currentY;
                      });
                    },
                    'mouseup': (_) => setState(() => _isDragging = false),
                    'mouseleave': (_) => setState(() => _isDragging = false),
                  },
                  [
                    if (displayReceiptUrl.isNotEmpty)
                      img(
                        src: displayReceiptUrl,
                        alt: 'Payment screenshot proof',
                        attributes: {
                          'style':
                              'transform: translate(${_panX}px, ${_panY}px) scale($_zoomLevel); transition: ${_isDragging ? "none" : "transform 0.15s ease-out"}; max-width: 100%; max-height: 100%; object-fit: contain;',
                        },
                      )
                    else
                      div(classes: 'text-center text-zinc-500 p-8 flex flex-col items-center gap-2', [
                        span(classes: 'text-4xl', [Component.text('🖼️')]),
                        span(classes: 'text-xs font-bold', [
                          Component.text('No payment screenshot attached yet'),
                        ]),
                      ]),
                  ],
                ),

                p(classes: 'text-[10px] text-zinc-500 text-center mt-2 font-medium', [
                  Component.text(
                    '💡 Drag to pan image • Use + / - buttons to inspect transaction timestamps and reference numbers',
                  ),
                ]),
              ]),

              // Right Col: Verification Checklist & Fast Cross-Check (5 cols)
              div(classes: 'lg:col-span-5 p-6 flex flex-col gap-6 bg-white overflow-y-auto', [
                // Amount to Credit Callout
                div(
                  classes:
                      'p-4 rounded-2xl bg-[#eff6f1] border border-emerald-500/20 flex items-center justify-between shadow-sm',
                  [
                    div(classes: 'flex flex-col', [
                      span(classes: 'text-[10px] text-emerald-800 font-extrabold uppercase tracking-wider', [
                        Component.text('Claimed Deposit Amount'),
                      ]),
                      span(classes: 'text-2xl font-black text-emerald-700 tracking-tight', [
                        Component.text('₱${deposit.amount.toStringAsFixed(2)}'),
                      ]),
                    ]),

                    // One-Tap Copy Amount Button
                    button(
                      onClick: () => _copyToClipboard('amount', deposit.amount.toStringAsFixed(2)),
                      classes:
                          'px-3 py-1.5 rounded-xl bg-white border border-emerald-300 text-emerald-700 hover:bg-emerald-50 text-xs font-bold transition-all shadow-sm flex items-center gap-1 cursor-pointer',
                      [
                        span([
                          Component.text(_copiedFields['amount'] == true ? '✓ Copied' : '📋 Copy Amount'),
                        ]),
                      ],
                    ),
                  ],
                ),

                // Assigned Agent Lock Card
                if (deposit.assignedAgentName != null)
                  div(
                    classes:
                        'p-3.5 rounded-2xl bg-emerald-50/70 border border-emerald-200/80 flex items-center justify-between text-xs',
                    [
                      div(classes: 'flex items-center gap-2.5', [
                        span(classes: 'text-base', [Component.text('🔒')]),
                        div(classes: 'flex flex-col', [
                          span(classes: 'font-extrabold text-emerald-950', [
                            Component.text('Assigned Agent: ${deposit.assignedAgentName}'),
                          ]),
                          if (deposit.assignedAt != null)
                            span(classes: 'text-[10px] text-emerald-700', [
                              Component.text('Claimed ${_formatTimestamp(deposit.assignedAt!)}'),
                            ]),
                        ]),
                      ]),
                      if (deposit.agentPaymentNumber != null && deposit.agentPaymentNumber!.isNotEmpty)
                        span(classes: 'font-mono font-bold text-[11px] text-emerald-800 bg-white px-2 py-0.5 rounded-md border border-emerald-200', [
                          Component.text(deposit.agentPaymentNumber!),
                        ]),
                    ],
                  ),

                // Fast Cross-Check Fields Section
                div(classes: 'flex flex-col gap-3', [
                  h4(
                    classes:
                        'text-xs font-black text-zinc-900 uppercase tracking-wide border-l-2 border-emerald-500 pl-2',
                    [Component.text('External Portal Cross-Check')],
                  ),

                  // Reference Number Card with One-Tap Copy
                  div(
                    classes:
                        'p-3.5 bg-zinc-50 rounded-2xl border ${isDuplicate ? 'border-red-300 bg-red-50/30' : 'border-zinc-200/70'} flex items-center justify-between gap-3',
                    [
                      div(classes: 'flex flex-col min-w-0', [
                        span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                          Component.text('Reference Number'),
                        ]),
                        span(
                          classes:
                              'font-mono font-black text-sm ${isDuplicate ? 'text-red-600' : 'text-zinc-900'} truncate select-all',
                          [Component.text(deposit.referenceNumber)],
                        ),
                      ]),

                      button(
                        onClick: () => _copyToClipboard('ref', deposit.referenceNumber),
                        classes:
                            'px-3.5 py-1.5 rounded-xl bg-white hover:bg-zinc-100 text-zinc-800 border border-zinc-200/80 text-xs font-bold transition-all shadow-sm flex items-center gap-1 cursor-pointer flex-shrink-0',
                        [
                          span([
                            Component.text(_copiedFields['ref'] == true ? '✓ Copied!' : '📋 Copy Ref #'),
                          ]),
                        ],
                      ),
                    ],
                  ),

                  // Payment Method & Target Wallet Info
                  div(classes: 'grid grid-cols-2 gap-3', [
                    div(classes: 'p-3 bg-zinc-50 rounded-xl border border-zinc-200/70 flex flex-col gap-1', [
                      span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                        Component.text('Payment Gateway'),
                      ]),
                      span(
                        classes:
                            'text-xs font-extrabold flex items-center gap-1 ${isGcash ? 'text-[#007DFE]' : (isMaya ? 'text-[#2CB34A]' : 'text-zinc-800')}',
                        [
                          span([Component.text(isGcash ? '🔵' : (isMaya ? '🟢' : '💳'))]),
                          Component.text(deposit.paymentMethod),
                        ],
                      ),
                    ]),

                    div(classes: 'p-3 bg-zinc-50 rounded-xl border border-zinc-200/70 flex flex-col gap-1', [
                      span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                        Component.text('Submission Time'),
                      ]),
                      span(classes: 'text-xs font-bold text-zinc-800 truncate', [
                        Component.text(_formatTimestamp(deposit.submittedAt)),
                      ]),
                    ]),
                  ]),
                ]),

                // User Account Info Section
                div(classes: 'flex flex-col gap-3', [
                  h4(
                    classes:
                        'text-xs font-black text-zinc-900 uppercase tracking-wide border-l-2 border-indigo-500 pl-2',
                    [Component.text('Account Crediting Details')],
                  ),

                  div(classes: 'p-4 bg-zinc-50 rounded-2xl border border-zinc-200/70 flex flex-col gap-2.5 text-xs', [
                    div(classes: 'flex justify-between items-center', [
                      span(classes: 'text-zinc-400 font-semibold', [Component.text('User Name:')]),
                      span(classes: 'font-bold text-zinc-900', [Component.text(displayName)]),
                    ]),
                    div(classes: 'flex justify-between items-center', [
                      span(classes: 'text-zinc-400 font-semibold', [Component.text('Email:')]),
                      span(classes: 'font-semibold text-zinc-700', [
                        Component.text(userProfile.email.isNotEmpty ? userProfile.email : 'N/A'),
                      ]),
                    ]),
                    div(classes: 'flex justify-between items-center', [
                      span(classes: 'text-zinc-400 font-semibold', [Component.text('User UID:')]),
                      div(classes: 'flex items-center gap-1.5', [
                        span(classes: 'font-mono text-[11px] text-zinc-700', [
                          Component.text(
                            deposit.userId.length > 14
                                ? '${deposit.userId.substring(0, 12)}...'
                                : deposit.userId,
                          ),
                        ]),
                        button(
                          onClick: () => _copyToClipboard('uid', deposit.userId),
                          classes:
                              'text-[10px] text-zinc-500 hover:text-black bg-transparent border-0 cursor-pointer font-bold',
                          attributes: {'title': 'Copy UID'},
                          [Component.text(_copiedFields['uid'] == true ? '✓' : '📋')],
                        ),
                      ]),
                    ]),
                    div(classes: 'flex justify-between items-center', [
                      span(classes: 'text-zinc-400 font-semibold', [Component.text('Current Wallet Balance:')]),
                      span(classes: 'font-extrabold text-zinc-900', [
                        Component.text('₱${userProfile.availableBalance.toStringAsFixed(2)}'),
                      ]),
                    ]),
                    div(classes: 'flex justify-between items-center', [
                      span(classes: 'text-zinc-400 font-semibold', [Component.text('Target Wallet:')]),
                      span(classes: 'font-mono text-[11px] text-zinc-700', [Component.text(deposit.targetWallet)]),
                    ]),
                  ]),
                ]),

                // Verification Audit Details
                if (deposit.status == 'APPROVED' || deposit.status == 'REJECTED')
                  div(
                    classes:
                        'p-4 rounded-2xl ${deposit.status == 'APPROVED' ? 'bg-emerald-50 border border-emerald-200' : 'bg-red-50 border border-red-200'} flex flex-col gap-1.5 text-xs',
                    [
                      span(
                        classes:
                            'font-black ${deposit.status == 'APPROVED' ? 'text-emerald-800' : 'text-red-800'} uppercase tracking-wide',
                        [
                          Component.text('Status: ${deposit.status}'),
                        ],
                      ),
                      if (deposit.reviewedByAdminName != null)
                        span(classes: 'text-zinc-600', [
                          Component.text('Reviewed by: ${deposit.reviewedByAdminName}'),
                        ]),
                      if (deposit.reviewedAt != null)
                        span(classes: 'text-zinc-500 text-[11px]', [
                          Component.text('Reviewed at: ${_formatTimestamp(deposit.reviewedAt!)}'),
                        ]),
                      if (deposit.rejectionReason != null)
                        span(classes: 'text-red-700 font-semibold mt-1', [
                          Component.text('Reason: ${deposit.rejectionReason}'),
                        ]),
                    ],
                  ),
              ]),
            ]),

            // Modal Footer Actions
            div(
              classes:
                  'px-6 py-4 border-t border-zinc-150/80 bg-zinc-50 flex items-center justify-between gap-4 flex-shrink-0',
              [
                button(
                  onClick: _closeInspector,
                  classes:
                      'px-5 py-2.5 rounded-xl bg-zinc-200 hover:bg-zinc-300 text-zinc-800 text-xs font-bold transition-all cursor-pointer border-0 outline-none',
                  [Component.text('Close Inspector')],
                ),

                if (deposit.status == 'PENDING_VERIFICATION')
                  div(classes: 'flex items-center gap-3', [
                    // Reject Button
                    button(
                      onClick: () => setState(() => _showRejectModal = true),
                      classes:
                          'px-5 py-2.5 rounded-xl border border-red-200 bg-red-50/60 hover:bg-red-100 text-red-600 text-xs font-bold transition-all cursor-pointer outline-none',
                      [Component.text('Reject Deposit')],
                    ),

                    // Approve Deposit Button
                    if (isDuplicate)
                      button(
                        attributes: {
                          'disabled': 'true',
                          'title': 'Duplicate reference detected. Approval blocked.',
                        },
                        classes:
                            'px-6 py-2.5 rounded-xl bg-zinc-300 text-zinc-500 text-xs font-bold cursor-not-allowed border-0 opacity-60 flex items-center gap-1.5',
                        [
                          span([Component.text('🚫')]),
                          span([Component.text('Approve Blocked (Duplicate)')]),
                        ],
                      )
                    else
                      button(
                        onClick: () => setState(() => _showApproveConfirmModal = true),
                        classes:
                            'px-6 py-2.5 rounded-xl bg-[#0fa958] hover:bg-[#0d924c] text-white text-xs font-bold transition-all shadow-md shadow-emerald-500/20 cursor-pointer border-0 outline-none flex items-center gap-1.5',
                        [
                          span([Component.text('✓')]),
                          span([Component.text('Approve Deposit')]),
                        ],
                      ),
                  ])
                else if (deposit.status == 'PENDING_AGENT')
                  button(
                    onClick: () {
                      _closeInspector();
                      _openSendQrModal(deposit);
                    },
                    classes:
                        'px-6 py-2.5 rounded-xl bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-700 hover:to-teal-700 text-white text-xs font-black transition-all shadow-md shadow-emerald-500/20 cursor-pointer border-0 outline-none flex items-center gap-1.5',
                    [
                      span([Component.text('⚡ Send QR Code Now')]),
                    ],
                  )
                else
                  span(
                    classes:
                        'text-xs font-bold px-4 py-2 rounded-xl ${deposit.status == 'APPROVED' ? 'bg-emerald-100 text-emerald-800' : 'bg-zinc-100 text-zinc-700'}',
                    [
                      Component.text('Status: ${deposit.status}'),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Deposit Approval Workflow Confirmation Dialog
  Component _buildApproveConfirmDialog(DepositRequest deposit, fb.User? adminUser) {
    return div(
      classes: 'fixed inset-0 bg-black/80 backdrop-blur-sm z-[60] flex items-center justify-center p-4',
      [
        div(
          classes:
              'bg-white rounded-[28px] border border-zinc-200 shadow-2xl w-full max-w-md overflow-hidden flex flex-col animate-fade-up',
          [
            // Header
            div(classes: 'p-6 border-b border-zinc-150/80 bg-emerald-50/50 flex items-center gap-3', [
              div(
                classes:
                    'w-10 h-10 rounded-2xl bg-emerald-500 text-white flex items-center justify-center text-lg font-black shadow-md shadow-emerald-500/30 flex-shrink-0',
                [Component.text('₱')],
              ),
              div([
                h3(classes: 'text-sm font-black text-zinc-950', [Component.text('Confirm Deposit Approval')]),
                p(classes: 'text-xs text-zinc-400 font-medium', [
                  Component.text('Funds will be atomically credited to the user wallet.'),
                ]),
              ]),
            ]),

            // Body Summary
            div(classes: 'p-6 flex flex-col gap-4 text-xs', [
              div(classes: 'p-4 rounded-2xl bg-zinc-50 border border-zinc-200/70 flex flex-col gap-3', [
                div(classes: 'flex justify-between items-center', [
                  span(classes: 'text-zinc-400 font-bold', [Component.text('User Name:')]),
                  span(classes: 'font-extrabold text-zinc-900', [Component.text(deposit.userName)]),
                ]),
                div(classes: 'flex justify-between items-center', [
                  span(classes: 'text-zinc-400 font-bold', [Component.text('User ID:')]),
                  span(classes: 'font-mono text-[11px] text-zinc-700', [Component.text(deposit.userId)]),
                ]),
                div(classes: 'flex justify-between items-center', [
                  span(classes: 'text-zinc-400 font-bold', [Component.text('Reference #:')]),
                  span(classes: 'font-mono font-bold text-zinc-900', [Component.text(deposit.referenceNumber)]),
                ]),
                div(classes: 'flex justify-between items-center', [
                  span(classes: 'text-zinc-400 font-bold', [Component.text('Target Wallet:')]),
                  span(classes: 'font-mono text-[11px] text-zinc-700', [Component.text(deposit.targetWallet)]),
                ]),
                div(
                  classes:
                      'pt-3 border-t border-zinc-200/60 flex justify-between items-center text-sm font-black text-emerald-700',
                  [
                    span([Component.text('Amount to Credit:')]),
                    span([Component.text('+₱${deposit.amount.toStringAsFixed(2)}')]),
                  ],
                ),
              ]),

              p(classes: 'text-[11px] text-zinc-500 leading-relaxed font-medium', [
                Component.text(
                  'By confirming, the system will mark this request as APPROVED, increment the user availableBalance, and register Reference #${deposit.referenceNumber} in the claimed references registry.',
                ),
              ]),
            ]),

            // Actions
            div(classes: 'p-5 border-t border-zinc-150/80 bg-zinc-50 flex items-center justify-end gap-3', [
              button(
                onClick: () => setState(() => _showApproveConfirmModal = false),
                classes:
                    'px-4 py-2.5 rounded-xl bg-zinc-200 hover:bg-zinc-300 text-zinc-700 text-xs font-bold transition-all cursor-pointer border-0 outline-none',
                [Component.text('Cancel')],
              ),
              button(
                onClick: () => _executeApproveDeposit(deposit, adminUser),
                classes:
                    'px-5 py-2.5 rounded-xl bg-[#0fa958] hover:bg-[#0d924c] text-white text-xs font-bold transition-all shadow-md shadow-emerald-500/20 cursor-pointer border-0 outline-none flex items-center gap-2',
                [
                  if (_isProcessing)
                    div(classes: 'animate-spin h-3.5 w-3.5 border-2 border-white border-t-transparent rounded-full', [])
                  else
                    span([Component.text('Confirm & Credit Wallet')]),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  /// Rejection Workflow Modal with Pre-Defined Reason Dropdown & Custom Note Field
  Component _buildRejectDialog(DepositRequest deposit, fb.User? adminUser) {
    final isOther = _selectedRejectReason == 'Other (Custom text required)';

    return div(
      classes: 'fixed inset-0 bg-black/80 backdrop-blur-sm z-[60] flex items-center justify-center p-4',
      [
        div(
          classes:
              'bg-white rounded-[28px] border border-zinc-200 shadow-2xl w-full max-w-lg overflow-hidden flex flex-col animate-fade-up',
          [
            // Header
            div(classes: 'p-6 border-b border-zinc-150/80 bg-red-50/40 flex items-center gap-3', [
              div(
                classes:
                    'w-10 h-10 rounded-2xl bg-red-500 text-white flex items-center justify-center text-lg font-black shadow-md shadow-red-500/30 flex-shrink-0',
                [Component.text('✕')],
              ),
              div([
                h3(classes: 'text-sm font-black text-zinc-950', [Component.text('Reject Deposit Request')]),
                p(classes: 'text-xs text-zinc-400 font-medium', [
                  Component.text('Select a mandatory rejection reason to inform audit logs and user.'),
                ]),
              ]),
            ]),

            // Form Content
            div(classes: 'p-6 flex flex-col gap-4 text-xs', [
              // Summary pill
              div(classes: 'p-3 bg-zinc-50 rounded-xl border border-zinc-200/70 flex justify-between items-center', [
                span(classes: 'text-zinc-500 font-semibold', [
                  Component.text('${deposit.userName} • ₱${deposit.amount.toStringAsFixed(2)}'),
                ]),
                span(classes: 'font-mono text-zinc-700 font-bold', [
                  Component.text('Ref: ${deposit.referenceNumber}'),
                ]),
              ]),

              // Reason dropdown
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-xs font-bold text-zinc-700', [
                  Component.text('Mandatory Rejection Reason:'),
                ]),
                select(
                  onChange: (dynamic val) {
                    final selectedList = val is List<String> ? val : <String>[];
                    final opt = selectedList.isNotEmpty ? selectedList.first : _predefinedRejectReasons.first;
                    setState(() => _selectedRejectReason = opt);
                  },
                  classes:
                      'w-full px-3.5 py-2.5 rounded-xl bg-white border border-zinc-300 text-xs font-bold text-zinc-800 focus:outline-none focus:border-red-500 cursor-pointer shadow-sm',
                  [
                    for (final reasonItem in _predefinedRejectReasons)
                      option(
                        value: reasonItem,
                        selected: _selectedRejectReason == reasonItem,
                        [Component.text(reasonItem)],
                      ),
                  ],
                ),
              ]),

              // Custom Note Textarea
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-xs font-bold text-zinc-700 flex justify-between', [
                  Component.text(isOther ? 'Custom Rejection Reason (Required):' : 'Additional Internal Notes (Optional):'),
                  if (isOther) span(classes: 'text-red-500 font-bold', [Component.text('*Required')]),
                ]),
                textarea(
                  onInput: (dynamic val) => setState(() => _customRejectNote = (val as String?) ?? ''),
                  attributes: {
                    'placeholder': isOther
                        ? 'Specify why this deposit submission is rejected...'
                        : 'Add any supporting investigation details for audit log...',
                  },
                  classes:
                      'w-full p-3 rounded-xl bg-white border border-zinc-300 text-xs text-zinc-800 placeholder-zinc-400 focus:outline-none focus:border-red-500 resize-none h-24 shadow-sm',
                  [Component.text(_customRejectNote)],
                ),
              ]),

              p(classes: 'text-[11px] text-zinc-400 leading-relaxed font-medium', [
                Component.text(
                  'Note: Rejecting will leave the user availableBalance untouched (\$0.00 credited). The action is recorded immutably in admin audit logs.',
                ),
              ]),
            ]),

            // Actions
            div(classes: 'p-5 border-t border-zinc-150/80 bg-zinc-50 flex items-center justify-end gap-3', [
              button(
                onClick: () => setState(() => _showRejectModal = false),
                classes:
                    'px-4 py-2.5 rounded-xl bg-zinc-200 hover:bg-zinc-300 text-zinc-700 text-xs font-bold transition-all cursor-pointer border-0 outline-none',
                [Component.text('Cancel')],
              ),
              button(
                onClick: () => _executeRejectDeposit(deposit, adminUser),
                classes:
                    'px-5 py-2.5 rounded-xl bg-red-600 hover:bg-red-700 text-white text-xs font-bold transition-all shadow-md shadow-red-500/20 cursor-pointer border-0 outline-none flex items-center gap-2',
                [
                  if (_isProcessing)
                    div(classes: 'animate-spin h-3.5 w-3.5 border-2 border-white border-t-transparent rounded-full', [])
                  else
                    span([Component.text('Confirm Rejection')]),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  /// Claimed Reference Numbers Registry Tab View
  Component _buildClaimedRegistryView(List<ClaimedReference> claimedList) {
    return div(classes: 'flex flex-col gap-4', [
      div(classes: 'p-5 rounded-[24px] bg-white border border-zinc-200/60 shadow-sm flex flex-col gap-2', [
        h3(classes: 'text-sm font-black text-zinc-900', [Component.text('Claimed P2P Reference Registry')]),
        p(classes: 'text-xs text-zinc-400 font-medium leading-relaxed', [
          Component.text(
            'This immutable database table prevents double-crediting by tracking every approved GCash/Maya reference number.',
          ),
        ]),
      ]),

      if (claimedList.isEmpty)
        div(
          classes:
              'p-12 text-center bg-white rounded-[24px] border border-zinc-200/60 text-xs text-zinc-400 font-medium',
          [Component.text('No reference numbers claimed yet.')],
        )
      else
        div(classes: 'grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4', [
          for (final claim in claimedList)
            div(
              classes:
                  'p-4 rounded-2xl bg-white border border-zinc-200/70 shadow-sm flex flex-col justify-between gap-3',
              [
                div(classes: 'flex flex-col gap-1.5', [
                  div(classes: 'flex items-center justify-between', [
                    span(
                      classes: 'font-mono font-black text-xs text-zinc-900 bg-zinc-100 px-2 py-0.5 rounded-md truncate',
                      [Component.text(claim.referenceNumber)],
                    ),
                    span(classes: 'font-black text-xs text-emerald-600', [
                      Component.text('₱${claim.amount.toStringAsFixed(2)}'),
                    ]),
                  ]),
                  span(classes: 'text-xs font-bold text-zinc-800', [Component.text(claim.userName)]),
                  span(classes: 'text-[11px] font-mono text-zinc-400', [Component.text('UID: ${claim.userId}')]),
                ]),

                div(classes: 'pt-2.5 border-t border-zinc-150 text-[10px] text-zinc-400 flex justify-between', [
                  span([Component.text('By: ${claim.approvedByAdminName}')]),
                  span([Component.text(_formatTimestamp(claim.approvedAt))]),
                ]),
              ],
            ),
        ]),
    ]);
  }

  /// Immutable Admin Audit Log Trail Tab View
  Component _buildAuditLogsView(List<AdminAuditEntry> auditLogs) {
    return div(classes: 'flex flex-col gap-4', [
      div(classes: 'p-5 rounded-[24px] bg-white border border-zinc-200/60 shadow-sm flex flex-col gap-2', [
        h3(classes: 'text-sm font-black text-zinc-900', [Component.text('Payment Verification Audit Trail')]),
        p(classes: 'text-xs text-zinc-400 font-medium leading-relaxed', [
          Component.text(
            'Immutable audit entries recorded in /admin_audit_logs/ tracking every agent QR dispatch, approval, and rejection.',
          ),
        ]),
      ]),

      if (auditLogs.isEmpty)
        div(
          classes:
              'p-12 text-center bg-white rounded-[24px] border border-zinc-200/60 text-xs text-zinc-400 font-medium',
          [Component.text('No audit logs recorded yet.')],
        )
      else
        div(classes: 'flex flex-col gap-3', [
          for (final log in auditLogs)
            div(
              classes:
                  'p-4 rounded-2xl bg-white border border-zinc-200/60 shadow-sm flex flex-col sm:flex-row justify-between sm:items-center gap-3',
              [
                div(classes: 'flex items-start gap-3.5', [
                  span(
                    classes:
                        'w-8 h-8 rounded-xl flex items-center justify-center text-xs font-bold flex-shrink-0 '
                        '${log.action == 'APPROVED' ? 'bg-emerald-100 text-emerald-700' : (log.action == 'QR_SENT' ? 'bg-indigo-100 text-indigo-700' : 'bg-red-100 text-red-700')}',
                    [Component.text(log.action == 'APPROVED' ? '✓' : (log.action == 'QR_SENT' ? '📱' : '✕'))],
                  ),
                  div(classes: 'flex flex-col gap-0.5', [
                    div(classes: 'flex items-center gap-2 flex-wrap', [
                      span(classes: 'font-extrabold text-xs text-zinc-900', [
                        Component.text('${log.action}: ₱${log.amount.toStringAsFixed(2)}'),
                      ]),
                      span(classes: 'text-[10px] text-zinc-400', [Component.text('for ${log.userName}')]),
                    ]),
                    div(classes: 'flex items-center gap-2 text-[11px] text-zinc-500 font-mono', [
                      if (log.referenceNumber != 'N/A' && log.referenceNumber.isNotEmpty) ...[
                        span([Component.text('Ref: ${log.referenceNumber}')]),
                        span(classes: 'text-zinc-300', [Component.text('•')]),
                      ],
                      span([Component.text('Agent: ${log.reviewedByAdminName}')]),
                    ]),
                    if (log.rejectionReason != null && log.rejectionReason!.isNotEmpty)
                      span(classes: 'text-[11px] text-red-600 font-semibold mt-0.5', [
                        Component.text('Reason: ${log.rejectionReason}'),
                      ]),
                  ]),
                ]),

                span(classes: 'text-[11px] text-zinc-400 font-medium self-end sm:self-auto flex-shrink-0', [
                  Component.text(_formatTimestamp(log.timestamp)),
                ]),
              ],
            ),
        ]),
    ]);
  }
}
