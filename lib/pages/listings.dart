import 'package:firebase_auth/firebase_auth.dart';
import 'package:web/web.dart' as web;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:riverpod/legacy.dart';

import '../core/providers/environment_provider.dart';

// Navigation tab: 'services', 'vehicles', 'properties'
final listingsTabProvider = StateProvider<String>((ref) => 'services');
final listingsPageProvider = StateProvider<int>((ref) => 1);
final listingsCursorsProvider = StateProvider<List<DocumentSnapshot?>>((ref) => [null]);

// Shared provider for global search integration
final selectedListingIdProvider = StateProvider<String?>((ref) => null);

class QnaMessage {
  final String id;
  final String senderName;
  final String text;
  final int createdAt;
  final String? reply;

  QnaMessage({required this.id, required this.senderName, required this.text, required this.createdAt, this.reply});

  factory QnaMessage.fromMap(String id, Map<String, dynamic> map) {
    return QnaMessage(
      id: id,
      senderName: map['senderName'] ?? map['userName'] ?? 'User',
      text: map['text'] ?? map['question'] ?? '',
      createdAt: map['createdAt'] ?? 0,
      reply: map['reply'] ?? map['answer'],
    );
  }
}

final listingQnaStreamProvider = StreamProvider.family<List<QnaMessage>, (String, String)>((ref, arg) {
  final firestore = ref.watch(firestoreProvider);
  final (colName, listingId) = arg;
  return firestore
      .collection(colName)
      .doc(listingId)
      .collection('qna')
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map((snap) {
        if (snap.docs.isEmpty) {
          // Fallback mock questions for UAT and UAT demo board
          return [
            QnaMessage(
              id: 'mock_1',
              senderName: 'Michael Tan',
              text: 'Is this rate negotiable for long-term hires?',
              createdAt: DateTime.now().subtract(const Duration(hours: 12)).millisecondsSinceEpoch,
              reply: 'Yes, we offer special discounts for durations exceeding 15 days.',
            ),
            QnaMessage(
              id: 'mock_2',
              senderName: 'Sophia Reyes',
              text: 'Are pets allowed in the vehicle/property?',
              createdAt: DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
            ),
          ];
        }
        return snap.docs.map((d) => QnaMessage.fromMap(d.id, d.data())).toList();
      })
      .handleError((_) => <QnaMessage>[]);
});

class ListingData {
  final String id;
  final String title;
  final String owner;
  final String priceLabel;
  final String status;
  final DateTime createdAt;
  final String icon;
  final int reportCount;
  final List<dynamic> reports;
  final Map<String, dynamic> rawData;

  ListingData({
    required this.id,
    required this.title,
    required this.owner,
    required this.priceLabel,
    required this.status,
    required this.createdAt,
    required this.icon,
    required this.reportCount,
    required this.reports,
    required this.rawData,
  });
}

final paginatedListingsProvider = FutureProvider<List<ListingData>>((ref) async {
  final firestore = ref.watch(firestoreProvider);
  final tab = ref.watch(listingsTabProvider);
  final page = ref.watch(listingsPageProvider);
  final cursors = ref.watch(listingsCursorsProvider);

  final cursor = cursors[page - 1];
  final limitAmount = 10;

  String collectionName;
  if (tab == 'vehicles') {
    collectionName = 'rentals';
  } else if (tab == 'properties') {
    collectionName = 'properties';
  } else {
    collectionName = 'jobs';
  }

  var query = firestore.collection(collectionName).orderBy('createdAt', descending: true).limit(limitAmount);

  if (cursor != null) {
    query = query.startAfterDocument(cursor);
  }

  QuerySnapshot<Map<String, dynamic>> snap;
  try {
    snap = await query.get().timeout(const Duration(seconds: 4));
  } catch (e) {
    print('[Listings] Query failed or timed out: $e');
    return <ListingData>[];
  }

  return snap.docs.map((doc) {
    final data = doc.data();
    final reportsList = data['reports'] as List? ?? [];
    final reportsCount =
        data['reportCount'] as int? ?? (data['reports'] != null ? (data['reports'] as List).length : 0);

    if (tab == 'vehicles') {
      final brand = data['brand'] ?? '';
      final model = data['model'] ?? '';
      final price = (data['priceDaily'] as num?)?.toDouble() ?? 0.0;
      return ListingData(
        id: doc.id,
        title: '$brand $model'.trim(),
        owner: data['hostName'] ?? 'Host',
        priceLabel: '₱${price.toStringAsFixed(2)}/day',
        status: data['status'] ?? 'Available',
        createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
        icon: '🚗',
        reportCount: reportsCount,
        reports: reportsList,
        rawData: data,
      );
    } else if (tab == 'properties') {
      final price = (data['priceDaily'] as num?)?.toDouble() ?? 0.0;
      return ListingData(
        id: doc.id,
        title: data['title'] ?? 'Real Estate Property',
        owner: data['hostName'] ?? 'Host',
        priceLabel: '₱${price.toStringAsFixed(2)}/day',
        status: data['status'] ?? 'Available',
        createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
        icon: '🏠',
        reportCount: reportsCount,
        reports: reportsList,
        rawData: data,
      );
    } else {
      final price = (data['pricingValue'] as num?)?.toDouble() ?? 0.0;
      final type = data['pricingType'] ?? 'fixed';
      return ListingData(
        id: doc.id,
        title: data['title'] ?? 'Gig Service',
        owner: data['creatorName'] ?? 'Client',
        priceLabel: '₱${price.toStringAsFixed(2)} ($type)',
        status: data['status'] ?? 'Open',
        createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
        icon: '💼',
        reportCount: reportsCount,
        reports: reportsList,
        rawData: data,
      );
    }
  }).toList();
});

class ListingsPage extends StatefulComponent {
  const ListingsPage({super.key});

  @override
  State<ListingsPage> createState() => _ListingsPageState();
}

class _ListingsPageState extends State<ListingsPage> {
  // Search and filter inputs
  String _searchQuery = '';
  String _locationFilter = '';
  String _categoryFilter = ''; // bodyType (vehicles), propertyType (properties), category (services)
  double? _priceMin;
  double? _priceMax;

  bool _showReportedOnly = false;

  // Single listing detailed view state
  ListingData? _detailsModalItem;

  // Q&A text states
  final Map<String, String> _activeReplies = {};
  String _newQuestionText = '';

  @override
  Component build(BuildContext context) {
    final activeTab = context.watch(listingsTabProvider);
    final currentPage = context.watch(listingsPageProvider);
    final listingsAsync = context.watch(paginatedListingsProvider);
    final selectedGlobalId = context.watch(selectedListingIdProvider);

    final qnaList = _detailsModalItem == null
        ? <QnaMessage>[]
        : (context
                  .watch(
                    listingQnaStreamProvider((
                      activeTab == 'vehicles'
                          ? 'rentals'
                          : activeTab == 'properties'
                          ? 'properties'
                          : 'jobs',
                      _detailsModalItem!.id,
                    )),
                  )
                  .value ??
              <QnaMessage>[]);

    // Watch dynamic global search click and fetch detail item if matching
    if (selectedGlobalId != null && _detailsModalItem?.id != selectedGlobalId) {
      final firestore = context.read(firestoreProvider);
      final col = activeTab == 'vehicles'
          ? 'rentals'
          : activeTab == 'properties'
          ? 'properties'
          : 'jobs';
      firestore.collection(col).doc(selectedGlobalId).get().then((doc) {
        if (doc.exists && mounted) {
          final data = doc.data()!;
          final reportsList = data['reports'] as List? ?? [];
          final reportsCount =
              data['reportCount'] as int? ?? (data['reports'] != null ? (data['reports'] as List).length : 0);

          ListingData item;
          if (activeTab == 'vehicles') {
            final price = (data['priceDaily'] as num?)?.toDouble() ?? 0.0;
            item = ListingData(
              id: doc.id,
              title: '${data['brand'] ?? ''} ${data['model'] ?? ''}'.trim(),
              owner: data['hostName'] ?? 'Host',
              priceLabel: '₱${price.toStringAsFixed(2)}/day',
              status: data['status'] ?? 'Available',
              createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
              icon: '🚗',
              reportCount: reportsCount,
              reports: reportsList,
              rawData: data,
            );
          } else if (activeTab == 'properties') {
            final price = (data['priceDaily'] as num?)?.toDouble() ?? 0.0;
            item = ListingData(
              id: doc.id,
              title: data['title'] ?? 'Property',
              owner: data['hostName'] ?? 'Host',
              priceLabel: '₱${price.toStringAsFixed(2)}/day',
              status: data['status'] ?? 'Available',
              createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
              icon: '🏠',
              reportCount: reportsCount,
              reports: reportsList,
              rawData: data,
            );
          } else {
            final price = (data['pricingValue'] as num?)?.toDouble() ?? 0.0;
            item = ListingData(
              id: doc.id,
              title: data['title'] ?? 'Service',
              owner: data['creatorName'] ?? 'Client',
              priceLabel: '₱${price.toStringAsFixed(2)}',
              status: data['status'] ?? 'Open',
              createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
              icon: '💼',
              reportCount: reportsCount,
              reports: reportsList,
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
          context.read(listingsTabProvider.notifier).state = value;
          context.read(listingsPageProvider.notifier).state = 1;
          context.read(listingsCursorsProvider.notifier).state = [null];
          // Clear filter inputs when changing tabs
          setState(() {
            _searchQuery = '';
            _locationFilter = '';
            _categoryFilter = '';
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

    // Helper to extract location string
    String getDisplayLocation(Map<String, dynamic> raw) {
      final loc = raw['location'] ?? raw['address'] ?? raw['city'] ?? raw['province'];
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

    // List of dynamic category options for dropdown filtering
    List<String> getCategoryOptions() {
      if (activeTab == 'vehicles') {
        return ['SUV', 'Sedan', 'Van', 'Motorcycle', 'Hatchback', 'Pickup'];
      } else if (activeTab == 'properties') {
        return ['Apartment', 'Condo', 'House', 'Room', 'Villa'];
      } else {
        return ['Tech', 'Design', 'Creative', 'Home Services', 'Delivery', 'Tutoring'];
      }
    }

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0] relative', [
      // Details Modal Overlay
      if (_detailsModalItem != null)
        div(
          classes:
              'fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4 animate-fade-in',
          events: {
            'click': (e) {
              context.read(selectedListingIdProvider.notifier).state = null;
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
                        Component.text('ID: ${_detailsModalItem!.id}'),
                      ]),
                    ]),
                  ]),
                  button(
                    onClick: () {
                      context.read(selectedListingIdProvider.notifier).state = null;
                      setState(() => _detailsModalItem = null);
                    },
                    classes: 'w-7 h-7 rounded-full bg-zinc-100 text-zinc-500 font-bold hover:bg-zinc-200 text-xs flex items-center justify-center',
                    [Component.text('✕')],
                  ),
                ]),

                // Modal Content Scroll
                div(classes: 'flex flex-col gap-4 text-xs text-zinc-700', [
                  // Row 1: Status & Price
                  div(classes: 'grid grid-cols-2 gap-4', [
                    div(classes: 'bg-[#f8faf9] p-3.5 rounded-2xl border border-zinc-200/20', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Rate Parameters'),
                      ]),
                      p(classes: 'text-sm font-black text-zinc-900 mt-1', [
                        Component.text(_detailsModalItem!.priceLabel),
                      ]),
                    ]),
                    div(classes: 'bg-[#f8faf9] p-3.5 rounded-2xl border border-zinc-200/20', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Listing Status'),
                      ]),
                      div(classes: 'mt-1.5', [
                        span(
                          classes:
                              'px-3 py-1 rounded-full text-[9px] font-extrabold border '
                              '${_detailsModalItem!.status == 'Available' || _detailsModalItem!.status == 'Open' ? 'bg-[#e2f1e9] text-[#0fa958] border-emerald-500/10' : 'bg-zinc-100 text-zinc-500 border-zinc-200'}',
                          [Component.text(_detailsModalItem!.status.toUpperCase())],
                        ),
                      ]),
                    ]),
                  ]),

                  // Row 2: Publisher & Location
                  div(classes: 'grid grid-cols-2 gap-4', [
                    div(classes: 'flex flex-col gap-1', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Owner / Publisher'),
                      ]),
                      p(classes: 'font-bold text-zinc-900', [Component.text(_detailsModalItem!.owner)]),
                      span(classes: 'text-[9px] text-zinc-400 font-mono', [
                        Component.text(
                          'ID: ${_detailsModalItem!.rawData['hostId'] ?? _detailsModalItem!.rawData['creatorId'] ?? 'N/A'}',
                        ),
                      ]),
                    ]),
                    div(classes: 'flex flex-col gap-1', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Geographic Location'),
                      ]),
                      p(classes: 'font-bold text-zinc-900', [
                        Component.text(getDisplayLocation(_detailsModalItem!.rawData)),
                      ]),
                    ]),
                  ]),

                  // Uploaded Media Images
                  () {
                    final imageUrls = <String>[];
                    if (activeTab == 'vehicles') {
                      final front = _detailsModalItem!.rawData['frontPhotoUrl'] as String?;
                      final back = _detailsModalItem!.rawData['backPhotoUrl'] as String?;
                      final interior = _detailsModalItem!.rawData['interiorPhotoUrl'] as String?;
                      if (front != null && front.isNotEmpty) imageUrls.add(front);
                      if (back != null && back.isNotEmpty) imageUrls.add(back);
                      if (interior != null && interior.isNotEmpty) imageUrls.add(interior);
                    } else if (activeTab == 'properties') {
                      final list = _detailsModalItem!.rawData['photoUrls'] as List?;
                      if (list != null) imageUrls.addAll(list.map((e) => e.toString()));
                    } else {
                      final list = _detailsModalItem!.rawData['imageUrls'] as List?;
                      if (list != null) imageUrls.addAll(list.map((e) => e.toString()));
                    }

                    if (imageUrls.isEmpty) return div([]);
                    return div(classes: 'flex flex-col gap-1.5 border-t border-zinc-100 pt-3', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Uploaded Media Images'),
                      ]),
                      div(classes: 'flex gap-2 overflow-x-auto py-1 no-scrollbar', [
                        for (final imgUrl in imageUrls)
                          img(
                            src: imgUrl,
                            classes: 'w-28 h-28 rounded-2xl object-cover border border-zinc-200/50 hover:scale-105 transition-all shadow-sm flex-shrink-0',
                            alt: 'Listing image',
                          ),
                      ]),
                    ]);
                  }(),

                  // Description
                  if (_detailsModalItem!.rawData['description'] != null &&
                      _detailsModalItem!.rawData['description'].toString().isNotEmpty)
                    div(classes: 'flex flex-col gap-1 border-t border-zinc-100 pt-3', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Description Details'),
                      ]),
                      p(
                        classes: 'text-zinc-650 leading-relaxed font-medium mt-1 bg-zinc-50/50 p-3 rounded-xl border border-zinc-100',
                        [Component.text(_detailsModalItem!.rawData['description'].toString())],
                      ),
                    ]),

                  // Specifications
                  div(classes: 'flex flex-col gap-2 border-t border-zinc-100 pt-3', [
                    span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                      Component.text('Technical Specifications'),
                    ]),
                    div(
                      classes: 'grid grid-cols-2 gap-2 bg-[#f8faf9] p-3 rounded-xl border border-zinc-200/20 text-[11px] font-medium text-zinc-600',
                      [
                        if (activeTab == 'vehicles') ...[
                          span([
                            Component.text(
                              'Body Type: ${(_detailsModalItem!.rawData['bodyType'] ?? 'Sedan').toUpperCase()}',
                            ),
                          ]),
                          span([
                            Component.text(
                              'Transmission: ${(_detailsModalItem!.rawData['transmission'] ?? 'Automatic').toUpperCase()}',
                            ),
                          ]),
                          span([
                            Component.text(
                              'Fuel Type: ${(_detailsModalItem!.rawData['fuelType'] ?? 'Gasoline').toUpperCase()}',
                            ),
                          ]),
                          span([Component.text('Year model: ${_detailsModalItem!.rawData['year'] ?? 'N/A'}')]),
                        ] else if (activeTab == 'properties') ...[
                          span([
                            Component.text(
                              'Type: ${(_detailsModalItem!.rawData['propertyType'] ?? 'Apartment').toUpperCase()}',
                            ),
                          ]),
                          span([Component.text('Bedrooms: ${_detailsModalItem!.rawData['bedrooms'] ?? 1}')]),
                          span([Component.text('Bathrooms: ${_detailsModalItem!.rawData['bathrooms'] ?? 1}')]),
                          span([Component.text('Max Guests: ${_detailsModalItem!.rawData['maxGuests'] ?? 2}')]),
                        ] else ...[
                          span([
                            Component.text(
                              'Category: ${(_detailsModalItem!.rawData['category'] ?? 'Gig').toUpperCase()}',
                            ),
                          ]),
                          span([
                            Component.text(
                              'Pricing Type: ${(_detailsModalItem!.rawData['pricingType'] ?? 'Fixed').toUpperCase()}',
                            ),
                          ]),
                          span([
                            Component.text(
                              'Complexity: ${(_detailsModalItem!.rawData['complexity'] ?? 'Medium').toUpperCase()}',
                            ),
                          ]),
                        ],
                      ],
                    ),
                  ]),

                  // Public Q&A Board
                  div(classes: 'flex flex-col gap-2 border-t border-zinc-100 pt-3', [
                    span(classes: 'text-[9px] font-black text-indigo-500 uppercase tracking-wider', [
                      Component.text('💬 Public Q&A Moderation Feed'),
                    ]),
                    if (qnaList.isEmpty)
                      div(classes: 'py-3 text-center text-[10px] text-zinc-400 font-semibold', [
                        Component.text('No public inquiries yet.'),
                      ])
                    else
                      div(classes: 'flex flex-col gap-2 max-h-52 overflow-y-auto pr-1 no-scrollbar', [
                        for (final qna in qnaList)
                          div(
                            classes: 'p-3 bg-zinc-50 border border-zinc-200/50 rounded-2xl flex flex-col gap-1.5 text-[10px]',
                            [
                              div(classes: 'flex justify-between items-start', [
                                div(classes: 'flex items-center gap-1.5', [
                                  span(classes: 'font-extrabold text-zinc-800', [Component.text(qna.senderName)]),
                                  span(classes: 'text-zinc-400 text-[8px] font-mono', [
                                    Component.text(
                                      qna.createdAt > 0
                                          ? DateTime.fromMillisecondsSinceEpoch(
                                              qna.createdAt,
                                            ).toString().split('.').first
                                          : 'Just now',
                                    ),
                                  ]),
                                ]),
                                button(
                                  onClick: () async {
                                    if (web.window.confirm('Delete this message permanently?')) {
                                      final firestore = context.read(firestoreProvider);
                                      final col = activeTab == 'vehicles'
                                          ? 'rentals'
                                          : activeTab == 'properties'
                                          ? 'properties'
                                          : 'jobs';
                                      if (qna.id.startsWith('mock_')) {
                                        web.window.alert('Mock question removed.');
                                      } else {
                                        await firestore
                                            .collection(col)
                                            .doc(_detailsModalItem!.id)
                                            .collection('qna')
                                            .doc(qna.id)
                                            .delete();
                                      }
                                    }
                                  },
                                  classes: 'text-red-500 font-bold hover:underline text-[9px]',
                                  [Component.text('Remove')],
                                ),
                              ]),
                              p(classes: 'text-zinc-650 font-medium', [Component.text(qna.text)]),
                              if (qna.reply != null)
                                div(classes: 'pl-3 border-l border-indigo-400 flex flex-col gap-0.5 mt-1 text-[10px]', [
                                  span(classes: 'font-extrabold text-indigo-500', [Component.text('Admin Response:')]),
                                  p(classes: 'text-zinc-600 font-medium', [Component.text(qna.reply!)]),
                                ])
                              else
                                div(classes: 'flex gap-2 mt-1.5 items-center', [
                                  input(
                                    classes: 'flex-1 px-3 py-1 bg-white border border-zinc-200 rounded-xl text-[10px] focus:outline-none focus:border-indigo-400',
                                    attributes: {'placeholder': 'Write response...'},
                                    onInput: (val) => setState(() => _activeReplies[qna.id] = val as String),
                                  ),
                                  button(
                                    onClick: () async {
                                      final repText = _activeReplies[qna.id]?.trim() ?? '';
                                      if (repText.isEmpty) return;
                                      final firestore = context.read(firestoreProvider);
                                      final col = activeTab == 'vehicles'
                                          ? 'rentals'
                                          : activeTab == 'properties'
                                          ? 'properties'
                                          : 'jobs';
                                      if (qna.id.startsWith('mock_')) {
                                        web.window.alert('Mock reply posted: "$repText"');
                                      } else {
                                        await firestore
                                            .collection(col)
                                            .doc(_detailsModalItem!.id)
                                            .collection('qna')
                                            .doc(qna.id)
                                            .update({
                                              'reply': repText,
                                            });
                                      }
                                    },
                                    classes: 'px-3 py-1 bg-indigo-500 hover:bg-indigo-600 text-white font-extrabold rounded-lg text-[9px] transition-colors shadow-sm',
                                    [Component.text('Reply')],
                                  ),
                                ]),
                            ],
                          ),
                      ]),
                    div(classes: 'flex gap-2 items-center mt-2 border-t border-zinc-150/60 pt-2', [
                      input(
                        classes: 'flex-1 px-3.5 py-1.5 bg-[#f3f6f4] border border-zinc-200 rounded-xl text-[10px] focus:outline-none focus:border-indigo-400',
                        attributes: {'placeholder': 'Post new announcement/question...'},
                        onInput: (val) => _newQuestionText = val as String,
                      ),
                      button(
                        onClick: () async {
                          final textVal = _newQuestionText.trim();
                          if (textVal.isEmpty) return;
                          final firestore = context.read(firestoreProvider);
                          final col = activeTab == 'vehicles'
                              ? 'rentals'
                              : activeTab == 'properties'
                              ? 'properties'
                              : 'jobs';
                          await firestore.collection(col).doc(_detailsModalItem!.id).collection('qna').add({
                            'senderName': 'Admin Support',
                            'text': textVal,
                            'createdAt': DateTime.now().millisecondsSinceEpoch,
                          });
                          setState(() => _newQuestionText = '');
                        },
                        classes: 'px-4.5 py-1.5 bg-black hover:bg-zinc-800 text-white font-extrabold rounded-xl text-[9px] transition-colors',
                        [Component.text('Post')],
                      ),
                    ]),
                  ]),

                  // Reports List
                  if (_detailsModalItem!.reportCount > 0)
                    div(classes: 'flex flex-col gap-2 border-t border-zinc-100 pt-3', [
                      span(classes: 'text-[9px] font-black text-red-500 uppercase tracking-wider', [
                        Component.text('🚨 Abuse Reports Logs'),
                      ]),
                      div(classes: 'flex flex-col gap-1.5', [
                        for (final r in _detailsModalItem!.reports)
                          div(
                            classes: 'p-2.5 bg-red-50/50 border border-red-200/30 rounded-xl flex flex-col gap-0.5 text-[10px]',
                            [
                              p(classes: 'text-red-600 font-bold', [
                                Component.text('Reason: ${r is Map ? r['reason'] : r}'),
                              ]),
                              if (r is Map && r['reporterName'] != null)
                                span(classes: 'text-zinc-400 font-medium', [
                                  Component.text('Reporter: ${r['reporterName']}'),
                                ]),
                            ],
                          ),
                      ]),
                    ]),
                  // Penalize Creator Dropdown
                  (() {
                    final creatorId =
                        _detailsModalItem!.rawData['hostId'] as String? ??
                        _detailsModalItem!.rawData['creatorId'] as String?;
                    if (creatorId == null || creatorId.isEmpty) return div([]);
                    return div(classes: 'flex flex-col gap-1.5 border-t border-zinc-100 pt-3 mt-2', [
                      span(classes: 'text-[9px] font-black text-red-500 uppercase tracking-wider', [
                        Component.text('⚠️ Penalize Listing Creator'),
                      ]),
                      p(classes: 'text-[10px] text-zinc-400 font-medium', [
                        Component.text('Apply account suspension directly to the creator of this listing.'),
                      ]),
                      select(
                        classes: 'bg-red-50/30 border border-red-200/50 rounded-xl px-3 py-2 text-[10px] font-black text-red-700 focus:outline-none cursor-pointer w-full mt-1',
                        onChange: (v) async {
                          if (v.isEmpty || v.first.isEmpty) return;

                          final selection = v.first;
                          final firestore = context.read(firestoreProvider);

                          bool isBanned = false;
                          int? suspendUntil;
                          String msg = 'Status updated.';
                          final nowMs = DateTime.now().millisecondsSinceEpoch;

                          if (selection == 'ban') {
                            isBanned = true;
                            msg = '🚫 Creator permanently banned.';
                          } else if (selection == '3d') {
                            suspendUntil = nowMs + (3 * 24 * 60 * 60 * 1000);
                            msg = '⏳ Creator suspended for 3 days.';
                          } else if (selection == '7d') {
                            suspendUntil = nowMs + (7 * 24 * 60 * 60 * 1000);
                            msg = '⏳ Creator suspended for 7 days.';
                          } else if (selection == '14d') {
                            suspendUntil = nowMs + (14 * 24 * 60 * 60 * 1000);
                            msg = '⏳ Creator suspended for 14 days.';
                          } else if (selection == 'active') {
                            msg = '✅ Creator account activated.';
                          }

                          await firestore.collection('users').doc(creatorId).update({
                            'banned': isBanned,
                            'suspendedUntil': suspendUntil,
                          });

                          web.window.alert(msg);
                        },
                        [
                          option(value: '', selected: true, [Component.text('Choose suspension timeframe...')]),
                          option(value: 'active', [Component.text('✅ Active (Lift Penalties)')]),
                          option(value: '3d', [Component.text('⏳ Suspend 3 Days')]),
                          option(value: '7d', [Component.text('⏳ Suspend 1 Week')]),
                          option(value: '14d', [Component.text('⏳ Suspend 2 Weeks')]),
                          option(value: 'ban', [Component.text('🚫 Permanent Ban')]),
                        ],
                      ),
                    ]);
                  }()),
                ]),

                // Modal Footer
                div(classes: 'flex justify-between items-center border-t border-zinc-100 pt-4 mt-2', [
                  button(
                    onClick: () async {
                      if (web.window.confirm('Are you absolutely sure you want to permanently delete this listing?')) {
                        final firestore = context.read(firestoreProvider);
                        final col = activeTab == 'vehicles'
                            ? 'rentals'
                            : activeTab == 'properties'
                            ? 'properties'
                            : 'jobs';
                        await firestore.collection(col).doc(_detailsModalItem!.id).delete();
                        context.invalidate(paginatedListingsProvider);
                        context.read(selectedListingIdProvider.notifier).state = null;
                        setState(() => _detailsModalItem = null);
                      }
                    },
                    classes: 'px-4 py-2 bg-red-500 hover:bg-red-600 text-white text-[10px] font-extrabold tracking-wide uppercase rounded-xl transition-all shadow-md shadow-red-500/10',
                    [Component.text('Delete Listing')],
                  ),
                  button(
                    onClick: () {
                      context.read(selectedListingIdProvider.notifier).state = null;
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
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [Component.text('Listings Directory')]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text('Review active services, vehicle rentals, and property listings.'),
          ]),
        ]),
        // Tabs styled in capsules
        div(classes: 'flex items-center gap-1 bg-white p-1 border border-zinc-200/50 rounded-full shadow-sm', [
          buildTabButton('💼 Services', 'services'),
          buildTabButton('🚗 Vehicles', 'vehicles'),
          buildTabButton('🏠 Real Estate', 'properties'),
        ]),
      ]),

      // Search & Filters Panel (Independent for listings)
      div(
        classes: 'w-full bg-white border border-zinc-200/50 rounded-[24px] p-5 shadow-[0_4px_20px_rgba(0,0,0,0.01)] flex flex-col gap-4',
        [
          // Title / Info row
          div(classes: 'flex items-center justify-between', [
            div(classes: 'flex items-center gap-4', [
              h3(classes: 'text-[11px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                Component.text('Database Query Filter'),
              ]),
              label(
                classes: 'flex items-center gap-1.5 cursor-pointer select-none text-[10px] font-black text-red-500 hover:text-red-650 transition-colors',
                [
                  input(
                    classes: 'rounded border-red-300 text-red-600 focus:ring-red-500 h-3.5 w-3.5 cursor-pointer',
                    attributes: {'type': 'checkbox'},
                    checked: _showReportedOnly,
                    onChange: (v) => setState(() => _showReportedOnly = !_showReportedOnly),
                  ),
                  Component.text('🚨 SHOW REPORTED ONLY'),
                ],
              ),
            ]),
            if (_searchQuery.isNotEmpty ||
                _locationFilter.isNotEmpty ||
                _categoryFilter.isNotEmpty ||
                _priceMin != null ||
                _priceMax != null ||
                _showReportedOnly)
              button(
                onClick: () => setState(() {
                  _searchQuery = '';
                  _locationFilter = '';
                  _categoryFilter = '';
                  _priceMin = null;
                  _priceMax = null;
                  _showReportedOnly = false;
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
                Component.text('Keyword Match'),
              ]),
              input(
                value: _searchQuery,
                onInput: (v) => setState(() => _searchQuery = v as String),
                classes: 'px-4 py-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-xl text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black/10',
                attributes: {'placeholder': 'Search title, publisher...'},
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
            // Category / Body Dropdown
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wide', [
                Component.text(
                  activeTab == 'vehicles'
                      ? 'Vehicle Type'
                      : activeTab == 'properties'
                      ? 'Property Type'
                      : 'Service Type',
                ),
              ]),
              select(
                classes: 'px-4 py-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-xl text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black/10',
                onChange: (v) => setState(() => _categoryFilter = v.isNotEmpty ? v.first : ''),
                [
                  option(value: '', selected: _categoryFilter == '', [Component.text('ALL CATEGORIES')]),
                  for (final opt in getCategoryOptions())
                    option(value: opt.toLowerCase(), selected: _categoryFilter == opt.toLowerCase(), [
                      Component.text(opt.toUpperCase()),
                    ]),
                ],
              ),
            ]),
            // Min Price
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wide', [
                Component.text('Min Rate (₱)'),
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
                Component.text('Max Rate (₱)'),
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
      listingsAsync.when(
        data: (listings) {
          // Perform high-fidelity client-side filtering on paginated batch
          final filteredListings = listings.where((item) {
            if (_showReportedOnly && item.reportCount == 0) return false;

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
              final matchesOwner = item.owner.toLowerCase().contains(q);
              final matchesId = item.id.toLowerCase().contains(q);
              final matchesDeep = checkValue(item.rawData);

              if (!matchesTitle && !matchesOwner && !matchesId && !matchesDeep) return false;
            }
            // Location filter
            if (_locationFilter.isNotEmpty) {
              final loc = getDisplayLocation(item.rawData).toLowerCase();
              if (!loc.contains(_locationFilter.toLowerCase())) return false;
            }
            // Category filter
            if (_categoryFilter.isNotEmpty) {
              final itemCat = activeTab == 'vehicles'
                  ? (item.rawData['bodyType'] ?? '').toString().toLowerCase()
                  : activeTab == 'properties'
                  ? (item.rawData['propertyType'] ?? '').toString().toLowerCase()
                  : (item.rawData['category'] ?? '').toString().toLowerCase();
              if (itemCat != _categoryFilter) return false;
            }
            // Min/Max Price filter
            final price = activeTab == 'vehicles' || activeTab == 'properties'
                ? (item.rawData['priceDaily'] as num?)?.toDouble() ?? 0.0
                : (item.rawData['pricingValue'] as num?)?.toDouble() ?? 0.0;
            if (_priceMin != null && price < _priceMin!) return false;
            if (_priceMax != null && price > _priceMax!) return false;

            return true;
          }).toList();

          if (filteredListings.isEmpty) {
            return div(
              classes: 'flex-grow flex flex-col items-center justify-center text-center p-16 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
              [
                span(classes: 'text-3xl mb-3', [Component.text('📂')]),
                h3(classes: 'text-sm font-bold text-zinc-900', [Component.text('No listings match criteria')]),
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
                        th(classes: 'p-5', [Component.text('Item / Service')]),
                        th(classes: 'p-5', [Component.text('Publisher')]),
                        th(classes: 'p-5', [Component.text('Location')]),
                        th(classes: 'p-5', [Component.text('Rate Parameters')]),
                        th(classes: 'p-5 text-center', [Component.text('Status')]),
                        th(classes: 'p-5 text-center', [Component.text('Reports')]),
                        th(classes: 'p-5 text-center', [Component.text('Created')]),
                        th(classes: 'p-5 text-right', [Component.text('Actions')]),
                      ]),
                    ],
                  ),
                  tbody(classes: 'divide-y divide-zinc-50', [
                    for (final item in filteredListings)
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
                                classes: 'truncate font-bold text-zinc-805 hover:text-indigo-600 transition-colors',
                                [Component.text(item.title)],
                              ),
                              span(classes: 'text-[9px] text-zinc-400 font-mono', [Component.text('ID: ${item.id}')]),
                            ]),
                          ]),
                          td(classes: 'p-5 text-zinc-650 font-medium', [Component.text(item.owner)]),
                          td(classes: 'p-5 text-zinc-650 font-semibold', [
                            Component.text(getDisplayLocation(item.rawData)),
                          ]),
                          td(classes: 'p-5 font-extrabold text-zinc-900', [Component.text(item.priceLabel)]),
                          td(classes: 'p-5 text-center', [
                            span(
                              classes:
                                  'px-3 py-1 rounded-full text-[9px] font-extrabold border '
                                  '${item.status == 'Available' || item.status == 'Open'
                                      ? 'bg-[#e2f1e9] text-[#0fa958] border-emerald-500/10'
                                      : item.status == 'Booked' || item.status == 'Active'
                                      ? 'bg-indigo-50 text-indigo-500 border-indigo-500/10'
                                      : 'bg-zinc-100 text-zinc-500 border-zinc-200'}',
                              [Component.text(item.status.toUpperCase())],
                            ),
                          ]),
                          td(classes: 'p-5 text-center', [
                            if (item.reportCount > 0)
                              span(
                                classes: 'px-2.5 py-0.5 rounded-full text-[9px] font-black bg-red-50 text-red-500 border border-red-500/10',
                                [Component.text('🚩 ${item.reportCount} Reports')],
                              )
                            else
                              span(classes: 'text-zinc-400 font-semibold', [Component.text('None')]),
                          ]),
                          td(classes: 'p-5 text-center text-zinc-400 font-semibold', [
                            Component.text(
                              '${item.createdAt.year}-${item.createdAt.month.toString().padLeft(2, '0')}-${item.createdAt.day.toString().padLeft(2, '0')}',
                            ),
                          ]),
                          td(classes: 'p-5 text-right', [
                            button(
                              events: {
                                'click': (e) async {
                                  e.stopPropagation(); // Prevent modal opening
                                  if (web.window.confirm(
                                    'Are you absolutely sure you want to permanently delete this listing?',
                                  )) {
                                    final firestore = context.read(firestoreProvider);
                                    final col = activeTab == 'vehicles'
                                        ? 'rentals'
                                        : activeTab == 'properties'
                                        ? 'properties'
                                        : 'jobs';
                                    await firestore.collection(col).doc(item.id).delete();
                                    context.invalidate(paginatedListingsProvider);
                                  }
                                },
                              },
                              classes: 'px-3.5 py-1.5 bg-red-50 hover:bg-red-100/50 border border-red-200 text-red-500 text-[10px] font-extrabold tracking-wide uppercase rounded-full transition-all shadow-sm',
                              [Component.text('Remove')],
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
                      context.read(listingsPageProvider.notifier).state = currentPage - 1;
                    }
                  },
                  classes:
                      'px-4 py-2 rounded-full border border-zinc-200 text-[10px] font-extrabold tracking-wide uppercase transition-all duration-200 '
                      '${currentPage == 1 ? 'opacity-40 cursor-not-allowed text-zinc-400' : 'bg-white text-zinc-800 hover:bg-zinc-50 shadow-sm'}',
                  [Component.text('PREVIOUS')],
                ),
                button(
                  disabled: listings.length < 10,
                  onClick: () async {
                    final firestore = context.read(firestoreProvider);
                    final tab = context.read(listingsTabProvider);
                    final cursors = context.read(listingsCursorsProvider);

                    String col;
                    if (tab == 'vehicles') {
                      col = 'rentals';
                    } else if (tab == 'properties') {
                      col = 'properties';
                    } else {
                      col = 'jobs';
                    }

                    final lastItem = listings.last;
                    final docRef = await firestore.collection(col).doc(lastItem.id).get();

                    context.read(listingsCursorsProvider.notifier).state = [...cursors, docRef];
                    context.read(listingsPageProvider.notifier).state = currentPage + 1;
                  },
                  classes:
                      'px-4 py-2 rounded-full border border-zinc-200 text-[10px] font-extrabold tracking-wide uppercase transition-all duration-200 '
                      '${listings.length < 10 ? 'opacity-40 cursor-not-allowed text-zinc-400' : 'bg-white text-zinc-800 hover:bg-zinc-50 shadow-sm'}',
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
          [Component.text('Error loading listings: $err')],
        ),
      ),
    ]);
  }
}
