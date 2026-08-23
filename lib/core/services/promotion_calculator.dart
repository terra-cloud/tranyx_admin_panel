import 'dart:math' as math;

/// TRANYX Fee Types that can be discounted by promotions.
/// Note: Base listing/rental/job prices are STRICTLY NEVER discountable.
class TranyxFeeType {
  static const String platformFee = 'platform_fee';
  static const String transactionFee = 'transaction_fee';
  static const String convenienceFee = 'convenience_fee';
  static const String serviceFee = 'service_fee';
  static const String markupFee = 'markup_fee';
  static const String allFees = 'all_fees';

  static const List<String> eligibleFees = [
    platformFee,
    transactionFee,
    convenienceFee,
    serviceFee,
    markupFee,
    allFees,
  ];

  static const List<String> prohibitedBaseTargets = [
    'listing_price',
    'rental_price',
    'service_provider_price',
    'property_price',
    'vehicle_price',
    'owner_price',
    'base_price',
    'provider_price',
  ];

  static String getLabel(String feeType) {
    switch (feeType) {
      case platformFee:
        return 'Platform Fee';
      case transactionFee:
        return 'Transaction Fee';
      case convenienceFee:
        return 'Convenience Fee';
      case serviceFee:
        return 'Service Fee';
      case markupFee:
        return 'Platform Markups & Surcharges';
      case allFees:
        return 'All TRANYX Platform Fees & Markups';
      default:
        return feeType;
    }
  }

  static bool isProhibitedTarget(String target) {
    final lower = target.toLowerCase().trim();
    for (final prohibited in prohibitedBaseTargets) {
      if (lower.contains(prohibited) || prohibited.contains(lower)) {
        return true;
      }
    }
    return false;
  }
}

/// Global & Category-Specific Fee & Markup Configurations Model.
class FeeConfiguration {
  // Global Base Fee Rates & Fixed Charges
  final double defaultPlatformFeeRate; // in percent, e.g. 10.0%
  final double defaultTransactionFeeRate; // in percent, e.g. 2.5%
  final double defaultTransactionFeeFixed; // in ₱, e.g. ₱15.00
  final double defaultConvenienceFeeRate; // in percent, e.g. 1.0%
  final double defaultConvenienceFeeFixed; // in ₱, e.g. ₱20.00
  final double defaultServiceFeeRate; // in percent, e.g. 5.0%
  final double defaultServiceFeeFixed; // in ₱, e.g. ₱0.00

  // Category-Specific Rates & Markups
  final double vehiclePlatformFeeRate; // e.g. 10.0%
  final double vehicleMarkupRate; // e.g. 2.0%
  final double propertyPlatformFeeRate; // e.g. 8.0%
  final double propertyMarkupRate; // e.g. 1.5%
  final double servicePlatformFeeRate; // e.g. 10.0%
  final double serviceMarkupRate; // e.g. 0.0%
  final double itemPlatformFeeRate; // e.g. 12.0%
  final double itemMarkupRate; // e.g. 2.0%

  // Special Surcharges & Platform Markups
  final double weekendSurchargeRate; // in percent, e.g. 3.0%
  final double peakSeasonSurchargeRate; // in percent, e.g. 5.0%
  final double securityHandlingFeeFixed; // in ₱, e.g. ₱50.00
  final double instantBookingFeeFixed; // in ₱, e.g. ₱30.00

  // Thresholds, Caps & Tier Discounts
  final double minPlatformFeeCap; // in ₱, e.g. ₱20.00
  final double maxPlatformFeeCap; // in ₱, e.g. ₱5,000.00
  final double subscribedFeeDiscountPct; // e.g. 20.0% discount on platform fee for subscribed accounts
  final double hybridFeeDiscountPct; // e.g. 30.0% discount on platform fee for hybrid PRO accounts

  final DateTime? updatedAt;
  final String? updatedBy;

  const FeeConfiguration({
    this.defaultPlatformFeeRate = 10.0,
    this.defaultTransactionFeeRate = 2.5,
    this.defaultTransactionFeeFixed = 15.0,
    this.defaultConvenienceFeeRate = 1.0,
    this.defaultConvenienceFeeFixed = 20.0,
    this.defaultServiceFeeRate = 5.0,
    this.defaultServiceFeeFixed = 0.0,
    this.vehiclePlatformFeeRate = 10.0,
    this.vehicleMarkupRate = 2.0,
    this.propertyPlatformFeeRate = 8.0,
    this.propertyMarkupRate = 1.5,
    this.servicePlatformFeeRate = 10.0,
    this.serviceMarkupRate = 0.0,
    this.itemPlatformFeeRate = 12.0,
    this.itemMarkupRate = 2.0,
    this.weekendSurchargeRate = 3.0,
    this.peakSeasonSurchargeRate = 5.0,
    this.securityHandlingFeeFixed = 50.0,
    this.instantBookingFeeFixed = 30.0,
    this.minPlatformFeeCap = 20.0,
    this.maxPlatformFeeCap = 5000.0,
    this.subscribedFeeDiscountPct = 20.0,
    this.hybridFeeDiscountPct = 30.0,
    this.updatedAt,
    this.updatedBy,
  });

  factory FeeConfiguration.fromMap(Map<String, dynamic> map) {
    double numToDouble(dynamic val, double fallback) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? fallback;
      return fallback;
    }

    return FeeConfiguration(
      defaultPlatformFeeRate: numToDouble(map['defaultPlatformFeeRate'], 10.0),
      defaultTransactionFeeRate: numToDouble(map['defaultTransactionFeeRate'], 2.5),
      defaultTransactionFeeFixed: numToDouble(map['defaultTransactionFeeFixed'], 15.0),
      defaultConvenienceFeeRate: numToDouble(map['defaultConvenienceFeeRate'], 1.0),
      defaultConvenienceFeeFixed: numToDouble(map['defaultConvenienceFeeFixed'], 20.0),
      defaultServiceFeeRate: numToDouble(map['defaultServiceFeeRate'], 5.0),
      defaultServiceFeeFixed: numToDouble(map['defaultServiceFeeFixed'], 0.0),
      vehiclePlatformFeeRate: numToDouble(map['vehiclePlatformFeeRate'], 10.0),
      vehicleMarkupRate: numToDouble(map['vehicleMarkupRate'], 2.0),
      propertyPlatformFeeRate: numToDouble(map['propertyPlatformFeeRate'], 8.0),
      propertyMarkupRate: numToDouble(map['propertyMarkupRate'], 1.5),
      servicePlatformFeeRate: numToDouble(map['servicePlatformFeeRate'], 10.0),
      serviceMarkupRate: numToDouble(map['serviceMarkupRate'], 0.0),
      itemPlatformFeeRate: numToDouble(map['itemPlatformFeeRate'], 12.0),
      itemMarkupRate: numToDouble(map['itemMarkupRate'], 2.0),
      weekendSurchargeRate: numToDouble(map['weekendSurchargeRate'], 3.0),
      peakSeasonSurchargeRate: numToDouble(map['peakSeasonSurchargeRate'], 5.0),
      securityHandlingFeeFixed: numToDouble(map['securityHandlingFeeFixed'], 50.0),
      instantBookingFeeFixed: numToDouble(map['instantBookingFeeFixed'], 30.0),
      minPlatformFeeCap: numToDouble(map['minPlatformFeeCap'], 20.0),
      maxPlatformFeeCap: numToDouble(map['maxPlatformFeeCap'], 5000.0),
      subscribedFeeDiscountPct: numToDouble(map['subscribedFeeDiscountPct'], 20.0),
      hybridFeeDiscountPct: numToDouble(map['hybridFeeDiscountPct'], 30.0),
      updatedBy: map['updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'defaultPlatformFeeRate': defaultPlatformFeeRate,
      'defaultTransactionFeeRate': defaultTransactionFeeRate,
      'defaultTransactionFeeFixed': defaultTransactionFeeFixed,
      'defaultConvenienceFeeRate': defaultConvenienceFeeRate,
      'defaultConvenienceFeeFixed': defaultConvenienceFeeFixed,
      'defaultServiceFeeRate': defaultServiceFeeRate,
      'defaultServiceFeeFixed': defaultServiceFeeFixed,
      'vehiclePlatformFeeRate': vehiclePlatformFeeRate,
      'vehicleMarkupRate': vehicleMarkupRate,
      'propertyPlatformFeeRate': propertyPlatformFeeRate,
      'propertyMarkupRate': propertyMarkupRate,
      'servicePlatformFeeRate': servicePlatformFeeRate,
      'serviceMarkupRate': serviceMarkupRate,
      'itemPlatformFeeRate': itemPlatformFeeRate,
      'itemMarkupRate': itemMarkupRate,
      'weekendSurchargeRate': weekendSurchargeRate,
      'peakSeasonSurchargeRate': peakSeasonSurchargeRate,
      'securityHandlingFeeFixed': securityHandlingFeeFixed,
      'instantBookingFeeFixed': instantBookingFeeFixed,
      'minPlatformFeeCap': minPlatformFeeCap,
      'maxPlatformFeeCap': maxPlatformFeeCap,
      'subscribedFeeDiscountPct': subscribedFeeDiscountPct,
      'hybridFeeDiscountPct': hybridFeeDiscountPct,
      if (updatedBy != null) 'updatedBy': updatedBy,
    };
  }
}

/// Detailed calculation breakdown for a checkout or transaction.
class PromotionCalculationResult {
  final double listingPrice;
  final double originalPlatformFee;
  final double originalTransactionFee;
  final double originalConvenienceFee;
  final double originalServiceFee;
  final double originalMarkupFee;
  final double originalTotalFees;

  final double eligibleFeeAmount;
  final double promotionDiscount;

  final double finalPlatformFee;
  final double finalTransactionFee;
  final double finalConvenienceFee;
  final double finalServiceFee;
  final double finalMarkupFee;
  final double finalTotalFees;

  final double customerTotal;
  final double providerSettlement;
  final double tranyxRevenue;
  final double tranyxPromotionalCost;

  final bool isValid;
  final String? validationMessage;
  final String? promoCode;
  final String? promoName;
  final String? appliedFeeTarget;

  const PromotionCalculationResult({
    required this.listingPrice,
    required this.originalPlatformFee,
    required this.originalTransactionFee,
    required this.originalConvenienceFee,
    required this.originalServiceFee,
    this.originalMarkupFee = 0.0,
    required this.originalTotalFees,
    required this.eligibleFeeAmount,
    required this.promotionDiscount,
    required this.finalPlatformFee,
    required this.finalTransactionFee,
    required this.finalConvenienceFee,
    required this.finalServiceFee,
    this.finalMarkupFee = 0.0,
    required this.finalTotalFees,
    required this.customerTotal,
    required this.providerSettlement,
    required this.tranyxRevenue,
    required this.tranyxPromotionalCost,
    required this.isValid,
    this.validationMessage,
    this.promoCode,
    this.promoName,
    this.appliedFeeTarget,
  });

  Map<String, dynamic> toMap() {
    return {
      'listingPrice': listingPrice,
      'originalPlatformFee': originalPlatformFee,
      'originalTransactionFee': originalTransactionFee,
      'originalConvenienceFee': originalConvenienceFee,
      'originalServiceFee': originalServiceFee,
      'originalMarkupFee': originalMarkupFee,
      'originalTotalFees': originalTotalFees,
      'eligibleFeeAmount': eligibleFeeAmount,
      'promotionDiscount': promotionDiscount,
      'finalPlatformFee': finalPlatformFee,
      'finalTransactionFee': finalTransactionFee,
      'finalConvenienceFee': finalConvenienceFee,
      'finalServiceFee': finalServiceFee,
      'finalMarkupFee': finalMarkupFee,
      'finalTotalFees': finalTotalFees,
      'customerTotal': customerTotal,
      'providerSettlement': providerSettlement,
      'tranyxRevenue': tranyxRevenue,
      'tranyxPromotionalCost': tranyxPromotionalCost,
      'isValid': isValid,
      'validationMessage': validationMessage,
      'promoCode': promoCode,
      'promoName': promoName,
      'appliedFeeTarget': appliedFeeTarget,
    };
  }
}

/// Core Calculator and Business Rule Engine for TRANYX Platform Fees, Markups and Promotions.
class TranyxPromotionCalculator {
  /// Computes initial fees and markups using a configured [FeeConfiguration].
  static PromotionCalculationResult calculateFromConfig({
    required double listingPrice,
    required FeeConfiguration feeConfig,
    String category = 'vehicles', // 'vehicles', 'properties', 'services', 'items'
    bool isWeekend = false,
    bool isPeakSeason = false,
    bool hasSecurityDeposit = false,
    bool isInstantBooking = false,
    bool isSubscribedUser = false,
    bool isHybridUser = false,
    String? promoCode,
    String? promoName,
    String applyToFee = TranyxFeeType.platformFee,
    String discountType = 'percentage',
    double discountValue = 0.0,
    double? minTransactionAmount,
    double? maxDiscountCap,
    DateTime? startDate,
    DateTime? expirationDate,
    int? maxUsers,
    int usedCount = 0,
    bool isSingleUsePerUser = false,
    bool hasUserAlreadyUsed = false,
    DateTime? evaluationTime,
  }) {
    // 1. Determine Category-Specific Platform Fee Rate & Markup Rate
    double platRate = feeConfig.defaultPlatformFeeRate;
    double markupRate = 0.0;

    switch (category.toLowerCase()) {
      case 'vehicles':
      case 'vehicle':
        platRate = feeConfig.vehiclePlatformFeeRate;
        markupRate = feeConfig.vehicleMarkupRate;
        break;
      case 'properties':
      case 'property':
        platRate = feeConfig.propertyPlatformFeeRate;
        markupRate = feeConfig.propertyMarkupRate;
        break;
      case 'services':
      case 'service':
        platRate = feeConfig.servicePlatformFeeRate;
        markupRate = feeConfig.serviceMarkupRate;
        break;
      case 'items':
      case 'item':
        platRate = feeConfig.itemPlatformFeeRate;
        markupRate = feeConfig.itemMarkupRate;
        break;
      default:
        platRate = feeConfig.defaultPlatformFeeRate;
        markupRate = 0.0;
        break;
    }

    // Apply Tier Fee Discount on Platform Fee Rate if eligible
    if (isHybridUser && feeConfig.hybridFeeDiscountPct > 0) {
      platRate = platRate * (1.0 - (feeConfig.hybridFeeDiscountPct / 100.0));
    } else if (isSubscribedUser && feeConfig.subscribedFeeDiscountPct > 0) {
      platRate = platRate * (1.0 - (feeConfig.subscribedFeeDiscountPct / 100.0));
    }

    // 2. Compute Base Platform Fee (and enforce min/max caps)
    double platformFee = (listingPrice * (platRate / 100.0) * 100.0).roundToDouble() / 100.0;
    if (feeConfig.minPlatformFeeCap > 0 && platformFee < feeConfig.minPlatformFeeCap && listingPrice > 0) {
      platformFee = feeConfig.minPlatformFeeCap;
    }
    if (feeConfig.maxPlatformFeeCap > 0 && platformFee > feeConfig.maxPlatformFeeCap) {
      platformFee = feeConfig.maxPlatformFeeCap;
    }

    // 3. Compute Transaction Fee
    double transactionFee = (((listingPrice * (feeConfig.defaultTransactionFeeRate / 100.0)) + feeConfig.defaultTransactionFeeFixed) * 100.0).roundToDouble() / 100.0;

    // 4. Compute Convenience Fee
    double convenienceFee = (((listingPrice * (feeConfig.defaultConvenienceFeeRate / 100.0)) + feeConfig.defaultConvenienceFeeFixed) * 100.0).roundToDouble() / 100.0;

    // 5. Compute Service Fee
    double serviceFee = (((listingPrice * (feeConfig.defaultServiceFeeRate / 100.0)) + feeConfig.defaultServiceFeeFixed) * 100.0).roundToDouble() / 100.0;

    // 6. Compute Markups & Surcharges
    double markupFee = listingPrice * (markupRate / 100.0);
    if (isWeekend && feeConfig.weekendSurchargeRate > 0) {
      markupFee += listingPrice * (feeConfig.weekendSurchargeRate / 100.0);
    }
    if (isPeakSeason && feeConfig.peakSeasonSurchargeRate > 0) {
      markupFee += listingPrice * (feeConfig.peakSeasonSurchargeRate / 100.0);
    }
    if (hasSecurityDeposit) {
      markupFee += feeConfig.securityHandlingFeeFixed;
    }
    if (isInstantBooking) {
      markupFee += feeConfig.instantBookingFeeFixed;
    }
    markupFee = (markupFee * 100.0).roundToDouble() / 100.0;

    return calculate(
      listingPrice: listingPrice,
      platformFee: platformFee,
      transactionFee: transactionFee,
      convenienceFee: convenienceFee,
      serviceFee: serviceFee,
      markupFee: markupFee,
      promoCode: promoCode,
      promoName: promoName,
      applyToFee: applyToFee,
      discountType: discountType,
      discountValue: discountValue,
      minTransactionAmount: minTransactionAmount,
      maxDiscountCap: maxDiscountCap,
      startDate: startDate,
      expirationDate: expirationDate,
      maxUsers: maxUsers,
      usedCount: usedCount,
      isSingleUsePerUser: isSingleUsePerUser,
      hasUserAlreadyUsed: hasUserAlreadyUsed,
      evaluationTime: evaluationTime,
    );
  }

  /// Calculates transaction breakdown enforcing that promotions ONLY discount TRANYX fees
  /// and NEVER reduce the provider/owner's base listing price.
  static PromotionCalculationResult calculate({
    required double listingPrice,
    double platformFee = 0.0,
    double transactionFee = 0.0,
    double convenienceFee = 0.0,
    double serviceFee = 0.0,
    double markupFee = 0.0,
    String? promoCode,
    String? promoName,
    String applyToFee = TranyxFeeType.platformFee,
    String discountType = 'percentage', // 'percentage' or 'flat'
    double discountValue = 0.0,
    double? minTransactionAmount,
    double? maxDiscountCap,
    DateTime? startDate,
    DateTime? expirationDate,
    int? maxUsers,
    int usedCount = 0,
    bool isSingleUsePerUser = false,
    bool hasUserAlreadyUsed = false,
    DateTime? evaluationTime,
  }) {
    final now = evaluationTime ?? DateTime.now();

    final origPlatform = math.max(0.0, platformFee);
    final origTransaction = math.max(0.0, transactionFee);
    final origConvenience = math.max(0.0, convenienceFee);
    final origService = math.max(0.0, serviceFee);
    final origMarkup = math.max(0.0, markupFee);
    final origTotalFees = origPlatform + origTransaction + origConvenience + origService + origMarkup;

    // Default result without promo
    if (promoCode == null || promoCode.trim().isEmpty || discountValue <= 0) {
      return PromotionCalculationResult(
        listingPrice: listingPrice,
        originalPlatformFee: origPlatform,
        originalTransactionFee: origTransaction,
        originalConvenienceFee: origConvenience,
        originalServiceFee: origService,
        originalMarkupFee: origMarkup,
        originalTotalFees: origTotalFees,
        eligibleFeeAmount: 0.0,
        promotionDiscount: 0.0,
        finalPlatformFee: origPlatform,
        finalTransactionFee: origTransaction,
        finalConvenienceFee: origConvenience,
        finalServiceFee: origService,
        finalMarkupFee: origMarkup,
        finalTotalFees: origTotalFees,
        customerTotal: listingPrice + origTotalFees,
        providerSettlement: listingPrice,
        tranyxRevenue: origTotalFees,
        tranyxPromotionalCost: 0.0,
        isValid: true,
      );
    }

    // Check prohibited targets
    if (TranyxFeeType.isProhibitedTarget(applyToFee)) {
      return PromotionCalculationResult(
        listingPrice: listingPrice,
        originalPlatformFee: origPlatform,
        originalTransactionFee: origTransaction,
        originalConvenienceFee: origConvenience,
        originalServiceFee: origService,
        originalMarkupFee: origMarkup,
        originalTotalFees: origTotalFees,
        eligibleFeeAmount: 0.0,
        promotionDiscount: 0.0,
        finalPlatformFee: origPlatform,
        finalTransactionFee: origTransaction,
        finalConvenienceFee: origConvenience,
        finalServiceFee: origService,
        finalMarkupFee: origMarkup,
        finalTotalFees: origTotalFees,
        customerTotal: listingPrice + origTotalFees,
        providerSettlement: listingPrice,
        tranyxRevenue: origTotalFees,
        tranyxPromotionalCost: 0.0,
        isValid: false,
        validationMessage: 'Promotions cannot target provider base prices. Only TRANYX platform fees and markups are discountable.',
        promoCode: promoCode,
        promoName: promoName,
        appliedFeeTarget: applyToFee,
      );
    }

    // Check Start Date
    if (startDate != null && now.isBefore(startDate)) {
      return PromotionCalculationResult(
        listingPrice: listingPrice,
        originalPlatformFee: origPlatform,
        originalTransactionFee: origTransaction,
        originalConvenienceFee: origConvenience,
        originalServiceFee: origService,
        originalMarkupFee: origMarkup,
        originalTotalFees: origTotalFees,
        eligibleFeeAmount: 0.0,
        promotionDiscount: 0.0,
        finalPlatformFee: origPlatform,
        finalTransactionFee: origTransaction,
        finalConvenienceFee: origConvenience,
        finalServiceFee: origService,
        finalMarkupFee: origMarkup,
        finalTotalFees: origTotalFees,
        customerTotal: listingPrice + origTotalFees,
        providerSettlement: listingPrice,
        tranyxRevenue: origTotalFees,
        tranyxPromotionalCost: 0.0,
        isValid: false,
        validationMessage: 'Promotion is not yet active (starts ${startDate.toIso8601String().split('T').first}).',
        promoCode: promoCode,
        promoName: promoName,
        appliedFeeTarget: applyToFee,
      );
    }

    // Check Expiration Date
    if (expirationDate != null && now.isAfter(expirationDate)) {
      return PromotionCalculationResult(
        listingPrice: listingPrice,
        originalPlatformFee: origPlatform,
        originalTransactionFee: origTransaction,
        originalConvenienceFee: origConvenience,
        originalServiceFee: origService,
        originalMarkupFee: origMarkup,
        originalTotalFees: origTotalFees,
        eligibleFeeAmount: 0.0,
        promotionDiscount: 0.0,
        finalPlatformFee: origPlatform,
        finalTransactionFee: origTransaction,
        finalConvenienceFee: origConvenience,
        finalServiceFee: origService,
        finalMarkupFee: origMarkup,
        finalTotalFees: origTotalFees,
        customerTotal: listingPrice + origTotalFees,
        providerSettlement: listingPrice,
        tranyxRevenue: origTotalFees,
        tranyxPromotionalCost: 0.0,
        isValid: false,
        validationMessage: 'Promotion expired on ${expirationDate.toIso8601String().split('T').first}.',
        promoCode: promoCode,
        promoName: promoName,
        appliedFeeTarget: applyToFee,
      );
    }

    // Check Max Users (e.g. First 1,000 users)
    if (maxUsers != null && maxUsers > 0 && usedCount >= maxUsers) {
      return PromotionCalculationResult(
        listingPrice: listingPrice,
        originalPlatformFee: origPlatform,
        originalTransactionFee: origTransaction,
        originalConvenienceFee: origConvenience,
        originalServiceFee: origService,
        originalMarkupFee: origMarkup,
        originalTotalFees: origTotalFees,
        eligibleFeeAmount: 0.0,
        promotionDiscount: 0.0,
        finalPlatformFee: origPlatform,
        finalTransactionFee: origTransaction,
        finalConvenienceFee: origConvenience,
        finalServiceFee: origService,
        finalMarkupFee: origMarkup,
        finalTotalFees: origTotalFees,
        customerTotal: listingPrice + origTotalFees,
        providerSettlement: listingPrice,
        tranyxRevenue: origTotalFees,
        tranyxPromotionalCost: 0.0,
        isValid: false,
        validationMessage: 'Promotion usage limit ($maxUsers users) has been reached.',
        promoCode: promoCode,
        promoName: promoName,
        appliedFeeTarget: applyToFee,
      );
    }

    // Check Single Use Per User
    if (isSingleUsePerUser && hasUserAlreadyUsed) {
      return PromotionCalculationResult(
        listingPrice: listingPrice,
        originalPlatformFee: origPlatform,
        originalTransactionFee: origTransaction,
        originalConvenienceFee: origConvenience,
        originalServiceFee: origService,
        originalMarkupFee: origMarkup,
        originalTotalFees: origTotalFees,
        eligibleFeeAmount: 0.0,
        promotionDiscount: 0.0,
        finalPlatformFee: origPlatform,
        finalTransactionFee: origTransaction,
        finalConvenienceFee: origConvenience,
        finalServiceFee: origService,
        finalMarkupFee: origMarkup,
        finalTotalFees: origTotalFees,
        customerTotal: listingPrice + origTotalFees,
        providerSettlement: listingPrice,
        tranyxRevenue: origTotalFees,
        tranyxPromotionalCost: 0.0,
        isValid: false,
        validationMessage: 'This single-use promotion has already been redeemed by your account.',
        promoCode: promoCode,
        promoName: promoName,
        appliedFeeTarget: applyToFee,
      );
    }

    // Check Minimum Transaction Amount
    if (minTransactionAmount != null && minTransactionAmount > 0 && listingPrice < minTransactionAmount) {
      return PromotionCalculationResult(
        listingPrice: listingPrice,
        originalPlatformFee: origPlatform,
        originalTransactionFee: origTransaction,
        originalConvenienceFee: origConvenience,
        originalServiceFee: origService,
        originalMarkupFee: origMarkup,
        originalTotalFees: origTotalFees,
        eligibleFeeAmount: 0.0,
        promotionDiscount: 0.0,
        finalPlatformFee: origPlatform,
        finalTransactionFee: origTransaction,
        finalConvenienceFee: origConvenience,
        finalServiceFee: origService,
        finalMarkupFee: origMarkup,
        finalTotalFees: origTotalFees,
        customerTotal: listingPrice + origTotalFees,
        providerSettlement: listingPrice,
        tranyxRevenue: origTotalFees,
        tranyxPromotionalCost: 0.0,
        isValid: false,
        validationMessage: 'Minimum transaction amount of ₱${minTransactionAmount.toStringAsFixed(2)} is required.',
        promoCode: promoCode,
        promoName: promoName,
        appliedFeeTarget: applyToFee,
      );
    }

    // Identify Eligible TRANYX Fee
    double eligibleFee = 0.0;
    switch (applyToFee) {
      case TranyxFeeType.platformFee:
        eligibleFee = origPlatform;
        break;
      case TranyxFeeType.transactionFee:
        eligibleFee = origTransaction;
        break;
      case TranyxFeeType.convenienceFee:
        eligibleFee = origConvenience;
        break;
      case TranyxFeeType.serviceFee:
        eligibleFee = origService;
        break;
      case TranyxFeeType.markupFee:
        eligibleFee = origMarkup;
        break;
      case TranyxFeeType.allFees:
        eligibleFee = origTotalFees;
        break;
      default:
        eligibleFee = origPlatform;
        break;
    }

    if (eligibleFee <= 0) {
      return PromotionCalculationResult(
        listingPrice: listingPrice,
        originalPlatformFee: origPlatform,
        originalTransactionFee: origTransaction,
        originalConvenienceFee: origConvenience,
        originalServiceFee: origService,
        originalMarkupFee: origMarkup,
        originalTotalFees: origTotalFees,
        eligibleFeeAmount: 0.0,
        promotionDiscount: 0.0,
        finalPlatformFee: origPlatform,
        finalTransactionFee: origTransaction,
        finalConvenienceFee: origConvenience,
        finalServiceFee: origService,
        finalMarkupFee: origMarkup,
        finalTotalFees: origTotalFees,
        customerTotal: listingPrice + origTotalFees,
        providerSettlement: listingPrice,
        tranyxRevenue: origTotalFees,
        tranyxPromotionalCost: 0.0,
        isValid: true,
        validationMessage: 'No applicable TRANYX fees to discount.',
        promoCode: promoCode,
        promoName: promoName,
        appliedFeeTarget: applyToFee,
      );
    }

    // Calculate Raw Promotional Discount
    double rawDiscount = 0.0;
    if (discountType == 'percentage') {
      final pct = math.min(100.0, math.max(0.0, discountValue));
      rawDiscount = eligibleFee * (pct / 100.0);
    } else {
      rawDiscount = math.max(0.0, discountValue);
    }

    // CRITICAL ENFORCEMENT 1: Promotion discount CANNOT exceed the eligible TRANYX fee
    double calculatedDiscount = math.min(rawDiscount, eligibleFee);

    // CRITICAL ENFORCEMENT 2: Respect maximum discount cap if specified
    if (maxDiscountCap != null && maxDiscountCap > 0) {
      calculatedDiscount = math.min(calculatedDiscount, maxDiscountCap);
    }

    // Calculate final TRANYX fees
    double finalPlatform = origPlatform;
    double finalTransaction = origTransaction;
    double finalConvenience = origConvenience;
    double finalService = origService;
    double finalMarkup = origMarkup;

    if (applyToFee == TranyxFeeType.platformFee) {
      finalPlatform = math.max(0.0, origPlatform - calculatedDiscount);
    } else if (applyToFee == TranyxFeeType.transactionFee) {
      finalTransaction = math.max(0.0, origTransaction - calculatedDiscount);
    } else if (applyToFee == TranyxFeeType.convenienceFee) {
      finalConvenience = math.max(0.0, origConvenience - calculatedDiscount);
    } else if (applyToFee == TranyxFeeType.serviceFee) {
      finalService = math.max(0.0, origService - calculatedDiscount);
    } else if (applyToFee == TranyxFeeType.markupFee) {
      finalMarkup = math.max(0.0, origMarkup - calculatedDiscount);
    } else if (applyToFee == TranyxFeeType.allFees) {
      var remainingDiscount = calculatedDiscount;
      final dPlat = math.min(finalPlatform, remainingDiscount);
      finalPlatform -= dPlat;
      remainingDiscount -= dPlat;

      final dTx = math.min(finalTransaction, remainingDiscount);
      finalTransaction -= dTx;
      remainingDiscount -= dTx;

      final dConv = math.min(finalConvenience, remainingDiscount);
      finalConvenience -= dConv;
      remainingDiscount -= dConv;

      final dServ = math.min(finalService, remainingDiscount);
      finalService -= dServ;
      remainingDiscount -= dServ;

      final dMark = math.min(finalMarkup, remainingDiscount);
      finalMarkup -= dMark;
      remainingDiscount -= dMark;
    }

    final finalTotalFees = finalPlatform + finalTransaction + finalConvenience + finalService + finalMarkup;
    final customerTotal = listingPrice + finalTotalFees;

    // CRITICAL ENFORCEMENT 3: Provider settlement remains 100% of listing price
    final providerSettlement = listingPrice;

    final tranyxRevenue = finalTotalFees;
    final tranyxPromotionalCost = calculatedDiscount;

    return PromotionCalculationResult(
      listingPrice: listingPrice,
      originalPlatformFee: origPlatform,
      originalTransactionFee: origTransaction,
      originalConvenienceFee: origConvenience,
      originalServiceFee: origService,
      originalMarkupFee: origMarkup,
      originalTotalFees: origTotalFees,
      eligibleFeeAmount: eligibleFee,
      promotionDiscount: calculatedDiscount,
      finalPlatformFee: finalPlatform,
      finalTransactionFee: finalTransaction,
      finalConvenienceFee: finalConvenience,
      finalServiceFee: finalService,
      finalMarkupFee: finalMarkup,
      finalTotalFees: finalTotalFees,
      customerTotal: customerTotal,
      providerSettlement: providerSettlement,
      tranyxRevenue: tranyxRevenue,
      tranyxPromotionalCost: tranyxPromotionalCost,
      isValid: true,
      promoCode: promoCode,
      promoName: promoName,
      appliedFeeTarget: applyToFee,
    );
  }
}
