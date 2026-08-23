import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:riverpod/legacy.dart';

import '../core/providers/environment_provider.dart';

// Navigation tab: 'services', 'vehicles', 'properties'
final bookingsTabProvider = StateProvider<String>((ref) => 'services');
final bookingsPageProvider = StateProvider<int>((ref) => 1);
final bookingsCursorsProvider = StateProvider<List<DocumentSnapshot?>>((ref) => [null]);

// Shared provider for global search integration
final selectedBookingIdProvider = StateProvider<String?>((ref) => null);

class BookingData {
  final String id;
  final String title;
  final String clientName;
  final String providerName;
  final String rateLabel;
  final String status;
  final DateTime createdAt;
  final String icon;
  final Map<String, dynamic> rawData;

  BookingData({
    required this.id,
    required this.title,
    required this.clientName,
    required this.providerName,
    required this.rateLabel,
    required this.status,
    required this.createdAt,
    required this.icon,
    required this.rawData,
  });
}

final paginatedBookingsProvider = FutureProvider<List<BookingData>>((ref) async {
  final firestore = ref.watch(firestoreProvider);
  final tab = ref.watch(bookingsTabProvider);
  final page = ref.watch(bookingsPageProvider);
  final cursors = ref.watch(bookingsCursorsProvider);

  final cursor = cursors[page - 1];
  final limitAmount = 10;

  if (tab == 'vehicles') {
    var query = firestore.collection('rental_requests').orderBy('createdAt', descending: true).limit(limitAmount);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await query.get().timeout(const Duration(seconds: 4));
    } catch (e) {
      print('[Bookings] Vehicles load failed/timed out: $e');
      return <BookingData>[];
    }
    return snap.docs.map((doc) {
      final data = doc.data();
      final total = (data['totalCost'] as num?)?.toDouble() ?? 0.0;
      final mult = data['multiplier'] ?? 1;
      final dur = data['durationType'] ?? 'day';
      return BookingData(
        id: doc.id,
        title: '${data['brand'] ?? ''} ${data['model'] ?? 'Vehicle'}'.trim(),
        clientName: data['renteeName'] ?? 'Renter',
        providerName: data['hostId'] ?? 'Host',
        rateLabel: '₱${total.toStringAsFixed(2)} ($mult $dur)',
        status: data['status'] ?? 'Pending',
        createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
        icon: '🚗',
        rawData: data,
      );
    }).toList();
  } else if (tab == 'properties') {
    var query = firestore.collection('property_requests').orderBy('createdAt', descending: true).limit(limitAmount);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await query.get().timeout(const Duration(seconds: 4));
    } catch (e) {
      print('[Bookings] Properties load failed/timed out: $e');
      return <BookingData>[];
    }
    return snap.docs.map((doc) {
      final data = doc.data();
      final total = (data['totalCost'] as num?)?.toDouble() ?? 0.0;
      final mult = data['multiplier'] ?? 1;
      final dur = data['durationType'] ?? 'month';
      return BookingData(
        id: doc.id,
        title: data['title'] ?? 'Property',
        clientName: data['renteeName'] ?? 'Renter',
        providerName: data['hostId'] ?? 'Host',
        rateLabel: '₱${total.toStringAsFixed(2)} ($mult $dur)',
        status: data['status'] ?? 'Pending',
        createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
        icon: '🏠',
        rawData: data,
      );
    }).toList();
  } else {
    // Services
    var query = firestore.collectionGroup('applications').orderBy('createdAt', descending: true).limit(limitAmount);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await query.get().timeout(const Duration(seconds: 4));
    } catch (e) {
      print('[Bookings] Services applications load failed/timed out: $e');
      return <BookingData>[];
    }
    return snap.docs.map((doc) {
      final data = doc.data();
      final rate = (data['proposalRate'] as num?)?.toDouble() ?? 0.0;
      return BookingData(
        id: doc.id,
        title: 'Job Bid Application',
        clientName: data['applicantName'] ?? 'Applicant',
        providerName: 'Job #${data['jobId'] ?? ''}',
        rateLabel: '₱${rate.toStringAsFixed(2)}',
        status: data['status'] ?? 'Pending',
        createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
        icon: '💼',
        rawData: data,
      );
    }).toList();
  }
});

class BookingsPage extends StatefulComponent {
  const BookingsPage({super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  // Search and filter inputs
  String _searchQuery = '';
  String _locationFilter = '';
  String _statusFilter = ''; // Pending, Approved, Completed, Cancelled
  double? _priceMin;
  double? _priceMax;

  // Single booking detailed view state
  BookingData? _detailsModalItem;

  @override
  Component build(BuildContext context) {
    final activeTab = context.watch(bookingsTabProvider);
    final currentPage = context.watch(bookingsPageProvider);
    final bookingsAsync = context.watch(paginatedBookingsProvider);
    final selectedGlobalId = context.watch(selectedBookingIdProvider);

    // Watch dynamic global search click and fetch detail item if matching
    if (selectedGlobalId != null && _detailsModalItem?.id != selectedGlobalId) {
      final firestore = context.read(firestoreProvider);

      Future<DocumentSnapshot<Map<String, dynamic>>?> getDoc() async {
        if (activeTab == 'vehicles') {
          return await firestore.collection('rental_requests').doc(selectedGlobalId).get();
        } else if (activeTab == 'properties') {
          return await firestore.collection('property_requests').doc(selectedGlobalId).get();
        } else {
          final group = await firestore.collectionGroup('applications').get();
          try {
            return group.docs.firstWhere((d) => d.id == selectedGlobalId);
          } catch (_) {
            return null;
          }
        }
      }

      getDoc().then((doc) {
        if (doc != null && doc.exists && mounted) {
          final data = doc.data()!;
          BookingData item;
          if (activeTab == 'vehicles') {
            final total = (data['totalCost'] as num?)?.toDouble() ?? 0.0;
            item = BookingData(
              id: doc.id,
              title: '${data['brand'] ?? ''} ${data['model'] ?? 'Vehicle'}'.trim(),
              clientName: data['renteeName'] ?? 'Renter',
              providerName: data['hostId'] ?? 'Host',
              rateLabel: '₱${total.toStringAsFixed(2)}',
              status: data['status'] ?? 'Pending',
              createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
              icon: '🚗',
              rawData: data,
            );
          } else if (activeTab == 'properties') {
            final total = (data['totalCost'] as num?)?.toDouble() ?? 0.0;
            item = BookingData(
              id: doc.id,
              title: data['title'] ?? 'Property',
              clientName: data['renteeName'] ?? 'Renter',
              providerName: data['hostId'] ?? 'Host',
              rateLabel: '₱${total.toStringAsFixed(2)}',
              status: data['status'] ?? 'Pending',
              createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
              icon: '🏠',
              rawData: data,
            );
          } else {
            final rate = (data['proposalRate'] as num?)?.toDouble() ?? 0.0;
            item = BookingData(
              id: doc.id,
              title: 'Job Bid Application',
              clientName: data['applicantName'] ?? 'Applicant',
              providerName: 'Job #${data['jobId'] ?? ''}',
              rateLabel: '₱${rate.toStringAsFixed(2)}',
              status: data['status'] ?? 'Pending',
              createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
              icon: '💼',
              rawData: data,
            );
          }
          setState(() {
            _detailsModalItem = item;
          });
        }
      });
    }

    Component buildTabButton(String label, String value) {
      final isActive = activeTab == value;
      return button(
        onClick: () {
          context.read(bookingsTabProvider.notifier).state = value;
          context.read(bookingsPageProvider.notifier).state = 1;
          context.read(bookingsCursorsProvider.notifier).state = [null];
          // Clear filters on tab change
          setState(() {
            _searchQuery = '';
            _statusFilter = '';
            _priceMin = null;
            _priceMax = null;
          });
        },
        classes:
            'px-5 py-2 text-xs font-bold transition-all duration-200 '
            '${isActive ? 'bg-black text-white rounded-full shadow-md shadow-black/10' : 'text-zinc-500 hover:text-zinc-900'}',
        [Component.text(label)],
      );
    }

    // Helper to extract location string for bookings
    String getDisplayLocation(Map<String, dynamic> raw) {
      final loc =
          raw['location'] ??
          raw['address'] ??
          raw['city'] ??
          raw['destination'] ??
          raw['jobLocation'] ??
          raw['province'];
      if (loc is Map) {
        final address = loc['address'] ?? loc['name'] ?? '';
        final city = loc['city'] ?? '';
        final province = loc['province'] ?? '';
        final parts = [address, city, province].map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        if (parts.isNotEmpty) {
          return parts.join(', ');
        }
        return 'Philippines';
      }
      if (loc != null && loc.toString().isNotEmpty) {
        return loc.toString();
      }
      return 'Philippines';
    }

    String formatDate(int ms) {
      if (ms == 0) return 'N/A';
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0] relative', [
      // Details Modal Overlay
      if (_detailsModalItem != null)
        div(
          classes:
              'fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4 animate-fade-in',
          events: {
            'click': (e) {
              context.read(selectedBookingIdProvider.notifier).state = null;
              setState(() => _detailsModalItem = null);
            },
          },
          [
            div(
              classes: 'bg-white rounded-[28px] max-w-xl w-full max-h-[85vh] overflow-y-auto p-7 shadow-2xl flex flex-col gap-5 border border-zinc-200/50 transform scale-100 transition-all',
              events: {
                'click': (e) {
                  e.stopPropagation();
                },
              },
              [
                // Modal Header
                div(classes: 'flex items-start justify-between border-b border-zinc-100 pb-4', [
                  div(classes: 'flex items-center gap-3', [
                    span(classes: 'text-2xl p-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-2xl', [
                      Component.text(_detailsModalItem!.icon),
                    ]),
                    div(classes: 'flex flex-col', [
                      h2(classes: 'text-base font-black text-zinc-900 leading-tight', [
                        Component.text(_detailsModalItem!.title),
                      ]),
                      span(classes: 'text-[9px] text-zinc-400 font-mono mt-0.5', [
                        Component.text('Booking ID: ${_detailsModalItem!.id}'),
                      ]),
                    ]),
                  ]),
                  button(
                    onClick: () {
                      context.read(selectedBookingIdProvider.notifier).state = null;
                      setState(() => _detailsModalItem = null);
                    },
                    classes: 'w-7 h-7 rounded-full bg-zinc-100 text-zinc-500 font-bold hover:bg-zinc-200 text-xs flex items-center justify-center',
                    [Component.text('✕')],
                  ),
                ]),

                // Modal Content
                div(classes: 'flex flex-col gap-4 text-xs text-zinc-700', [
                  // Row 1: Status & Rates
                  div(classes: 'grid grid-cols-2 gap-4', [
                    div(classes: 'bg-[#f8faf9] p-3.5 rounded-2xl border border-zinc-200/20', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Deal Parameters'),
                      ]),
                      p(classes: 'text-sm font-black text-zinc-900 mt-1', [
                        Component.text(_detailsModalItem!.rateLabel),
                      ]),
                    ]),
                    div(classes: 'bg-[#f8faf9] p-3.5 rounded-2xl border border-zinc-200/20', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Transaction Status'),
                      ]),
                      div(classes: 'mt-1.5', [
                        span(
                          classes:
                              'px-3 py-1 rounded-full text-[9px] font-extrabold border '
                              '${_detailsModalItem!.status == 'Approved' || _detailsModalItem!.status == 'Completed' || _detailsModalItem!.status == 'Active'
                                  ? 'bg-[#e2f1e9] text-[#0fa958] border-emerald-500/10'
                                  : _detailsModalItem!.status == 'Pending'
                                  ? 'bg-amber-50 text-amber-500 border-amber-500/10'
                                  : 'bg-zinc-100 text-zinc-500 border-zinc-200'}',
                          [Component.text(_detailsModalItem!.status.toUpperCase())],
                        ),
                      ]),
                    ]),
                  ]),

                  // Row 2: Parties Involved
                  div(classes: 'grid grid-cols-2 gap-4', [
                    div(classes: 'flex flex-col gap-1', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Client / Renter'),
                      ]),
                      p(classes: 'font-bold text-zinc-900', [Component.text(_detailsModalItem!.clientName)]),
                      span(classes: 'text-[9px] text-zinc-400 font-mono', [
                        Component.text(
                          'ID: ${_detailsModalItem!.rawData['renteeId'] ?? _detailsModalItem!.rawData['applicantId'] ?? 'N/A'}',
                        ),
                      ]),
                    ]),
                    div(classes: 'flex flex-col gap-1', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Provider / Host'),
                      ]),
                      p(classes: 'font-bold text-zinc-900', [
                        Component.text(
                          _detailsModalItem!.providerName.startsWith('Job #')
                              ? 'Job Listing Host'
                              : _detailsModalItem!.providerName,
                        ),
                      ]),
                      span(classes: 'text-[9px] text-zinc-400 font-mono', [
                        Component.text(
                          'ID: ${_detailsModalItem!.rawData['hostId'] ?? _detailsModalItem!.rawData['jobId'] ?? 'N/A'}',
                        ),
                      ]),
                    ]),
                  ]),

                  // Time parameters
                  div(classes: 'flex flex-col gap-2 border-t border-zinc-100 pt-3', [
                    span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                      Component.text('Schedule & Timeline'),
                    ]),
                    div(
                      classes: 'grid grid-cols-2 gap-2 bg-[#f8faf9] p-3 rounded-xl border border-zinc-200/20 text-[11px] font-medium text-zinc-650',
                      [
                        if (activeTab == 'vehicles' || activeTab == 'properties') ...[
                          span([
                            Component.text(
                              'Start Date: ${formatDate(_detailsModalItem!.rawData['startDate'] ?? _detailsModalItem!.rawData['rentStart'] ?? 0)}',
                            ),
                          ]),
                          span([
                            Component.text(
                              'End Date: ${formatDate(_detailsModalItem!.rawData['endDate'] ?? _detailsModalItem!.rawData['rentEnd'] ?? 0)}',
                            ),
                          ]),
                          span([
                            Component.text(
                              'Duration: ${_detailsModalItem!.rawData['multiplier'] ?? 1} ${_detailsModalItem!.rawData['durationType'] ?? 'units'}',
                            ),
                          ]),
                          span([
                            Component.text('Booked At: ${formatDate(_detailsModalItem!.rawData['createdAt'] ?? 0)}'),
                          ]),
                        ] else ...[
                          span([
                            Component.text(
                              'Bid Rate: ₱${(_detailsModalItem!.rawData['proposalRate'] ?? 0).toString()}',
                            ),
                          ]),
                          span([
                            Component.text('Work Estimate: ${_detailsModalItem!.rawData['deliveryTime'] ?? 'N/A'}'),
                          ]),
                          span([
                            Component.text('Applied At: ${formatDate(_detailsModalItem!.rawData['createdAt'] ?? 0)}'),
                          ]),
                          span([
                            Component.text(
                              'Cover Note: ${_detailsModalItem!.rawData['coverLetter'] ?? 'None provided'}',
                            ),
                          ]),
                        ],
                      ],
                    ),
                  ]),

                  // Financial Breakdown & Promotion Reconciliation
                  (() {
                    final raw = _detailsModalItem!.rawData;
                    final totalCost =
                        (raw['totalCost'] as num?)?.toDouble() ?? (raw['proposalRate'] as num?)?.toDouble() ?? 0.0;
                    final platformFee = (raw['platformFee'] as num?)?.toDouble() ?? (totalCost * 0.10);
                    final listingPrice =
                        (raw['basePrice'] as num?)?.toDouble() ??
                        (raw['listingPrice'] as num?)?.toDouble() ??
                        (totalCost - platformFee > 0 ? totalCost - platformFee : totalCost);
                    final promoCode = raw['promoCode'] as String? ?? raw['promotion'] as String?;
                    final promoDiscount =
                        (raw['promoDiscount'] as num?)?.toDouble() ??
                        (raw['discountAmount'] as num?)?.toDouble() ??
                        0.0;
                    final finalPlatformFee = (platformFee - promoDiscount).clamp(0.0, platformFee);
                    final customerPaid = listingPrice + finalPlatformFee;
                    final providerSettlement = listingPrice;

                    return div(classes: 'flex flex-col gap-2 border-t border-zinc-100 pt-3', [
                      div(classes: 'flex items-center justify-between', [
                        span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                          Component.text('Financial Reconciliation Breakdown'),
                        ]),
                        span(classes: 'text-[9px] font-bold text-emerald-600', [
                          Component.text('🛡️ Base Price Protected'),
                        ]),
                      ]),
                      div(
                        classes: 'bg-zinc-50 p-3 rounded-xl border border-zinc-200/40 flex flex-col gap-1.5 text-xs',
                        [
                          div(classes: 'flex justify-between text-zinc-800 font-semibold', [
                            span([Component.text('Listing Price (Provider Base):')]),
                            span([Component.text('₱${listingPrice.toStringAsFixed(2)}')]),
                          ]),
                          div(classes: 'flex justify-between text-zinc-600', [
                            span([Component.text('Original TRANYX Platform Fee:')]),
                            span([Component.text('₱${platformFee.toStringAsFixed(2)}')]),
                          ]),
                          if (promoCode != null && promoCode.isNotEmpty) ...[
                            div(
                              classes: 'flex justify-between text-emerald-600 font-bold bg-emerald-50/70 p-1.5 rounded',
                              [
                                span([Component.text('Promo ($promoCode) Fee Waiver:')]),
                                span([Component.text('-₱${promoDiscount.toStringAsFixed(2)}')]),
                              ],
                            ),
                            div(classes: 'flex justify-between text-zinc-500 font-medium', [
                              span([Component.text('Final Platform Fee Collected:')]),
                              span([Component.text('₱${finalPlatformFee.toStringAsFixed(2)}')]),
                            ]),
                          ],
                          div(
                            classes: 'flex justify-between text-zinc-900 font-black border-t border-zinc-200/50 pt-1.5',
                            [
                              span([Component.text('Customer Total Paid:')]),
                              span(classes: 'text-indigo-600', [Component.text('₱${customerPaid.toStringAsFixed(2)}')]),
                            ],
                          ),
                          div(
                            classes: 'flex justify-between text-emerald-800 font-black bg-emerald-50 p-1.5 rounded-lg border border-emerald-100 mt-1',
                            [
                              span([Component.text('Provider Settlement (100% Unchanged):')]),
                              span([Component.text('₱${providerSettlement.toStringAsFixed(2)}')]),
                            ],
                          ),
                        ],
                      ),
                    ]);
                  })(),

                  // Blockchain signature if available
                  if (_detailsModalItem!.rawData['signature'] != null || _detailsModalItem!.rawData['txHash'] != null)
                    div(classes: 'flex flex-col gap-1 border-t border-zinc-100 pt-3', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Escrow Transaction Signature'),
                      ]),
                      p(
                        classes: 'font-mono text-[10px] text-indigo-500 font-bold bg-zinc-50 p-2.5 rounded-lg border border-zinc-200/30 break-all',
                        [
                          Component.text(
                            (_detailsModalItem!.rawData['signature'] ?? _detailsModalItem!.rawData['txHash'])
                                .toString(),
                          ),
                        ],
                      ),
                    ]),
                ]),

                // Modal Footer
                div(classes: 'flex justify-end items-center border-t border-zinc-100 pt-4 mt-2', [
                  button(
                    onClick: () {
                      context.read(selectedBookingIdProvider.notifier).state = null;
                      setState(() => _detailsModalItem = null);
                    },
                    classes: 'px-4 py-2 bg-zinc-200 hover:bg-zinc-300 text-zinc-800 text-[10px] font-extrabold tracking-wide uppercase rounded-xl transition-all',
                    [Component.text('Close')],
                  ),
                ]),
              ],
            ),
          ],
        ),

      // Modern Header block
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [Component.text('Bookings & Requests')]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text('Review active transaction agreements and job applications.'),
          ]),
        ]),
        // Tabs styled in capsules
        div(classes: 'flex items-center gap-1 bg-white p-1 border border-zinc-200/50 rounded-full shadow-sm', [
          buildTabButton('💼 Services', 'services'),
          buildTabButton('🚗 Vehicles', 'vehicles'),
          buildTabButton('🏠 Real Estate', 'properties'),
        ]),
      ]),

      // Search & Filters Panel (Independent for bookings)
      div(
        classes: 'w-full bg-white border border-zinc-200/50 rounded-[24px] p-5 shadow-[0_4px_20px_rgba(0,0,0,0.01)] flex flex-col gap-4',
        [
          // Title / Info row
          div(classes: 'flex items-center justify-between', [
            h3(classes: 'text-[11px] font-extrabold text-zinc-400 uppercase tracking-wider', [
              Component.text('Booking Parameters Filter'),
            ]),
            if (_searchQuery.isNotEmpty ||
                _locationFilter.isNotEmpty ||
                _statusFilter.isNotEmpty ||
                _priceMin != null ||
                _priceMax != null)
              button(
                onClick: () => setState(() {
                  _searchQuery = '';
                  _locationFilter = '';
                  _statusFilter = '';
                  _priceMin = null;
                  _priceMax = null;
                }),
                classes: 'text-[10px] font-bold text-indigo-500 hover:underline',
                [Component.text('Clear Active Filters')],
              ),
          ]),

          // Input Grid
          div(classes: 'grid grid-cols-1 md:grid-cols-5 gap-3.5', [
            // Search Input
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wide', [
                Component.text('Search Keywords'),
              ]),
              input(
                value: _searchQuery,
                onInput: (v) => setState(() => _searchQuery = v as String),
                classes: 'px-4 py-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-xl text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black/10',
                attributes: {'placeholder': 'Search client, provider...'},
              ),
            ]),
            // Location Input
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wide', [
                Component.text('Location'),
              ]),
              input(
                value: _locationFilter,
                onInput: (v) => setState(() => _locationFilter = v as String),
                classes: 'px-4 py-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-xl text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black/10',
                attributes: {'placeholder': 'e.g. Metro Manila'},
              ),
            ]),
            // Status Dropdown
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wide', [
                Component.text('Booking Status'),
              ]),
              select(
                classes: 'px-4 py-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-xl text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black/10',
                onChange: (v) => setState(() => _statusFilter = v.isNotEmpty ? v.first : ''),
                [
                  option(value: '', selected: _statusFilter == '', [Component.text('ALL STATUSES')]),
                  option(value: 'pending', selected: _statusFilter == 'pending', [Component.text('PENDING')]),
                  option(value: 'approved', selected: _statusFilter == 'approved', [Component.text('APPROVED')]),
                  option(value: 'completed', selected: _statusFilter == 'completed', [Component.text('COMPLETED')]),
                  option(value: 'cancelled', selected: _statusFilter == 'cancelled', [Component.text('CANCELLED')]),
                ],
              ),
            ]),
            // Min Price
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wide', [
                Component.text('Min Total (₱)'),
              ]),
              input(
                value: _priceMin?.toString() ?? '',
                onInput: (v) => setState(() => _priceMin = double.tryParse(v as String)),
                classes: 'px-4 py-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-xl text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black/10',
                attributes: {'placeholder': '0', 'type': 'number'},
              ),
            ]),
            // Max Price
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wide', [
                Component.text('Max Total (₱)'),
              ]),
              input(
                value: _priceMax?.toString() ?? '',
                onInput: (v) => setState(() => _priceMax = double.tryParse(v as String)),
                classes: 'px-4 py-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-xl text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black/10',
                attributes: {'placeholder': '999999', 'type': 'number'},
              ),
            ]),
          ]),
        ],
      ),

      // Main Table Card
      bookingsAsync.when(
        data: (bookings) {
          // Perform high-fidelity client-side filtering on paginated batch
          final filteredBookings = bookings.where((item) {
            // Keyword filter (recursively searches all properties)
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              bool checkValue(dynamic val) {
                if (val == null) return false;
                if (val is String) {
                  return val.toLowerCase().contains(q);
                }
                if (val is num || val is bool) {
                  return val.toString().toLowerCase().contains(q);
                }
                if (val is List) {
                  return val.any(checkValue);
                }
                if (val is Map) {
                  return val.values.any(checkValue);
                }
                return false;
              }

              final matchesTitle = item.title.toLowerCase().contains(q);
              final matchesClient = item.clientName.toLowerCase().contains(q);
              final matchesProvider = item.providerName.toLowerCase().contains(q);
              final matchesId = item.id.toLowerCase().contains(q);
              final matchesDeep = checkValue(item.rawData);

              if (!matchesTitle && !matchesClient && !matchesProvider && !matchesId && !matchesDeep) return false;
            }
            // Location filter
            if (_locationFilter.isNotEmpty) {
              final loc = getDisplayLocation(item.rawData).toLowerCase();
              if (!loc.contains(_locationFilter.toLowerCase())) return false;
            }
            // Status filter
            if (_statusFilter.isNotEmpty) {
              if (item.status.toLowerCase() != _statusFilter.toLowerCase()) return false;
            }
            // Min/Max Price filter
            final total =
                (item.rawData['totalCost'] as num?)?.toDouble() ??
                (item.rawData['proposalRate'] as num?)?.toDouble() ??
                0.0;
            if (_priceMin != null && total < _priceMin!) return false;
            if (_priceMax != null && total > _priceMax!) return false;

            return true;
          }).toList();

          if (filteredBookings.isEmpty) {
            return div(
              classes: 'flex-grow flex flex-col items-center justify-center text-center p-16 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
              [
                span(classes: 'text-3xl mb-3', [Component.text('📂')]),
                h3(classes: 'text-sm font-bold text-zinc-900', [Component.text('No bookings match criteria')]),
                p(classes: 'text-xs text-zinc-500 mt-1', [
                  Component.text('Adjust or clear your active query filters above.'),
                ]),
              ],
            );
          }

          return div(classes: 'flex flex-col gap-6', [
            div(
              classes: 'overflow-x-auto w-full rounded-[28px] border border-zinc-200/50 bg-white shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
              [
                table(classes: 'w-full text-left text-xs border-collapse', [
                  thead(
                    classes: 'bg-[#f8faf9] text-zinc-500 font-bold border-b border-zinc-100 text-[10px] uppercase tracking-wider',
                    [
                      tr([
                        th(classes: 'p-5', [Component.text('Target Asset')]),
                        th(classes: 'p-5', [Component.text('Renter / Applicant')]),
                        th(classes: 'p-5', [Component.text('Provider / Destination')]),
                        th(classes: 'p-5', [Component.text('Location')]),
                        th(classes: 'p-5', [Component.text('Deal Parameters')]),
                        th(classes: 'p-5 text-center', [Component.text('Status')]),
                        th(classes: 'p-5 text-right', [Component.text('Created')]),
                      ]),
                    ],
                  ),
                  tbody(classes: 'divide-y divide-zinc-50', [
                    for (final item in filteredBookings)
                      tr(
                        classes: 'hover:bg-[#fcfdfc] transition-colors cursor-pointer',
                        events: {
                          'click': (e) {
                            setState(() => _detailsModalItem = item);
                          },
                        },
                        [
                          td(classes: 'p-5 font-bold text-zinc-900 flex items-center gap-3', [
                            span(classes: 'text-lg p-2 bg-[#f3f6f4] border border-zinc-200/50 rounded-xl', [
                              Component.text(item.icon),
                            ]),
                            div(classes: 'flex flex-col gap-0.5 min-w-0', [
                              span(
                                classes: 'truncate font-bold text-zinc-800 hover:text-indigo-600 transition-colors',
                                [Component.text(item.title)],
                              ),
                              span(classes: 'text-[9px] text-zinc-400 font-mono', [Component.text('ID: ${item.id}')]),
                            ]),
                          ]),
                          td(classes: 'p-5 text-zinc-650 font-semibold', [Component.text(item.clientName)]),
                          td(classes: 'p-5 text-zinc-650 font-medium', [
                            Component.text(
                              item.providerName.startsWith('Job #') ? 'Job Posting Host' : item.providerName,
                            ),
                          ]),
                          td(classes: 'p-5 text-zinc-650 font-medium', [
                            Component.text(getDisplayLocation(item.rawData)),
                          ]),
                          td(classes: 'p-5 font-extrabold text-zinc-900', [Component.text(item.rateLabel)]),
                          td(classes: 'p-5 text-center', [
                            span(
                              classes:
                                  'px-3 py-1 rounded-full text-[9px] font-extrabold border '
                                  '${item.status == 'Approved' || item.status == 'Completed' || item.status == 'Active'
                                      ? 'bg-[#e2f1e9] text-[#0fa958] border-emerald-500/10'
                                      : item.status == 'Pending'
                                      ? 'bg-amber-50 text-amber-500 border-amber-500/10'
                                      : 'bg-zinc-100 text-zinc-500 border-zinc-200'}',
                              [Component.text(item.status.toUpperCase())],
                            ),
                          ]),
                          td(classes: 'p-5 text-right text-zinc-400 font-medium', [
                            Component.text(
                              '${item.createdAt.year}-${item.createdAt.month.toString().padLeft(2, '0')}-${item.createdAt.day.toString().padLeft(2, '0')}',
                            ),
                          ]),
                        ],
                      ),
                  ]),
                ]),
              ],
            ),

            // Pagination Pill Controls
            div(classes: 'flex justify-between items-center px-4', [
              span(classes: 'text-[11px] text-zinc-400 font-semibold', [Component.text('PAGE $currentPage')]),
              div(classes: 'flex items-center gap-2', [
                button(
                  disabled: currentPage == 1,
                  onClick: () {
                    if (currentPage > 1) {
                      context.read(bookingsPageProvider.notifier).state = currentPage - 1;
                    }
                  },
                  classes:
                      'px-4 py-2 rounded-full border border-zinc-200 text-[10px] font-extrabold tracking-wide uppercase transition-all duration-200 '
                      '${currentPage == 1 ? 'opacity-40 cursor-not-allowed text-zinc-400' : 'bg-white text-zinc-800 hover:bg-zinc-50 shadow-sm'}',
                  [Component.text('PREVIOUS')],
                ),
                button(
                  disabled: bookings.length < 10,
                  onClick: () async {
                    final firestore = context.read(firestoreProvider);
                    final tab = context.read(bookingsTabProvider);
                    final cursors = context.read(bookingsCursorsProvider);

                    final lastItem = bookings.last;
                    DocumentSnapshot docRef;

                    if (tab == 'vehicles') {
                      docRef = await firestore.collection('rental_requests').doc(lastItem.id).get();
                    } else if (tab == 'properties') {
                      docRef = await firestore.collection('property_requests').doc(lastItem.id).get();
                    } else {
                      final jobDocs = await firestore.collectionGroup('applications').get();
                      docRef = jobDocs.docs.firstWhere((d) => d.id == lastItem.id);
                    }

                    context.read(bookingsCursorsProvider.notifier).state = [...cursors, docRef];
                    context.read(bookingsPageProvider.notifier).state = currentPage + 1;
                  },
                  classes:
                      'px-4 py-2 rounded-full border border-zinc-200 text-[10px] font-extrabold tracking-wide uppercase transition-all duration-200 '
                      '${bookings.length < 10 ? 'opacity-40 cursor-not-allowed text-zinc-400' : 'bg-white text-zinc-800 hover:bg-zinc-50 shadow-sm'}',
                  [Component.text('NEXT')],
                ),
              ]),
            ]),
          ]);
        },
        loading: () => div(
          classes: 'flex-grow flex justify-center items-center py-20 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
          [div(classes: 'animate-spin h-6 w-6 border-2 border-zinc-200 border-t-indigo-500 rounded-full', [])],
        ),
        error: (err, _) => div(
          classes: 'p-6 bg-red-50/5 border border-red-500/10 text-red-500 text-xs rounded-[20px] font-mono shadow-sm',
          [Component.text('Error loading bookings: $err')],
        ),
      ),
    ]);
  }
}
