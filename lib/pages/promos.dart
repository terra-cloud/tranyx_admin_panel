import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:web/web.dart' as web;

import '../app.dart';
import '../core/providers/environment_provider.dart';
import '../core/services/promotion_calculator.dart';

class PromoItem {
  final String code;
  final String name;
  final String applyToFee; // 'platform_fee', 'transaction_fee', 'convenience_fee', 'service_fee', 'markup_fee', 'all_fees'
  final String applicableTo; // 'both', 'rentals', 'services', 'vehicles', 'properties', 'items'
  final String discountType; // 'percentage', 'flat'
  final double discountValue;
  final double? minTransactionAmount;
  final double? maxDiscountCap;
  final DateTime? startDate;
  final DateTime? expirationDate;
  final int? maxUsers;
  final bool isSingleUsePerUser;
  final bool isAutoApply;
  final List<String> eligibleUserUids;
  final bool onlyForSubscribed;
  final bool onlyForHybrid;
  final List<String> applicableRoles;
  final bool isActive;
  final int usedCount;
  final List<String> usedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  bool get isExpired {
    if (expirationDate == null) return false;
    final now = DateTime.now();
    final expEnd = DateTime(expirationDate!.year, expirationDate!.month, expirationDate!.day, 23, 59, 59);
    return now.isAfter(expEnd);
  }

  bool get isUpcoming {
    if (startDate == null) return false;
    final now = DateTime.now();
    return now.isBefore(startDate!);
  }

  bool get isLimitReached {
    if (maxUsers == null || maxUsers! <= 0) return false;
    return usedCount >= maxUsers!;
  }

  bool get isCurrentlyActive {
    return isActive && !isExpired && !isUpcoming && !isLimitReached;
  }

  String get effectiveStatusLabel {
    if (!isActive) return 'Paused';
    if (isExpired) return 'Expired';
    if (isUpcoming) return 'Scheduled';
    if (isLimitReached) return 'Limit Reached';
    return 'Active';
  }

  PromoItem({
    required this.code,
    required this.name,
    required this.applyToFee,
    required this.applicableTo,
    required this.discountType,
    required this.discountValue,
    this.minTransactionAmount,
    this.maxDiscountCap,
    this.startDate,
    this.expirationDate,
    this.maxUsers,
    required this.isSingleUsePerUser,
    required this.isAutoApply,
    required this.eligibleUserUids,
    required this.onlyForSubscribed,
    required this.onlyForHybrid,
    required this.applicableRoles,
    required this.isActive,
    required this.usedCount,
    required this.usedBy,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  factory PromoItem.fromMap(String code, Map<String, dynamic> map) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return PromoItem(
      code: code,
      name: map['name'] ?? map['title'] ?? 'Promo $code',
      applyToFee: map['applyToFee'] ?? map['targetFee'] ?? TranyxFeeType.platformFee,
      applicableTo: map['applicableTo'] ?? 'both',
      discountType: map['discountType'] ?? 'percentage',
      discountValue: (map['discountValue'] as num?)?.toDouble() ?? 0.0,
      minTransactionAmount: (map['minTransactionAmount'] as num?)?.toDouble(),
      maxDiscountCap: (map['maxDiscountCap'] as num?)?.toDouble(),
      startDate: parseDate(map['startDate']),
      expirationDate: parseDate(map['expirationDate']),
      maxUsers: map['maxUsers'] != null ? (map['maxUsers'] as num).toInt() : null,
      isSingleUsePerUser: map['isSingleUsePerUser'] == true,
      isAutoApply: map['isAutoApply'] == true,
      eligibleUserUids: List<String>.from(map['eligibleUserUids'] ?? []),
      onlyForSubscribed: map['onlyForSubscribed'] == true,
      onlyForHybrid: map['onlyForHybrid'] == true,
      applicableRoles: List<String>.from(map['applicableRoles'] ?? []),
      isActive: map['isActive'] != false,
      usedCount: (map['usedCount'] as num? ?? 0).toInt(),
      usedBy: List<String>.from(map['usedBy'] ?? []),
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      createdBy: map['createdBy'],
      updatedBy: map['updatedBy'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'name': name,
      'applyToFee': applyToFee,
      'applicableTo': applicableTo,
      'discountType': discountType,
      'discountValue': discountValue,
      'minTransactionAmount': minTransactionAmount,
      'maxDiscountCap': maxDiscountCap,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'expirationDate': expirationDate != null ? Timestamp.fromDate(expirationDate!) : null,
      'maxUsers': maxUsers,
      'isSingleUsePerUser': isSingleUsePerUser,
      'isAutoApply': isAutoApply,
      'eligibleUserUids': eligibleUserUids,
      'onlyForSubscribed': onlyForSubscribed,
      'onlyForHybrid': onlyForHybrid,
      'applicableRoles': applicableRoles,
      'isActive': isActive,
      'usedCount': usedCount,
      'usedBy': usedBy,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (createdBy != null) 'createdBy': createdBy,
      if (updatedBy != null) 'updatedBy': updatedBy,
    };
  }
}

class PromoAuditEntry {
  final String id;
  final String promoCode;
  final String promoName;
  final String action; // 'CREATED', 'UPDATED', 'ACTIVATED', 'DEACTIVATED', 'DELETED', 'UPDATED_FEE_CONFIG'
  final String adminEmail;
  final String adminName;
  final String applyToFee;
  final String discountSummary;
  final DateTime timestamp;
  final Map<String, dynamic> details;

  PromoAuditEntry({
    required this.id,
    required this.promoCode,
    required this.promoName,
    required this.action,
    required this.adminEmail,
    required this.adminName,
    required this.applyToFee,
    required this.discountSummary,
    required this.timestamp,
    required this.details,
  });

  factory PromoAuditEntry.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return PromoAuditEntry(
      id: id,
      promoCode: map['promoCode'] ?? 'UNKNOWN',
      promoName: map['promoName'] ?? 'Promotion',
      action: map['action'] ?? 'MODIFIED',
      adminEmail: map['adminEmail'] ?? 'staff@tranyx.com',
      adminName: map['adminName'] ?? 'Admin Staff',
      applyToFee: map['applyToFee'] ?? TranyxFeeType.platformFee,
      discountSummary: map['discountSummary'] ?? '',
      timestamp: parseDate(map['timestamp']),
      details: Map<String, dynamic>.from(map['details'] ?? {}),
    );
  }
}

final promosStreamProvider = StreamProvider<List<PromoItem>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final userAsync = ref.watch(activeEnvAuthUserProvider);

  if (userAsync.value == null) {
    return Stream.value(<PromoItem>[]);
  }

  return firestore
      .collection('promos')
      .snapshots()
      .map((snap) {
        final list = snap.docs.map((doc) => PromoItem.fromMap(doc.id, doc.data())).toList();
        list.sort((itemA, itemB) {
          final aDate = itemA.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = itemB.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
        return list;
      })
      .handleError((err) {
        print('[Promos] Stream failed: $err');
        return <PromoItem>[];
      });
});

final feeConfigStreamProvider = StreamProvider<FeeConfiguration>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final userAsync = ref.watch(activeEnvAuthUserProvider);

  if (userAsync.value == null) {
    return Stream.value(const FeeConfiguration());
  }

  return firestore
      .collection('system_config')
      .doc('fee_configurations')
      .snapshots()
      .map((doc) {
        if (!doc.exists || doc.data() == null) {
          return const FeeConfiguration();
        }
        return FeeConfiguration.fromMap(doc.data()!);
      })
      .handleError((err) {
        print('[Fee Config] Stream error: $err');
        return const FeeConfiguration();
      });
});

final promoAuditStreamProvider = StreamProvider<List<PromoAuditEntry>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final userAsync = ref.watch(activeEnvAuthUserProvider);

  if (userAsync.value == null) {
    return Stream.value(<PromoAuditEntry>[]);
  }

  return firestore
      .collection('promo_audit_trail')
      .orderBy('timestamp', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) {
        return snap.docs.map((doc) => PromoAuditEntry.fromMap(doc.id, doc.data())).toList();
      })
      .handleError((err) {
        print('[Promo Audit] Stream failed: $err');
        return <PromoAuditEntry>[];
      });
});

class PromosPage extends StatefulComponent {
  const PromosPage({super.key});

  @override
  State<PromosPage> createState() => _PromosPageState();
}

class _PromosPageState extends State<PromosPage> {
  // Form Key Version to force full DOM reset on submit
  int _formVersion = 0;

  // Active View Tab: 'list', 'fee_config', 'simulator', 'audit'
  String _activeTab = 'list';

  // Search & Filter
  String _searchFilter = '';
  String _statusFilter = 'all'; // 'all', 'active', 'inactive', 'auto'
  String _feeTargetFilter = 'all';

  // Promotion Form State
  String _name = '';
  String _code = '';
  String _applyToFee = TranyxFeeType.platformFee;
  String _applicableTo = 'both';
  String _discountType = 'percentage';
  String _discountValueStr = '100';
  String _minTransactionStr = '';
  String _maxDiscountCapStr = '';
  String _startDateStr = '';
  String _expirationDateStr = '';
  String _maxUsersStr = '1000';
  bool _isSingleUsePerUser = true;
  bool _isAutoApply = true;
  String _eligibleUserUidsStr = '';
  bool _onlyForSubscribed = false;
  bool _onlyForHybrid = false;
  bool _isActive = true;

  // Targeted Roles
  bool _roleRenter = true;
  bool _roleHost = true;
  bool _roleEmployer = true;
  bool _roleNyxian = true;

  // Editing State
  PromoItem? _editingPromo;

  // Fee & Markups Configuration Form State
  bool _isFeeConfigLoaded = false;
  String _cfgDefaultPlatformRate = '10.0';
  String _cfgDefaultTxRate = '2.5';
  String _cfgDefaultTxFixed = '15.0';
  String _cfgDefaultConvRate = '1.0';
  String _cfgDefaultConvFixed = '20.0';
  String _cfgDefaultServiceRate = '5.0';
  String _cfgDefaultServiceFixed = '0.0';
  String _cfgVehiclePlatformRate = '10.0';
  String _cfgVehicleMarkupRate = '2.0';
  String _cfgPropertyPlatformRate = '8.0';
  String _cfgPropertyMarkupRate = '1.5';
  String _cfgServicePlatformRate = '10.0';
  String _cfgServiceMarkupRate = '0.0';
  String _cfgItemPlatformRate = '12.0';
  String _cfgItemMarkupRate = '2.0';
  String _cfgWeekendSurcharge = '3.0';
  String _cfgPeakSeasonSurcharge = '5.0';
  String _cfgSecurityHandlingFixed = '50.0';
  String _cfgInstantBookingFixed = '30.0';
  String _cfgMinPlatformCap = '20.0';
  String _cfgMaxPlatformCap = '5000.0';
  String _cfgSubscribedDiscount = '20.0';
  String _cfgHybridDiscount = '30.0';
  bool _isSavingFeeConfig = false;
  String? _feeConfigMessage;

  // Live Simulator Inputs
  double _simListingPrice = 2000.0;
  String _simCategory = 'vehicles';
  bool _simIsWeekend = false;
  bool _simIsPeak = false;
  bool _simHasDeposit = false;
  bool _simIsInstant = false;
  bool _simIsSubscribed = false;
  bool _simIsHybrid = false;
  String _simSelectedPromoCode = 'ZEROFEES1000';

  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _applyAutoZeroFeesTemplate();
  }

  void _syncFeeConfigState(FeeConfiguration config) {
    if (_isFeeConfigLoaded) return;
    _isFeeConfigLoaded = true;
    _cfgDefaultPlatformRate = config.defaultPlatformFeeRate.toString();
    _cfgDefaultTxRate = config.defaultTransactionFeeRate.toString();
    _cfgDefaultTxFixed = config.defaultTransactionFeeFixed.toString();
    _cfgDefaultConvRate = config.defaultConvenienceFeeRate.toString();
    _cfgDefaultConvFixed = config.defaultConvenienceFeeFixed.toString();
    _cfgDefaultServiceRate = config.defaultServiceFeeRate.toString();
    _cfgDefaultServiceFixed = config.defaultServiceFeeFixed.toString();
    _cfgVehiclePlatformRate = config.vehiclePlatformFeeRate.toString();
    _cfgVehicleMarkupRate = config.vehicleMarkupRate.toString();
    _cfgPropertyPlatformRate = config.propertyPlatformFeeRate.toString();
    _cfgPropertyMarkupRate = config.propertyMarkupRate.toString();
    _cfgServicePlatformRate = config.servicePlatformFeeRate.toString();
    _cfgServiceMarkupRate = config.serviceMarkupRate.toString();
    _cfgItemPlatformRate = config.itemPlatformFeeRate.toString();
    _cfgItemMarkupRate = config.itemMarkupRate.toString();
    _cfgWeekendSurcharge = config.weekendSurchargeRate.toString();
    _cfgPeakSeasonSurcharge = config.peakSeasonSurchargeRate.toString();
    _cfgSecurityHandlingFixed = config.securityHandlingFeeFixed.toString();
    _cfgInstantBookingFixed = config.instantBookingFeeFixed.toString();
    _cfgMinPlatformCap = config.minPlatformFeeCap.toString();
    _cfgMaxPlatformCap = config.maxPlatformFeeCap.toString();
    _cfgSubscribedDiscount = config.subscribedFeeDiscountPct.toString();
    _cfgHybridDiscount = config.hybridFeeDiscountPct.toString();
  }

  void _applyAutoZeroFeesTemplate() {
    setState(() {
      _name = 'Auto Zero Fees (First 1,000 Users)';
      _code = 'ZEROFEES1000';
      _applyToFee = TranyxFeeType.platformFee;
      _applicableTo = 'both';
      _discountType = 'percentage';
      _discountValueStr = '100';
      _minTransactionStr = '';
      _maxDiscountCapStr = '';
      _startDateStr = '';
      _expirationDateStr = '';
      _maxUsersStr = '1000';
      _isSingleUsePerUser = true;
      _isAutoApply = true;
      _onlyForSubscribed = false;
      _onlyForHybrid = false;
      _isActive = true;
      _roleRenter = true;
      _roleHost = true;
      _roleEmployer = true;
      _roleNyxian = true;
      _errorMessage = null;
      _successMessage = 'Auto Zero Fees (First 1,000 Users) template loaded!';
    });
  }

  void _apply50PercentLaunchTemplate() {
    setState(() {
      _name = 'TRANYX Launch Promo';
      _code = 'LAUNCH50';
      _applyToFee = TranyxFeeType.platformFee;
      _applicableTo = 'both';
      _discountType = 'percentage';
      _discountValueStr = '50';
      _minTransactionStr = '500';
      _maxDiscountCapStr = '100';
      _startDateStr = '';
      _expirationDateStr = '';
      _maxUsersStr = '500';
      _isSingleUsePerUser = true;
      _isAutoApply = false;
      _onlyForSubscribed = false;
      _onlyForHybrid = false;
      _isActive = true;
      _errorMessage = null;
      _successMessage = '50% Platform Fee Launch template loaded!';
    });
  }

  void _applyFlat50FeeTemplate() {
    setState(() {
      _name = '₱50 OFF Platform Fee';
      _code = 'FEE50OFF';
      _applyToFee = TranyxFeeType.platformFee;
      _applicableTo = 'both';
      _discountType = 'flat';
      _discountValueStr = '50';
      _minTransactionStr = '';
      _maxDiscountCapStr = '';
      _startDateStr = '';
      _expirationDateStr = '';
      _maxUsersStr = '';
      _isSingleUsePerUser = true;
      _isAutoApply = false;
      _onlyForSubscribed = false;
      _onlyForHybrid = false;
      _isActive = true;
      _errorMessage = null;
      _successMessage = '₱50 Flat Platform Fee template loaded!';
    });
  }

  void _resetForm() {
    setState(() {
      _formVersion++;
      _editingPromo = null;
      _name = '';
      _code = '';
      _applyToFee = TranyxFeeType.platformFee;
      _applicableTo = 'both';
      _discountType = 'percentage';
      _discountValueStr = '';
      _minTransactionStr = '';
      _maxDiscountCapStr = '';
      _startDateStr = '';
      _expirationDateStr = '';
      _maxUsersStr = '';
      _isSingleUsePerUser = false;
      _isAutoApply = false;
      _eligibleUserUidsStr = '';
      _onlyForSubscribed = false;
      _onlyForHybrid = false;
      _isActive = true;
      _roleRenter = false;
      _roleHost = false;
      _roleEmployer = false;
      _roleNyxian = false;
      _errorMessage = null;
      _successMessage = null;
    });
  }

  void _loadPromoForEdit(PromoItem promo) {
    setState(() {
      _editingPromo = promo;
      _name = promo.name;
      _code = promo.code;
      _applyToFee = promo.applyToFee;
      _applicableTo = promo.applicableTo;
      _discountType = promo.discountType;
      _discountValueStr = promo.discountValue.toString();
      _minTransactionStr = promo.minTransactionAmount != null ? promo.minTransactionAmount.toString() : '';
      _maxDiscountCapStr = promo.maxDiscountCap != null ? promo.maxDiscountCap.toString() : '';
      _startDateStr = promo.startDate != null
          ? '${promo.startDate!.year}-${promo.startDate!.month.toString().padLeft(2, '0')}-${promo.startDate!.day.toString().padLeft(2, '0')}'
          : '';
      _expirationDateStr = promo.expirationDate != null
          ? '${promo.expirationDate!.year}-${promo.expirationDate!.month.toString().padLeft(2, '0')}-${promo.expirationDate!.day.toString().padLeft(2, '0')}'
          : '';
      _maxUsersStr = promo.maxUsers != null ? promo.maxUsers.toString() : '';
      _isSingleUsePerUser = promo.isSingleUsePerUser;
      _isAutoApply = promo.isAutoApply;
      _eligibleUserUidsStr = promo.eligibleUserUids.join(', ');
      _onlyForSubscribed = promo.onlyForSubscribed;
      _onlyForHybrid = promo.onlyForHybrid;
      _isActive = promo.isActive;
      _roleRenter = promo.applicableRoles.contains('renter');
      _roleHost = promo.applicableRoles.contains('host');
      _roleEmployer = promo.applicableRoles.contains('employer');
      _roleNyxian = promo.applicableRoles.contains('nyxian');
      _activeTab = 'list';
      _errorMessage = null;
      _successMessage = 'Loaded promo ${promo.code} into form for modification.';
    });
  }

  Future<void> _logAuditTrail({
    required BuildContext context,
    required String promoCode,
    required String promoName,
    required String action,
    required String applyToFee,
    required String discountSummary,
    required Map<String, dynamic> details,
  }) async {
    try {
      final firestore = context.read(firestoreProvider);
      final user = context.read(adminCurrentUserProvider).value;
      final adminEmail = user?.email ?? 'admin@tranyx.com';
      final adminName = user?.displayName ?? 'System Admin';

      await firestore.collection('promo_audit_trail').add({
        'promoCode': promoCode,
        'promoName': promoName,
        'action': action,
        'adminEmail': adminEmail,
        'adminName': adminName,
        'adminUid': user?.uid ?? 'unknown',
        'applyToFee': applyToFee,
        'discountSummary': discountSummary,
        'timestamp': FieldValue.serverTimestamp(),
        'details': details,
      });
    } catch (e) {
      print('[Audit] Failed to log promo action: $e');
    }
  }

  Future<void> _saveFeeConfigurations(BuildContext context) async {
    setState(() {
      _isSavingFeeConfig = true;
      _feeConfigMessage = null;
    });

    try {
      final firestore = context.read(firestoreProvider);
      final user = context.read(adminCurrentUserProvider).value;

      double parseNum(String val, double fallback) => double.tryParse(val.trim()) ?? fallback;

      final config = FeeConfiguration(
        defaultPlatformFeeRate: parseNum(_cfgDefaultPlatformRate, 10.0),
        defaultTransactionFeeRate: parseNum(_cfgDefaultTxRate, 2.5),
        defaultTransactionFeeFixed: parseNum(_cfgDefaultTxFixed, 15.0),
        defaultConvenienceFeeRate: parseNum(_cfgDefaultConvRate, 1.0),
        defaultConvenienceFeeFixed: parseNum(_cfgDefaultConvFixed, 20.0),
        defaultServiceFeeRate: parseNum(_cfgDefaultServiceRate, 5.0),
        defaultServiceFeeFixed: parseNum(_cfgDefaultServiceFixed, 0.0),
        vehiclePlatformFeeRate: parseNum(_cfgVehiclePlatformRate, 10.0),
        vehicleMarkupRate: parseNum(_cfgVehicleMarkupRate, 2.0),
        propertyPlatformFeeRate: parseNum(_cfgPropertyPlatformRate, 8.0),
        propertyMarkupRate: parseNum(_cfgPropertyMarkupRate, 1.5),
        servicePlatformFeeRate: parseNum(_cfgServicePlatformRate, 10.0),
        serviceMarkupRate: parseNum(_cfgServiceMarkupRate, 0.0),
        itemPlatformFeeRate: parseNum(_cfgItemPlatformRate, 12.0),
        itemMarkupRate: parseNum(_cfgItemMarkupRate, 2.0),
        weekendSurchargeRate: parseNum(_cfgWeekendSurcharge, 3.0),
        peakSeasonSurchargeRate: parseNum(_cfgPeakSeasonSurcharge, 5.0),
        securityHandlingFeeFixed: parseNum(_cfgSecurityHandlingFixed, 50.0),
        instantBookingFeeFixed: parseNum(_cfgInstantBookingFixed, 30.0),
        minPlatformFeeCap: parseNum(_cfgMinPlatformCap, 20.0),
        maxPlatformFeeCap: parseNum(_cfgMaxPlatformCap, 5000.0),
        subscribedFeeDiscountPct: parseNum(_cfgSubscribedDiscount, 20.0),
        hybridFeeDiscountPct: parseNum(_cfgHybridDiscount, 30.0),
        updatedAt: DateTime.now(),
        updatedBy: user?.email ?? 'admin@tranyx.com',
      );

      await firestore.collection('system_config').doc('fee_configurations').set(config.toMap(), SetOptions(merge: true));

      await _logAuditTrail(
        context: context,
        promoCode: 'SYSTEM_FEE_CONFIG',
        promoName: 'Fee & Markup Global Rule',
        action: 'UPDATED_FEE_CONFIG',
        applyToFee: 'all_fees',
        discountSummary: 'Updated Platform Fees, Markups & Surcharges',
        details: config.toMap(),
      );

      setState(() {
        _feeConfigMessage = 'Fee and markup configurations successfully updated and deployed!';
      });
    } catch (e) {
      setState(() {
        _feeConfigMessage = 'Failed to save fee configurations: $e';
      });
    } finally {
      setState(() {
        _isSavingFeeConfig = false;
      });
    }
  }

  Future<void> _submitPromo(BuildContext context) async {
    final cleanCode = _code.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      setState(() => _errorMessage = 'Promotion code is required.');
      return;
    }

    final cleanName = _name.trim().isEmpty ? cleanCode : _name.trim();

    // STRICT VALIDATION: Ensure target is an eligible TRANYX fee
    if (TranyxFeeType.isProhibitedTarget(_applyToFee)) {
      setState(
        () => _errorMessage = 'Promotions can ONLY be applied to TRANYX fees. Listing/Base prices are protected.',
      );
      return;
    }

    final discountValue = double.tryParse(_discountValueStr) ?? 0.0;
    if (discountValue <= 0) {
      setState(() => _errorMessage = 'Discount value must be greater than 0.');
      return;
    }

    if (_discountType == 'percentage' && discountValue > 100) {
      setState(() => _errorMessage = 'Percentage discount cannot exceed 100%.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final firestore = context.read(firestoreProvider);
      final user = context.read(adminCurrentUserProvider).value;

      // Parse dates and numbers
      DateTime? startDate;
      if (_startDateStr.isNotEmpty) {
        startDate = DateTime.tryParse(_startDateStr);
      }
      DateTime? expirationDate;
      if (_expirationDateStr.isNotEmpty) {
        expirationDate = DateTime.tryParse(_expirationDateStr);
      }

      if (startDate != null && expirationDate != null && expirationDate.isBefore(startDate)) {
        setState(() => _errorMessage = 'End date cannot be earlier than start date.');
        return;
      }

      double? minTransactionAmount;
      if (_minTransactionStr.trim().isNotEmpty) {
        minTransactionAmount = double.tryParse(_minTransactionStr.trim());
      }

      double? maxDiscountCap;
      if (_maxDiscountCapStr.trim().isNotEmpty) {
        maxDiscountCap = double.tryParse(_maxDiscountCapStr.trim());
      }

      int? maxUsers;
      if (_maxUsersStr.isNotEmpty) {
        maxUsers = int.tryParse(_maxUsersStr);
      }

      // Parse user UIDs
      final userUids = _eligibleUserUidsStr.isEmpty
          ? <String>[]
          : _eligibleUserUidsStr.split(',').map((u) => u.trim()).where((u) => u.isNotEmpty).toList();

      // Gather roles
      final roles = <String>[];
      if (_roleRenter) roles.add('renter');
      if (_roleHost) roles.add('host');
      if (_roleEmployer) roles.add('employer');
      if (_roleNyxian) roles.add('nyxian');

      final isEditing = _editingPromo != null;
      final existingUsedCount = isEditing ? _editingPromo!.usedCount : 0;
      final existingUsedBy = isEditing ? _editingPromo!.usedBy : <String>[];
      final existingCreatedAt = isEditing ? _editingPromo!.createdAt : DateTime.now();

      final promoItem = PromoItem(
        code: cleanCode,
        name: cleanName,
        applyToFee: _applyToFee,
        applicableTo: _applicableTo,
        discountType: _discountType,
        discountValue: discountValue,
        minTransactionAmount: minTransactionAmount,
        maxDiscountCap: maxDiscountCap,
        startDate: startDate,
        expirationDate: expirationDate,
        maxUsers: maxUsers,
        isSingleUsePerUser: _isSingleUsePerUser,
        isAutoApply: _isAutoApply,
        eligibleUserUids: userUids,
        onlyForSubscribed: _onlyForSubscribed,
        onlyForHybrid: _onlyForHybrid,
        applicableRoles: roles,
        isActive: _isActive,
        usedCount: existingUsedCount,
        usedBy: existingUsedBy,
        createdAt: existingCreatedAt,
        updatedAt: DateTime.now(),
        createdBy: isEditing ? _editingPromo!.createdBy : (user?.email ?? 'admin@tranyx.com'),
        updatedBy: user?.email ?? 'admin@tranyx.com',
      );

      await firestore.collection('promos').doc(cleanCode).set(promoItem.toMap(), SetOptions(merge: true));

      // Record audit log
      final discountDesc = _discountType == 'percentage'
          ? '${discountValue.toStringAsFixed(0)}%'
          : '₱${discountValue.toStringAsFixed(2)}';
      await _logAuditTrail(
        context: context,
        promoCode: cleanCode,
        promoName: cleanName,
        action: isEditing ? 'UPDATED' : 'CREATED',
        applyToFee: _applyToFee,
        discountSummary: '$discountDesc OFF ${TranyxFeeType.getLabel(_applyToFee)}',
        details: promoItem.toMap(),
      );

      setState(() {
        _successMessage = isEditing
            ? 'Promotion $cleanCode successfully updated!'
            : 'Promotion $cleanCode created successfully! Applied to ${TranyxFeeType.getLabel(_applyToFee)}.';
        _resetForm();
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to save promotion: $e');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deletePromo(BuildContext context, PromoItem promo) async {
    if (!web.window.confirm('Are you sure you want to permanently delete promo code ${promo.code}?')) return;
    try {
      final firestore = context.read(firestoreProvider);

      await firestore.collection('promos').doc(promo.code).delete();

      // Clear from active promo state
      final usersWithPromo = await firestore.collection('users').where('activePromoCode', isEqualTo: promo.code).get();

      final batch = firestore.batch();
      for (final userDoc in usersWithPromo.docs) {
        batch.update(userDoc.reference, {
          'activePromoCode': null,
          'activePromoDiscountType': null,
          'activePromoDiscountValue': null,
        });
      }
      await batch.commit();

      await _logAuditTrail(
        context: context,
        promoCode: promo.code,
        promoName: promo.name,
        action: 'DELETED',
        applyToFee: promo.applyToFee,
        discountSummary: 'Deleted promotion',
        details: promo.toMap(),
      );

      setState(() {
        _successMessage = 'Promo code ${promo.code} deleted.';
      });
    } catch (e) {
      web.window.alert('Failed to delete promo: $e');
    }
  }

  Future<void> _toggleActivePromo(BuildContext context, PromoItem promo) async {
    try {
      final firestore = context.read(firestoreProvider);
      final newActiveState = !promo.isActive;

      await firestore.collection('promos').doc(promo.code).update({
        'isActive': newActiveState,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // If deactivating, clear from all users currently using it
      if (!newActiveState) {
        final usersWithPromo = await firestore
            .collection('users')
            .where('activePromoCode', isEqualTo: promo.code)
            .get();

        final batch = firestore.batch();
        for (final userDoc in usersWithPromo.docs) {
          batch.update(userDoc.reference, {
            'activePromoCode': null,
            'activePromoDiscountType': null,
            'activePromoDiscountValue': null,
          });
        }
        await batch.commit();
      }

      await _logAuditTrail(
        context: context,
        promoCode: promo.code,
        promoName: promo.name,
        action: newActiveState ? 'ACTIVATED' : 'DEACTIVATED',
        applyToFee: promo.applyToFee,
        discountSummary: newActiveState ? 'Activated promo' : 'Deactivated promo',
        details: {'isActive': newActiveState},
      );
    } catch (e) {
      web.window.alert('Failed to toggle active state: $e');
    }
  }

  @override
  Component build(BuildContext context) {
    final promosAsync = context.watch(promosStreamProvider);
    final feeConfigAsync = context.watch(feeConfigStreamProvider);
    final auditAsync = context.watch(promoAuditStreamProvider);

    feeConfigAsync.whenData((cfg) => _syncFeeConfigState(cfg));

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0]', [
      // Top Header Block
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          div(classes: 'flex items-center gap-2', [
            h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [
              Component.text('Promotions & Fee Console'),
            ]),
            span(
              classes:
                  'text-[10px] font-black uppercase px-2.5 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-300',
              [Component.text('Fee Protection Active')],
            ),
          ]),
          p(classes: 'text-xs text-zinc-500 font-medium', [
            Component.text(
              'Manage platform fee rates, category markups, surcharges & promotional discounts. Provider listing prices remain 100% protected.',
            ),
          ]),
        ]),

        // Navigation Mode Tabs
        div(classes: 'flex items-center gap-1.5 bg-white p-1.5 border border-zinc-200/50 rounded-2xl shadow-sm', [
          button(
            onClick: () => setState(() => _activeTab = 'list'),
            classes:
                'px-4 py-2 text-xs font-bold rounded-xl transition-all '
                '${_activeTab == 'list' ? 'bg-black text-white shadow-sm' : 'text-zinc-500 hover:text-zinc-900'}',
            [Component.text('🎟️ Promotions')],
          ),
          button(
            onClick: () => setState(() => _activeTab = 'fee_config'),
            classes:
                'px-4 py-2 text-xs font-bold rounded-xl transition-all '
                '${_activeTab == 'fee_config' ? 'bg-black text-white shadow-sm' : 'text-zinc-500 hover:text-zinc-900'}',
            [Component.text('⚙️ Fees & Markups')],
          ),
          button(
            onClick: () => setState(() => _activeTab = 'simulator'),
            classes:
                'px-4 py-2 text-xs font-bold rounded-xl transition-all '
                '${_activeTab == 'simulator' ? 'bg-black text-white shadow-sm' : 'text-zinc-500 hover:text-zinc-900'}',
            [Component.text('🧮 Fee Calculator')],
          ),
          button(
            onClick: () => setState(() => _activeTab = 'audit'),
            classes:
                'px-4 py-2 text-xs font-bold rounded-xl transition-all '
                '${_activeTab == 'audit' ? 'bg-black text-white shadow-sm' : 'text-zinc-500 hover:text-zinc-900'}',
            [Component.text('📜 Audit Trail')],
          ),
        ]),
      ]),

      // Stats Banner & Auto Zero Fees Quota Card
      promosAsync.when(
        data: (promosList) {
          final totalPromos = promosList.length;
          final activePromos = promosList.where((item) => item.isCurrentlyActive).length;
          final autoApplyCount = promosList.where((item) => item.isAutoApply && item.isCurrentlyActive).length;

          // Find Auto Zero Fees Campaign if exists
          PromoItem? autoZeroPromo;
          try {
            autoZeroPromo = promosList.firstWhere(
              (item) =>
                  item.code.toUpperCase().contains('ZERO') ||
                  item.code.toUpperCase().contains('1000') ||
                  (item.discountType == 'percentage' && item.discountValue >= 100 && item.isAutoApply),
            );
          } catch (_) {
            autoZeroPromo = null;
          }

          final zeroLimit = autoZeroPromo?.maxUsers ?? 1000;
          final zeroUsed = autoZeroPromo?.usedCount ?? 0;
          final zeroPercent = zeroLimit > 0 ? (zeroUsed / zeroLimit * 100).clamp(0, 100) : 0;
          final zeroRemaining = (zeroLimit - zeroUsed).clamp(0, zeroLimit);

          return div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-4', [
            // Banner 1: Auto Zero Fees Campaign Card (Highlighted)
            div(
              classes:
                  'p-5 rounded-[24px] bg-gradient-to-br from-indigo-900 to-zinc-900 text-white flex flex-col justify-between shadow-lg relative overflow-hidden',
              [
                div(classes: 'flex items-center justify-between z-10', [
                  div(classes: 'flex items-center gap-2', [
                    span(classes: 'text-lg', [Component.text('⚡')]),
                    span(classes: 'text-xs font-extrabold tracking-wider uppercase text-indigo-200', [
                      Component.text('Auto Zero Fees Campaign'),
                    ]),
                  ]),
                  span(
                    classes:
                        'text-[10px] font-black uppercase px-2.5 py-0.5 rounded-full ${autoZeroPromo != null && autoZeroPromo.isCurrentlyActive ? "bg-emerald-500/20 text-emerald-300 border border-emerald-400/30" : "bg-zinc-700 text-zinc-300"}',
                    [Component.text(autoZeroPromo != null && autoZeroPromo.isCurrentlyActive ? 'ACTIVE' : (autoZeroPromo != null && autoZeroPromo.isExpired ? 'EXPIRED' : 'READY TO DEPLOY'))],
                  ),
                ]),
                div(classes: 'my-3 z-10 flex flex-col gap-1.5', [
                  div(classes: 'flex items-baseline justify-between', [
                    span(classes: 'text-2xl font-black', [
                      Component.text('$zeroUsed / $zeroLimit claimed'),
                    ]),
                    span(classes: 'text-xs text-indigo-200 font-semibold', [
                      Component.text('$zeroRemaining remaining'),
                    ]),
                  ]),
                  // Progress Bar
                  div(classes: 'w-full bg-white/20 h-2 rounded-full overflow-hidden', [
                    div(
                      classes: 'bg-emerald-400 h-full rounded-full transition-all duration-500',
                      attributes: {'style': 'width: ${zeroPercent.toStringAsFixed(1)}%'},
                      [],
                    ),
                  ]),
                ]),
                div(classes: 'flex items-center justify-between z-10 text-[10px] text-zinc-300', [
                  span([Component.text('Applies: 100% Platform Fee Waiver')]),
                  if (autoZeroPromo == null)
                    button(
                      onClick: () {
                        _applyAutoZeroFeesTemplate();
                        setState(() => _activeTab = 'list');
                      },
                      classes:
                          'px-2.5 py-1 bg-white text-zinc-900 font-black rounded-lg hover:bg-zinc-100 transition-all',
                      [Component.text('Deploy Now')],
                    ),
                ]),
              ],
            ),

            // Banner 2: Active Promotions Overview
            div(
              classes: 'p-5 rounded-[24px] bg-white border border-zinc-200/50 flex flex-col justify-between shadow-sm',
              [
                div(classes: 'flex items-center justify-between', [
                  span(classes: 'text-xs font-bold text-zinc-400 uppercase tracking-wider', [
                    Component.text('Promotions Active'),
                  ]),
                  span(classes: 'text-base', [Component.text('🏷️')]),
                ]),
                div(classes: 'my-2', [
                  span(classes: 'text-3xl font-black text-zinc-900', [Component.text('$activePromos')]),
                  span(classes: 'text-xs text-zinc-400 font-semibold ml-2', [Component.text('of $totalPromos total')]),
                ]),
                div(
                  classes: 'flex items-center justify-between text-[10px] text-zinc-500 border-t border-zinc-100 pt-2',
                  [
                    span([Component.text('Auto-Apply at Checkout:')]),
                    span(classes: 'font-extrabold text-indigo-600', [Component.text('$autoApplyCount promo(s)')]),
                  ],
                ),
              ],
            ),

            // Banner 3: Platform Protected Policy Card
            div(
              classes:
                  'p-5 rounded-[24px] bg-[#f8faf9] border border-emerald-200/60 flex flex-col justify-between shadow-sm',
              [
                div(classes: 'flex items-center justify-between', [
                  span(
                    classes: 'text-xs font-bold text-emerald-800 uppercase tracking-wider flex items-center gap-1.5',
                    [
                      span([Component.text('🛡️')]),
                      Component.text('Provider Price Protection'),
                    ],
                  ),
                  span(classes: 'text-[9px] font-black px-2 py-0.5 rounded bg-emerald-100 text-emerald-700', [
                    Component.text('STRICT RULE'),
                  ]),
                ]),
                p(classes: 'text-xs text-zinc-600 font-medium my-2 leading-relaxed', [
                  Component.text(
                    'Promotions are 100% platform-funded. They strictly discount TRANYX fees & markups and never reduce the provider/owner base listing amount.',
                  ),
                ]),
                div(
                  classes:
                      'flex items-center justify-between text-[10px] text-zinc-500 border-t border-emerald-100 pt-2',
                  [
                    span([Component.text('Provider Settlement:')]),
                    span(classes: 'font-extrabold text-[#0fa958]', [Component.text('100% Preserved')]),
                  ],
                ),
              ],
            ),
          ]);
        },
        loading: () => div(classes: 'h-24 bg-white rounded-2xl animate-pulse', []),
        error: (_, __) => div([]),
      ),

      // Conditional Tabs Rendering
      if (_activeTab == 'list') _buildPromosListAndForm(context, promosAsync),
      if (_activeTab == 'fee_config') _buildFeeConfigurationConsole(context),
      if (_activeTab == 'simulator') _buildFeeCalculatorSimulator(context, promosAsync, feeConfigAsync),
      if (_activeTab == 'audit') _buildAuditTrailView(context, auditAsync),
    ]);
  }

  /// Fee & Markups Global Configuration View
  Component _buildFeeConfigurationConsole(BuildContext context) {
    return div(classes: 'flex flex-col gap-6', [
      div(classes: 'p-6 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm flex flex-col gap-6', [
        div(classes: 'flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-zinc-150 pb-4', [
          div(classes: 'flex flex-col gap-0.5', [
            h2(classes: 'text-sm font-black text-zinc-900 flex items-center gap-2', [
              span([Component.text('⚙️')]),
              Component.text('Platform Fees, Markups & Surcharges Configuration'),
            ]),
            p(classes: 'text-xs text-zinc-400 font-medium', [
              Component.text(
                'Configure global baseline charges, category markups, peak surcharges, and fee limits applied at checkout.',
              ),
            ]),
          ]),
          button(
            onClick: () => _saveFeeConfigurations(context),
            disabled: _isSavingFeeConfig,
            classes:
                'px-5 py-2.5 bg-black hover:bg-zinc-800 disabled:bg-zinc-300 text-white rounded-xl text-xs font-black tracking-wider uppercase transition-all shadow-md shadow-black/10 flex items-center gap-2',
            [
              if (_isSavingFeeConfig)
                span(
                  classes: 'inline-block animate-spin h-3.5 w-3.5 border-2 border-white/30 border-t-white rounded-full',
                  [],
                ),
              Component.text(_isSavingFeeConfig ? 'Saving...' : '💾 Save Configurations'),
            ],
          ),
        ]),

        if (_feeConfigMessage != null)
          div(
            classes:
                'p-3.5 rounded-xl text-xs font-semibold ${_feeConfigMessage!.contains("Failed") ? "bg-red-50 text-red-500 border border-red-200" : "bg-emerald-50 text-emerald-800 border border-emerald-200"}',
            [Component.text(_feeConfigMessage!)],
          ),

        div(classes: 'grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6', [
          // Block 1: Global Platform & Transaction Fees
          div(classes: 'p-5 bg-zinc-50 border border-zinc-200/60 rounded-2xl flex flex-col gap-4', [
            h3(classes: 'text-xs font-black uppercase tracking-wider text-zinc-900 flex items-center gap-1.5', [
              span([Component.text('💳')]),
              Component.text('Global Base Fees'),
            ]),
            div(classes: 'flex flex-col gap-1', [
              label(classes: 'text-[10px] font-black text-zinc-400 uppercase', [Component.text('Platform Fee Rate (%)')]),
              input(
                classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                attributes: {'type': 'number', 'step': 'any', 'value': _cfgDefaultPlatformRate},
                events: {'input': (e) => setState(() => _cfgDefaultPlatformRate = (e.target as dynamic).value as String)},
              ),
            ]),
            div(classes: 'grid grid-cols-2 gap-2', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Tx Fee Rate (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgDefaultTxRate},
                  events: {'input': (e) => setState(() => _cfgDefaultTxRate = (e.target as dynamic).value as String)},
                ),
              ]),
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Tx Fixed (₱)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgDefaultTxFixed},
                  events: {'input': (e) => setState(() => _cfgDefaultTxFixed = (e.target as dynamic).value as String)},
                ),
              ]),
            ]),
            div(classes: 'grid grid-cols-2 gap-2', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Conv Rate (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgDefaultConvRate},
                  events: {'input': (e) => setState(() => _cfgDefaultConvRate = (e.target as dynamic).value as String)},
                ),
              ]),
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Conv Fixed (₱)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgDefaultConvFixed},
                  events: {'input': (e) => setState(() => _cfgDefaultConvFixed = (e.target as dynamic).value as String)},
                ),
              ]),
            ]),
          ]),

          // Block 2: Category Platform Rates & Markups
          div(classes: 'p-5 bg-zinc-50 border border-zinc-200/60 rounded-2xl flex flex-col gap-4', [
            h3(classes: 'text-xs font-black uppercase tracking-wider text-zinc-900 flex items-center gap-1.5', [
              span([Component.text('🚗')]),
              Component.text('Vehicle & Property'),
            ]),
            div(classes: 'grid grid-cols-2 gap-2', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Vehicle Fee (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgVehiclePlatformRate},
                  events: {'input': (e) => setState(() => _cfgVehiclePlatformRate = (e.target as dynamic).value as String)},
                ),
              ]),
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Vehicle Markup (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgVehicleMarkupRate},
                  events: {'input': (e) => setState(() => _cfgVehicleMarkupRate = (e.target as dynamic).value as String)},
                ),
              ]),
            ]),
            div(classes: 'grid grid-cols-2 gap-2', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Property Fee (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgPropertyPlatformRate},
                  events: {'input': (e) => setState(() => _cfgPropertyPlatformRate = (e.target as dynamic).value as String)},
                ),
              ]),
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Property Markup (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgPropertyMarkupRate},
                  events: {'input': (e) => setState(() => _cfgPropertyMarkupRate = (e.target as dynamic).value as String)},
                ),
              ]),
            ]),
          ]),

          // Block 3: Services & Item Markups
          div(classes: 'p-5 bg-zinc-50 border border-zinc-200/60 rounded-2xl flex flex-col gap-4', [
            h3(classes: 'text-xs font-black uppercase tracking-wider text-zinc-900 flex items-center gap-1.5', [
              span([Component.text('💼')]),
              Component.text('Services & Items'),
            ]),
            div(classes: 'grid grid-cols-2 gap-2', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Service Fee (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgServicePlatformRate},
                  events: {'input': (e) => setState(() => _cfgServicePlatformRate = (e.target as dynamic).value as String)},
                ),
              ]),
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Service Markup (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgServiceMarkupRate},
                  events: {'input': (e) => setState(() => _cfgServiceMarkupRate = (e.target as dynamic).value as String)},
                ),
              ]),
            ]),
            div(classes: 'grid grid-cols-2 gap-2', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Item Fee (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgItemPlatformRate},
                  events: {'input': (e) => setState(() => _cfgItemPlatformRate = (e.target as dynamic).value as String)},
                ),
              ]),
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Item Markup (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgItemMarkupRate},
                  events: {'input': (e) => setState(() => _cfgItemMarkupRate = (e.target as dynamic).value as String)},
                ),
              ]),
            ]),
          ]),

          // Block 4: Surcharges & Platform Limits
          div(classes: 'p-5 bg-zinc-50 border border-zinc-200/60 rounded-2xl flex flex-col gap-4', [
            h3(classes: 'text-xs font-black uppercase tracking-wider text-zinc-900 flex items-center gap-1.5', [
              span([Component.text('🛡️')]),
              Component.text('Surcharges & Caps'),
            ]),
            div(classes: 'grid grid-cols-2 gap-2', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Weekend Surcharge (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgWeekendSurcharge},
                  events: {'input': (e) => setState(() => _cfgWeekendSurcharge = (e.target as dynamic).value as String)},
                ),
              ]),
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Peak Surcharge (%)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgPeakSeasonSurcharge},
                  events: {'input': (e) => setState(() => _cfgPeakSeasonSurcharge = (e.target as dynamic).value as String)},
                ),
              ]),
            ]),
            div(classes: 'grid grid-cols-2 gap-2', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Min Platform Cap (₱)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgMinPlatformCap},
                  events: {'input': (e) => setState(() => _cfgMinPlatformCap = (e.target as dynamic).value as String)},
                ),
              ]),
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[9px] font-black text-zinc-400 uppercase', [Component.text('Max Platform Cap (₱)')]),
                input(
                  classes: 'w-full px-3 py-2 bg-white border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none',
                  attributes: {'type': 'number', 'step': 'any', 'value': _cfgMaxPlatformCap},
                  events: {'input': (e) => setState(() => _cfgMaxPlatformCap = (e.target as dynamic).value as String)},
                ),
              ]),
            ]),
          ]),
        ]),
      ]),
    ]);
  }

  Component _buildPromosListAndForm(BuildContext context, AsyncValue<List<PromoItem>> promosAsync) {
    return div(classes: 'grid grid-cols-1 lg:grid-cols-3 gap-6', [
      // Left Column: Create / Edit Promotion Form
      div(
        key: ValueKey(_formVersion),
        classes:
            'lg:col-span-1 p-6 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm flex flex-col gap-5 h-fit',
        [
          div(classes: 'flex items-center justify-between border-b border-zinc-150 pb-3', [
            h2(classes: 'text-sm font-black text-zinc-900 flex items-center gap-2', [
              span([Component.text(_editingPromo != null ? '✏️' : '➕')]),
              Component.text(_editingPromo != null ? 'Edit Promotion' : 'Configure Promotion'),
            ]),
            if (_editingPromo != null)
              button(
                onClick: _resetForm,
                classes: 'text-[10px] font-bold text-zinc-500 hover:text-zinc-800 underline',
                [Component.text('Cancel Edit')],
              ),
          ]),

          // Quick Preset Templates Bar (When creating new)
          if (_editingPromo == null)
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                Component.text('Quick Setup Templates'),
              ]),
              div(classes: 'grid grid-cols-3 gap-1.5', [
                button(
                  onClick: _applyAutoZeroFeesTemplate,
                  classes:
                      'p-2 bg-indigo-50 hover:bg-indigo-100 text-indigo-700 rounded-xl text-[10px] font-extrabold text-left border border-indigo-150 flex flex-col leading-tight transition-all',
                  [
                    span(classes: 'font-black', [Component.text('⚡ Zero Fees')]),
                    span(classes: 'text-[8px] text-indigo-500 opacity-80', [Component.text('First 1k users')]),
                  ],
                ),
                button(
                  onClick: _apply50PercentLaunchTemplate,
                  classes:
                      'p-2 bg-purple-50 hover:bg-purple-100 text-purple-700 rounded-xl text-[10px] font-extrabold text-left border border-purple-150 flex flex-col leading-tight transition-all',
                  [
                    span(classes: 'font-black', [Component.text('🏷️ 50% Launch')]),
                    span(classes: 'text-[8px] text-purple-500 opacity-80', [Component.text('Platform fee')]),
                  ],
                ),
                button(
                  onClick: _applyFlat50FeeTemplate,
                  classes:
                      'p-2 bg-amber-50 hover:bg-amber-100 text-amber-700 rounded-xl text-[10px] font-extrabold text-left border border-amber-150 flex flex-col leading-tight transition-all',
                  [
                    span(classes: 'font-black', [Component.text('💵 ₱50 Flat')]),
                    span(classes: 'text-[8px] text-amber-500 opacity-80', [Component.text('Fee discount')]),
                  ],
                ),
              ]),
            ]),

          if (_errorMessage != null)
            div(classes: 'p-3 bg-red-50 text-red-500 rounded-xl text-xs font-semibold border border-red-200', [
              Component.text(_errorMessage!),
            ]),

          if (_successMessage != null)
            div(
              classes: 'p-3 bg-emerald-50 text-[#0fa958] rounded-xl text-xs font-semibold border border-emerald-200',
              [Component.text(_successMessage!)],
            ),

          div(classes: 'flex flex-col gap-4', [
            // Promotion Name
            div(classes: 'flex flex-col gap-1', [
              label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                Component.text('Promotion Name / Campaign Title'),
              ]),
              input(
                classes:
                    'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                attributes: {
                  'type': 'text',
                  'placeholder': 'e.g., Auto Zero Fees (First 1,000 Users)',
                  'value': _name,
                },
                events: {
                  'input': (e) => setState(() => _name = (e.target as dynamic).value as String),
                },
              ),
            ]),

            // Promo Code Input
            div(classes: 'flex flex-col gap-1', [
              label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                Component.text('Promotion Code'),
              ]),
              input(
                classes:
                    'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-mono font-black focus:outline-none focus:border-indigo-500 uppercase tracking-wider',
                attributes: {
                  'type': 'text',
                  'placeholder': 'e.g., ZEROFEES1000',
                  'value': _code,
                  if (_editingPromo != null) 'disabled': 'true',
                },
                events: {
                  'input': (e) => setState(() => _code = (e.target as dynamic).value as String),
                },
              ),
            ]),

            // APPLY DISCOUNT TO: ONLY ELIGIBLE TRANYX FEES (PROHIBIT LISTING PRICES)
            div(classes: 'flex flex-col gap-1', [
              div(classes: 'flex items-center justify-between', [
                label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Apply Discount To (TRANYX Fee Target)'),
                ]),
                span(classes: 'text-[9px] font-bold text-emerald-600', [Component.text('Fees Only')]),
              ]),
              select(
                classes:
                    'w-full px-4 py-2.5 bg-emerald-50/50 border border-emerald-300 rounded-xl text-xs font-bold focus:outline-none focus:border-emerald-500 text-zinc-900',
                events: {
                  'change': (e) => setState(() => _applyToFee = (e.target as dynamic).value as String),
                },
                [
                  option(value: TranyxFeeType.platformFee, selected: _applyToFee == TranyxFeeType.platformFee, [
                    Component.text('Platform Fee (Recommended)'),
                  ]),
                  option(
                    value: TranyxFeeType.transactionFee,
                    selected: _applyToFee == TranyxFeeType.transactionFee,
                    [Component.text('Transaction Fee')],
                  ),
                  option(
                    value: TranyxFeeType.convenienceFee,
                    selected: _applyToFee == TranyxFeeType.convenienceFee,
                    [Component.text('Convenience Fee')],
                  ),
                  option(value: TranyxFeeType.serviceFee, selected: _applyToFee == TranyxFeeType.serviceFee, [
                    Component.text('Service Fee'),
                  ]),
                  option(value: TranyxFeeType.markupFee, selected: _applyToFee == TranyxFeeType.markupFee, [
                    Component.text('Platform Markups & Surcharges'),
                  ]),
                  option(value: TranyxFeeType.allFees, selected: _applyToFee == TranyxFeeType.allFees, [
                    Component.text('All TRANYX Platform Fees & Markups (Full Platform Waiver)'),
                  ]),
                ],
              ),
              span(classes: 'text-[9px] text-zinc-400 font-medium italic mt-0.5', [
                Component.text('* Listing, rental, and provider prices cannot be selected and remain 100% payable.'),
              ]),
            ]),

            // Discount Type & Value Grid
            div(classes: 'grid grid-cols-2 gap-3', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Discount Type'),
                ]),
                select(
                  classes:
                      'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                  events: {
                    'change': (e) => setState(() => _discountType = (e.target as dynamic).value as String),
                  },
                  [
                    option(value: 'percentage', selected: _discountType == 'percentage', [
                      Component.text('Percentage (%)'),
                    ]),
                    option(value: 'flat', selected: _discountType == 'flat', [Component.text('Fixed Amount (₱)')]),
                  ],
                ),
              ]),
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text(_discountType == 'percentage' ? 'Rate (%)' : 'Amount (₱)'),
                ]),
                input(
                  classes:
                      'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                  attributes: {
                    'type': 'number',
                    'step': 'any',
                    'placeholder': _discountType == 'percentage' ? '100' : '50.00',
                    'value': _discountValueStr,
                  },
                  events: {
                    'input': (e) => setState(() => _discountValueStr = (e.target as dynamic).value as String),
                  },
                ),
              ]),
            ]),

            // Applicable Category / Platform Modules
            div(classes: 'flex flex-col gap-1', [
              label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                Component.text('Eligible Platform Modules'),
              ]),
              select(
                classes:
                    'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                events: {
                  'change': (e) => setState(() => _applicableTo = (e.target as dynamic).value as String),
                },
                [
                  option(value: 'both', selected: _applicableTo == 'both', [
                    Component.text('All Modules (Services, Vehicles & Properties)'),
                  ]),
                  option(value: 'vehicles', selected: _applicableTo == 'vehicles', [
                    Component.text('Vehicle Rentals Only'),
                  ]),
                  option(value: 'properties', selected: _applicableTo == 'properties', [
                    Component.text('Property Rentals Only'),
                  ]),
                  option(value: 'services', selected: _applicableTo == 'services', [
                    Component.text('Jobs & Services Only'),
                  ]),
                ],
              ),
            ]),

            // Min Transaction Amount & Max Discount Limit Grid
            div(classes: 'grid grid-cols-2 gap-3', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Min Tx Amount (₱)'),
                ]),
                input(
                  classes:
                      'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                  attributes: {
                    'type': 'number',
                    'step': 'any',
                    'placeholder': 'Optional (e.g. 500)',
                    'value': _minTransactionStr,
                  },
                  events: {
                    'input': (e) => setState(() => _minTransactionStr = (e.target as dynamic).value as String),
                  },
                ),
              ]),
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Max Discount Cap (₱)'),
                ]),
                input(
                  classes:
                      'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                  attributes: {
                    'type': 'number',
                    'step': 'any',
                    'placeholder': 'Optional (e.g. 100)',
                    'value': _maxDiscountCapStr,
                  },
                  events: {
                    'input': (e) => setState(() => _maxDiscountCapStr = (e.target as dynamic).value as String),
                  },
                ),
              ]),
            ]),

            // Start Date & Expiration Date Grid
            div(classes: 'grid grid-cols-2 gap-3', [
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Start Date'),
                ]),
                input(
                  classes:
                      'w-full px-4 py-2 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                  attributes: {
                    'type': 'date',
                    'value': _startDateStr,
                  },
                  events: {
                    'input': (e) => setState(() => _startDateStr = (e.target as dynamic).value as String),
                    'change': (e) => setState(() => _startDateStr = (e.target as dynamic).value as String),
                  },
                ),
              ]),
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('End Date'),
                ]),
                input(
                  classes:
                      'w-full px-4 py-2 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                  attributes: {
                    'type': 'date',
                    'value': _expirationDateStr,
                  },
                  events: {
                    'input': (e) => setState(() => _expirationDateStr = (e.target as dynamic).value as String),
                    'change': (e) => setState(() => _expirationDateStr = (e.target as dynamic).value as String),
                  },
                ),
              ]),
            ]),

            // Max Users Limit (1,000 users)
            div(classes: 'flex flex-col gap-1', [
              label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                Component.text('Max Total Users / Activations Limit'),
              ]),
              input(
                classes:
                    'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                attributes: {
                  'type': 'number',
                  'placeholder': 'e.g., 1000 for Auto Zero Fees',
                  'value': _maxUsersStr,
                },
                events: {
                  'input': (e) => setState(() => _maxUsersStr = (e.target as dynamic).value as String),
                },
              ),
            ]),

            // Targeted Roles (Checkbox grid)
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                Component.text('Targeted Roles / User Types'),
              ]),
              div(classes: 'grid grid-cols-2 gap-2 bg-zinc-50 p-3 border border-zinc-200 rounded-xl', [
                div(classes: 'flex items-center gap-2', [
                  input(
                    classes: 'h-4 w-4 text-indigo-500 rounded border-zinc-300 focus:ring-indigo-500',
                    attributes: {
                      'type': 'checkbox',
                      if (_roleRenter) 'checked': 'true',
                    },
                    events: {
                      'change': (e) => setState(() => _roleRenter = (e.target as dynamic).checked as bool),
                    },
                  ),
                  span(classes: 'text-xs text-zinc-700 font-semibold', [Component.text('Renter / Client')]),
                ]),
                div(classes: 'flex items-center gap-2', [
                  input(
                    classes: 'h-4 w-4 text-indigo-500 rounded border-zinc-300 focus:ring-indigo-500',
                    attributes: {
                      'type': 'checkbox',
                      if (_roleHost) 'checked': 'true',
                    },
                    events: {
                      'change': (e) => setState(() => _roleHost = (e.target as dynamic).checked as bool),
                    },
                  ),
                  span(classes: 'text-xs text-zinc-700 font-semibold', [Component.text('Host / Owner')]),
                ]),
                div(classes: 'flex items-center gap-2', [
                  input(
                    classes: 'h-4 w-4 text-indigo-500 rounded border-zinc-300 focus:ring-indigo-500',
                    attributes: {
                      'type': 'checkbox',
                      if (_roleEmployer) 'checked': 'true',
                    },
                    events: {
                      'change': (e) => setState(() => _roleEmployer = (e.target as dynamic).checked as bool),
                    },
                  ),
                  span(classes: 'text-xs text-zinc-700 font-semibold', [Component.text('Employer')]),
                ]),
                div(classes: 'flex items-center gap-2', [
                  input(
                    classes: 'h-4 w-4 text-indigo-500 rounded border-zinc-300 focus:ring-indigo-500',
                    attributes: {
                      'type': 'checkbox',
                      if (_roleNyxian) 'checked': 'true',
                    },
                    events: {
                      'change': (e) => setState(() => _roleNyxian = (e.target as dynamic).checked as bool),
                    },
                  ),
                  span(classes: 'text-xs text-zinc-700 font-semibold', [Component.text('Nyxian Provider')]),
                ]),
              ]),
            ]),

            // Eligible UIDs list (Comma separated)
            div(classes: 'flex flex-col gap-1', [
              label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                Component.text('Eligible User UIDs (Optional Specific Targeting)'),
              ]),
              textarea(
                placeholder: 'e.g., uid1, uid2, uid3 (leave empty for public)',
                classes:
                    'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-semibold focus:outline-none focus:border-indigo-500 h-14 resize-none',
                events: {
                  'input': (e) => setState(() => _eligibleUserUidsStr = (e.target as dynamic).value as String),
                },
                [_eligibleUserUidsStr.isNotEmpty ? Component.text(_eligibleUserUidsStr) : Component.text('')],
              ),
            ]),

            // Configuration Switches / Checkboxes
            div(classes: 'flex flex-col gap-2.5 bg-zinc-50 p-4 border border-zinc-200 rounded-xl', [
              // Auto Apply
              div(classes: 'flex items-center justify-between', [
                div(classes: 'flex flex-col', [
                  span(classes: 'text-xs font-bold text-zinc-800', [Component.text('Auto Apply at Checkout')]),
                  span(classes: 'text-[9px] text-zinc-400 font-medium', [
                    Component.text('Automatically applies to first 1,000 eligible users'),
                  ]),
                ]),
                input(
                  classes: 'h-4 w-4 text-indigo-500 rounded border-zinc-300 focus:ring-indigo-500',
                  attributes: {
                    'type': 'checkbox',
                    if (_isAutoApply) 'checked': 'true',
                  },
                  events: {
                    'change': (e) => setState(() => _isAutoApply = (e.target as dynamic).checked as bool),
                  },
                ),
              ]),

              // Single Use Per User
              div(classes: 'flex items-center justify-between border-t border-zinc-200/50 pt-2.5', [
                div(classes: 'flex flex-col', [
                  span(classes: 'text-xs font-bold text-zinc-800', [Component.text('Single Use Per User')]),
                  span(classes: 'text-[9px] text-zinc-400 font-medium', [
                    Component.text('Limit to one activation per user account'),
                  ]),
                ]),
                input(
                  classes: 'h-4 w-4 text-indigo-500 rounded border-zinc-300 focus:ring-indigo-500',
                  attributes: {
                    'type': 'checkbox',
                    if (_isSingleUsePerUser) 'checked': 'true',
                  },
                  events: {
                    'change': (e) => setState(() => _isSingleUsePerUser = (e.target as dynamic).checked as bool),
                  },
                ),
              ]),

              // Subscribed Users Only
              div(classes: 'flex items-center justify-between border-t border-zinc-200/50 pt-2.5', [
                div(classes: 'flex flex-col', [
                  span(classes: 'text-xs font-bold text-zinc-800', [Component.text('Subscribed Users Only')]),
                  span(classes: 'text-[9px] text-zinc-400 font-medium', [
                    Component.text('Only for premium subscribed accounts'),
                  ]),
                ]),
                input(
                  classes: 'h-4 w-4 text-indigo-500 rounded border-zinc-300 focus:ring-indigo-500',
                  attributes: {
                    'type': 'checkbox',
                    if (_onlyForSubscribed) 'checked': 'true',
                  },
                  events: {
                    'change': (e) => setState(() => _onlyForSubscribed = (e.target as dynamic).checked as bool),
                  },
                ),
              ]),

              // Hybrid Accounts Only
              div(classes: 'flex items-center justify-between border-t border-zinc-200/50 pt-2.5', [
                div(classes: 'flex flex-col', [
                  span(classes: 'text-xs font-bold text-zinc-800', [Component.text('Hybrid Accounts Only')]),
                  span(classes: 'text-[9px] text-zinc-400 font-medium', [Component.text('Only hybrid PRO accounts')]),
                ]),
                input(
                  classes: 'h-4 w-4 text-indigo-500 rounded border-zinc-300 focus:ring-indigo-500',
                  attributes: {
                    'type': 'checkbox',
                    if (_onlyForHybrid) 'checked': 'true',
                  },
                  events: {
                    'change': (e) => setState(() => _onlyForHybrid = (e.target as dynamic).checked as bool),
                  },
                ),
              ]),

              // Global Status
              div(classes: 'flex items-center justify-between border-t border-zinc-200/50 pt-2.5', [
                div(classes: 'flex flex-col', [
                  span(classes: 'text-xs font-bold text-zinc-800', [Component.text('Active Status')]),
                  span(classes: 'text-[9px] text-zinc-400 font-medium', [Component.text('Enable or pause globally')]),
                ]),
                input(
                  classes: 'h-4 w-4 text-indigo-500 rounded border-zinc-300 focus:ring-indigo-500',
                  attributes: {
                    'type': 'checkbox',
                    if (_isActive) 'checked': 'true',
                  },
                  events: {
                    'change': (e) => setState(() => _isActive = (e.target as dynamic).checked as bool),
                  },
                ),
              ]),
            ]),

            button(
              onClick: () => _submitPromo(context),
              disabled: _isSubmitting,
              classes:
                  'w-full py-3.5 bg-black hover:bg-zinc-800 disabled:bg-zinc-300 text-white rounded-2xl text-xs font-black tracking-wider uppercase transition-all shadow-md shadow-black/10 mt-2 flex items-center justify-center gap-2',
              [
                if (_isSubmitting)
                  span(
                    classes:
                        'inline-block animate-spin h-3.5 w-3.5 border-2 border-white/30 border-t-white rounded-full',
                    [],
                  ),
                Component.text(
                  _isSubmitting
                      ? 'Saving Configuration...'
                      : (_editingPromo != null ? 'Update Promotion' : 'Publish Promotion'),
                ),
              ],
            ),
          ]),
        ],
      ),

      // Right Column: List of Promotions with Search & Filter
      div(classes: 'lg:col-span-2 flex flex-col gap-4', [
        // Filter and Search Header Card
        div(
          classes:
              'p-4 bg-white border border-zinc-200/50 rounded-2xl shadow-sm flex flex-col sm:flex-row gap-3 items-center justify-between',
          [
            // Search Input
            div(classes: 'relative w-full sm:w-64', [
              input(
                classes:
                    'w-full pl-9 pr-4 py-2 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                attributes: {
                  'type': 'text',
                  'placeholder': 'Search promo name or code...',
                  'value': _searchFilter,
                },
                events: {
                  'input': (e) => setState(() => _searchFilter = (e.target as dynamic).value as String),
                },
              ),
              span(classes: 'absolute left-3 top-2.5 text-xs text-zinc-400', [Component.text('🔍')]),
            ]),

            // Status & Fee Filters
            div(classes: 'flex items-center gap-2 w-full sm:w-auto', [
              select(
                classes:
                    'px-3 py-2 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none text-zinc-700',
                events: {
                  'change': (e) => setState(() => _statusFilter = (e.target as dynamic).value as String),
                },
                [
                  option(value: 'all', selected: _statusFilter == 'all', [Component.text('All Statuses')]),
                  option(value: 'active', selected: _statusFilter == 'active', [Component.text('Active Only')]),
                  option(value: 'inactive', selected: _statusFilter == 'inactive', [Component.text('Paused Only')]),
                  option(value: 'expired', selected: _statusFilter == 'expired', [Component.text('Expired Only')]),
                  option(value: 'auto', selected: _statusFilter == 'auto', [Component.text('Auto-Apply Only')]),
                ],
              ),
              select(
                classes:
                    'px-3 py-2 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none text-zinc-700',
                events: {
                  'change': (e) => setState(() => _feeTargetFilter = (e.target as dynamic).value as String),
                },
                [
                  option(value: 'all', selected: _feeTargetFilter == 'all', [Component.text('All Fee Targets')]),
                  option(
                    value: TranyxFeeType.platformFee,
                    selected: _feeTargetFilter == TranyxFeeType.platformFee,
                    [Component.text('Platform Fee')],
                  ),
                  option(
                    value: TranyxFeeType.transactionFee,
                    selected: _feeTargetFilter == TranyxFeeType.transactionFee,
                    [Component.text('Transaction Fee')],
                  ),
                  option(
                    value: TranyxFeeType.convenienceFee,
                    selected: _feeTargetFilter == TranyxFeeType.convenienceFee,
                    [Component.text('Convenience Fee')],
                  ),
                  option(
                    value: TranyxFeeType.markupFee,
                    selected: _feeTargetFilter == TranyxFeeType.markupFee,
                    [Component.text('Markups & Surcharges')],
                  ),
                  option(
                    value: TranyxFeeType.allFees,
                    selected: _feeTargetFilter == TranyxFeeType.allFees,
                    [Component.text('All Fees & Markups')],
                  ),
                ],
              ),
            ]),
          ],
        ),

        // Promotions Cards List
        promosAsync.when(
          data: (promosList) {
            var filtered = promosList;

            if (_searchFilter.trim().isNotEmpty) {
              final q = _searchFilter.trim().toLowerCase();
              filtered = filtered
                  .where((promo) => promo.code.toLowerCase().contains(q) || promo.name.toLowerCase().contains(q))
                  .toList();
            }

            if (_statusFilter == 'active') {
              filtered = filtered.where((promo) => promo.isCurrentlyActive).toList();
            } else if (_statusFilter == 'inactive') {
              filtered = filtered.where((promo) => !promo.isActive).toList();
            } else if (_statusFilter == 'expired') {
              filtered = filtered.where((promo) => promo.isExpired).toList();
            } else if (_statusFilter == 'auto') {
              filtered = filtered.where((promo) => promo.isAutoApply && promo.isCurrentlyActive).toList();
            }

            if (_feeTargetFilter != 'all') {
              filtered = filtered.where((promo) => promo.applyToFee == _feeTargetFilter).toList();
            }

            if (filtered.isEmpty) {
              return div(
                classes:
                    'flex-grow flex flex-col items-center justify-center text-center p-16 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
                [
                  span(classes: 'text-4xl mb-3', [Component.text('🎟️')]),
                  h3(classes: 'text-sm font-bold text-zinc-900', [Component.text('No Matching Promotions')]),
                  p(classes: 'text-xs text-zinc-500 mt-1 max-w-sm', [
                    Component.text(
                      'No promotions found matching your current filter. Try adjusting your search query or creating a new campaign.',
                    ),
                  ]),
                ],
              );
            }

            return div(classes: 'flex flex-col gap-4 overflow-y-auto max-h-[850px] pr-2 no-scrollbar', [
              for (final promo in filtered)
                div(
                  classes:
                      'p-5 rounded-[24px] bg-white border border-zinc-200/50 flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.01)] hover:border-zinc-300 transition-all relative overflow-hidden',
                  [
                    // Row 1: Code, Target Fee Capsule, and Action Buttons
                    div(classes: 'flex flex-col sm:flex-row sm:items-center justify-between gap-2.5', [
                      div(classes: 'flex flex-wrap items-center gap-2', [
                        span(
                          classes:
                              'text-sm font-mono font-black tracking-wider px-3 py-1.5 rounded-xl border '
                              '${promo.isCurrentlyActive ? "bg-indigo-50 text-indigo-700 border-indigo-200" : (promo.isExpired ? "bg-rose-50 text-rose-700 border-rose-200" : "bg-zinc-100 text-zinc-400 border-zinc-200")}',
                          [Component.text(promo.code)],
                        ),
                        span(
                          classes:
                              'text-[10px] font-extrabold px-3 py-1 rounded-full border bg-emerald-50 text-emerald-700 border-emerald-200 flex items-center gap-1',
                          [
                            span([Component.text('🛡️')]),
                            Component.text('Applies to: ${TranyxFeeType.getLabel(promo.applyToFee)}'),
                          ],
                        ),
                        if (promo.isAutoApply)
                          span(
                            classes:
                                'text-[10px] font-black px-2.5 py-0.5 rounded-full bg-indigo-100 text-indigo-800 border border-indigo-200',
                            [Component.text('⚡ Auto-Apply')],
                          ),
                      ]),
                      div(classes: 'flex items-center gap-1.5 self-end sm:self-auto', [
                        button(
                          onClick: () => _loadPromoForEdit(promo),
                          classes:
                              'px-3 py-1.5 rounded-lg border border-zinc-200 bg-zinc-50 hover:bg-zinc-100 text-[10px] font-bold text-zinc-700 transition-all',
                          [Component.text('✏️ Edit')],
                        ),
                        button(
                          onClick: () => _toggleActivePromo(context, promo),
                          classes:
                              'px-3 py-1.5 rounded-lg border text-[10px] font-black transition-all '
                              '${promo.isActive ? "bg-zinc-50 hover:bg-zinc-150 border-zinc-200 text-zinc-600" : "bg-emerald-50 border-emerald-200 text-emerald-700"}',
                          [Component.text(promo.isActive ? 'Pause' : 'Activate')],
                        ),
                        button(
                          onClick: () => _deletePromo(context, promo),
                          classes:
                              'p-1.5 rounded-lg border border-red-200 bg-red-50/50 text-red-500 hover:bg-red-100/50 transition-all text-xs',
                          [Component.text('🗑️')],
                        ),
                      ]),
                    ]),

                    // Promotion Name & Description
                    div(classes: 'flex flex-col gap-0.5', [
                      h3(classes: 'text-sm font-black text-zinc-900', [Component.text(promo.name)]),
                      p(classes: 'text-[11px] text-zinc-500 font-medium', [
                        Component.text(
                          'Promotional discount of ${promo.discountType == "percentage" ? "${promo.discountValue.toStringAsFixed(0)}%" : "₱${promo.discountValue.toStringAsFixed(2)}"} strictly applied against ${TranyxFeeType.getLabel(promo.applyToFee)} (Provider listing amount preserved).',
                        ),
                      ]),
                    ]),

                    // Quota Progress Bar (for limited promotions like 1,000 users)
                    if (promo.maxUsers != null && promo.maxUsers! > 0)
                      div(classes: 'bg-zinc-50 p-3 rounded-xl border border-zinc-200/40 flex flex-col gap-1.5', [
                        div(classes: 'flex items-center justify-between text-[10px] font-bold', [
                          span(classes: 'text-zinc-500', [Component.text('Usage / Quota Limit')]),
                          span(classes: 'text-zinc-900', [
                            Component.text('${promo.usedCount} of ${promo.maxUsers} users claimed'),
                          ]),
                        ]),
                        div(classes: 'w-full bg-zinc-200 h-2 rounded-full overflow-hidden', [
                          div(
                            classes: 'bg-indigo-600 h-full rounded-full transition-all duration-300',
                            attributes: {
                              'style':
                                  'width: ${((promo.usedCount / promo.maxUsers!) * 100).clamp(0, 100).toStringAsFixed(1)}%',
                            },
                            [],
                          ),
                        ]),
                      ]),

                    // Row 2: Discount & Restrictions Grid
                    div(
                      classes:
                          'grid grid-cols-2 sm:grid-cols-4 gap-3 bg-[#f8faf9] p-3.5 border border-zinc-150 rounded-2xl text-xs',
                      [
                        div(classes: 'flex flex-col gap-0.5', [
                          span(classes: 'text-[9px] font-bold text-zinc-400 uppercase tracking-wide', [
                            Component.text('Discount Value'),
                          ]),
                          span(classes: 'text-xs font-black text-indigo-700', [
                            Component.text(
                              promo.discountType == 'percentage'
                                  ? '${promo.discountValue.toStringAsFixed(0)}% OFF'
                                  : '₱${promo.discountValue.toStringAsFixed(2)} OFF',
                            ),
                          ]),
                        ]),
                        div(classes: 'flex flex-col gap-0.5', [
                          span(classes: 'text-[9px] font-bold text-zinc-400 uppercase tracking-wide', [
                            Component.text('Min Tx / Max Cap'),
                          ]),
                          span(classes: 'text-xs font-bold text-zinc-800', [
                            Component.text(
                              '${promo.minTransactionAmount != null ? "Min ₱${promo.minTransactionAmount!.toStringAsFixed(0)}" : "No Min"} / '
                              '${promo.maxDiscountCap != null ? "Cap ₱${promo.maxDiscountCap!.toStringAsFixed(0)}" : "No Cap"}',
                            ),
                          ]),
                        ]),
                        div(classes: 'flex flex-col gap-0.5', [
                          span(classes: 'text-[9px] font-bold text-zinc-400 uppercase tracking-wide', [
                            Component.text('Active Period'),
                          ]),
                          span(classes: 'text-xs font-bold text-zinc-800', [
                            Component.text(
                              promo.expirationDate != null
                                  ? 'Until ${promo.expirationDate!.year}-${promo.expirationDate!.month.toString().padLeft(2, '0')}-${promo.expirationDate!.day.toString().padLeft(2, '0')}'
                                  : 'No Expiry',
                            ),
                          ]),
                        ]),
                        div(classes: 'flex flex-col gap-0.5', [
                          span(classes: 'text-[9px] font-bold text-zinc-400 uppercase tracking-wide', [
                            Component.text('Status'),
                          ]),
                          span(
                            classes:
                                'text-xs font-black '
                                '${promo.isCurrentlyActive ? "text-[#0fa958]" : (promo.isExpired ? "text-rose-500" : (promo.isUpcoming ? "text-amber-500" : (promo.isLimitReached ? "text-amber-600" : "text-zinc-400")))}',
                            [
                              Component.text(
                                promo.isCurrentlyActive
                                    ? '● Active'
                                    : (promo.isExpired
                                        ? '○ Expired'
                                        : (promo.isUpcoming
                                            ? '⏱ Scheduled'
                                            : (promo.isLimitReached ? '🔒 Limit Reached' : '○ Paused'))),
                              ),
                            ],
                          ),
                        ]),
                      ],
                    ),

                    // Row 3: Targeting Tags
                    div(classes: 'flex flex-wrap items-center gap-1.5 text-[9px] font-bold', [
                      span(
                        classes: 'px-2 py-0.5 rounded bg-zinc-100 border border-zinc-200 text-zinc-600',
                        [
                          Component.text(
                            'Category: ${promo.applicableTo == "both" ? "All Modules" : (promo.applicableTo == "vehicles" ? "Vehicles" : (promo.applicableTo == "properties" ? "Properties" : "Services"))}',
                          ),
                        ],
                      ),
                      if (promo.isSingleUsePerUser)
                        span(classes: 'px-2 py-0.5 rounded bg-blue-50 border border-blue-100 text-blue-600', [
                          Component.text('Single Use Per User'),
                        ]),
                      if (promo.onlyForSubscribed)
                        span(classes: 'px-2 py-0.5 rounded bg-purple-50 border border-purple-100 text-purple-600', [
                          Component.text('Subscribed Only'),
                        ]),
                      if (promo.onlyForHybrid)
                        span(classes: 'px-2 py-0.5 rounded bg-amber-50 border border-amber-100 text-amber-600', [
                          Component.text('Hybrid Only'),
                        ]),
                      if (promo.applicableRoles.isNotEmpty)
                        span(classes: 'px-2 py-0.5 rounded bg-zinc-100 border border-zinc-200 text-zinc-600', [
                          Component.text('Roles: ${promo.applicableRoles.join(", ")}'),
                        ]),
                      if (promo.eligibleUserUids.isNotEmpty)
                        span(classes: 'px-2 py-0.5 rounded bg-zinc-100 border border-zinc-200 text-zinc-600', [
                          Component.text('Targeted: ${promo.eligibleUserUids.length} users'),
                        ]),
                    ]),
                  ],
                ),
            ]);
          },
          loading: () => div(
            classes:
                'flex-grow flex justify-center items-center py-20 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
            [div(classes: 'animate-spin h-6 w-6 border-2 border-zinc-200 border-t-indigo-500 rounded-full', [])],
          ),
          error: (err, _) => div(
            classes: 'p-6 bg-red-50 border border-red-200 text-red-500 text-xs rounded-[20px] font-mono shadow-sm',
            [Component.text('Error loading Promos list: $err')],
          ),
        ),
      ]),
    ]);
  }

  /// Interactive Checkout & Fee Calculator / Simulator
  Component _buildFeeCalculatorSimulator(
    BuildContext context,
    AsyncValue<List<PromoItem>> promosAsync,
    AsyncValue<FeeConfiguration> feeConfigAsync,
  ) {
    final feeConfig = feeConfigAsync.value ?? const FeeConfiguration();

    return promosAsync.when(
      data: (promosList) {
        // Find selected promo
        PromoItem? selectedPromo;
        try {
          selectedPromo = promosList.firstWhere((p) => p.code == _simSelectedPromoCode);
        } catch (_) {
          if (promosList.isNotEmpty) {
            selectedPromo = promosList.first;
          }
        }

        final calcResult = TranyxPromotionCalculator.calculateFromConfig(
          listingPrice: _simListingPrice,
          feeConfig: feeConfig,
          category: _simCategory,
          isWeekend: _simIsWeekend,
          isPeakSeason: _simIsPeak,
          hasSecurityDeposit: _simHasDeposit,
          isInstantBooking: _simIsInstant,
          isSubscribedUser: _simIsSubscribed,
          isHybridUser: _simIsHybrid,
          promoCode: selectedPromo?.code,
          promoName: selectedPromo?.name,
          applyToFee: selectedPromo?.applyToFee ?? TranyxFeeType.platformFee,
          discountType: selectedPromo?.discountType ?? 'percentage',
          discountValue: selectedPromo?.discountValue ?? 0.0,
          minTransactionAmount: selectedPromo?.minTransactionAmount,
          maxDiscountCap: selectedPromo?.maxDiscountCap,
          startDate: selectedPromo?.startDate,
          expirationDate: selectedPromo?.expirationDate,
          maxUsers: selectedPromo?.maxUsers,
          usedCount: selectedPromo?.usedCount ?? 0,
          isSingleUsePerUser: selectedPromo?.isSingleUsePerUser ?? false,
        );

        return div(classes: 'grid grid-cols-1 lg:grid-cols-2 gap-8', [
          // Left: Test Inputs & Parameters
          div(classes: 'p-6 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm flex flex-col gap-5', [
            div(classes: 'border-b border-zinc-150 pb-3', [
              h2(classes: 'text-sm font-black text-zinc-900 flex items-center gap-2', [
                span([Component.text('🧮')]),
                Component.text('Transaction Fee & Markup Simulator'),
              ]),
              p(classes: 'text-xs text-zinc-400 font-medium mt-1', [
                Component.text(
                  'Test live checkout calculations using active Fee Configurations and Promotion waivers.',
                ),
              ]),
            ]),

            div(classes: 'flex flex-col gap-4', [
              // Listing Price Input
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-500 uppercase tracking-wider', [
                  Component.text('Provider Listing / Base Price (₱)'),
                ]),
                input(
                  classes:
                      'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-sm font-black focus:outline-none focus:border-indigo-500',
                  attributes: {
                    'type': 'number',
                    'step': 'any',
                    'value': _simListingPrice.toString(),
                  },
                  events: {
                    'input': (e) {
                      final val = double.tryParse((e.target as dynamic).value as String) ?? 0.0;
                      setState(() => _simListingPrice = val);
                    },
                  },
                ),
                span(classes: 'text-[10px] text-emerald-600 font-semibold', [
                  Component.text('✓ This base amount is guaranteed to the listing owner/provider.'),
                ]),
              ]),

              // Category Selector
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-500 uppercase tracking-wider', [
                  Component.text('Listing Category / Module'),
                ]),
                select(
                  classes:
                      'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                  events: {
                    'change': (e) => setState(() => _simCategory = (e.target as dynamic).value as String),
                  },
                  [
                    option(value: 'vehicles', selected: _simCategory == 'vehicles', [
                      Component.text('Vehicle Rentals (Platform Fee: ${feeConfig.vehiclePlatformFeeRate}%, Markup: ${feeConfig.vehicleMarkupRate}%)'),
                    ]),
                    option(value: 'properties', selected: _simCategory == 'properties', [
                      Component.text('Property Rentals (Platform Fee: ${feeConfig.propertyPlatformFeeRate}%, Markup: ${feeConfig.propertyMarkupRate}%)'),
                    ]),
                    option(value: 'services', selected: _simCategory == 'services', [
                      Component.text('Jobs & Services (Platform Fee: ${feeConfig.servicePlatformFeeRate}%)'),
                    ]),
                    option(value: 'items', selected: _simCategory == 'items', [
                      Component.text('Item Rentals (Platform Fee: ${feeConfig.itemPlatformFeeRate}%, Markup: ${feeConfig.itemMarkupRate}%)'),
                    ]),
                  ],
                ),
              ]),

              // Surcharges & Modifiers Toggles
              div(classes: 'flex flex-col gap-2 p-3.5 bg-zinc-50 border border-zinc-200/60 rounded-2xl', [
                span(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Surcharges & Account Modifiers'),
                ]),
                div(classes: 'grid grid-cols-2 gap-2 text-xs font-semibold text-zinc-700', [
                  div(classes: 'flex items-center gap-2', [
                    input(
                      attributes: {'type': 'checkbox', if (_simIsWeekend) 'checked': 'true'},
                      events: {'change': (e) => setState(() => _simIsWeekend = (e.target as dynamic).checked as bool)},
                    ),
                    span([Component.text('Weekend (+${feeConfig.weekendSurchargeRate}%)')]),
                  ]),
                  div(classes: 'flex items-center gap-2', [
                    input(
                      attributes: {'type': 'checkbox', if (_simIsPeak) 'checked': 'true'},
                      events: {'change': (e) => setState(() => _simIsPeak = (e.target as dynamic).checked as bool)},
                    ),
                    span([Component.text('Peak Season (+${feeConfig.peakSeasonSurchargeRate}%)')]),
                  ]),
                  div(classes: 'flex items-center gap-2', [
                    input(
                      attributes: {'type': 'checkbox', if (_simHasDeposit) 'checked': 'true'},
                      events: {'change': (e) => setState(() => _simHasDeposit = (e.target as dynamic).checked as bool)},
                    ),
                    span([Component.text('Deposit Handling (+₱${feeConfig.securityHandlingFeeFixed})')]),
                  ]),
                  div(classes: 'flex items-center gap-2', [
                    input(
                      attributes: {'type': 'checkbox', if (_simIsInstant) 'checked': 'true'},
                      events: {'change': (e) => setState(() => _simIsInstant = (e.target as dynamic).checked as bool)},
                    ),
                    span([Component.text('Instant Booking (+₱${feeConfig.instantBookingFeeFixed})')]),
                  ]),
                  div(classes: 'flex items-center gap-2', [
                    input(
                      attributes: {'type': 'checkbox', if (_simIsSubscribed) 'checked': 'true'},
                      events: {'change': (e) => setState(() => _simIsSubscribed = (e.target as dynamic).checked as bool)},
                    ),
                    span([Component.text('Subscribed Account (-${feeConfig.subscribedFeeDiscountPct}%)')]),
                  ]),
                  div(classes: 'flex items-center gap-2', [
                    input(
                      attributes: {'type': 'checkbox', if (_simIsHybrid) 'checked': 'true'},
                      events: {'change': (e) => setState(() => _simIsHybrid = (e.target as dynamic).checked as bool)},
                    ),
                    span([Component.text('Hybrid PRO Account (-${feeConfig.hybridFeeDiscountPct}%)')]),
                  ]),
                ]),
              ]),

              // Select Promotion to Test
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-500 uppercase tracking-wider', [
                  Component.text('Select Configured Promotion (or Zero Fees)'),
                ]),
                select(
                  classes:
                      'w-full px-4 py-2.5 bg-indigo-50/50 border border-indigo-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                  events: {
                    'change': (e) => setState(() => _simSelectedPromoCode = (e.target as dynamic).value as String),
                  },
                  [
                    for (final promo in promosList)
                      option(
                        value: promo.code,
                        selected: promo.code == _simSelectedPromoCode,
                        [
                          Component.text(
                            '${promo.code} - ${promo.name} (${promo.discountType == "percentage" ? "${promo.discountValue.toStringAsFixed(0)}%" : "₱${promo.discountValue.toStringAsFixed(2)}"} OFF ${TranyxFeeType.getLabel(promo.applyToFee)})',
                          ),
                        ],
                      ),
                  ],
                ),
              ]),
            ]),
          ]),

          // Right: Real-time Calculation Breakdown Card
          div(
            classes:
                'p-6 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm flex flex-col justify-between gap-5',
            [
              div(classes: 'flex flex-col gap-3', [
                div(classes: 'flex items-center justify-between border-b border-zinc-150 pb-3', [
                  h2(classes: 'text-sm font-black text-zinc-900 flex items-center gap-2', [
                    span([Component.text('🧾')]),
                    Component.text('Itemized Checkout & Accounting Breakdown'),
                  ]),
                  span(
                    classes:
                        'text-[10px] font-black px-2.5 py-0.5 rounded-full ${calcResult.isValid ? "bg-emerald-100 text-emerald-800" : "bg-red-100 text-red-700"}',
                    [Component.text(calcResult.isValid ? 'VALIDATION PASSED' : 'INELIGIBLE')],
                  ),
                ]),

                if (calcResult.validationMessage != null)
                  div(
                    classes:
                        'p-3 rounded-xl text-xs font-semibold ${calcResult.isValid ? "bg-blue-50 text-blue-700 border border-blue-200" : "bg-red-50 text-red-600 border border-red-200"}',
                    [Component.text(calcResult.validationMessage!)],
                  ),

                // Itemized Breakdown Table
                div(classes: 'flex flex-col gap-2.5 bg-zinc-50 p-4 rounded-2xl border border-zinc-200/60 text-xs', [
                  // Base Price (Provider)
                  div(classes: 'flex items-center justify-between font-bold text-zinc-800', [
                    span([Component.text('Base Listing Price (Provider Settlement)')]),
                    span(classes: 'text-sm font-black', [
                      Component.text('₱${calcResult.listingPrice.toStringAsFixed(2)}'),
                    ]),
                  ]),

                  // Platform Fee
                  div(classes: 'flex items-center justify-between text-zinc-600 border-t border-zinc-200/40 pt-2', [
                    span([Component.text('Platform Fee')]),
                    span([Component.text('₱${calcResult.originalPlatformFee.toStringAsFixed(2)}')]),
                  ]),

                  // Transaction Fee
                  div(classes: 'flex items-center justify-between text-zinc-600', [
                    span([Component.text('Transaction Fee')]),
                    span([Component.text('₱${calcResult.originalTransactionFee.toStringAsFixed(2)}')]),
                  ]),

                  // Convenience Fee
                  div(classes: 'flex items-center justify-between text-zinc-600', [
                    span([Component.text('Convenience Fee')]),
                    span([Component.text('₱${calcResult.originalConvenienceFee.toStringAsFixed(2)}')]),
                  ]),

                  // Service Fee
                  if (calcResult.originalServiceFee > 0)
                    div(classes: 'flex items-center justify-between text-zinc-600', [
                      span([Component.text('Service / Escrow Fee')]),
                      span([Component.text('₱${calcResult.originalServiceFee.toStringAsFixed(2)}')]),
                    ]),

                  // Markups & Surcharges
                  if (calcResult.originalMarkupFee > 0)
                    div(classes: 'flex items-center justify-between text-zinc-600', [
                      span([Component.text('Platform Markups & Surcharges')]),
                      span([Component.text('₱${calcResult.originalMarkupFee.toStringAsFixed(2)}')]),
                    ]),

                  // Promotion Discount
                  if (calcResult.promotionDiscount > 0)
                    div(
                      classes:
                          'flex items-center justify-between text-emerald-600 font-extrabold bg-emerald-50/70 p-2 rounded-lg',
                      [
                        div(classes: 'flex items-center gap-1.5', [
                          span([Component.text('🎟️')]),
                          Component.text(
                            'Promotion: ${calcResult.promoCode ?? ""} (${TranyxFeeType.getLabel(calcResult.appliedFeeTarget ?? "")})',
                          ),
                        ]),
                        span([Component.text('-₱${calcResult.promotionDiscount.toStringAsFixed(2)}')]),
                      ],
                    ),

                  // Net TRANYX Fee
                  div(
                    classes:
                        'flex items-center justify-between text-zinc-500 font-bold border-t border-zinc-200/40 pt-2',
                    [
                      span([Component.text('Net TRANYX Platform Revenue')]),
                      span([Component.text('₱${calcResult.finalTotalFees.toStringAsFixed(2)}')]),
                    ],
                  ),

                  // Customer Total
                  div(
                    classes:
                        'flex items-center justify-between text-base font-black text-zinc-900 border-t-2 border-zinc-300 pt-2.5',
                    [
                      span([Component.text('Total Customer Pays')]),
                      span(classes: 'text-indigo-600', [
                        Component.text('₱${calcResult.customerTotal.toStringAsFixed(2)}'),
                      ]),
                    ],
                  ),
                ]),

                // Accounting Verification Dual Card
                div(classes: 'grid grid-cols-2 gap-3 mt-1', [
                  div(classes: 'p-3.5 bg-emerald-50/60 border border-emerald-200 rounded-2xl flex flex-col gap-1', [
                    span(classes: 'text-[9px] font-black text-emerald-800 uppercase tracking-wider', [
                      Component.text('Provider Settlement'),
                    ]),
                    span(classes: 'text-sm font-black text-emerald-900', [
                      Component.text('₱${calcResult.providerSettlement.toStringAsFixed(2)}'),
                    ]),
                    span(classes: 'text-[8px] font-bold text-emerald-700', [
                      Component.text('✓ 100% full listing price'),
                    ]),
                  ]),

                  div(classes: 'p-3.5 bg-indigo-50/60 border border-indigo-200 rounded-2xl flex flex-col gap-1', [
                    span(classes: 'text-[9px] font-black text-indigo-800 uppercase tracking-wider', [
                      Component.text('TRANYX Promo Cost'),
                    ]),
                    span(classes: 'text-sm font-black text-indigo-900', [
                      Component.text('₱${calcResult.tranyxPromotionalCost.toStringAsFixed(2)}'),
                    ]),
                    span(classes: 'text-[8px] font-bold text-indigo-700', [
                      Component.text('✓ Platform revenue sacrificed'),
                    ]),
                  ]),
                ]),
              ]),

              div(classes: 'p-3 bg-zinc-50 border border-zinc-200/50 rounded-xl text-[10px] text-zinc-500 font-medium', [
                Component.text(
                  'Validation Rule: Final Customer Amount = Listing Price + (TRANYX Fees & Markups - Promotional Discount). Provider settlement is NEVER discounted.',
                ),
              ]),
            ],
          ),
        ]);
      },
      loading: () => div(classes: 'h-64 flex items-center justify-center', [
        div(classes: 'animate-spin h-6 w-6 border-2 border-zinc-200 border-t-indigo-500 rounded-full', []),
      ]),
      error: (err, _) => div(classes: 'text-red-500 text-xs font-mono', [Component.text('Error: $err')]),
    );
  }

  /// Audit Trail & Configuration History View
  Component _buildAuditTrailView(BuildContext context, AsyncValue<List<PromoAuditEntry>> auditAsync) {
    return div(classes: 'flex flex-col gap-4', [
      div(classes: 'p-6 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm flex flex-col gap-4', [
        div(classes: 'flex items-center justify-between border-b border-zinc-150 pb-3', [
          div(classes: 'flex flex-col gap-0.5', [
            h2(classes: 'text-sm font-black text-zinc-900 flex items-center gap-2', [
              span([Component.text('📜')]),
              Component.text('Promotions & Fee Audit Trail Log'),
            ]),
            p(classes: 'text-xs text-zinc-400 font-medium', [
              Component.text(
                'Immutable audit log of all promotion creations, updates, fee configurations, and status changes.',
              ),
            ]),
          ]),
        ]),

        auditAsync.when(
          data: (auditList) {
            if (auditList.isEmpty) {
              return div(classes: 'py-12 text-center text-zinc-400 text-xs font-semibold', [
                Component.text('No audit entries recorded yet. Actions will appear here in real-time.'),
              ]);
            }

            return div(classes: 'flex flex-col gap-3 overflow-y-auto max-h-[700px] pr-2 no-scrollbar', [
              for (final entry in auditList)
                div(
                  classes:
                      'p-4 rounded-2xl bg-zinc-50 border border-zinc-200/60 flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-xs hover:bg-zinc-100/50 transition-all',
                  [
                    div(classes: 'flex items-start gap-3', [
                      span(
                        classes:
                            'px-2.5 py-1 rounded-lg text-[9px] font-black uppercase tracking-wider '
                            '${entry.action == "CREATED" ? "bg-emerald-100 text-emerald-800" : (entry.action == "UPDATED" || entry.action == "UPDATED_FEE_CONFIG" ? "bg-blue-100 text-blue-800" : (entry.action == "DELETED" ? "bg-red-100 text-red-800" : "bg-amber-100 text-amber-800"))}',
                        [Component.text(entry.action)],
                      ),
                      div(classes: 'flex flex-col gap-0.5', [
                        div(classes: 'flex items-center gap-2', [
                          span(classes: 'font-mono font-black text-zinc-900', [Component.text(entry.promoCode)]),
                          span(classes: 'text-zinc-500 font-medium', [Component.text('(${entry.promoName})')]),
                        ]),
                        span(classes: 'text-[11px] text-zinc-600 font-semibold', [
                          Component.text(entry.discountSummary),
                        ]),
                        span(classes: 'text-[9px] text-zinc-400 font-medium', [
                          Component.text('Modified by: ${entry.adminName} (${entry.adminEmail})'),
                        ]),
                      ]),
                    ]),

                    span(classes: 'text-[10px] font-mono text-zinc-400 font-semibold self-end sm:self-center', [
                      Component.text(
                        '${entry.timestamp.year}-${entry.timestamp.month.toString().padLeft(2, '0')}-${entry.timestamp.day.toString().padLeft(2, '0')} ${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}',
                      ),
                    ]),
                  ],
                ),
            ]);
          },
          loading: () => div(classes: 'py-12 flex justify-center', [
            div(classes: 'animate-spin h-6 w-6 border-2 border-zinc-200 border-t-indigo-500 rounded-full', []),
          ]),
          error: (err, _) => div(classes: 'text-red-500 text-xs font-mono', [Component.text('Audit load error: $err')]),
        ),
      ]),
    ]);
  }
}
