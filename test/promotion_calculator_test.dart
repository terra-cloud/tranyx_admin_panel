import 'package:tranyx_admin_portal/core/services/promotion_calculator.dart';

void main() {
  int passed = 0;
  int failed = 0;

  void assertEqual(dynamic actual, dynamic expected, String testName) {
    if (actual == expected) {
      print('✓ PASS: $testName');
      passed++;
    } else {
      print('✗ FAIL: $testName (Expected: $expected, Got: $actual)');
      failed++;
    }
  }

  print('--- RUNNING TRANYX PROMOTION & FEE CONFIGURATION TESTS ---');

  // Test 1: Example – Vehicle Rental (50% Platform Fee Promotion)
  // Listing: ₱2,000, Platform Fee: ₱200 -> Discount: ₱100, Final Fee: ₱100, Customer: ₱2,100, Provider: ₱2,000
  {
    final res = TranyxPromotionCalculator.calculate(
      listingPrice: 2000.0,
      platformFee: 200.0,
      promoCode: 'LAUNCH50',
      promoName: 'TRANYX Launch Promo',
      applyToFee: TranyxFeeType.platformFee,
      discountType: 'percentage',
      discountValue: 50.0,
    );

    assertEqual(res.listingPrice, 2000.0, 'Test 1 - Listing Price');
    assertEqual(res.originalPlatformFee, 200.0, 'Test 1 - Original Platform Fee');
    assertEqual(res.promotionDiscount, 100.0, 'Test 1 - Promo Discount ₱100');
    assertEqual(res.finalPlatformFee, 100.0, 'Test 1 - Final Platform Fee ₱100');
    assertEqual(res.customerTotal, 2100.0, 'Test 1 - Customer Pays ₱2,100');
    assertEqual(res.providerSettlement, 2000.0, 'Test 1 - Provider Receives ₱2,000');
    assertEqual(res.tranyxRevenue, 100.0, 'Test 1 - TRANYX Revenue ₱100');
    assertEqual(res.tranyxPromotionalCost, 100.0, 'Test 1 - TRANYX Promo Cost ₱100');
  }

  // Test 2: Auto Zero Fees (First 1,000 Users) - 100% Platform Fee Waiver
  // Listing: ₱2,000, Platform Fee: ₱200 -> Discount: ₱200, Final Fee: ₱0, Customer: ₱2,000, Provider: ₱2,000
  {
    final res = TranyxPromotionCalculator.calculate(
      listingPrice: 2000.0,
      platformFee: 200.0,
      promoCode: 'ZEROFEES1000',
      promoName: 'Auto Zero Fees (First 1,000 Users)',
      applyToFee: TranyxFeeType.platformFee,
      discountType: 'percentage',
      discountValue: 100.0,
      maxUsers: 1000,
      usedCount: 15,
      isSingleUsePerUser: true,
    );

    assertEqual(res.listingPrice, 2000.0, 'Test 2 - Listing Price');
    assertEqual(res.promotionDiscount, 200.0, 'Test 2 - 100% Fee Waived (₱200)');
    assertEqual(res.finalPlatformFee, 0.0, 'Test 2 - Zero Fee Collected');
    assertEqual(res.customerTotal, 2000.0, 'Test 2 - Customer Total equals Listing Price');
    assertEqual(res.providerSettlement, 2000.0, 'Test 2 - Provider receives 100%');
    assertEqual(res.tranyxPromotionalCost, 200.0, 'Test 2 - TRANYX Sacrificed ₱200');
  }

  // Test 3: Service Listing 100% Transaction Fee Discount
  // Service Price: ₱1,500, Transaction Fee: ₱150 -> Discount: ₱150, Customer: ₱1,500, Provider: ₱1,500
  {
    final res = TranyxPromotionCalculator.calculate(
      listingPrice: 1500.0,
      transactionFee: 150.0,
      promoCode: 'SERVICETX0',
      applyToFee: TranyxFeeType.transactionFee,
      discountType: 'percentage',
      discountValue: 100.0,
    );

    assertEqual(res.listingPrice, 1500.0, 'Test 3 - Service Price ₱1,500');
    assertEqual(res.finalTransactionFee, 0.0, 'Test 3 - Zero Transaction Fee');
    assertEqual(res.customerTotal, 1500.0, 'Test 3 - Customer Pays ₱1,500');
    assertEqual(res.providerSettlement, 1500.0, 'Test 3 - Provider Receives ₱1,500');
  }

  // Test 4: Fixed Amount Promotion (₱50 OFF Platform Fee)
  // Listing: ₱2,000, Platform Fee: ₱200 -> Discount: ₱50, Final Fee: ₱150, Customer: ₱2,150, Provider: ₱2,000
  {
    final res = TranyxPromotionCalculator.calculate(
      listingPrice: 2000.0,
      platformFee: 200.0,
      promoCode: 'FEE50OFF',
      applyToFee: TranyxFeeType.platformFee,
      discountType: 'flat',
      discountValue: 50.0,
    );

    assertEqual(res.listingPrice, 2000.0, 'Test 4 - Listing Price ₱2,000');
    assertEqual(res.promotionDiscount, 50.0, 'Test 4 - Flat Discount ₱50');
    assertEqual(res.finalPlatformFee, 150.0, 'Test 4 - Net Platform Fee ₱150');
    assertEqual(res.customerTotal, 2150.0, 'Test 4 - Customer Total ₱2,150');
    assertEqual(res.providerSettlement, 2000.0, 'Test 4 - Provider Untouched ₱2,000');
  }

  // Test 5: Maximum Discount Cap Enforcement
  // 50% discount on ₱500 fee would be ₱250, but capped at ₱100 max discount
  {
    final res = TranyxPromotionCalculator.calculate(
      listingPrice: 5000.0,
      platformFee: 500.0,
      promoCode: 'LAUNCH50',
      applyToFee: TranyxFeeType.platformFee,
      discountType: 'percentage',
      discountValue: 50.0,
      maxDiscountCap: 100.0,
    );

    assertEqual(res.promotionDiscount, 100.0, 'Test 5 - Discount Capped at ₱100');
    assertEqual(res.finalPlatformFee, 400.0, 'Test 5 - Net Platform Fee ₱400');
    assertEqual(res.customerTotal, 5400.0, 'Test 5 - Customer Pays ₱5,400');
    assertEqual(res.providerSettlement, 5000.0, 'Test 5 - Provider Receives ₱5,000');
  }

  // Test 6: Strict Prohibited Target Validation
  // Attempting to apply discount to listing/rental/provider price must be rejected
  {
    final res = TranyxPromotionCalculator.calculate(
      listingPrice: 2000.0,
      platformFee: 200.0,
      promoCode: 'MALICIOUS',
      applyToFee: 'listing_price',
      discountType: 'percentage',
      discountValue: 50.0,
    );

    assertEqual(res.isValid, false, 'Test 6 - Disallowed Target Rejected');
    assertEqual(res.promotionDiscount, 0.0, 'Test 6 - Zero Discount Applied');
    assertEqual(res.providerSettlement, 2000.0, 'Test 6 - Provider Price Preserved');
  }

  // Test 7: Max Quota Limit (1,000 users reached)
  {
    final res = TranyxPromotionCalculator.calculate(
      listingPrice: 2000.0,
      platformFee: 200.0,
      promoCode: 'ZEROFEES1000',
      applyToFee: TranyxFeeType.platformFee,
      discountType: 'percentage',
      discountValue: 100.0,
      maxUsers: 1000,
      usedCount: 1000,
    );

    assertEqual(res.isValid, false, 'Test 7 - Quota Reached Rejected');
    assertEqual(res.promotionDiscount, 0.0, 'Test 7 - Zero Discount when Exceeded');
  }

  // Test 8: Fee Configurations & Category Markups Calculation
  {
    const feeConfig = FeeConfiguration(
      vehiclePlatformFeeRate: 10.0,
      vehicleMarkupRate: 2.0,
      weekendSurchargeRate: 3.0,
      securityHandlingFeeFixed: 50.0,
    );

    // Listing: ₱1,000, Category: vehicles, Weekend: true, Deposit: true
    // Platform Fee = 10% of 1,000 = ₱100
    // Markups = 2% (markup) + 3% (weekend) + ₱50 = 20 + 30 + 50 = ₱100
    // Zero Fees Promo applied to Platform Fee
    final res = TranyxPromotionCalculator.calculateFromConfig(
      listingPrice: 1000.0,
      feeConfig: feeConfig,
      category: 'vehicles',
      isWeekend: true,
      hasSecurityDeposit: true,
      promoCode: 'ZEROFEES1000',
      applyToFee: TranyxFeeType.platformFee,
      discountType: 'percentage',
      discountValue: 100.0,
    );

    assertEqual(res.listingPrice, 1000.0, 'Test 8 - Listing Price ₱1,000');
    assertEqual(res.originalPlatformFee, 100.0, 'Test 8 - Original Platform Fee ₱100');
    assertEqual(res.originalMarkupFee, 100.0, 'Test 8 - Markups & Surcharges ₱100');
    assertEqual(res.finalPlatformFee, 0.0, 'Test 8 - Zero Platform Fee after 100% waiver');
    assertEqual(res.providerSettlement, 1000.0, 'Test 8 - Provider Settlement Untouched ₱1,000');
  }

  // Test 9: Subscribed & Hybrid Tier Fee Discounts
  {
    const feeConfig = FeeConfiguration(
      defaultPlatformFeeRate: 10.0,
      hybridFeeDiscountPct: 30.0, // 30% discount on 10% platform fee -> 7%
    );

    final res = TranyxPromotionCalculator.calculateFromConfig(
      listingPrice: 10000.0,
      feeConfig: feeConfig,
      isHybridUser: true,
    );

    assertEqual(res.originalPlatformFee, 700.0, 'Test 9 - Hybrid 30% fee rate reduction (₱700)');
    assertEqual(res.providerSettlement, 10000.0, 'Test 9 - Provider receives 100%');
  }

  print('\nSUMMARY: $passed Passed, $failed Failed.');
  if (failed > 0) {
    throw Exception('$failed tests failed!');
  }
}
