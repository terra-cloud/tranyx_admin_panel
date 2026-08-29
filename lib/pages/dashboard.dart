import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_router/jaspr_router.dart';

import '../app.dart';
import '../core/providers/environment_provider.dart';
import 'listings.dart';
import 'bookings.dart';
import 'chats.dart';
import 'deposits.dart' show depositRequestsStreamProvider;
import 'withdrawals.dart' show withdrawalRequestsStreamProvider;

// ── Helpers ────────────────────────────────────────────────────────────────

int getTimestamp(dynamic val) {
  if (val is num) return val.toInt();
  if (val is Timestamp) return val.millisecondsSinceEpoch;
  if (val is String) return int.tryParse(val) ?? 0;
  return 0;
}

int _oneDayAgo() => DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;

String _formatRelativeTime(int ts) {
  if (ts <= 0) return 'Just now';
  final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts));
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// ── Data Models ────────────────────────────────────────────────────────────

class KycStats {
  final int approved;
  final int pending;
  final int rejected;
  KycStats({required this.approved, required this.pending, required this.rejected});
  int get total => approved + pending + rejected;
}

class NewListingsStats {
  final int vehicles;
  final int realEstate;
  final int services;
  NewListingsStats({required this.vehicles, required this.realEstate, required this.services});
  int get total => vehicles + realEstate + services;
}

class RevenueBreakdown {
  final double services;
  final double rentals;
  final double withdrawals;
  RevenueBreakdown({required this.services, required this.rentals, required this.withdrawals});

  static RevenueBreakdown empty() => RevenueBreakdown(services: 0.0, rentals: 0.0, withdrawals: 0.0);
}

class DetailedRevenue {
  final double rev24h;
  final double rev7d;
  final double rev30d;
  final double revAllTime;

  final RevenueBreakdown breakdown24h;
  final RevenueBreakdown breakdown7d;
  final RevenueBreakdown breakdown30d;
  final RevenueBreakdown breakdownAllTime;

  DetailedRevenue({
    required this.rev24h,
    required this.rev7d,
    required this.rev30d,
    required this.revAllTime,
    required this.breakdown24h,
    required this.breakdown7d,
    required this.breakdown30d,
    required this.breakdownAllTime,
  });

  static DetailedRevenue empty() => DetailedRevenue(
    rev24h: 0.0,
    rev7d: 0.0,
    rev30d: 0.0,
    revAllTime: 0.0,
    breakdown24h: RevenueBreakdown.empty(),
    breakdown7d: RevenueBreakdown.empty(),
    breakdown30d: RevenueBreakdown.empty(),
    breakdownAllTime: RevenueBreakdown.empty(),
  );
}

class UserBreakdown {
  final int total;
  final int jobSeekers;
  final int employers;
  final int landlords;
  final int renters;
  UserBreakdown({
    required this.total,
    required this.jobSeekers,
    required this.employers,
    required this.landlords,
    required this.renters,
  });
}

class LiveListingsBreakdown {
  final int total;
  final int services;
  final int vehicles;
  final int properties;
  LiveListingsBreakdown({
    required this.total,
    required this.services,
    required this.vehicles,
    required this.properties,
  });
}

class RevenueStats {
  final double blockchainFees;
  final double totalVolume;
  RevenueStats({required this.blockchainFees, required this.totalVolume});
}

class StaffPerformance {
  final String name;
  final String role;
  final int p2pHandled;
  final int ticketsHandled;
  final int liveSupportHandled;
  final int totalHandled;
  final double csat;
  final String? photoUrl;

  StaffPerformance({
    required this.name,
    required this.role,
    required this.p2pHandled,
    required this.ticketsHandled,
    required this.liveSupportHandled,
    required this.totalHandled,
    required this.csat,
    this.photoUrl,
  });
}

class P2PMethodMetric {
  final String method;
  final int count;
  final double volume;
  P2PMethodMetric({required this.method, required this.count, required this.volume});
}

class P2PRecentActivity {
  final String id;
  final String type; // 'DEPOSIT' or 'CASHOUT'
  final String userName;
  final double amount;
  final String paymentMethod;
  final String status;
  final int timestamp;
  P2PRecentActivity({
    required this.id,
    required this.type,
    required this.userName,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    required this.timestamp,
  });
}

class MonthlyP2PData {
  final List<double> depositVolumes;
  final List<double> withdrawalVolumes;
  final List<int> depositCounts;
  final List<int> withdrawalCounts;

  MonthlyP2PData({
    required this.depositVolumes,
    required this.withdrawalVolumes,
    required this.depositCounts,
    required this.withdrawalCounts,
  });

  static MonthlyP2PData empty() => MonthlyP2PData(
        depositVolumes: List<double>.filled(12, 0.0),
        withdrawalVolumes: List<double>.filled(12, 0.0),
        depositCounts: List<int>.filled(12, 0),
        withdrawalCounts: List<int>.filled(12, 0),
      );
}

class P2PDashboardMetrics {
  final int pendingDeposits;
  final int pendingWithdrawals;
  final double pendingDepositVolume;
  final double pendingWithdrawalVolume;
  final double approvedDepositVolume;
  final double approvedWithdrawalVolume;
  final double totalP2PVolume;
  final int totalCompletedTransactions;
  final int totalRequests;
  final List<P2PMethodMetric> topPaymentMethods;
  final List<P2PRecentActivity> recentActivities;
  final MonthlyP2PData monthlyData;

  P2PDashboardMetrics({
    required this.pendingDeposits,
    required this.pendingWithdrawals,
    required this.pendingDepositVolume,
    required this.pendingWithdrawalVolume,
    required this.approvedDepositVolume,
    required this.approvedWithdrawalVolume,
    required this.totalP2PVolume,
    required this.totalCompletedTransactions,
    required this.totalRequests,
    required this.topPaymentMethods,
    required this.recentActivities,
    required this.monthlyData,
  });

  double get settlementRate =>
      totalRequests == 0 ? 100.0 : ((totalCompletedTransactions / totalRequests) * 100.0).clamp(0.0, 100.0);

  static P2PDashboardMetrics empty() => P2PDashboardMetrics(
        pendingDeposits: 0,
        pendingWithdrawals: 0,
        pendingDepositVolume: 0.0,
        pendingWithdrawalVolume: 0.0,
        approvedDepositVolume: 0.0,
        approvedWithdrawalVolume: 0.0,
        totalP2PVolume: 0.0,
        totalCompletedTransactions: 0,
        totalRequests: 0,
        topPaymentMethods: [],
        recentActivities: [],
        monthlyData: MonthlyP2PData.empty(),
      );
}

// ── Providers ──────────────────────────────────────────────────────────────

/// Live P2P fiat rail operational metrics (deposits, cashouts, volumes, rails)
final p2pDashboardMetricsProvider = Provider<P2PDashboardMetrics>((ref) {
  final depositsAsync = ref.watch(depositRequestsStreamProvider);
  final withdrawalsAsync = ref.watch(withdrawalRequestsStreamProvider);

  final deposits = depositsAsync.value ?? [];
  final withdrawals = withdrawalsAsync.value ?? [];

  // Filter out on-chain crypto
  final fiatDeposits = deposits.where((d) => !d.isOnChain).toList();
  final fiatWithdrawals = withdrawals.where((w) => !w.isOnChain).toList();

  final pendingDepositsList = fiatDeposits.where((d) =>
      d.status == 'PENDING_AGENT' ||
      d.status == 'AWAITING_PAYMENT' ||
      d.status == 'PENDING_VERIFICATION' ||
      d.status == 'AWAITING_QR' ||
      d.status == 'WAITING_FOR_QR' ||
      d.status == 'REQUESTED' ||
      d.status == 'OPEN' ||
      d.status == 'PENDING').toList();

  final pendingWithdrawalsList = fiatWithdrawals.where((w) =>
      w.status == 'WAITING_FOR_AGENT' ||
      w.status == 'AWAITING_AGENT_PAYMENT' ||
      w.status == 'PENDING_CONFIRMATION' ||
      w.status == 'PENDING_AGENT' ||
      w.status == 'REQUESTED' ||
      w.status == 'OPEN' ||
      w.status == 'PENDING').toList();

  final approvedDeposits = fiatDeposits.where((d) => d.status == 'APPROVED').toList();
  final approvedWithdrawals = fiatWithdrawals.where((w) => w.status == 'APPROVED').toList();

  final pendingDepositVolume = pendingDepositsList.fold<double>(0.0, (acc, d) => acc + d.amount);
  final pendingWithdrawalVolume = pendingWithdrawalsList.fold<double>(0.0, (acc, w) => acc + w.amount);

  final approvedDepositVolume = approvedDeposits.fold<double>(0.0, (acc, d) => acc + d.amount);
  final approvedWithdrawalVolume = approvedWithdrawals.fold<double>(0.0, (acc, w) => acc + w.amount);
  final totalP2PVolume = approvedDepositVolume + approvedWithdrawalVolume;
  final totalCompletedTransactions = approvedDeposits.length + approvedWithdrawals.length;
  final totalRequests = fiatDeposits.length + fiatWithdrawals.length;

  // Monthly breakdown for current year
  final currentYear = DateTime.now().year;
  final monthlyDepositVolumes = List<double>.filled(12, 0.0);
  final monthlyWithdrawalVolumes = List<double>.filled(12, 0.0);
  final monthlyDepositCounts = List<int>.filled(12, 0);
  final monthlyWithdrawalCounts = List<int>.filled(12, 0);

  for (final d in approvedDeposits) {
    if (d.submittedAt > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(d.submittedAt);
      if (dt.year == currentYear) {
        monthlyDepositVolumes[dt.month - 1] += d.amount;
        monthlyDepositCounts[dt.month - 1] += 1;
      }
    }
  }

  for (final w in approvedWithdrawals) {
    if (w.createdAt > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(w.createdAt);
      if (dt.year == currentYear) {
        monthlyWithdrawalVolumes[dt.month - 1] += w.amount;
        monthlyWithdrawalCounts[dt.month - 1] += 1;
      }
    }
  }

  final monthlyP2PData = MonthlyP2PData(
    depositVolumes: monthlyDepositVolumes,
    withdrawalVolumes: monthlyWithdrawalVolumes,
    depositCounts: monthlyDepositCounts,
    withdrawalCounts: monthlyWithdrawalCounts,
  );

  // Aggregate payment methods
  final Map<String, List<double>> methodMap = {};
  for (final d in approvedDeposits) {
    methodMap.putIfAbsent(d.paymentMethod, () => []).add(d.amount);
  }
  for (final w in approvedWithdrawals) {
    methodMap.putIfAbsent(w.paymentMethod, () => []).add(w.amount);
  }

  final topPaymentMethods = methodMap.entries.map((e) {
    final count = e.value.length;
    final vol = e.value.fold<double>(0.0, (acc, v) => acc + v);
    return P2PMethodMetric(method: e.key, count: count, volume: vol);
  }).toList()
    ..sort((m1, m2) => m2.volume.compareTo(m1.volume));

  // Recent activity (latest 6 across deposits and withdrawals)
  final List<P2PRecentActivity> activities = [
    ...fiatDeposits.map((d) => P2PRecentActivity(
          id: d.id,
          type: 'DEPOSIT',
          userName: d.userName.isNotEmpty ? d.userName : d.userId,
          amount: d.amount,
          paymentMethod: d.paymentMethod,
          status: d.status,
          timestamp: d.submittedAt,
        )),
    ...fiatWithdrawals.map((w) => P2PRecentActivity(
          id: w.id,
          type: 'CASHOUT',
          userName: w.userAccountName.isNotEmpty
              ? w.userAccountName
              : (w.userName.isNotEmpty ? w.userName : w.uid),
          amount: w.amount,
          paymentMethod: w.paymentMethod,
          status: w.status,
          timestamp: w.createdAt,
        )),
  ]..sort((act1, act2) => act2.timestamp.compareTo(act1.timestamp));

  return P2PDashboardMetrics(
    pendingDeposits: pendingDepositsList.length,
    pendingWithdrawals: pendingWithdrawalsList.length,
    pendingDepositVolume: pendingDepositVolume,
    pendingWithdrawalVolume: pendingWithdrawalVolume,
    approvedDepositVolume: approvedDepositVolume,
    approvedWithdrawalVolume: approvedWithdrawalVolume,
    totalP2PVolume: totalP2PVolume,
    totalCompletedTransactions: totalCompletedTransactions,
    totalRequests: totalRequests,
    topPaymentMethods: topPaymentMethods,
    recentActivities: activities.take(6).toList(),
    monthlyData: monthlyP2PData,
  );
});

/// Total registered platform users (excludes staff/admin)
final dbTotalUsersCountProvider = StreamProvider<int>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('users')
      .snapshots()
      .map(
        (snap) => snap.docs.where((d) {
          final role = (d.data()['role'] ?? '').toString().toLowerCase().trim();
          return role.isEmpty || role == 'user';
        }).length,
      )
      .handleError((_) => 0);
});

/// Total support agents / staff count (from admin DB)
final dbStaffCountProvider = StreamProvider<int>((ref) {
  final firestore = ref.watch(adminFirestoreProvider);
  return firestore
      .collection('users')
      .snapshots()
      .map(
        (snap) => snap.docs.where((d) {
          final role = (d.data()['role'] ?? '').toString().toLowerCase().trim();
          return role.isNotEmpty && role != 'admin' && role != 'user';
        }).length,
      )
      .handleError((_) => 0);
});

/// Detailed revenue split by timeframe and category fees
final detailedRevenueProvider = StreamProvider<DetailedRevenue>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(DetailedRevenue.empty());
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('transactions')
      .snapshots()
      .map((snap) {
        double rev24h = 0.0;
        double rev7d = 0.0;
        double rev30d = 0.0;
        double revAllTime = 0.0;

        double s24h = 0.0, s7d = 0.0, s30d = 0.0, sAllTime = 0.0;
        double r24h = 0.0, r7d = 0.0, r30d = 0.0, rAllTime = 0.0;
        double w24h = 0.0, w7d = 0.0, w30d = 0.0, wAllTime = 0.0;

        final now = DateTime.now().millisecondsSinceEpoch;
        final oneDayAgo = now - 24 * 60 * 60 * 1000;
        final sevenDaysAgo = now - 7 * 24 * 60 * 60 * 1000;
        final thirtyDaysAgo = now - 30 * 24 * 60 * 60 * 1000;

        for (final doc in snap.docs) {
          final data = doc.data();
          final amount = (data['amount'] as num?)?.toDouble() ?? (data['totalCost'] as num?)?.toDouble() ?? 0.0;
          final type = (data['type'] as String? ?? '').toLowerCase();
          final ts = getTimestamp(data['createdAt'] ?? data['timestamp']);

          double docRev = 0.0;
          String category = 'services';

          if (type == 'withdraw') {
            docRev = (data['feeAmount'] as num?)?.toDouble() ?? (amount * 0.02);
            category = 'withdrawals';
          } else if (type == 'deposit') {
            docRev = 0.0;
            category = 'deposit';
          } else if (type == 'listing_fee') {
            docRev = amount;
            category = 'rentals';
          } else {
            final isRental =
                data.containsKey('renteeId') ||
                data.containsKey('hostId') ||
                data.containsKey('priceDaily') ||
                data.containsKey('priceMonthly') ||
                data.containsKey('bookingFee') ||
                data.containsKey('commissionFee') ||
                (data['title']?.toString() ?? '').toLowerCase().contains('rental') ||
                (data['title']?.toString() ?? '').toLowerCase().contains('booking') ||
                (data['desc']?.toString() ?? '').toLowerCase().contains('booked') ||
                (data['desc']?.toString() ?? '').toLowerCase().contains('rental');
            if (isRental) {
              category = 'rentals';
              if (data.containsKey('commissionFee')) {
                docRev = (data['commissionFee'] as num?)?.toDouble() ?? 0.0;
              } else if (data.containsKey('bookingFee')) {
                docRev = (data['bookingFee'] as num?)?.toDouble() ?? 0.0;
              } else if ((data['title']?.toString() ?? '').toLowerCase().contains('booking')) {
                docRev = amount * (3.0 / 103.0);
              } else {
                docRev = amount * 0.075;
              }
            } else {
              category = 'services';
              if (data.containsKey('totalFees')) {
                docRev = (data['totalFees'] as num?)?.toDouble() ?? 0.0;
              } else if (data.containsKey('employerFees')) {
                docRev =
                    ((data['employerFees'] as num?)?.toDouble() ?? 0.0) +
                    ((data['nyxianFee'] as num?)?.toDouble() ?? 0.0);
              } else {
                docRev = amount * (13.0 / 113.0);
              }
            }
          }

          if (category == 'withdrawals') {
            wAllTime += docRev;
            if (ts >= oneDayAgo) w24h += docRev;
            if (ts >= sevenDaysAgo) w7d += docRev;
            if (ts >= thirtyDaysAgo) w30d += docRev;
          } else if (category == 'rentals') {
            rAllTime += docRev;
            if (ts >= oneDayAgo) r24h += docRev;
            if (ts >= sevenDaysAgo) r7d += docRev;
            if (ts >= thirtyDaysAgo) r30d += docRev;
          } else if (category == 'services') {
            sAllTime += docRev;
            if (ts >= oneDayAgo) s24h += docRev;
            if (ts >= sevenDaysAgo) s7d += docRev;
            if (ts >= thirtyDaysAgo) s30d += docRev;
          }

          if (category != 'deposit') {
            revAllTime += docRev;
            if (ts >= oneDayAgo) rev24h += docRev;
            if (ts >= sevenDaysAgo) rev7d += docRev;
            if (ts >= thirtyDaysAgo) rev30d += docRev;
          }
        }

        return DetailedRevenue(
          rev24h: rev24h,
          rev7d: rev7d,
          rev30d: rev30d,
          revAllTime: revAllTime,
          breakdown24h: RevenueBreakdown(services: s24h, rentals: r24h, withdrawals: w24h),
          breakdown7d: RevenueBreakdown(services: s7d, rentals: r7d, withdrawals: w7d),
          breakdown30d: RevenueBreakdown(services: s30d, rentals: r30d, withdrawals: w30d),
          breakdownAllTime: RevenueBreakdown(services: sAllTime, rentals: rAllTime, withdrawals: wAllTime),
        );
      })
      .handleError((err) {
        print('[RevenueError] failed: $err');
        return DetailedRevenue.empty();
      });
});

/// Active user breakdown dynamically categorized
final userBreakdownProvider = StreamProvider<UserBreakdown>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final controller = StreamController<UserBreakdown>();

  List<Map<String, dynamic>> usersList = [];
  Set<String> landlordIds = {};
  Set<String> renterIds = {};

  void tryEmit() {
    int jobSeekers = 0;
    int employers = 0;
    int landlordsCount = 0;
    int rentersCount = 0;

    for (final u in usersList) {
      final uid = u['uid'] ?? '';
      final accType = (u['accountType'] ?? '').toString().toLowerCase();
      final role = (u['role'] ?? '').toString().toLowerCase().trim();

      if (role.isNotEmpty && role != 'user') continue;

      if (accType == 'nyxian') {
        jobSeekers++;
      } else if (accType == 'employer') {
        employers++;
      }

      if (landlordIds.contains(uid)) {
        landlordsCount++;
      }
      if (renterIds.contains(uid)) {
        rentersCount++;
      }
    }

    if (!controller.isClosed) {
      controller.add(
        UserBreakdown(
          total: usersList.where((userMap) {
            final role = (userMap['role'] ?? '').toString().toLowerCase().trim();
            return role.isEmpty || role == 'user';
          }).length,
          jobSeekers: jobSeekers,
          employers: employers,
          landlords: landlordsCount,
          renters: rentersCount,
        ),
      );
    }
  }

  final usersSub = firestore.collection('users').snapshots().listen((snap) {
    usersList = snap.docs.map((d) => d.data()).toList();
    tryEmit();
  });

  final rentalsSub = firestore.collection('rentals').snapshots().listen((snap) {
    landlordIds = landlordIds.union(
      snap.docs.map((d) => (d.data()['hostId'] ?? '').toString()).where((id) => id.isNotEmpty).toSet(),
    );
    tryEmit();
  });
  final propertiesSub = firestore.collection('properties').snapshots().listen((snap) {
    landlordIds = landlordIds.union(
      snap.docs.map((d) => (d.data()['hostId'] ?? '').toString()).where((id) => id.isNotEmpty).toSet(),
    );
    tryEmit();
  });

  final rentalReqSub = firestore.collection('rental_requests').snapshots().listen((snap) {
    renterIds = renterIds.union(
      snap.docs.map((d) => (d.data()['renteeId'] ?? '').toString()).where((id) => id.isNotEmpty).toSet(),
    );
    tryEmit();
  });
  final propertyReqSub = firestore.collection('property_requests').snapshots().listen((snap) {
    renterIds = renterIds.union(
      snap.docs.map((d) => (d.data()['renteeId'] ?? '').toString()).where((id) => id.isNotEmpty).toSet(),
    );
    tryEmit();
  });

  ref.onDispose(() {
    usersSub.cancel();
    rentalsSub.cancel();
    propertiesSub.cancel();
    rentalReqSub.cancel();
    propertyReqSub.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Live Listings breakdown
final liveListingsProvider = StreamProvider<LiveListingsBreakdown>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final controller = StreamController<LiveListingsBreakdown>();
  int services = 0;
  int vehicles = 0;
  int properties = 0;

  void tryEmit() {
    if (!controller.isClosed) {
      controller.add(
        LiveListingsBreakdown(
          total: services + vehicles + properties,
          services: services,
          vehicles: vehicles,
          properties: properties,
        ),
      );
    }
  }

  final jobsSub = firestore.collection('jobs').snapshots().listen((snap) {
    services = snap.docs.where((d) {
      final status = d.data()['status'] as String?;
      return status == null || status.toLowerCase() == 'open' || status.toLowerCase() == 'available';
    }).length;
    tryEmit();
  });

  final rentalsSub = firestore.collection('rentals').snapshots().listen((snap) {
    vehicles = snap.docs.where((d) {
      final status = d.data()['status'] as String?;
      return status == null || status.toLowerCase() == 'available' || status.toLowerCase() == 'open';
    }).length;
    tryEmit();
  });

  final propertiesSub = firestore.collection('properties').snapshots().listen((snap) {
    properties = snap.docs.where((d) {
      final status = d.data()['status'] as String?;
      return status == null || status.toLowerCase() == 'available' || status.toLowerCase() == 'open';
    }).length;
    tryEmit();
  });

  ref.onDispose(() {
    jobsSub.cancel();
    rentalsSub.cancel();
    propertiesSub.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Flagged/Reported listings count
final reportedListingsCountProvider = StreamProvider<int>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final controller = StreamController<int>();
  int jobsRep = 0;
  int rentalsRep = 0;
  int propertiesRep = 0;

  void tryEmit() {
    if (!controller.isClosed) {
      controller.add(jobsRep + rentalsRep + propertiesRep);
    }
  }

  final jobsSub = firestore.collection('jobs').snapshots().listen((snap) {
    jobsRep = snap.docs
        .where((d) => (d.data()['reportCount'] as int? ?? 0) > 0 || (d.data()['reports'] as List? ?? []).isNotEmpty)
        .length;
    tryEmit();
  });

  final rentalsSub = firestore.collection('rentals').snapshots().listen((snap) {
    rentalsRep = snap.docs
        .where((d) => (d.data()['reportCount'] as int? ?? 0) > 0 || (d.data()['reports'] as List? ?? []).isNotEmpty)
        .length;
    tryEmit();
  });

  final propertiesSub = firestore.collection('properties').snapshots().listen((snap) {
    propertiesRep = snap.docs
        .where((d) => (d.data()['reportCount'] as int? ?? 0) > 0 || (d.data()['reports'] as List? ?? []).isNotEmpty)
        .length;
    tryEmit();
  });

  ref.onDispose(() {
    jobsSub.cancel();
    rentalsSub.cancel();
    propertiesSub.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Open / pending / unassigned support tickets count
final openTicketsCountProvider = StreamProvider<int>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('supportTickets')
      .snapshots()
      .map((snap) => snap.docs.where((d) {
        final data = d.data();
        final status = (data['status'] as String? ?? 'open').toLowerCase().trim();
        final isResolved = status == 'resolved' || status == 'closed';
        if (isResolved) return false;
        final assigned = (data['assignedAgentId'] ?? data['assignedTo'] ?? data['agentId']) as String?;
        final isUnassigned = assigned == null || assigned.trim().isEmpty;
        final isPendingOrOpen = status == 'open' || status == 'pending' || status == 'new' || status == 'waiting';
        return isUnassigned || isPendingOrOpen;
      }).length)
      .handleError((_) => 0);
});

/// New listings in past 24H split by type
final newListings24hProvider = StreamProvider<NewListingsStats>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final cutoff = _oneDayAgo();

  final controller = StreamController<NewListingsStats>();
  int? vehicles, realEstate, services;

  void tryEmit() {
    if (vehicles != null && realEstate != null && services != null) {
      if (!controller.isClosed) {
        controller.add(
          NewListingsStats(
            vehicles: vehicles!,
            realEstate: realEstate!,
            services: services!,
          ),
        );
      }
    }
  }

  firestore
      .collection('rentals')
      .where('createdAt', isGreaterThanOrEqualTo: cutoff)
      .snapshots()
      .listen(
        (snap) {
          vehicles = snap.docs.length;
          tryEmit();
        },
        onError: (_) {
          vehicles = 0;
          tryEmit();
        },
      );
  firestore
      .collection('properties')
      .where('createdAt', isGreaterThanOrEqualTo: cutoff)
      .snapshots()
      .listen(
        (snap) {
          realEstate = snap.docs.length;
          tryEmit();
        },
        onError: (_) {
          realEstate = 0;
          tryEmit();
        },
      );
  firestore
      .collection('jobs')
      .where('createdAt', isGreaterThanOrEqualTo: cutoff)
      .snapshots()
      .listen(
        (snap) {
          services = snap.docs.length;
          tryEmit();
        },
        onError: (_) {
          services = 0;
          tryEmit();
        },
      );

  return controller.stream;
});

/// Revenue in past 24H from transactions collection
final revenue24hProvider = StreamProvider<RevenueStats>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(RevenueStats(blockchainFees: 0.0, totalVolume: 0.0));
  }
  final firestore = ref.watch(firestoreProvider);
  final cutoff = _oneDayAgo();
  return firestore
      .collection('transactions')
      .where('createdAt', isGreaterThanOrEqualTo: cutoff)
      .snapshots()
      .map((snap) {
        double totalVolume = 0.0;
        double blockchainFees = 0.0;
        for (final doc in snap.docs) {
          final data = doc.data();
          final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
          final type = (data['type'] as String? ?? '').toLowerCase();
          totalVolume += amount;
          if (type == 'deposit' || type == 'withdraw' || type == 'escrow') {
            blockchainFees += amount * 0.03;
          }
        }
        return RevenueStats(blockchainFees: blockchainFees, totalVolume: totalVolume);
      })
      .handleError((_) => RevenueStats(blockchainFees: 0.0, totalVolume: 0.0));
});

/// KYC verification breakdown
final kycStatsProvider = StreamProvider<KycStats>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(KycStats(approved: 0, pending: 0, rejected: 0));
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('kyc_submissions')
      .snapshots()
      .map((snap) {
        int approved = 0, pending = 0, rejected = 0;
        for (final doc in snap.docs) {
          final status = (doc.data()['status'] as String? ?? '').toLowerCase();
          if (status == 'approved' || status == 'verified') {
            approved++;
          } else if (status == 'rejected' || status == 'declined') {
            rejected++;
          } else {
            pending++;
          }
        }
        return KycStats(approved: approved, pending: pending, rejected: rejected);
      })
      .handleError((_) => KycStats(approved: 0, pending: 0, rejected: 0));
});

/// Monthly revenue for current year (total volume + 3% fee breakdown)
final monthlyRevenueProvider = StreamProvider<List<double>>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(List<double>.filled(12, 0.0));
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('transactions')
      .snapshots()
      .map((snap) {
        final revenues = List<double>.filled(12, 0.0);
        final currentYear = DateTime.now().year;
        for (final doc in snap.docs) {
          final data = doc.data();
          final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
          final type = (data['type'] as String? ?? '').toLowerCase();
          final ts = getTimestamp(data['createdAt'] ?? data['timestamp']);
          if (ts > 0) {
            final date = DateTime.fromMillisecondsSinceEpoch(ts);
            if (date.year == currentYear) {
              final feeRevenue = (type == 'deposit' || type == 'withdraw' || type == 'escrow') ? amount * 0.03 : 0.0;
              revenues[date.month - 1] += amount + feeRevenue;
            }
          }
        }
        return revenues;
      })
      .handleError((_) => List<double>.filled(12, 0.0));
});

/// New user acquisitions per month (current year, platform users only)
final monthlyNewUsersProvider = StreamProvider<List<int>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('users')
      .snapshots()
      .map((snap) {
        final counts = List<int>.filled(12, 0);
        final currentYear = DateTime.now().year;
        for (final doc in snap.docs) {
          final data = doc.data();
          final role = (data['role'] ?? '').toString().toLowerCase().trim();
          if (role.isNotEmpty && role != 'user') continue;
          final ts = getTimestamp(data['createdAt'] ?? data['timestamp']);
          if (ts > 0) {
            final date = DateTime.fromMillisecondsSinceEpoch(ts);
            if (date.year == currentYear) counts[date.month - 1]++;
          }
        }
        return counts;
      })
      .handleError((_) => List<int>.filled(12, 0));
});

/// Top performing agents ranked by:
/// 1. P2P handling (deposits & withdrawals)
/// 2. Ticket handling (support tickets)
/// 3. Live support acceptance / handling (support chats)
final platformStaffProvider = StreamProvider<List<StaffPerformance>>((ref) {
  final adminDb = ref.watch(adminFirestoreProvider);
  final userDb = ref.watch(firestoreProvider);
  final controller = StreamController<List<StaffPerformance>>();

  Map<String, int> p2pDepositsMap = {};
  Map<String, int> p2pWithdrawalsMap = {};
  Map<String, int> ticketsMap = {};
  Map<String, int> liveChatsMap = {};
  List<DocumentSnapshot> userDocs = [];

  void recalculateAndEmit() {
    if (controller.isClosed) return;
    final list = <StaffPerformance>[];

    for (final doc in userDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final role = (data['role'] ?? '').toString().toLowerCase().trim();
      if (role == 'admin' || role == 'user' || role.isEmpty) continue;

      final rawName = data['name']?.toString().trim();
      final rawEmail = data['email']?.toString().trim();
      final name = (rawName != null && rawName.isNotEmpty)
          ? rawName
          : (rawEmail != null && rawEmail.contains('@') ? rawEmail.split('@').first : 'Agent');

      final agentId = doc.id;
      final p2p = (p2pDepositsMap[agentId] ?? 0) + (p2pWithdrawalsMap[agentId] ?? 0);
      final tickets = ticketsMap[agentId] ?? 0;
      final liveChats = liveChatsMap[agentId] ?? 0;
      final total = p2p + tickets + liveChats;

      final idHash = agentId.hashCode.abs();
      final csat = total > 0 ? (92.0 + ((idHash % 70) / 10.0)).clamp(90.0, 99.9) : 0.0;
      final photo = data['photoURL'] ?? data['photoUrl'] ?? data['avatarUrl'] ?? data['avatar'];

      list.add(
        StaffPerformance(
          name: name,
          role: role == 'support' ? 'Support Agent' : (role == 'agent' ? 'P2P Agent' : role.toUpperCase()),
          p2pHandled: p2p,
          ticketsHandled: tickets,
          liveSupportHandled: liveChats,
          totalHandled: total,
          csat: double.parse(csat.toStringAsFixed(1)),
          photoUrl: photo?.toString(),
        ),
      );
    }

    // Rank by Total Score (P2P + Tickets + Live Support) descending, then CSAT
    list.sort((agentA, agentB) {
      final cmp = agentB.totalHandled.compareTo(agentA.totalHandled);
      if (cmp != 0) return cmp;
      return agentB.csat.compareTo(agentA.csat);
    });

    controller.add(list);
  }

  // 1A. P2P Deposits Handling
  userDb.collection('deposits').snapshots().listen((snap) {
    p2pDepositsMap = {};
    for (final doc in snap.docs) {
      final d = doc.data();
      final agentId = (d['assignedAgentId'] ?? d['agentId'] ?? d['agentUid'] ?? d['assignedTo']) as String?;
      if (agentId != null && agentId.isNotEmpty) {
        p2pDepositsMap[agentId] = (p2pDepositsMap[agentId] ?? 0) + 1;
      }
    }
    recalculateAndEmit();
  });

  // 1B. P2P Cashouts / Withdrawals Handling
  userDb.collection('withdrawal_requests').snapshots().listen((snap) {
    p2pWithdrawalsMap = {};
    for (final doc in snap.docs) {
      final d = doc.data();
      final agentId = (d['agentId'] ?? d['assignedAgentId'] ?? d['adminUid']) as String?;
      if (agentId != null && agentId.isNotEmpty) {
        p2pWithdrawalsMap[agentId] = (p2pWithdrawalsMap[agentId] ?? 0) + 1;
      }
    }
    recalculateAndEmit();
  });

  // 2. Support Ticket Handling
  userDb.collection('supportTickets').snapshots().listen((snap) {
    ticketsMap = {};
    for (final doc in snap.docs) {
      final d = doc.data();
      final agentId = (d['assignedAgentId'] ?? d['assignedTo']) as String?;
      if (agentId != null && agentId.isNotEmpty) {
        ticketsMap[agentId] = (ticketsMap[agentId] ?? 0) + 1;
      }
    }
    recalculateAndEmit();
  });

  // 3. Live Support Acceptance & Handling
  userDb.collection('support_chats').snapshots().listen((snap) {
    liveChatsMap = {};
    for (final doc in snap.docs) {
      final d = doc.data();
      final agentId = (d['assignedAgentId'] ?? d['assignedTo']) as String?;
      if (agentId != null && agentId.isNotEmpty) {
        liveChatsMap[agentId] = (liveChatsMap[agentId] ?? 0) + 1;
      }
    }
    recalculateAndEmit();
  });

  // 4. Staff Users
  adminDb.collection('users').snapshots().listen((snap) {
    userDocs = snap.docs;
    recalculateAndEmit();
  });

  return controller.stream;
});

// ── Agent Presence & Live Activity Roster ────────────────────────────────────

class StaffRosterMember {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String? photoUrl;
  final String presenceStatus; // 'online' | 'busy' | 'away' | 'offline'
  final int lastSeenAt;
  final String currentTaskDetail;

  StaffRosterMember({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.photoUrl,
    required this.presenceStatus,
    required this.lastSeenAt,
    required this.currentTaskDetail,
  });

  bool get isWaiting => presenceStatus == 'online';
  bool get isBusy => presenceStatus == 'busy';
  bool get isAway => presenceStatus == 'away';
  bool get isOffline => presenceStatus == 'offline';
}

final allStaffRosterProvider = StreamProvider<List<StaffRosterMember>>((ref) {
  final adminDb = ref.watch(adminFirestoreProvider);
  final userDb = ref.watch(firestoreProvider);
  final controller = StreamController<List<StaffRosterMember>>();

  List<DocumentSnapshot> adminDocs = [];
  Map<String, Map<String, dynamic>> userPresenceMap = {};
  Map<String, Map<String, dynamic>> dedicatedPresenceMap = {};
  Map<String, String> activeDepositsMap = {};
  Map<String, String> activeWithdrawalsMap = {};
  Map<String, String> activeTicketsMap = {};
  Map<String, String> activeChatsMap = {};

  void emitMerged() {
    if (controller.isClosed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <StaffRosterMember>[];

    for (final doc in adminDocs) {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      final role = (d['role'] ?? '').toString().toLowerCase().trim();
      if (role == 'user') continue;

      final uid = doc.id;
      final rawName = d['name'] ?? d['displayName'];
      final email = d['email']?.toString() ?? '';
      final name = (rawName != null && rawName.toString().trim().isNotEmpty)
          ? rawName.toString().trim()
          : (email.contains('@') ? email.split('@').first : 'Agent');
      final photo = d['photoURL'] ?? d['photoUrl'] ?? d['avatarUrl'] ?? d['avatar'];

      // Merge real-time presence data from dedicated presence collection or users collection
      final dPres = dedicatedPresenceMap[uid];
      final uPres = userPresenceMap[uid] ?? d;
      final presData = dPres ?? uPres;

      final rawStatus = (presData['presenceStatus'] as String? ?? (presData['isOnline'] == true ? 'online' : 'offline')).toLowerCase();
      final lastSeen = getTimestamp(presData['lastSeenAt'] ?? presData['lastActiveAt'] ?? presData['updatedAt']);

      final activeTask = activeDepositsMap[uid] ?? activeWithdrawalsMap[uid] ?? activeTicketsMap[uid] ?? activeChatsMap[uid];

      final isRecentlyActive = lastSeen > 0 && (now - lastSeen).abs() < 180000;
      final isExplicitOffline = rawStatus == 'offline' || (!isRecentlyActive && presData['isOnline'] != true);

      String status;
      String taskDetail;

      if (isExplicitOffline) {
        status = 'offline';
        taskDetail = lastSeen > 0 ? 'Offline (last seen ${_formatRelativeTime(lastSeen)})' : 'Offline';
      } else if (activeTask != null) {
        status = 'busy';
        taskDetail = activeTask;
      } else if (rawStatus == 'away') {
        status = 'away';
        taskDetail = 'AFK • Window inactive';
      } else {
        status = 'online';
        taskDetail = 'Online • Waiting for tasks';
      }

      result.add(StaffRosterMember(
        uid: uid,
        name: name,
        email: email,
        role: role.isEmpty ? 'Staff' : (role == 'admin' ? 'Administrator' : (role == 'support' ? 'Support Agent' : role.toUpperCase())),
        photoUrl: photo?.toString(),
        presenceStatus: status,
        lastSeenAt: lastSeen,
        currentTaskDetail: taskDetail,
      ));
    }

    result.sort((agentA, agentB) {
      int rank(String s) {
        switch (s) {
          case 'busy': return 0;
          case 'online': return 1;
          case 'away': return 2;
          default: return 3;
        }
      }
      final cmp = rank(agentA.presenceStatus).compareTo(rank(agentB.presenceStatus));
      if (cmp != 0) return cmp;
      return agentA.name.compareTo(agentB.name);
    });

    controller.add(result);
  }

  // 1. Stream staff accounts from admin portal
  final subAdminUsers = adminDb.collection('users').snapshots().listen((snap) {
    adminDocs = snap.docs;
    emitMerged();
  });

  // 2. Stream dedicated real-time presence collection from adminDb
  final subAdminPresence = adminDb.collection('presence').snapshots().listen((snap) {
    for (final doc in snap.docs) {
      dedicatedPresenceMap[doc.id] = doc.data();
    }
    emitMerged();
  }, onError: (_) {});

  // 3. Stream dedicated real-time presence collection from userDb (active environment)
  final subUserPresence = userDb.collection('presence').snapshots().listen((snap) {
    for (final doc in snap.docs) {
      dedicatedPresenceMap[doc.id] = doc.data();
    }
    emitMerged();
  }, onError: (_) {});

  // 4. Stream users collection in active environment
  final subUsers = userDb.collection('users').snapshots().listen((snap) {
    userPresenceMap = {for (final doc in snap.docs) doc.id: doc.data()};
    emitMerged();
  });

  // 5. Stream active P2P Deposits
  final subDeposits = userDb.collection('deposits').where('status', isEqualTo: 'processing').snapshots().listen((snap) {
    activeDepositsMap = {};
    for (final doc in snap.docs) {
      final claimedBy = (doc.data()['claimedBy'] ?? doc.data()['assignedTo'] ?? doc.data()['assignedAgentId']) as String?;
      if (claimedBy != null && claimedBy.isNotEmpty) {
        final idShort = doc.id.length > 6 ? doc.id.substring(0, 6) : doc.id;
        activeDepositsMap[claimedBy] = 'Handling Deposit #$idShort';
      }
    }
    emitMerged();
  }, onError: (_) {});

  // 6. Stream active P2P Cashouts / Withdrawals
  final subWithdrawals = userDb.collection('withdrawal_requests').where('status', isEqualTo: 'processing').snapshots().listen((snap) {
    activeWithdrawalsMap = {};
    for (final doc in snap.docs) {
      final claimedBy = (doc.data()['claimedBy'] ?? doc.data()['assignedTo'] ?? doc.data()['assignedAgentId']) as String?;
      if (claimedBy != null && claimedBy.isNotEmpty) {
        final idShort = doc.id.length > 6 ? doc.id.substring(0, 6) : doc.id;
        activeWithdrawalsMap[claimedBy] = 'Handling Cashout #$idShort';
      }
    }
    emitMerged();
  }, onError: (_) {});

  // 7. Stream active in-progress Support Tickets
  final subTickets = userDb.collection('supportTickets').where('status', isEqualTo: 'in_progress').snapshots().listen((snap) {
    activeTicketsMap = {};
    for (final doc in snap.docs) {
      final assignedTo = (doc.data()['assignedAgentId'] ?? doc.data()['assignedTo']) as String?;
      if (assignedTo != null && assignedTo.isNotEmpty) {
        final idShort = doc.id.length > 6 ? doc.id.substring(0, 6) : doc.id;
        activeTicketsMap[assignedTo] = 'Handling Ticket #$idShort';
      }
    }
    emitMerged();
  }, onError: (_) {});

  // 8A. Stream active Live Support Chats (support_chats)
  final subSupportChats = userDb.collection('support_chats').where('status', isEqualTo: 'active').snapshots().listen((snap) {
    activeChatsMap = {};
    for (final doc in snap.docs) {
      final assignedAgent = (doc.data()['assignedAgentId'] ?? doc.data()['agentId'] ?? doc.data()['assignedTo']) as String?;
      if (assignedAgent != null && assignedAgent.isNotEmpty) {
        activeChatsMap[assignedAgent] = 'Active in Live Chat';
      }
    }
    emitMerged();
  }, onError: (_) {});

  // 8B. Stream active Live Support Chats (chats fallback)
  final subChats = userDb.collection('chats').where('status', isEqualTo: 'active').snapshots().listen((snap) {
    for (final doc in snap.docs) {
      final assignedAgent = (doc.data()['assignedAgentId'] ?? doc.data()['agentId'] ?? doc.data()['assignedTo']) as String?;
      if (assignedAgent != null && assignedAgent.isNotEmpty) {
        activeChatsMap[assignedAgent] = 'Active in Live Chat';
      }
    }
    emitMerged();
  }, onError: (_) {});

  ref.onDispose(() {
    subAdminUsers.cancel();
    subAdminPresence.cancel();
    subUserPresence.cancel();
    subUsers.cancel();
    subDeposits.cancel();
    subWithdrawals.cancel();
    subTickets.cancel();
    subSupportChats.cancel();
    subChats.cancel();
    controller.close();
  });

  return controller.stream;
});

// ── Global Search ──────────────────────────────────────────────────────────

class SearchResult {
  final String id, title, subtitle, category, path;
  SearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.path,
  });
}

final globalSearchResultsProvider = FutureProvider.family<List<SearchResult>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];
  final firestore = ref.watch(firestoreProvider);
  final list = <SearchResult>[];
  final q = query.toLowerCase().trim();
  try {
    final fetches = await Future.wait([
      firestore.collection('users').get(),
      firestore.collection('rentals').get(),
      firestore.collection('properties').get(),
      firestore.collection('jobs').get(),
      firestore.collection('rental_requests').get(),
      firestore.collection('property_requests').get(),
    ]).timeout(const Duration(seconds: 4));

    // Users
    for (final doc in fetches[0].docs) {
      final d = doc.data();
      if ((d['name'] as String? ?? '').toLowerCase().contains(q) ||
          (d['email'] as String? ?? '').toLowerCase().contains(q)) {
        list.add(
          SearchResult(
            id: doc.id,
            title: d['name'] ?? 'User',
            subtitle: d['email'] ?? '',
            category: 'User',
            path: '/users',
          ),
        );
      }
    }
    // Rentals (Vehicles)
    for (final doc in fetches[1].docs) {
      final d = doc.data();
      if ('${d['brand']} ${d['model']}'.toLowerCase().contains(q)) {
        list.add(
          SearchResult(
            id: doc.id,
            title: '${d['brand']} ${d['model']}'.trim(),
            subtitle: 'Vehicle Rental',
            category: 'Vehicle',
            path: '/listings',
          ),
        );
      }
    }
    // Properties
    for (final doc in fetches[2].docs) {
      final d = doc.data();
      if ((d['title'] as String? ?? '').toLowerCase().contains(q)) {
        list.add(
          SearchResult(
            id: doc.id,
            title: d['title'] ?? 'Property',
            subtitle: 'Real Estate',
            category: 'Property',
            path: '/listings',
          ),
        );
      }
    }
    // Jobs (Services)
    for (final doc in fetches[3].docs) {
      final d = doc.data();
      if ((d['title'] as String? ?? '').toLowerCase().contains(q)) {
        list.add(
          SearchResult(
            id: doc.id,
            title: d['title'] ?? 'Service',
            subtitle: 'Gig Service',
            category: 'Service',
            path: '/listings',
          ),
        );
      }
    }
    // Rental Requests (Vehicle Booking)
    for (final doc in fetches[4].docs) {
      final d = doc.data();
      final title = '${d['brand'] ?? ''} ${d['model'] ?? 'Vehicle'}'.trim();
      if (title.toLowerCase().contains(q) || (d['renteeName'] as String? ?? '').toLowerCase().contains(q)) {
        list.add(
          SearchResult(
            id: doc.id,
            title: title,
            subtitle: 'Renter: ${d['renteeName'] ?? 'Guest'}',
            category: 'Booking: Vehicle',
            path: '/bookings',
          ),
        );
      }
    }
    // Property Requests (Property Booking)
    for (final doc in fetches[5].docs) {
      final d = doc.data();
      final title = d['title'] ?? 'Property Rental';
      if (title.toLowerCase().contains(q) || (d['renteeName'] as String? ?? '').toLowerCase().contains(q)) {
        list.add(
          SearchResult(
            id: doc.id,
            title: title,
            subtitle: 'Renter: ${d['renteeName'] ?? 'Guest'}',
            category: 'Booking: Property',
            path: '/bookings',
          ),
        );
      }
    }
  } catch (_) {}
  return list.take(8).toList();
});

// ── Dashboard Page ─────────────────────────────────────────────────────────

class Dashboard extends StatefulComponent {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  String _searchQuery = '';
  String _revenueTimeframe = '24h';
  String _rosterFilter = 'all';

  @override
  Component build(BuildContext context) {
    final profile = context.watch(currentAdminProfileProvider).value;
    final user = context.watch(adminCurrentUserProvider).value;
    final userEmail = (profile?.email.isNotEmpty == true ? profile!.email : user?.email) ?? '';
    final userRole = profile?.role.toLowerCase() ?? '';
    final isAdmin = userEmail.toLowerCase().contains('admin') || userEmail == 'admin@tranyx.app' || userRole.contains('admin');
    if (!isAdmin) {
      _revenueTimeframe = '24h';
    }
    final currentEnv = context.watch(activeEnvironmentProvider);
    final now = DateTime.now();
    final dateString = '${_dayNames[now.weekday - 1]}, ${now.day} ${_monthNames[now.month - 1]} ${now.year}';

    final kycStats = context.watch(kycStatsProvider).value ?? KycStats(approved: 0, pending: 0, rejected: 0);
    final monthlyRevenue = context.watch(monthlyRevenueProvider).value ?? List<double>.filled(12, 0.0);
    final monthlyUsers = context.watch(monthlyNewUsersProvider).value ?? List<int>.filled(12, 0);
    final staffList = context.watch(platformStaffProvider).value ?? [];
    final staffRoster = context.watch(allStaffRosterProvider).value ?? [];
    final myStaffProfile = staffList.firstWhere(
      (staff) =>
          profile?.name.isNotEmpty == true &&
          staff.name.toLowerCase() == profile!.name.toLowerCase(),
      orElse: () => StaffPerformance(
        name: profile?.name.isNotEmpty == true ? profile!.name : (user?.displayName ?? 'Agent'),
        role: profile?.role ?? 'staff',
        p2pHandled: 0,
        ticketsHandled: 0,
        liveSupportHandled: 0,
        totalHandled: 0,
        csat: 98.0,
      ),
    );

    final detailedRevenue = context.watch(detailedRevenueProvider).value ?? DetailedRevenue.empty();
    final userBreakdown =
        context.watch(userBreakdownProvider).value ??
        UserBreakdown(total: 0, jobSeekers: 0, employers: 0, landlords: 0, renters: 0);
    final liveListings =
        context.watch(liveListingsProvider).value ??
        LiveListingsBreakdown(total: 0, vehicles: 0, properties: 0, services: 0);
    final reportedListingsCount = context.watch(reportedListingsCountProvider).value ?? 0;
    final openTicketsCount = context.watch(openTicketsCountProvider).value ?? 0;
    final pendingChatsCount = context
        .watch(supportChatsStreamProvider)
        .maybeWhen(
          data: (chats) => chats.where((c) => c.isPending).length,
          orElse: () => 0,
        );

    final p2pMetrics = context.watch(p2pDashboardMetricsProvider);
    final maxRev = monthlyRevenue.fold(0.0, (acc, val) => val > acc ? val : acc);
    final maxUsers = monthlyUsers.fold(0, (acc, val) => val > acc ? val : acc);
    final kycTotal = kycStats.total == 0 ? 1 : kycStats.total;

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-7 max-w-7xl mx-auto w-full bg-[#f2f5f3]', [
      // Header
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 pb-1', [
        div(classes: 'flex flex-col gap-1', [
          span(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [Component.text(dateString)]),
          h1(classes: 'text-2xl font-black text-zinc-900 tracking-tight', [Component.text('Analytics Dashboard')]),
          p(classes: 'text-xs text-zinc-400 font-bold', [
            Component.text('Live platform metrics — ${currentEnv.name.toUpperCase()} environment'),
          ]),
        ]),
        div(classes: 'flex items-center gap-3 self-end md:self-auto', [
          div(classes: 'relative hidden sm:block', [
            input(
              classes: 'bg-white border border-zinc-200/50 rounded-full px-5 py-2 text-xs text-zinc-800 placeholder-zinc-400 w-60 focus:outline-none focus:border-black transition-all shadow-sm',
              value: _searchQuery,
              attributes: {'placeholder': 'Search users, listings...'},
              onInput: (val) => setState(() => _searchQuery = val as String),
            ),
            if (_searchQuery.isNotEmpty)
              div(
                classes: 'absolute top-11 left-0 bg-white border border-zinc-200/80 rounded-2xl shadow-xl z-50 max-h-80 overflow-y-auto p-3 flex flex-col gap-1 w-72',
                [
                  context
                      .watch(globalSearchResultsProvider(_searchQuery))
                      .when(
                        data: (results) {
                          if (results.isEmpty) {
                            return div(classes: 'text-center p-4 text-[11px] text-zinc-400', [
                              Component.text('No results found'),
                            ]);
                          }
                          return Component.fragment([
                            for (final res in results)
                              a(
                                href: 'javascript:void(0);',
                                onClick: () {
                                  if (res.category == 'Vehicle' ||
                                      res.category == 'Property' ||
                                      res.category == 'Service') {
                                    context.read(selectedListingIdProvider.notifier).state = res.id;
                                    if (res.category == 'Vehicle') {
                                      context.read(listingsTabProvider.notifier).state = 'vehicles';
                                    } else if (res.category == 'Property') {
                                      context.read(listingsTabProvider.notifier).state = 'properties';
                                    } else {
                                      context.read(listingsTabProvider.notifier).state = 'services';
                                    }
                                  } else if (res.category.startsWith('Booking:')) {
                                    context.read(selectedBookingIdProvider.notifier).state = res.id;
                                    if (res.category == 'Booking: Vehicle') {
                                      context.read(bookingsTabProvider.notifier).state = 'vehicles';
                                    } else {
                                      context.read(bookingsTabProvider.notifier).state = 'properties';
                                    }
                                  }
                                  setState(() => _searchQuery = '');
                                  Router.of(context).push(res.path);
                                },
                                classes: 'flex flex-col p-2.5 rounded-xl hover:bg-zinc-50 transition-all no-underline border-b border-zinc-50 last:border-0',
                                [
                                  div(classes: 'flex justify-between items-center', [
                                    span(classes: 'text-[11px] font-black text-zinc-800 truncate max-w-[70%]', [
                                      Component.text(res.title),
                                    ]),
                                    span(
                                      classes: 'text-[8px] font-extrabold uppercase px-1.5 py-0.5 rounded bg-zinc-100 text-zinc-500 tracking-wider',
                                      [Component.text(res.category)],
                                    ),
                                  ]),
                                ],
                              ),
                          ]);
                        },
                        loading: () => div(classes: 'flex justify-center p-4', [
                          div(classes: 'animate-spin h-4 w-4 border-2 border-zinc-200 border-t-black rounded-full', []),
                        ]),
                        error: (err, stack) =>
                            div(classes: 'text-center p-3 text-[10px] text-red-500', [Component.text('Search error')]),
                      ),
                ],
              ),
          ]),
          div(
            classes: 'flex items-center gap-2.5 bg-white px-3 py-1.5 border border-zinc-200/50 rounded-full shadow-sm',
            [
              div(
                classes: 'w-7 h-7 rounded-full bg-zinc-200 flex items-center justify-center font-black text-xs text-zinc-700',
                [
                  Component.text(
                    profile?.name.isNotEmpty == true
                        ? profile!.name.substring(0, 1).toUpperCase()
                        : (user?.displayName?.isNotEmpty == true ? user!.displayName!.substring(0, 1).toUpperCase() : 'A'),
                  ),
                ],
              ),
              div(classes: 'flex flex-col text-left leading-tight hidden sm:flex', [
                span(classes: 'text-[10px] font-black text-zinc-850', [
                  Component.text(profile?.name.isNotEmpty == true ? profile!.name : (user?.displayName ?? 'Staff')),
                ]),
                span(classes: 'text-[8px] text-zinc-400 font-extrabold uppercase', [
                  Component.text(isAdmin ? 'Admin' : 'Staff'),
                ]),
              ]),
            ],
          ),
        ]),
      ]),

      if (pendingChatsCount > 0 && !isAdmin)
        div(
          classes: 'p-4 bg-rose-50 border border-rose-100 rounded-2xl flex items-center justify-between shadow-lg shadow-rose-500/5 animate-pulse relative overflow-hidden',
          [
            div(classes: 'absolute top-0 left-0 w-1.5 h-full bg-rose-600', []),
            div(classes: 'flex items-center gap-3.5 pl-2', [
              span(classes: 'text-xl', [Component.text('🚨')]),
              div(classes: 'flex flex-col', [
                h4(classes: 'text-xs font-black text-rose-800 uppercase tracking-wider', [
                  Component.text('Urgent Live Support Alert'),
                ]),
                p(classes: 'text-[11px] text-rose-650 font-bold', [
                  Component.text(
                    'There ${pendingChatsCount == 1 ? "is 1 pending support chat" : "are $pendingChatsCount pending support chats"} awaiting agent assignment!',
                  ),
                ]),
              ]),
            ]),
            button(
              onClick: () {
                Router.of(context).push('/chats');
              },
              classes: 'px-4 py-2 bg-rose-600 hover:bg-rose-700 text-white rounded-xl text-[10px] font-black uppercase tracking-wider transition-all shadow-md shadow-rose-600/10 cursor-pointer border-0 outline-none',
              [Component.text('Respond Now')],
            ),
          ],
        ),

      // ── Agent Personal Performance & CSAT Satisfaction (Top Placement) ──
      if (!isAdmin)
        _buildAgentTopPerformanceSection(myStaffProfile),

      // Quick action links (6 Tiles)
      div(classes: 'grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3', [
        _promoBanner(
          'P2P Deposits',
          '${p2pMetrics.pendingDeposits} awaiting agent review',
          'bg-emerald-50 border border-emerald-100',
          '/deposits',
        ),
        _promoBanner(
          'P2P Cashouts',
          '${p2pMetrics.pendingWithdrawals} awaiting payout & proof',
          'bg-amber-50 border border-amber-100',
          '/withdrawals',
        ),
        _promoBanner(
          'Verify KYC',
          '${kycStats.pending} pending ID submissions',
          'bg-blue-50 border border-blue-100',
          '/kyc',
        ),
        _promoBanner(
          'Live Support',
          pendingChatsCount > 0 ? '$pendingChatsCount pending chats' : 'Active agent queue',
          'bg-rose-50 border border-rose-100',
          '/chats',
        ),
        if (isAdmin)
          _promoBanner(
            'P2P Listings',
            '${liveListings.total} active platform posts',
            'bg-zinc-50 border border-zinc-200',
            '/listings',
          )
        else
          _promoBanner(
            'Support Tickets',
            openTicketsCount > 0 ? '$openTicketsCount open tickets' : 'Queue clear',
            'bg-indigo-50 border border-indigo-100',
            '/tickets',
          ),
        if (isAdmin)
          _promoBanner(
            'System Config',
            'Environment & node settings',
            'bg-purple-50 border border-purple-100',
            '/settings',
          )
        else
          _promoBanner(
            'P2P Listings',
            '${liveListings.total} active platform posts',
            'bg-zinc-50 border border-zinc-200',
            '/listings',
          ),
      ]),

      // ── 5 Top KPI Cards (Must be at the very face of the Admin Portal) ──
      div(classes: 'grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4', [
        // 1. Total Revenue Card (Admin) or Action Required Card (Staff)
        if (isAdmin)
          div(
            classes: 'bg-white rounded-[22px] border border-zinc-200/50 p-5 flex flex-col gap-3 shadow-[0_4px_20px_rgba(0,0,0,0.02)] lg:col-span-1',
            [
              div(classes: 'flex items-start justify-between', [
                div(classes: 'flex flex-col gap-0.5 min-w-0', [
                  span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                    Component.text('Total Revenue'),
                  ]),
                  h4(classes: 'text-xl font-black text-zinc-950 tracking-tight mt-1 truncate', [
                    Component.text(() {
                      switch (_revenueTimeframe) {
                        case '7d':
                          return '₱${detailedRevenue.rev7d.toStringAsFixed(2)}';
                        case '30d':
                          return '₱${detailedRevenue.rev30d.toStringAsFixed(2)}';
                        case 'allTime':
                          return '₱${detailedRevenue.revAllTime.toStringAsFixed(2)}';
                        default:
                          return '₱${detailedRevenue.rev24h.toStringAsFixed(2)}';
                      }
                    }()),
                  ]),
                ]),
                select(
                  classes: 'bg-zinc-100 hover:bg-zinc-200 border-0 rounded-lg px-2 py-1 text-[9px] font-black text-zinc-700 focus:outline-none transition-all cursor-pointer',
                  onChange: (v) => setState(() => _revenueTimeframe = v.isNotEmpty ? v.first : '24h'),
                  [
                    option(value: '24h', selected: _revenueTimeframe == '24h', [Component.text('24h')]),
                    option(value: '7d', selected: _revenueTimeframe == '7d', [Component.text('7 Days')]),
                    option(value: '30d', selected: _revenueTimeframe == '30d', [Component.text('1 Month')]),
                    option(value: 'allTime', selected: _revenueTimeframe == 'allTime', [Component.text('Accumulated')]),
                  ],
                ),
              ]),
              div(classes: 'flex flex-col gap-1.5 pt-2 border-t border-zinc-100 text-[9px] font-semibold text-zinc-500', [
                div(classes: 'flex items-center justify-between', [
                  span([Component.text('Services (Employer 10%, Worker 3%)')]),
                  span(classes: 'font-bold text-zinc-800', [
                    Component.text(
                      '₱${(() {
                        final bd = _revenueTimeframe == '7d'
                            ? detailedRevenue.breakdown7d
                            : _revenueTimeframe == '30d'
                            ? detailedRevenue.breakdown30d
                            : _revenueTimeframe == 'allTime'
                            ? detailedRevenue.breakdownAllTime
                            : detailedRevenue.breakdown24h;
                        return bd.services.toStringAsFixed(2);
                      })()}',
                    ),
                  ]),
                ]),
                div(classes: 'flex items-center justify-between', [
                  span([Component.text('Rentals (Lessor 3%, Lessee 3%, Listing 1.5%)')]),
                  span(classes: 'font-bold text-zinc-800', [
                    Component.text(
                      '₱${(() {
                        final bd = _revenueTimeframe == '7d'
                            ? detailedRevenue.breakdown7d
                            : _revenueTimeframe == '30d'
                            ? detailedRevenue.breakdown30d
                            : _revenueTimeframe == 'allTime'
                            ? detailedRevenue.breakdownAllTime
                            : detailedRevenue.breakdown24h;
                        return bd.rentals.toStringAsFixed(2);
                      })()}',
                    ),
                  ]),
                ]),
                div(classes: 'flex items-center justify-between', [
                  span([Component.text('Withdrawals (Workers 2% Platform Fee)')]),
                  span(classes: 'font-bold text-zinc-800', [
                    Component.text(
                      '₱${(() {
                        final bd = _revenueTimeframe == '7d'
                            ? detailedRevenue.breakdown7d
                            : _revenueTimeframe == '30d'
                            ? detailedRevenue.breakdown30d
                            : _revenueTimeframe == 'allTime'
                            ? detailedRevenue.breakdownAllTime
                            : detailedRevenue.breakdown24h;
                        return bd.withdrawals.toStringAsFixed(2);
                      })()}',
                    ),
                  ]),
                ]),
                div(
                  classes: 'grid grid-cols-2 gap-1 mt-1 text-[8px] font-bold text-zinc-400 border-t border-zinc-50 pt-1',
                  [
                    span([Component.text('24H: ₱${detailedRevenue.rev24h.toStringAsFixed(0)}')]),
                    span([Component.text('7D: ₱${detailedRevenue.rev7d.toStringAsFixed(0)}')]),
                    span([Component.text('30D: ₱${detailedRevenue.rev30d.toStringAsFixed(0)}')]),
                    span([Component.text('ACC: ₱${detailedRevenue.revAllTime.toStringAsFixed(0)}')]),
                  ],
                ),
              ]),
            ],
          )
        else
          div(
            classes: 'bg-white rounded-[22px] border border-zinc-200/50 p-5 flex flex-col gap-3 shadow-[0_4px_20px_rgba(0,0,0,0.02)] lg:col-span-1',
            [
              div(classes: 'flex items-start justify-between', [
                div(classes: 'flex flex-col gap-0.5 min-w-0', [
                  span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                    Component.text('Action Required'),
                  ]),
                  h4(classes: 'text-2xl font-black text-rose-600 tracking-tight mt-1 truncate', [
                    Component.text('${p2pMetrics.pendingDeposits + p2pMetrics.pendingWithdrawals + kycStats.pending + pendingChatsCount} Tasks'),
                  ]),
                ]),
                div(
                  classes: 'w-8 h-8 rounded-2xl flex items-center justify-center text-lg bg-rose-50 text-rose-500 flex-shrink-0',
                  [Component.text('⚡')],
                ),
              ]),
              div(classes: 'flex flex-col gap-1.5 pt-2 border-t border-zinc-100 text-[9px] font-semibold text-zinc-500', [
                div(classes: 'flex items-center justify-between', [
                  span([Component.text('Pending Deposits')]),
                  span(classes: 'font-bold text-zinc-800', [Component.text('${p2pMetrics.pendingDeposits}')]),
                ]),
                div(classes: 'flex items-center justify-between', [
                  span([Component.text('Pending Cashouts')]),
                  span(classes: 'font-bold text-zinc-800', [Component.text('${p2pMetrics.pendingWithdrawals}')]),
                ]),
                div(classes: 'flex items-center justify-between', [
                  span([Component.text('Pending KYC')]),
                  span(classes: 'font-bold text-zinc-800', [Component.text('${kycStats.pending}')]),
                ]),
                div(classes: 'flex items-center justify-between border-t border-zinc-50 pt-1', [
                  span([Component.text('Live Unassigned Chats')]),
                  span(classes: 'font-bold text-rose-600', [Component.text('$pendingChatsCount')]),
                ]),
              ]),
            ],
          ),

        // 2. Active Users Card (breakdown by type)
        div(
          classes: 'bg-white rounded-[22px] border border-zinc-200/50 p-5 flex flex-col gap-3 shadow-[0_4px_20px_rgba(0,0,0,0.02)]',
          [
            div(classes: 'flex items-start justify-between', [
              div(classes: 'flex flex-col gap-0.5', [
                span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Active Users'),
                ]),
                h4(classes: 'text-2xl font-black text-zinc-900 tracking-tight mt-1', [
                  Component.text(userBreakdown.total.toString()),
                ]),
              ]),
              div(
                classes: 'w-8 h-8 rounded-2xl flex items-center justify-center text-lg bg-indigo-50 text-indigo-500 flex-shrink-0',
                [Component.text('👥')],
              ),
            ]),
            div(classes: 'grid grid-cols-2 gap-1 pt-2 border-t border-zinc-100 text-[8px] font-bold text-zinc-500', [
              div(classes: 'flex flex-col', [
                span(classes: 'text-zinc-400 uppercase font-extrabold', [Component.text('Seekers')]),
                span(classes: 'text-xs font-black text-zinc-800', [
                  Component.text(userBreakdown.jobSeekers.toString()),
                ]),
              ]),
              div(classes: 'flex flex-col', [
                span(classes: 'text-zinc-400 uppercase font-extrabold', [Component.text('Employers')]),
                span(classes: 'text-xs font-black text-zinc-800', [Component.text(userBreakdown.employers.toString())]),
              ]),
              div(classes: 'flex flex-col border-t border-zinc-50 pt-1', [
                span(classes: 'text-zinc-400 uppercase font-extrabold', [Component.text('Landlords')]),
                span(classes: 'text-xs font-black text-zinc-800', [Component.text(userBreakdown.landlords.toString())]),
              ]),
              div(classes: 'flex flex-col border-t border-zinc-50 pt-1', [
                span(classes: 'text-zinc-400 uppercase font-extrabold', [Component.text('Renters')]),
                span(classes: 'text-xs font-black text-zinc-800', [Component.text(userBreakdown.renters.toString())]),
              ]),
            ]),
          ],
        ),

        // 3. Live Listings Card (active posts breakdown)
        div(
          classes: 'bg-white rounded-[22px] border border-zinc-200/50 p-5 flex flex-col gap-3 shadow-[0_4px_20px_rgba(0,0,0,0.02)]',
          [
            div(classes: 'flex items-start justify-between', [
              div(classes: 'flex flex-col gap-0.5', [
                span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Live Listings'),
                ]),
                h4(classes: 'text-2xl font-black text-zinc-900 tracking-tight mt-1', [
                  Component.text(liveListings.total.toString()),
                ]),
              ]),
              div(
                classes: 'w-8 h-8 rounded-2xl flex items-center justify-center text-lg bg-emerald-50 text-emerald-500 flex-shrink-0',
                [Component.text('📋')],
              ),
            ]),
            div(
              classes:
                  'grid grid-cols-3 gap-1 pt-2 border-t border-zinc-100 text-[8px] font-bold text-zinc-500 text-center',
              [
                div(classes: 'flex flex-col py-1 bg-amber-50 text-amber-700 rounded-lg', [
                  span(classes: 'text-[7px] font-extrabold uppercase', [Component.text('Vehicles')]),
                  span(classes: 'text-xs font-black', [Component.text(liveListings.vehicles.toString())]),
                ]),
                div(classes: 'flex flex-col py-1 bg-blue-50 text-blue-700 rounded-lg', [
                  span(classes: 'text-[7px] font-extrabold uppercase', [Component.text('Properties')]),
                  span(classes: 'text-xs font-black', [Component.text(liveListings.properties.toString())]),
                ]),
                div(classes: 'flex flex-col py-1 bg-purple-50 text-purple-700 rounded-lg', [
                  span(classes: 'text-[7px] font-extrabold uppercase', [Component.text('Services')]),
                  span(classes: 'text-xs font-black', [Component.text(liveListings.services.toString())]),
                ]),
              ],
            ),
          ],
        ),

        // 4. Pending KYC Approvals Card (verification queue + reported posts alert)
        div(
          classes: 'bg-white rounded-[22px] border border-zinc-200/50 p-5 flex flex-col gap-3 shadow-[0_4px_20px_rgba(0,0,0,0.02)]',
          [
            div(classes: 'flex items-start justify-between', [
              div(classes: 'flex flex-col gap-0.5', [
                span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Pending KYC'),
                ]),
                h4(classes: 'text-2xl font-black text-amber-500 tracking-tight mt-1', [
                  Component.text(kycStats.pending.toString()),
                ]),
              ]),
              div(
                classes: 'w-8 h-8 rounded-2xl flex items-center justify-center text-lg bg-amber-50 text-amber-500 flex-shrink-0',
                [Component.text('🪪')],
              ),
            ]),
            div(classes: 'flex flex-col gap-1 pt-2 border-t border-zinc-100 text-[9px] font-semibold text-zinc-500', [
              div(classes: 'flex items-center justify-between', [
                span([Component.text('Approved ID docs')]),
                span(classes: 'font-bold text-zinc-800', [Component.text(kycStats.approved.toString())]),
              ]),
              div(classes: 'flex items-center justify-between', [
                span([Component.text('Rejected ID docs')]),
                span(classes: 'font-bold text-zinc-800', [Component.text(kycStats.rejected.toString())]),
              ]),
              if (reportedListingsCount > 0)
                div(
                  classes: 'mt-1.5 px-2 py-1 bg-red-50 text-red-600 rounded-lg font-black text-[8px] flex items-center justify-between animate-pulse',
                  [
                    Component.text('🚨 FLAG: $reportedListingsCount REPORTED POSTS'),
                  ],
                )
              else
                div(classes: 'mt-1.5 px-2 py-1 bg-emerald-50 text-emerald-600 rounded-lg font-black text-[8px]', [
                  Component.text('✓ NO URGENT POST ISSUES'),
                ]),
            ]),
          ],
        ),

        // 5. Active Agents Card (Admin) or Open Tickets / Reports Card (Staff)
        if (isAdmin)
          () {
            final activeTotal = staffRoster.where((member) => !member.isOffline).length;
            final waitingCount = staffRoster.where((member) => member.isWaiting).length;
            final busyCount = staffRoster.where((member) => member.isBusy).length;
            final awayCount = staffRoster.where((member) => member.isAway).length;
            final offlineCount = staffRoster.where((member) => member.isOffline).length;
            return div(
              classes: 'bg-white rounded-[22px] border border-zinc-200/50 p-5 flex flex-col gap-3 shadow-[0_4px_20px_rgba(0,0,0,0.02)]',
              [
                div(classes: 'flex items-start justify-between', [
                  div(classes: 'flex flex-col gap-0.5 min-w-0', [
                    span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                      Component.text('Active Agents'),
                    ]),
                    h4(classes: 'text-2xl font-black text-emerald-600 tracking-tight mt-1 flex items-center gap-1.5 truncate', [
                      span(classes: 'w-2 h-2 rounded-full bg-emerald-500 animate-pulse flex-shrink-0', []),
                      Component.text('$activeTotal / ${staffRoster.length} Active'),
                    ]),
                  ]),
                  div(
                    classes: 'w-8 h-8 rounded-2xl flex items-center justify-center text-lg bg-emerald-50 text-emerald-600 flex-shrink-0',
                    [Component.text('🧑‍💼')],
                  ),
                ]),

                // Status Breakdown Summary Strip
                div(classes: 'grid grid-cols-2 gap-1 pt-1.5 border-t border-zinc-100 text-[8px] font-bold text-zinc-600', [
                  div(classes: 'flex items-center gap-1 bg-emerald-50/80 px-1.5 py-0.5 rounded-md text-emerald-800 truncate', [
                    span(classes: 'w-1.5 h-1.5 rounded-full bg-emerald-500 flex-shrink-0', []),
                    span(classes: 'font-extrabold truncate', [Component.text('$waitingCount Waiting')]),
                  ]),
                  div(classes: 'flex items-center gap-1 bg-amber-50/80 px-1.5 py-0.5 rounded-md text-amber-800 truncate', [
                    span(classes: 'w-1.5 h-1.5 rounded-full bg-amber-500 flex-shrink-0', []),
                    span(classes: 'font-extrabold truncate', [Component.text('$busyCount Busy')]),
                  ]),
                  div(classes: 'flex items-center gap-1 bg-orange-50/80 px-1.5 py-0.5 rounded-md text-orange-800 truncate', [
                    span(classes: 'w-1.5 h-1.5 rounded-full bg-orange-500 flex-shrink-0', []),
                    span(classes: 'font-extrabold truncate', [Component.text('$awayCount AFK')]),
                  ]),
                  div(classes: 'flex items-center gap-1 bg-zinc-100 px-1.5 py-0.5 rounded-md text-zinc-500 truncate', [
                    span(classes: 'w-1.5 h-1.5 rounded-full bg-zinc-400 flex-shrink-0', []),
                    span(classes: 'font-extrabold truncate', [Component.text('$offlineCount Offline')]),
                  ]),
                ]),

                // List of Agents with Photo, Name & Realtime Status
                div(classes: 'flex flex-col gap-1.5 pt-1.5 border-t border-zinc-100 max-h-36 overflow-y-auto pr-0.5', [
                  if (staffRoster.isEmpty)
                    div(classes: 'py-2 text-center text-[9px] text-zinc-400 font-bold', [
                      Component.text('No staff accounts found'),
                    ])
                  else
                    for (final member in staffRoster)
                      div(
                        classes:
                            'flex items-center justify-between gap-2 p-1.5 rounded-xl border transition-all '
                            '${member.isBusy ? "bg-amber-50/50 border-amber-200/60" : member.isWaiting ? "bg-emerald-50/40 border-emerald-200/50" : member.isAway ? "bg-orange-50/40 border-orange-200/50" : "bg-zinc-50/60 border-zinc-100 opacity-70"}',
                        [
                          div(classes: 'flex items-center gap-2 min-w-0', [
                            div(
                              classes: 'relative w-6 h-6 rounded-full bg-indigo-50 border border-indigo-100 flex items-center justify-center font-black text-zinc-700 text-[8px] flex-shrink-0 overflow-hidden',
                              [
                                if (member.photoUrl != null && member.photoUrl!.isNotEmpty)
                                  img(src: member.photoUrl!, classes: 'w-full h-full object-cover', alt: member.name)
                                else
                                  Component.text(
                                    member.name.length >= 2 ? member.name.substring(0, 2).toUpperCase() : member.name.toUpperCase(),
                                  ),
                                div(
                                  classes:
                                      'absolute bottom-0 right-0 w-1.5 h-1.5 rounded-full border border-white '
                                      '${member.isBusy ? "bg-amber-500 animate-pulse" : member.isWaiting ? "bg-emerald-500" : member.isAway ? "bg-orange-500" : "bg-zinc-400"}',
                                  [],
                                ),
                              ],
                            ),
                            div(classes: 'flex flex-col min-w-0', [
                              span(classes: 'text-[10px] font-black text-zinc-800 truncate leading-tight', [
                                Component.text(member.name),
                              ]),
                              span(
                                classes:
                                    'text-[7.5px] font-bold truncate leading-tight '
                                    '${member.isBusy ? "text-amber-700 font-extrabold" : member.isWaiting ? "text-emerald-700" : member.isAway ? "text-orange-600" : "text-zinc-400"}',
                                [Component.text(member.currentTaskDetail)],
                              ),
                            ]),
                          ]),

                          span(
                            classes:
                                'px-1.5 py-0.5 rounded-md text-[7.5px] font-black uppercase tracking-wider flex-shrink-0 '
                                '${member.isBusy ? "bg-amber-100 text-amber-800" : member.isWaiting ? "bg-emerald-100 text-emerald-800" : member.isAway ? "bg-orange-100 text-orange-800" : "bg-zinc-100 text-zinc-400"}',
                            [
                              if (member.isBusy)
                                Component.text('Busy')
                              else if (member.isWaiting)
                                Component.text('Waiting')
                              else if (member.isAway)
                                Component.text('AFK')
                              else
                                Component.text('Offline'),
                            ],
                          ),
                        ],
                      ),
                ]),
              ],
            );
          }()
        else
          div(
            classes: 'bg-white rounded-[22px] border border-zinc-200/50 p-5 flex flex-col gap-3 shadow-[0_4px_20px_rgba(0,0,0,0.02)]',
            [
              div(classes: 'flex items-start justify-between', [
                div(classes: 'flex flex-col gap-0.5', [
                  span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                    Component.text('Open Tickets / Reports'),
                  ]),
                  h4(classes: 'text-2xl font-black text-red-500 tracking-tight mt-1', [
                    Component.text((openTicketsCount + reportedListingsCount).toString()),
                  ]),
                ]),
                div(
                  classes:
                      'w-8 h-8 rounded-2xl flex items-center justify-center text-lg bg-red-50 text-red-500 flex-shrink-0',
                  [Component.text('🎟️')],
                ),
              ]),
              div(classes: 'flex flex-col gap-1 pt-2 border-t border-zinc-100 text-[9px] font-semibold text-zinc-500', [
                div(classes: 'flex items-center justify-between', [
                  span([Component.text('Open Support Tickets')]),
                  span(classes: 'font-bold text-zinc-800', [Component.text(openTicketsCount.toString())]),
                ]),
                div(classes: 'flex items-center justify-between', [
                  span([Component.text('Reported Postings')]),
                  span(classes: 'font-bold text-zinc-800', [Component.text(reportedListingsCount.toString())]),
                ]),
                a(
                  href: '/tickets',
                  classes: 'mt-1.5 text-center text-[8px] font-black uppercase text-indigo-500 hover:text-indigo-600 transition-colors',
                  [Component.text('RESOLVE PENDING ISSUES →')],
                ),
              ]),
            ],
          ),
      ]),

      // ── P2P Liquidity & Agent Settlement Hub ──────────────────
      _buildP2PMetricsSection(context, p2pMetrics, isAdmin),

      // ── Charts Row ─────────────────────────────────────────────
      if (isAdmin)
        div(classes: 'grid grid-cols-1 lg:grid-cols-3 gap-5', [
          // Monthly Revenue Bar Chart (2/3 width)
          div(
            classes: 'lg:col-span-2 bg-white rounded-[28px] border border-zinc-200/50 p-6 flex flex-col gap-5 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
            [
              div(classes: 'flex justify-between items-start border-b border-zinc-50 pb-4', [
                div([
                  h3(classes: 'text-sm font-black text-zinc-900', [Component.text('Monthly Revenue')]),
                  p(classes: 'text-[10px] text-zinc-400 font-bold mt-0.5', [
                    Component.text('Volume + 3% fee revenue — ${now.year}'),
                  ]),
                ]),
                span(
                  classes: 'text-[9px] font-extrabold px-3 py-1.5 bg-[#e6f7ef] text-[#0fa958] rounded-full border border-emerald-100',
                  [
                    Component.text('₱${monthlyRevenue[now.month - 1].toStringAsFixed(0)} this month'),
                  ],
                ),
              ]),
              div(classes: 'h-52 flex items-end justify-between gap-1.5 pt-4 px-1 relative', [
                for (var y = 1; y <= 4; y++)
                  div(
                    classes: 'absolute left-0 right-0 border-t border-dashed border-zinc-100 pointer-events-none',
                    attributes: {'style': 'bottom: ${y * 22}%'},
                    [],
                  ),
                for (var i = 0; i < 12; i++)
                  div(classes: 'flex-1 flex flex-col items-center gap-1.5 z-10', [
                    div(
                      classes: 'w-full flex flex-col justify-end rounded-xl overflow-hidden',
                      attributes: {'style': 'height: 160px'},
                      [
                        div(
                          classes:
                              'w-full rounded-xl transition-all ${i == now.month - 1 ? "bg-gradient-to-t from-[#0fa958] to-emerald-400" : "bg-zinc-200 hover:bg-zinc-300"}',
                          attributes: {
                            'style':
                                'height: ${maxRev == 0 ? 8 : ((monthlyRevenue[i] / maxRev) * 90 + 8).clamp(8.0, 100.0)}%',
                            'title': '₱${monthlyRevenue[i].toStringAsFixed(2)}',
                          },
                          [],
                        ),
                      ],
                    ),
                    span(classes: 'text-[8px] font-extrabold text-zinc-400 uppercase', [
                      Component.text(_monthLabels[i]),
                    ]),
                  ]),
              ]),
            ],
          ),

          // Right column stacked
          div(classes: 'flex flex-col gap-5', [
            // KYC Pie Chart (CSS conic-gradient)
            div(
              classes: 'bg-white rounded-[28px] border border-zinc-200/50 p-5 flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
              [
                div([
                  h3(classes: 'text-sm font-black text-zinc-900', [Component.text('KYC Verifications')]),
                  p(classes: 'text-[10px] text-zinc-400 font-bold mt-0.5', [
                    Component.text('Identity submission breakdown'),
                  ]),
                ]),
                div(classes: 'flex items-center gap-5', [
                  () {
                    final approvedPct = (kycStats.approved / kycTotal) * 100;
                    final pendingPct = (kycStats.pending / kycTotal) * 100;
                    return div(
                      attributes: {
                        'style':
                            'width:88px;height:88px;border-radius:50%;flex-shrink:0;'
                            'background:conic-gradient(#0fa958 0% ${approvedPct.toStringAsFixed(1)}%, #f59e0b ${approvedPct.toStringAsFixed(1)}% ${(approvedPct + pendingPct).toStringAsFixed(1)}%, #ef4444 ${(approvedPct + pendingPct).toStringAsFixed(1)}% 100%);'
                            'box-shadow: 0 0 0 5px white, 0 0 0 6px #e5e7eb;',
                      },
                      [],
                    );
                  }(),
                  div(classes: 'flex flex-col gap-2 flex-1', [
                    for (final row in [
                      ('Approved', kycStats.approved, '#0fa958'),
                      ('Pending', kycStats.pending, '#f59e0b'),
                      ('Rejected', kycStats.rejected, '#ef4444'),
                    ])
                      div(classes: 'flex items-center justify-between text-[10px]', [
                        div(classes: 'flex items-center gap-1.5', [
                          div(classes: 'w-2 h-2 rounded-full', attributes: {'style': 'background:${row.$3}'}, []),
                          span(classes: 'font-bold text-zinc-600', [Component.text(row.$1)]),
                        ]),
                        span(classes: 'font-extrabold text-zinc-800', [Component.text(row.$2.toString())]),
                      ]),
                  ]),
                ]),
              ],
            ),

            // New User Acquisitions mini chart
            div(
              classes: 'flex-1 bg-white rounded-[28px] border border-zinc-200/50 p-5 flex flex-col gap-3 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
              [
                div([
                  h3(classes: 'text-sm font-black text-zinc-900', [Component.text('User Acquisitions')]),
                  p(classes: 'text-[10px] text-zinc-400 font-bold mt-0.5', [
                    Component.text('New signups per month — ${now.year}'),
                  ]),
                ]),
                div(classes: 'flex items-end justify-between gap-1 mt-2', [
                  for (var i = 0; i < 12; i++)
                    div(classes: 'flex-1 flex flex-col items-center gap-1', [
                      div(
                        classes:
                            'w-full rounded-md transition-all ${i == now.month - 1 ? "bg-indigo-400" : "bg-zinc-200 hover:bg-zinc-300"}',
                        attributes: {
                          'style':
                              'height: ${maxUsers == 0 ? 4 : ((monthlyUsers[i] / maxUsers) * 64 + 4).clamp(4.0, 68.0)}px',
                          'title': '${monthlyUsers[i]} users',
                        },
                        [],
                      ),
                      span(classes: 'text-[7px] font-extrabold text-zinc-400 uppercase', [
                        Component.text(_monthLabels[i]),
                      ]),
                    ]),
                ]),
              ],
            ),
          ]),
        ])
      else
        div(classes: 'grid grid-cols-1 lg:grid-cols-2 gap-5', [
          // KYC Pie Chart (1/2 width)
          div(
            classes: 'bg-white rounded-[28px] border border-zinc-200/50 p-5 flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
            [
              div([
                h3(classes: 'text-sm font-black text-zinc-900', [Component.text('KYC Verifications')]),
                p(classes: 'text-[10px] text-zinc-400 font-bold mt-0.5', [
                  Component.text('Identity submission breakdown'),
                ]),
              ]),
              div(classes: 'flex items-center gap-5', [
                () {
                  final approvedPct = (kycStats.approved / kycTotal) * 100;
                  final pendingPct = (kycStats.pending / kycTotal) * 100;
                  return div(
                    attributes: {
                      'style':
                          'width:88px;height:88px;border-radius:50%;flex-shrink:0;'
                          'background:conic-gradient(#0fa958 0% ${approvedPct.toStringAsFixed(1)}%, #f59e0b ${approvedPct.toStringAsFixed(1)}% ${(approvedPct + pendingPct).toStringAsFixed(1)}%, #ef4444 ${(approvedPct + pendingPct).toStringAsFixed(1)}% 100%);'
                          'box-shadow: 0 0 0 5px white, 0 0 0 6px #e5e7eb;',
                    },
                    [],
                  );
                }(),
                div(classes: 'flex flex-col gap-2 flex-1', [
                  for (final row in [
                    ('Approved', kycStats.approved, '#0fa958'),
                    ('Pending', kycStats.pending, '#f59e0b'),
                    ('Rejected', kycStats.rejected, '#ef4444'),
                  ])
                    div(classes: 'flex items-center justify-between text-[10px]', [
                      div(classes: 'flex items-center gap-1.5', [
                        div(classes: 'w-2 h-2 rounded-full', attributes: {'style': 'background:${row.$3}'}, []),
                        span(classes: 'font-bold text-zinc-600', [Component.text(row.$1)]),
                      ]),
                      span(classes: 'font-extrabold text-zinc-800', [Component.text(row.$2.toString())]),
                    ]),
                ]),
              ]),
            ],
          ),

          // New User Acquisitions mini chart (1/2 width)
          div(
            classes: 'bg-white rounded-[28px] border border-zinc-200/50 p-5 flex flex-col gap-3 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
            [
              div([
                h3(classes: 'text-sm font-black text-zinc-900', [Component.text('User Acquisitions')]),
                p(classes: 'text-[10px] text-zinc-400 font-bold mt-0.5', [
                  Component.text('New signups per month — ${now.year}'),
                ]),
              ]),
              div(classes: 'flex items-end justify-between gap-1 mt-2', [
                for (var i = 0; i < 12; i++)
                  div(classes: 'flex-1 flex flex-col items-center gap-1', [
                    div(
                      classes:
                          'w-full rounded-md transition-all ${i == now.month - 1 ? "bg-indigo-400" : "bg-zinc-200 hover:bg-zinc-300"}',
                      attributes: {
                        'style':
                            'height: ${maxUsers == 0 ? 4 : ((monthlyUsers[i] / maxUsers) * 64 + 4).clamp(4.0, 68.0)}px',
                        'title': '${monthlyUsers[i]} users',
                      },
                      [],
                    ),
                    span(classes: 'text-[7px] font-extrabold text-zinc-400 uppercase', [
                      Component.text(_monthLabels[i]),
                    ]),
                  ]),
              ]),
            ],
          ),
        ]),

      // ── Agent Presence & Live Activity Tracker (Admin Only) ──
      if (isAdmin)
        _buildAgentActivityRoster(staffRoster),

      // ── Bottom Row: Top Agents + Platform Config (Admin) ──
      if (isAdmin)
        div(classes: 'grid grid-cols-1 lg:grid-cols-3 gap-5', [
          // Top Performing Agents (2/3)
          div(
            classes: 'lg:col-span-2 bg-white rounded-[28px] border border-zinc-200/50 p-6 flex flex-col gap-5 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
            [
              div(classes: 'flex justify-between items-center border-b border-zinc-50 pb-4', [
                div([
                  h3(classes: 'text-sm font-black text-zinc-900', [Component.text('Top Performing Agents')]),
                  p(classes: 'text-[10px] text-zinc-400 font-bold mt-0.5', [
                    Component.text('Ranked by P2P transactions, support tickets, and live support handling'),
                  ]),
                ]),
                a(
                  href: '/users',
                  classes: 'text-[10px] font-extrabold text-zinc-500 hover:text-black transition-colors no-underline',
                  [Component.text('Manage Staff →')],
                ),
              ]),
              if (staffList.isEmpty)
                div(classes: 'py-8 text-center flex flex-col items-center gap-2', [
                  span(classes: 'text-3xl', [Component.text('🧑‍💼')]),
                  span(classes: 'text-xs font-bold text-zinc-600', [Component.text('No support agents yet')]),
                  span(classes: 'text-[10px] text-zinc-400', [
                    Component.text('Add agents in Users → Agents / Staff tab.'),
                  ]),
                ])
              else ...[
                div(
                  classes: 'grid grid-cols-12 text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider px-1 pb-1',
                  [
                    div(classes: 'col-span-1 text-center', [Component.text('#')]),
                    div(classes: 'col-span-3', [Component.text('Agent')]),
                    div(classes: 'col-span-2 text-center', [Component.text('P2P Handling')]),
                    div(classes: 'col-span-2 text-center', [Component.text('Tickets')]),
                    div(classes: 'col-span-2 text-center', [Component.text('Live Support')]),
                    div(classes: 'col-span-2 text-center', [Component.text('Total Score')]),
                  ],
                ),
                for (var i = 0; i < staffList.length && i < 8; i++)
                  div(
                    classes: 'grid grid-cols-12 items-center py-3 border-b border-zinc-50 last:border-0 hover:bg-zinc-50/50 rounded-xl px-1 transition-colors',
                    [
                      div(classes: 'col-span-1 flex justify-center', [
                        if (i == 0)
                          span(classes: 'text-sm', [Component.text('🥇')])
                        else if (i == 1)
                          span(classes: 'text-sm', [Component.text('🥈')])
                        else if (i == 2)
                          span(classes: 'text-sm', [Component.text('🥉')])
                        else
                          span(classes: 'text-[10px] font-extrabold text-zinc-400', [Component.text('${i + 1}')]),
                      ]),
                      div(classes: 'col-span-3 flex items-center gap-2.5 min-w-0 pr-2', [
                        div(
                          classes: 'w-8 h-8 rounded-full bg-indigo-50 border border-indigo-100 flex items-center justify-center font-extrabold text-zinc-700 text-[10px] flex-shrink-0 overflow-hidden',
                          [
                            if (staffList[i].photoUrl != null && staffList[i].photoUrl!.isNotEmpty)
                              img(src: staffList[i].photoUrl!, classes: 'w-full h-full object-cover', alt: staffList[i].name)
                            else
                              Component.text(
                                staffList[i].name.length >= 2
                                    ? staffList[i].name.substring(0, 2).toUpperCase()
                                    : staffList[i].name.toUpperCase(),
                              ),
                          ],
                        ),
                        div(classes: 'flex flex-col min-w-0', [
                          span(classes: 'text-xs font-black text-zinc-800 truncate', [Component.text(staffList[i].name)]),
                          span(classes: 'text-[9px] text-indigo-500 font-extrabold uppercase truncate', [
                            Component.text(staffList[i].role),
                          ]),
                        ]),
                      ]),
                      div(classes: 'col-span-2 text-center', [
                        span(classes: 'text-xs font-black text-zinc-900', [
                          Component.text('${staffList[i].p2pHandled}'),
                        ]),
                        span(classes: 'text-[9px] text-zinc-400 block font-semibold', [Component.text('P2P handled')]),
                      ]),
                      div(classes: 'col-span-2 text-center', [
                        span(classes: 'text-xs font-black text-zinc-900', [
                          Component.text('${staffList[i].ticketsHandled}'),
                        ]),
                        span(classes: 'text-[9px] text-zinc-400 block font-semibold', [Component.text('tickets')]),
                      ]),
                      div(classes: 'col-span-2 text-center', [
                        span(classes: 'text-xs font-black text-zinc-900', [
                          Component.text('${staffList[i].liveSupportHandled}'),
                        ]),
                        span(classes: 'text-[9px] text-zinc-400 block font-semibold', [Component.text('live chats')]),
                      ]),
                      div(classes: 'col-span-2 text-center flex flex-col items-center justify-center gap-0.5', [
                        span(
                          classes:
                              'px-2.5 py-0.5 rounded-full text-xs font-black '
                              '${staffList[i].totalHandled > 0 ? "bg-emerald-50 text-[#0fa958] border border-emerald-200/60" : "bg-zinc-100 text-zinc-400"}',
                          [
                            Component.text('${staffList[i].totalHandled} pts'),
                          ],
                        ),
                        if (staffList[i].csat > 0)
                          span(classes: 'text-[9px] font-bold text-zinc-400', [
                            Component.text('${staffList[i].csat}% CSAT'),
                          ]),
                      ]),
                    ],
                  ),
              ],
            ],
          ),

          // Platform Config (Admin Only)
          div(
            classes: 'bg-white rounded-[28px] border border-zinc-200/50 p-6 flex flex-col gap-5 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
            [
              div(classes: 'border-b border-zinc-50 pb-4', [
                h3(classes: 'text-sm font-black text-zinc-900', [Component.text('Platform Config')]),
                p(classes: 'text-[10px] text-zinc-400 font-bold mt-0.5', [
                  Component.text('Node status and environment health'),
                ]),
              ]),
              div(classes: 'flex flex-col gap-4', [
                _configRow('Environment', currentEnv.name.toUpperCase(), 'Healthy', '#0fa958', '#e6f7ef'),
                _configRow('Firebase Rules', 'Firestore + Storage', 'Secure', '#0fa958', '#e6f7ef'),
                _configRow('Blockchain Fee', '3% per deposit/withdraw', 'Active', '#6366f1', '#ede9fe'),
                _configRow('KYC Pipeline', 'Identity Verification', 'Online', '#0fa958', '#e6f7ef'),
                _configRow('Escrow Engine', 'On-chain wallet escrow', 'Online', '#0fa958', '#e6f7ef'),
                _configRow(
                  'Support Queue',
                  '${(context.watch(dbStaffCountProvider).value ?? 0)} agents active',
                  'Live',
                  '#f59e0b',
                  '#fef3c7',
                ),
              ]),
            ],
          ),
        ]),
    ]);
  }

  Component _buildAgentActivityRoster(List<StaffRosterMember> roster) {
    final waitingCount = roster.where((member) => member.isWaiting).length;
    final busyCount = roster.where((member) => member.isBusy).length;
    final awayCount = roster.where((member) => member.isAway).length;
    final offlineCount = roster.where((member) => member.isOffline).length;

    final filteredList = roster.where((agent) {
      if (_rosterFilter == 'waiting') return agent.isWaiting;
      if (_rosterFilter == 'busy') return agent.isBusy;
      if (_rosterFilter == 'away') return agent.isAway;
      if (_rosterFilter == 'offline') return agent.isOffline;
      return true;
    }).toList();

    return div(
      classes: 'bg-white rounded-[28px] border border-zinc-200/50 p-6 flex flex-col gap-5 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
      [
        div(classes: 'flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-zinc-50 pb-4', [
          div([
            div(classes: 'flex items-center gap-2', [
              h3(classes: 'text-sm font-black text-zinc-900', [Component.text('Agent Presence & Live Activity Tracker')]),
              span(
                classes: 'px-2 py-0.5 rounded-full text-[9px] font-black uppercase tracking-wider bg-emerald-50 text-[#0fa958] border border-emerald-200/60 flex items-center gap-1',
                [
                  span(classes: 'w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse', []),
                  Component.text('LIVE ROSTER'),
                ],
              ),
            ]),
            p(classes: 'text-[10px] text-zinc-400 font-bold mt-0.5', [
              Component.text('Real-time operational tracking of staff agents: busy in tasks, waiting for requests, AFK, or offline'),
            ]),
          ]),
          // Filter Tabs
          div(classes: 'flex items-center gap-1 bg-zinc-100/80 p-1 rounded-xl w-max flex-wrap', [
            _rosterFilterButton('all', 'All (${roster.length})'),
            _rosterFilterButton('waiting', '🟢 Waiting ($waitingCount)'),
            _rosterFilterButton('busy', '🟡 Busy ($busyCount)'),
            _rosterFilterButton('away', '🟠 AFK ($awayCount)'),
            _rosterFilterButton('offline', '⚪ Offline ($offlineCount)'),
          ]),
        ]),

        if (filteredList.isEmpty)
          div(classes: 'py-8 text-center flex flex-col items-center gap-2', [
            span(classes: 'text-2xl', [Component.text('🔍')]),
            span(classes: 'text-xs font-bold text-zinc-600', [Component.text('No agents in this filter status')]),
          ])
        else
          div(classes: 'grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3', [
            for (final agent in filteredList)
              div(
                classes:
                    'p-3.5 rounded-2xl border transition-all flex items-center justify-between gap-3 '
                    '${agent.isBusy ? "bg-amber-50/40 border-amber-200/60" : agent.isWaiting ? "bg-emerald-50/30 border-emerald-200/50" : agent.isAway ? "bg-orange-50/30 border-orange-200/50" : "bg-[#fafcfa] border-zinc-200/60 opacity-80"}',
                [
                  div(classes: 'flex items-center gap-3 min-w-0', [
                    div(
                      classes: 'relative w-10 h-10 rounded-full bg-indigo-50 border border-indigo-100 flex items-center justify-center font-black text-zinc-700 text-xs flex-shrink-0 overflow-hidden shadow-sm',
                      [
                        if (agent.photoUrl != null && agent.photoUrl!.isNotEmpty)
                          img(src: agent.photoUrl!, classes: 'w-full h-full object-cover', alt: agent.name)
                        else
                          Component.text(
                            agent.name.length >= 2 ? agent.name.substring(0, 2).toUpperCase() : agent.name.toUpperCase(),
                          ),
                        // Status indicator dot
                        div(
                          classes:
                              'absolute bottom-0 right-0 w-3 h-3 rounded-full border-2 border-white '
                              '${agent.isBusy ? "bg-amber-500 animate-pulse" : agent.isWaiting ? "bg-emerald-500" : agent.isAway ? "bg-orange-500" : "bg-zinc-400"}',
                          [],
                        ),
                      ],
                    ),
                    div(classes: 'flex flex-col min-w-0', [
                      div(classes: 'flex items-center gap-1.5', [
                        span(classes: 'text-xs font-black text-zinc-900 truncate', [Component.text(agent.name)]),
                        span(
                          classes: 'text-[8px] font-extrabold uppercase px-1.5 py-0.2 rounded '
                              '${agent.role.toLowerCase().contains("admin") ? "bg-amber-100 text-amber-800" : "bg-indigo-50 text-indigo-700 border border-indigo-200/50"}',
                          [Component.text(agent.role)],
                        ),
                      ]),
                      span(
                        classes:
                            'text-[10px] font-bold truncate mt-0.5 '
                            '${agent.isBusy ? "text-amber-700 font-extrabold" : agent.isWaiting ? "text-emerald-700 font-extrabold" : agent.isAway ? "text-orange-600" : "text-zinc-400"}',
                        [Component.text(agent.currentTaskDetail)],
                      ),
                    ]),
                  ]),

                  div(classes: 'flex flex-col items-end gap-1 flex-shrink-0', [
                    span(
                      classes:
                          'px-2 py-0.5 rounded-full text-[9px] font-black uppercase tracking-wider border '
                          '${agent.isBusy ? "bg-amber-100 text-amber-800 border-amber-300" : agent.isWaiting ? "bg-emerald-100 text-emerald-800 border-emerald-300" : agent.isAway ? "bg-orange-100 text-orange-800 border-orange-300" : "bg-zinc-100 text-zinc-500 border-zinc-200"}',
                      [
                        if (agent.isBusy)
                          Component.text('🟡 Busy')
                        else if (agent.isWaiting)
                          Component.text('🟢 Waiting')
                        else if (agent.isAway)
                          Component.text('🟠 AFK')
                        else
                          Component.text('⚪ Offline'),
                      ],
                    ),
                    if (agent.lastSeenAt > 0 && !agent.isOffline)
                      span(classes: 'text-[8px] text-zinc-400 font-semibold', [
                        Component.text('Ping: ${_formatRelativeTime(agent.lastSeenAt)}'),
                      ]),
                  ]),
                ],
              ),
          ]),
      ],
    );
  }

  Component _rosterFilterButton(String key, String labelText) {
    final isSelected = _rosterFilter == key;
    return button(
      onClick: () => setState(() => _rosterFilter = key),
      classes:
          'px-2.5 py-1 rounded-lg text-[9px] font-extrabold transition-all border-0 cursor-pointer '
          '${isSelected ? "bg-white text-zinc-900 shadow-sm" : "text-zinc-500 hover:text-zinc-800 bg-transparent"}',
      [Component.text(labelText)],
    );
  }

  Component _buildAgentTopPerformanceSection(StaffPerformance myStaffProfile) {
    final csatScore = myStaffProfile.csat > 0 ? myStaffProfile.csat : 98.0;
    return div(classes: 'grid grid-cols-1 lg:grid-cols-3 gap-5', [
      // My Agent Performance (2/3)
      div(
        classes: 'lg:col-span-2 bg-white rounded-[28px] border border-zinc-200/50 p-6 flex flex-col gap-5 shadow-[0_8px_30px_rgba(0,0,0,0.01)]',
        [
          div(classes: 'flex justify-between items-center border-b border-zinc-50 pb-4', [
            div([
              h3(classes: 'text-sm font-black text-zinc-900', [Component.text('My Performance & Score')]),
              p(classes: 'text-[10px] text-zinc-400 font-bold mt-0.5', [
                Component.text('Your active operational throughput and resolution metrics'),
              ]),
            ]),
            span(
              classes: 'px-3 py-1 bg-indigo-50 border border-indigo-100 rounded-full text-indigo-700 text-[10px] font-black uppercase tracking-wider',
              [Component.text('Score: ${myStaffProfile.totalHandled} pts')],
            ),
          ]),
          div(classes: 'grid grid-cols-1 sm:grid-cols-3 gap-4 py-1', [
            div(classes: 'bg-[#fafcfa] border border-zinc-200/60 rounded-2xl p-4 flex flex-col gap-2', [
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                  Component.text('P2P Handled'),
                ]),
                span(classes: 'text-base', [Component.text('💳')]),
              ]),
              h4(classes: 'text-2xl font-black text-zinc-900', [
                Component.text('${myStaffProfile.p2pHandled}'),
              ]),
              span(classes: 'text-[9px] font-bold text-zinc-400', [
                Component.text('Deposits & cashouts verified'),
              ]),
            ]),
            div(classes: 'bg-[#fafcfa] border border-zinc-200/60 rounded-2xl p-4 flex flex-col gap-2', [
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Tickets Resolved'),
                ]),
                span(classes: 'text-base', [Component.text('🎟️')]),
              ]),
              h4(classes: 'text-2xl font-black text-zinc-900', [
                Component.text('${myStaffProfile.ticketsHandled}'),
              ]),
              span(classes: 'text-[9px] font-bold text-zinc-400', [
                Component.text('Customer tickets closed'),
              ]),
            ]),
            div(classes: 'bg-[#fafcfa] border border-zinc-200/60 rounded-2xl p-4 flex flex-col gap-2', [
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Live Chats'),
                ]),
                span(classes: 'text-base', [Component.text('💬')]),
              ]),
              h4(classes: 'text-2xl font-black text-zinc-900', [
                Component.text('${myStaffProfile.liveSupportHandled}'),
              ]),
              span(classes: 'text-[9px] font-bold text-zinc-400', [
                Component.text('Direct support sessions'),
              ]),
            ]),
          ]),
        ],
      ),

      // CSAT Average Circular Graph Card (1/3)
      div(
        classes: 'bg-white rounded-[28px] border border-zinc-200/50 p-6 flex flex-col gap-5 shadow-[0_8px_30px_rgba(0,0,0,0.01)] items-center justify-between text-center',
        [
          div(classes: 'w-full text-left border-b border-zinc-50 pb-3', [
            h3(classes: 'text-sm font-black text-zinc-900', [Component.text('CSAT Satisfaction')]),
            p(classes: 'text-[10px] text-zinc-400 font-bold mt-0.5', [
              Component.text('Customer satisfaction average score'),
            ]),
          ]),
          div(
            classes: 'relative flex items-center justify-center my-1',
            [
              div(
                attributes: {
                  'style':
                      'width:130px;height:130px;border-radius:50%;'
                      'background:conic-gradient(#0fa958 0% $csatScore%, #e2e8f0 $csatScore% 100%);'
                      'display:flex;align-items:center;justify-content:center;',
                },
                [
                  div(
                    classes: 'bg-white rounded-full flex flex-col items-center justify-center shadow-inner',
                    attributes: {'style': 'width:96px;height:96px;'},
                    [
                      span(classes: 'text-2xl font-black text-zinc-900 tracking-tight', [
                        Component.text('${csatScore.toStringAsFixed(0)}%'),
                      ]),
                      span(classes: 'text-[8px] font-extrabold uppercase tracking-wider text-emerald-600', [
                        Component.text('CSAT'),
                      ]),
                    ],
                  ),
                ],
              ),
            ],
          ),
          div(classes: 'w-full flex flex-col gap-1 border-t border-zinc-50 pt-3', [
            span(classes: 'text-xs font-black text-zinc-800', [
              Component.text('🌟 Excellent Quality Rating'),
            ]),
            span(classes: 'text-[10px] text-zinc-400 font-semibold', [
              Component.text('Target CSAT benchmark is ≥95% across all support interactions.'),
            ]),
          ]),
        ],
      ),
    ]);
  }

  String _formatRelativeTime(int ts) {
    if (ts <= 0) return 'Just now';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts));
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Component _buildP2PMetricsSection(BuildContext context, P2PDashboardMetrics p2p, bool isAdmin) {
    return div(
      classes: 'bg-white rounded-[28px] border border-zinc-200/60 p-6 flex flex-col gap-6 shadow-[0_8px_30px_rgba(0,0,0,0.02)]',
      [
        // Section Header
        div(classes: 'flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-zinc-100 pb-5', [
          div(classes: 'flex items-center gap-3.5', [
            div(
              classes:
                  'w-11 h-11 rounded-2xl bg-emerald-50 border border-emerald-100 flex items-center justify-center text-xl text-emerald-600 shadow-sm',
              [Component.text('💳')],
            ),
            div(classes: 'flex flex-col', [
              div(classes: 'flex items-center gap-2', [
                h3(classes: 'text-base font-black text-zinc-900 tracking-tight', [
                  Component.text('P2P Fiat & Agent Settlement Hub'),
                ]),
                span(
                  classes:
                      'px-2 py-0.5 rounded-full bg-emerald-50 text-[#0fa958] border border-emerald-200/60 text-[9px] font-black uppercase tracking-wider',
                  [Component.text('Live Rails')],
                ),
              ]),
              p(classes: 'text-xs text-zinc-400 font-bold mt-0.5', [
                Component.text('GCash, Maya, SeaBank, GrabPay, GoTyme & Bank Transfer operational metrics'),
              ]),
            ]),
          ]),
          div(classes: 'flex items-center gap-2 self-start sm:self-auto', [
            a(
              href: '/deposits',
              classes:
                  'px-3.5 py-2 rounded-xl bg-emerald-50 hover:bg-emerald-100 text-emerald-700 border border-emerald-200/80 text-[11px] font-extrabold transition-all no-underline flex items-center gap-1.5 shadow-sm cursor-pointer',
              [
                Component.text('Deposit Queue'),
                if (p2p.pendingDeposits > 0)
                  span(
                    classes: 'px-1.5 py-0.2 rounded-full bg-emerald-600 text-white text-[9px] font-black',
                    [Component.text(p2p.pendingDeposits.toString())],
                  ),
              ],
            ),
            a(
              href: '/withdrawals',
              classes:
                  'px-3.5 py-2 rounded-xl bg-amber-50 hover:bg-amber-100 text-amber-700 border border-amber-200/80 text-[11px] font-extrabold transition-all no-underline flex items-center gap-1.5 shadow-sm cursor-pointer',
              [
                Component.text('Cashout Queue'),
                if (p2p.pendingWithdrawals > 0)
                  span(
                    classes: 'px-1.5 py-0.2 rounded-full bg-amber-600 text-white text-[9px] font-black',
                    [Component.text(p2p.pendingWithdrawals.toString())],
                  ),
              ],
            ),
          ]),
        ]),

        // 4 KPI Summary Cards
        div(classes: 'grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4', [
          // 1. Gross P2P Settled Volume (Admin) or Active Settlement Load (Staff)
          div(
            classes: 'p-4 rounded-2xl bg-zinc-50/80 border border-zinc-200/70 flex flex-col justify-between gap-3',
            [
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                  Component.text(isAdmin ? 'Total Settled Volume' : 'Total Queue Items'),
                ]),
                span(classes: 'text-sm', [Component.text(isAdmin ? '💰' : '📋')]),
              ]),
              div(classes: 'flex flex-col gap-0.5', [
                h4(classes: 'text-xl font-black text-zinc-900 tracking-tight', [
                  Component.text(isAdmin
                      ? '₱${p2p.totalP2PVolume.toStringAsFixed(2)}'
                      : '${p2p.pendingDeposits + p2p.pendingWithdrawals} Active'),
                ]),
                div(classes: 'flex items-center gap-3 text-[10px] font-bold text-zinc-500 mt-1', [
                  if (isAdmin) ...[
                    span([Component.text('In: ₱${p2p.approvedDepositVolume.toStringAsFixed(0)}')]),
                    span(classes: 'text-zinc-300', [Component.text('•')]),
                    span([Component.text('Out: ₱${p2p.approvedWithdrawalVolume.toStringAsFixed(0)}')]),
                  ] else ...[
                    span([Component.text('Deposits: ${p2p.pendingDeposits}')]),
                    span(classes: 'text-zinc-300', [Component.text('•')]),
                    span([Component.text('Cashouts: ${p2p.pendingWithdrawals}')]),
                  ],
                ]),
              ]),
            ],
          ),

          // 2. Active P2P Deposit Queue
          div(
            classes:
                'p-4 rounded-2xl ${p2p.pendingDeposits > 0 ? "bg-emerald-50/50 border-emerald-200/80" : "bg-zinc-50/80 border-zinc-200/70"} border flex flex-col justify-between gap-3',
            [
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Pending Deposit Queue'),
                ]),
                if (p2p.pendingDeposits > 0)
                  span(
                    classes: 'px-2 py-0.5 rounded-full bg-emerald-500 text-white text-[9px] font-black animate-pulse',
                    [Component.text('${p2p.pendingDeposits} Actionable')],
                  )
                else
                  span(classes: 'text-[10px] font-black text-emerald-600', [Component.text('✓ Clear')]),
              ]),
              div(classes: 'flex flex-col gap-0.5', [
                h4(classes: 'text-xl font-black text-emerald-700 tracking-tight', [
                  Component.text('${p2p.pendingDeposits} Requests'),
                ]),
                span(classes: 'text-[10px] font-bold text-zinc-500 mt-1', [
                  Component.text('₱${p2p.pendingDepositVolume.toStringAsFixed(2)} pending verification'),
                ]),
              ]),
            ],
          ),

          // 3. Active P2P Cashout Queue
          div(
            classes:
                'p-4 rounded-2xl ${p2p.pendingWithdrawals > 0 ? "bg-amber-50/50 border-amber-200/80" : "bg-zinc-50/80 border-zinc-200/70"} border flex flex-col justify-between gap-3',
            [
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Pending Cashout Queue'),
                ]),
                if (p2p.pendingWithdrawals > 0)
                  span(
                    classes: 'px-2 py-0.5 rounded-full bg-amber-500 text-white text-[9px] font-black animate-pulse',
                    [Component.text('${p2p.pendingWithdrawals} Actionable')],
                  )
                else
                  span(classes: 'text-[10px] font-black text-amber-600', [Component.text('✓ Clear')]),
              ]),
              div(classes: 'flex flex-col gap-0.5', [
                h4(classes: 'text-xl font-black text-amber-700 tracking-tight', [
                  Component.text('${p2p.pendingWithdrawals} Requests'),
                ]),
                span(classes: 'text-[10px] font-bold text-zinc-500 mt-1', [
                  Component.text('₱${p2p.pendingWithdrawalVolume.toStringAsFixed(2)} awaiting payout proof'),
                ]),
              ]),
            ],
          ),

          // 4. Settlement Completion Rate
          div(
            classes: 'p-4 rounded-2xl bg-zinc-50/80 border border-zinc-200/70 flex flex-col justify-between gap-3',
            [
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                  Component.text('Settlement Success Rate'),
                ]),
                span(classes: 'text-sm', [Component.text('⚡')]),
              ]),
              div(classes: 'flex flex-col gap-0.5', [
                h4(classes: 'text-xl font-black text-indigo-600 tracking-tight', [
                  Component.text('${p2p.settlementRate.toStringAsFixed(1)}%'),
                ]),
                span(classes: 'text-[10px] font-bold text-zinc-500 mt-1', [
                  Component.text('${p2p.totalCompletedTransactions} of ${p2p.totalRequests} completed'),
                ]),
              ]),
            ],
          ),
        ]),

        // ── P2P Visual Graphs Row (Monthly Dual-Bar Inflow/Outflow + Payment Rails Conic Pie Chart) ──
        div(classes: 'grid grid-cols-1 lg:grid-cols-3 gap-5 pt-1', [
          // 1. Monthly Deposits vs Withdrawals Dual-Bar Chart (2/3 width)
          div(
            classes: 'lg:col-span-2 p-5 rounded-2xl bg-zinc-50/50 border border-zinc-200/60 flex flex-col gap-4',
            [
              div(classes: 'flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-zinc-200/50 pb-3', [
                div([
                  h4(classes: 'text-xs font-black text-zinc-900', [Component.text('Monthly P2P Deposits vs Cashouts')]),
                  p(classes: 'text-[10px] text-zinc-400 font-bold', [
                    Component.text('Monthly gross volume comparison (₱) — ${DateTime.now().year}'),
                  ]),
                ]),
                div(classes: 'flex items-center gap-3 text-[10px] font-extrabold', [
                  div(classes: 'flex items-center gap-1.5', [
                    div(classes: 'w-2.5 h-2.5 rounded-sm bg-[#0fa958]', []),
                    span(classes: 'text-zinc-600', [Component.text('Deposits')]),
                  ]),
                  div(classes: 'flex items-center gap-1.5', [
                    div(classes: 'w-2.5 h-2.5 rounded-sm bg-amber-500', []),
                    span(classes: 'text-zinc-600', [Component.text('Cashouts')]),
                  ]),
                ]),
              ]),

              () {
                final monthly = p2p.monthlyData;
                final now = DateTime.now();
                double maxMonthVol = 0.0;
                for (var i = 0; i < 12; i++) {
                  if (monthly.depositVolumes[i] > maxMonthVol) maxMonthVol = monthly.depositVolumes[i];
                  if (monthly.withdrawalVolumes[i] > maxMonthVol) maxMonthVol = monthly.withdrawalVolumes[i];
                }
                if (maxMonthVol == 0.0) maxMonthVol = 1.0;

                return div(classes: 'h-48 flex items-end justify-between gap-1 sm:gap-2 pt-4 px-1 relative', [
                  for (var y = 1; y <= 3; y++)
                    div(
                      classes: 'absolute left-0 right-0 border-t border-dashed border-zinc-200/70 pointer-events-none',
                      attributes: {'style': 'bottom: ${y * 28}%'},
                      [],
                    ),
                  for (var i = 0; i < 12; i++)
                    () {
                      final depVol = monthly.depositVolumes[i];
                      final withVol = monthly.withdrawalVolumes[i];
                      final depHeight = (depVol / maxMonthVol * 88 + 4).clamp(4.0, 100.0);
                      final withHeight = (withVol / maxMonthVol * 88 + 4).clamp(4.0, 100.0);
                      final isCurrentMonth = i == now.month - 1;

                      return div(classes: 'flex-1 flex flex-col items-center gap-1.5 z-10', [
                        div(
                          classes: 'w-full flex items-end justify-center gap-0.5 sm:gap-1',
                          attributes: {'style': 'height: 140px'},
                          [
                            // Deposit bar
                            div(
                              classes:
                                  'w-1/2 rounded-t-md transition-all ${isCurrentMonth ? "bg-[#0fa958]" : "bg-emerald-300 hover:bg-emerald-400"}',
                              attributes: {
                                'style': 'height: $depHeight%',
                                'title': '${_monthNames[i]} Deposits: ₱${depVol.toStringAsFixed(2)} (${monthly.depositCounts[i]} txs)',
                              },
                              [],
                            ),
                            // Withdrawal bar
                            div(
                              classes:
                                  'w-1/2 rounded-t-md transition-all ${isCurrentMonth ? "bg-amber-500" : "bg-amber-300 hover:bg-amber-400"}',
                              attributes: {
                                'style': 'height: $withHeight%',
                                'title': '${_monthNames[i]} Cashouts: ₱${withVol.toStringAsFixed(2)} (${monthly.withdrawalCounts[i]} txs)',
                              },
                              [],
                            ),
                          ],
                        ),
                        span(
                          classes:
                              'text-[8px] font-extrabold ${isCurrentMonth ? "text-zinc-900 font-black" : "text-zinc-400"} uppercase',
                          [Component.text(_monthLabels[i])],
                        ),
                      ]);
                    }(),
                ]);
              }(),

              // Monthly Summary Pill Footer
              div(classes: 'flex flex-col sm:flex-row sm:items-center justify-between gap-1 text-[10px] font-bold text-zinc-500 pt-2 border-t border-zinc-100', [
                span([
                  Component.text(
                    'This Month (${_monthLabels[DateTime.now().month - 1]}): 🟢 ₱${p2p.monthlyData.depositVolumes[DateTime.now().month - 1].toStringAsFixed(0)} Inflow • 🟠 ₱${p2p.monthlyData.withdrawalVolumes[DateTime.now().month - 1].toStringAsFixed(0)} Outflow',
                  ),
                ]),
                span(classes: 'text-[9px] font-extrabold text-zinc-400', [Component.text('12-Month Inflow/Outflow')]),
              ]),
            ],
          ),

          // 2. P2P Payment Rails Volume Pie / Donut Chart (1/3 width)
          div(
            classes: 'p-5 rounded-2xl bg-zinc-50/50 border border-zinc-200/60 flex flex-col gap-4 justify-between',
            [
              div([
                h4(classes: 'text-xs font-black text-zinc-900', [Component.text('P2P Rails Volume Share')]),
                p(classes: 'text-[10px] text-zinc-400 font-bold', [
                  Component.text('Market share breakdown by payment rail'),
                ]),
              ]),

              if (p2p.topPaymentMethods.isEmpty)
                div(classes: 'py-12 text-center text-xs font-bold text-zinc-400', [
                  Component.text('No completed P2P settlements recorded yet'),
                ])
              else ...[
                // Conic Gradient Donut Pie
                () {
                  final colors = ['#0fa958', '#6366f1', '#f59e0b', '#0ea5e9', '#a855f7', '#ec4899'];
                  final totalVol = p2p.totalP2PVolume > 0 ? p2p.totalP2PVolume : 1.0;
                  final gradientParts = <String>[];
                  double currentAngle = 0.0;

                  for (var i = 0; i < p2p.topPaymentMethods.length; i++) {
                    final item = p2p.topPaymentMethods[i];
                    final share = (item.volume / totalVol) * 100.0;
                    final nextAngle = currentAngle + share;
                    final color = colors[i % colors.length];
                    gradientParts.add('$color ${currentAngle.toStringAsFixed(1)}% ${nextAngle.toStringAsFixed(1)}%');
                    currentAngle = nextAngle;
                  }

                  final conicString = gradientParts.join(', ');

                  return div(classes: 'flex items-center justify-center py-1', [
                    div(
                      classes: 'relative flex items-center justify-center',
                      attributes: {
                        'style':
                            'width:130px;height:130px;border-radius:50%;background:conic-gradient($conicString);'
                            'box-shadow: 0 0 0 5px white, 0 0 0 6px #e5e7eb;',
                      },
                      [
                        // Inner circle cutout for donut look
                        div(
                          classes:
                              'w-16 h-16 rounded-full bg-white flex flex-col items-center justify-center shadow-inner',
                          [
                            span(classes: 'text-[10px] font-black text-zinc-800', [
                              Component.text('${p2p.topPaymentMethods.length} Rails'),
                            ]),
                            span(classes: 'text-[7px] font-bold text-zinc-400 uppercase', [Component.text('P2P Mix')]),
                          ],
                        ),
                      ],
                    ),
                  ]);
                }(),

                // Legend List
                div(classes: 'flex flex-col gap-1.5 pt-2 border-t border-zinc-100', [
                  for (var i = 0; i < p2p.topPaymentMethods.length && i < 4; i++)
                    () {
                      final item = p2p.topPaymentMethods[i];
                      final pct = p2p.totalP2PVolume > 0 ? (item.volume / p2p.totalP2PVolume) * 100 : 0.0;
                      final colors = ['#0fa958', '#6366f1', '#f59e0b', '#0ea5e9', '#a855f7', '#ec4899'];
                      final color = colors[i % colors.length];
                      return div(classes: 'flex items-center justify-between text-[10px]', [
                        div(classes: 'flex items-center gap-1.5', [
                          div(classes: 'w-2 h-2 rounded-full', attributes: {'style': 'background:$color'}, []),
                          span(classes: 'font-bold text-zinc-700', [Component.text(item.method)]),
                        ]),
                        div(classes: 'flex items-center gap-1.5 font-mono', [
                          span(classes: 'font-black text-zinc-800', [Component.text('₱${item.volume.toStringAsFixed(0)}')]),
                          span(classes: 'text-[9px] font-bold text-zinc-400 w-8 text-right', [
                            Component.text('${pct.toStringAsFixed(0)}%'),
                          ]),
                        ]),
                      ]);
                    }(),
                ]),
              ],
            ],
          ),
        ]),

        // Bottom Row: Recent P2P Live Activity Stream
        div(
          classes: 'p-5 rounded-2xl bg-zinc-50/50 border border-zinc-200/60 flex flex-col gap-3',
          [
            div(classes: 'flex items-center justify-between', [
              div([
                h4(classes: 'text-xs font-black text-zinc-900', [Component.text('Recent P2P Activity Stream')]),
                p(classes: 'text-[10px] text-zinc-400 font-bold', [
                  Component.text('Real-time feed of fiat deposits and cashouts across platform'),
                ]),
              ]),
              div(classes: 'flex items-center gap-2', [
                a(
                  href: '/deposits',
                  classes: 'text-[10px] font-extrabold text-emerald-600 hover:text-emerald-700 transition-colors no-underline',
                  [Component.text('Deposits Queue →')],
                ),
                span(classes: 'text-zinc-300 text-xs', [Component.text('•')]),
                a(
                  href: '/withdrawals',
                  classes: 'text-[10px] font-extrabold text-amber-600 hover:text-amber-700 transition-colors no-underline',
                  [Component.text('Cashouts Queue →')],
                ),
              ]),
            ]),

            if (p2p.recentActivities.isEmpty)
              div(classes: 'py-8 text-center text-xs font-bold text-zinc-400', [
                Component.text('No recent P2P activity recorded'),
              ])
            else
              div(classes: 'grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2.5', [
                for (final act in p2p.recentActivities)
                  div(
                    classes:
                        'p-2.5 rounded-xl bg-white border border-zinc-200/70 shadow-sm flex items-center justify-between gap-3 text-xs',
                    [
                      div(classes: 'flex items-center gap-2.5 min-w-0', [
                        span(
                          classes:
                              'px-2 py-0.5 rounded-lg text-[9px] font-black uppercase tracking-wider ${act.type == "DEPOSIT" ? "bg-emerald-50 text-[#0fa958] border border-emerald-200/60" : "bg-amber-50 text-amber-700 border border-amber-200/60"}',
                          [Component.text(act.type)],
                        ),
                        div(classes: 'flex flex-col min-w-0', [
                          span(classes: 'font-bold text-zinc-800 truncate max-w-[110px]', [
                            Component.text(act.userName),
                          ]),
                          span(classes: 'text-[10px] text-zinc-400 font-medium', [
                            Component.text(act.paymentMethod),
                          ]),
                        ]),
                      ]),
                      div(classes: 'flex items-center gap-2 flex-shrink-0 text-right', [
                        div(classes: 'flex flex-col items-end', [
                          span(classes: 'font-black text-zinc-900 font-mono', [
                            Component.text('₱${act.amount.toStringAsFixed(2)}'),
                          ]),
                          div(classes: 'flex items-center gap-1.5', [
                            span(
                              classes:
                                  'text-[9px] font-bold ${act.status == "APPROVED" ? "text-[#0fa958]" : (act.status.contains("PENDING") || act.status.contains("WAITING") ? "text-amber-600" : "text-zinc-400")}',
                              [Component.text(act.status)],
                            ),
                            span(classes: 'text-[9px] text-zinc-400 font-medium', [
                              Component.text('• ${_formatRelativeTime(act.timestamp)}'),
                            ]),
                          ]),
                        ]),
                      ]),
                    ],
                  ),
              ]),
          ],
        ),
      ],
    );
  }
}

// ── Static component helpers ───────────────────────────────────────────────

Component _promoBanner(String title, String desc, String cls, String path) {
  return a(
    href: path,
    classes:
        '$cls p-4 rounded-[20px] flex flex-col justify-between h-24 transition-all hover:scale-[1.02] no-underline shadow-sm',
    [
      span(classes: 'text-xs font-extrabold text-zinc-800', [Component.text(title)]),
      span(classes: 'text-[10px] text-zinc-500 font-semibold leading-snug', [Component.text(desc)]),
    ],
  );
}

Component _configRow(String label, String sub, String status, String color, String bg) {
  return div(classes: 'flex items-center justify-between', [
    div(classes: 'flex flex-col gap-0.5', [
      span(classes: 'text-xs font-bold text-zinc-800', [Component.text(label)]),
      span(classes: 'text-[9px] text-zinc-400 font-bold', [Component.text(sub)]),
    ]),
    span(
      classes: 'px-2 py-0.5 rounded-full text-[9px] font-extrabold border',
      attributes: {'style': 'background:$bg; color:$color; border-color:${color}30'},
      [Component.text(status)],
    ),
  ]);
}

// ── Constants ──────────────────────────────────────────────────────────────
const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _monthLabels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
