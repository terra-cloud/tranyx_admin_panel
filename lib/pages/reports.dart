import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:web/web.dart' as web;

import '../core/providers/environment_provider.dart';
import 'listings.dart';

final reportedJobsStreamProvider = StreamProvider<List<ListingData>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  ref.watch(activeEnvAuthUserProvider);
  return firestore.collection('jobs').snapshots().map((snap) {
    return snap.docs
        .map((doc) {
          final data = doc.data();
          final reportsList = data['reports'] as List? ?? [];
          final reportsCount =
              data['reportCount'] as int? ?? (data['reports'] != null ? (data['reports'] as List).length : 0);
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
            rawData: {...data, 'collectionType': 'jobs'},
          );
        })
        .where((item) => item.reportCount > 0)
        .toList();
  });
});

final reportedRentalsStreamProvider = StreamProvider<List<ListingData>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  ref.watch(activeEnvAuthUserProvider);
  return firestore.collection('rentals').snapshots().map((snap) {
    return snap.docs
        .map((doc) {
          final data = doc.data();
          final reportsList = data['reports'] as List? ?? [];
          final reportsCount =
              data['reportCount'] as int? ?? (data['reports'] != null ? (data['reports'] as List).length : 0);
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
            rawData: {...data, 'collectionType': 'rentals'},
          );
        })
        .where((item) => item.reportCount > 0)
        .toList();
  });
});

final reportedPropertiesStreamProvider = StreamProvider<List<ListingData>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  ref.watch(activeEnvAuthUserProvider);
  return firestore.collection('properties').snapshots().map((snap) {
    return snap.docs
        .map((doc) {
          final data = doc.data();
          final reportsList = data['reports'] as List? ?? [];
          final reportsCount =
              data['reportCount'] as int? ?? (data['reports'] != null ? (data['reports'] as List).length : 0);
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
            rawData: {...data, 'collectionType': 'properties'},
          );
        })
        .where((item) => item.reportCount > 0)
        .toList();
  });
});

final combinedReportedListingsProvider = Provider<AsyncValue<List<ListingData>>>((ref) {
  final jobs = ref.watch(reportedJobsStreamProvider);
  final rentals = ref.watch(reportedRentalsStreamProvider);
  final properties = ref.watch(reportedPropertiesStreamProvider);

  if (jobs.isLoading || rentals.isLoading || properties.isLoading) {
    return const AsyncValue.loading();
  }

  if (jobs.hasError) return AsyncValue.error(jobs.error!, jobs.stackTrace!);
  if (rentals.hasError) return AsyncValue.error(rentals.error!, rentals.stackTrace!);
  if (properties.hasError) return AsyncValue.error(properties.error!, properties.stackTrace!);

  final List<ListingData> all = [
    ...jobs.value ?? [],
    ...rentals.value ?? [],
    ...properties.value ?? [],
  ];

  // Sort by reportCount descending, then by createdAt descending
  all.sort((a, b) {
    final countCompare = b.reportCount.compareTo(a.reportCount);
    if (countCompare != 0) return countCompare;
    return b.createdAt.compareTo(a.createdAt);
  });

  return AsyncValue.data(all);
});

class ReportsPage extends StatefulComponent {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String _searchQuery = '';
  String _typeFilter = 'all'; // all, services, vehicles, properties
  ListingData? _detailsModalItem;

  @override
  Component build(BuildContext context) {
    final currentEnv = context.watch(activeEnvironmentProvider);
    final reportedListingsAsync = context.watch(combinedReportedListingsProvider);

    return div(classes: 'w-full p-8 flex flex-col gap-6 relative', [
      // Details Modal Overlay
      if (_detailsModalItem != null)
        div(
          classes:
              'fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4 animate-fade-in',
          events: {
            'click': (e) => setState(() => _detailsModalItem = null),
          },
          [
            div(
              classes: 'bg-white rounded-[32px] border border-zinc-200/50 shadow-2xl p-6 w-full max-w-lg flex flex-col gap-4 relative animate-scale-up',
              events: {
                'click': (e) => e.stopPropagation(),
              },
              [
                // Modal Header
                div(classes: 'flex items-center justify-between border-b border-zinc-50 pb-3', [
                  div(classes: 'flex items-center gap-2.5', [
                    span(classes: 'text-2xl', [Component.text(_detailsModalItem!.icon)]),
                    div(classes: 'flex flex-col min-w-0', [
                      h3(classes: 'text-sm font-black text-zinc-900 truncate max-w-xs', [
                        Component.text(_detailsModalItem!.title),
                      ]),
                      span(classes: 'text-[9px] text-zinc-400 font-bold uppercase tracking-wider', [
                        Component.text(
                          '${_detailsModalItem!.rawData['collectionType']?.toString().toUpperCase()} • ID: ${_detailsModalItem!.id.substring(0, 8)}',
                        ),
                      ]),
                    ]),
                  ]),
                  button(
                    onClick: () => setState(() => _detailsModalItem = null),
                    classes: 'w-7 h-7 rounded-full bg-zinc-50 hover:bg-zinc-100 flex items-center justify-center font-bold text-zinc-400 transition-colors',
                    [Component.text('✕')],
                  ),
                ]),

                // Modal Body / Details
                div(classes: 'flex flex-col gap-3.5 max-h-[360px] overflow-y-auto pr-1.5', [
                  div(classes: 'grid grid-cols-2 gap-3 text-xs', [
                    div(classes: 'bg-[#fafbfa] p-3 rounded-2xl border border-zinc-200/30', [
                      span(classes: 'text-[9px] font-black text-zinc-400 uppercase tracking-wider', [
                        Component.text('Publisher'),
                      ]),
                      p(classes: 'font-black text-zinc-800 mt-0.5 truncate', [
                        Component.text(_detailsModalItem!.owner),
                      ]),
                    ]),
                    div(classes: 'bg-[#fafbfa] p-3 rounded-2xl border border-zinc-200/30', [
                      span(classes: 'text-[9px] font-black text-zinc-400 uppercase tracking-wider', [
                        Component.text('Pricing / Rate'),
                      ]),
                      p(classes: 'font-black text-zinc-800 mt-0.5 truncate', [
                        Component.text(_detailsModalItem!.priceLabel),
                      ]),
                    ]),
                  ]),

                  // Description
                  if (_detailsModalItem!.rawData['description'] != null)
                    div(classes: 'flex flex-col gap-1', [
                      span(classes: 'text-[9px] font-black text-zinc-400 uppercase tracking-wider', [
                        Component.text('Description'),
                      ]),
                      p(
                        classes: 'text-[11px] text-zinc-600 bg-zinc-50/50 p-2.5 rounded-xl border border-zinc-100/50 leading-relaxed font-medium',
                        [Component.text(_detailsModalItem!.rawData['description'] as String)],
                      ),
                    ]),

                  // Reports logs list
                  if (_detailsModalItem!.reportCount > 0)
                    div(classes: 'flex flex-col gap-2 border-t border-zinc-100 pt-3', [
                      span(classes: 'text-[9px] font-black text-red-500 uppercase tracking-wider', [
                        Component.text('🚨 Abuse Reports Logs (${_detailsModalItem!.reportCount})'),
                      ]),
                      div(classes: 'flex flex-col gap-1.5', [
                        for (final r in _detailsModalItem!.reports)
                          div(
                            classes: 'p-2.5 bg-red-50/50 border border-red-200/30 rounded-xl flex flex-col gap-0.5 text-[10px]',
                            [
                              p(classes: 'text-red-650 font-bold', [
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
                          setState(() => _detailsModalItem = null);
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
                        final col = _detailsModalItem!.rawData['collectionType'] as String;
                        await firestore.collection(col).doc(_detailsModalItem!.id).delete();
                        setState(() => _detailsModalItem = null);
                        web.window.alert('Listing deleted.');
                      }
                    },
                    classes: 'px-4 py-2 bg-red-500 hover:bg-red-600 text-white text-[10px] font-extrabold tracking-wide uppercase rounded-xl transition-all shadow-md shadow-red-500/10',
                    [Component.text('Delete Listing')],
                  ),
                  button(
                    onClick: () => setState(() => _detailsModalItem = null),
                    classes: 'px-4 py-2 bg-zinc-200 hover:bg-zinc-300 text-zinc-800 text-[10px] font-extrabold tracking-wide uppercase rounded-xl transition-all',
                    [Component.text('Close')],
                  ),
                ]),
              ],
            ),
          ],
        ),

      // Header block
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [Component.text('Abuse Reports Center')]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text('Review flagged listings, view log reasons, and moderate accounts.'),
          ]),
        ]),
      ]),

      // Filters Bar
      div(
        classes: 'w-full bg-white border border-zinc-200/50 rounded-[24px] p-5 shadow-[0_4px_20px_rgba(0,0,0,0.01)] flex flex-col gap-4',
        [
          div(classes: 'flex items-center justify-between', [
            h3(classes: 'text-[11px] font-extrabold text-zinc-400 uppercase tracking-wider', [
              Component.text('Reports Filters'),
            ]),
            if (_searchQuery.isNotEmpty || _typeFilter != 'all')
              button(
                onClick: () => setState(() {
                  _searchQuery = '';
                  _typeFilter = 'all';
                }),
                classes: 'text-[10px] font-bold text-indigo-500 hover:underline',
                [Component.text('Clear Active Filters')],
              ),
          ]),

          div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-3.5', [
            // Keyword search
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

            // Listing Type
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wide', [
                Component.text('Listing Type'),
              ]),
              select(
                classes: 'px-4 py-2.5 bg-[#f3f6f4] border border-zinc-200/50 rounded-xl text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black/10 cursor-pointer',
                onChange: (v) => setState(() => _typeFilter = v.isNotEmpty ? v.first : 'all'),
                [
                  option(value: 'all', selected: _typeFilter == 'all', [Component.text('ALL LISTINGS')]),
                  option(value: 'services', selected: _typeFilter == 'services', [
                    Component.text('💼 SERVICES (GIGS)'),
                  ]),
                  option(value: 'vehicles', selected: _typeFilter == 'vehicles', [Component.text('🚗 VEHICLES')]),
                  option(value: 'properties', selected: _typeFilter == 'properties', [
                    Component.text('🏠 REAL ESTATE'),
                  ]),
                ],
              ),
            ]),
          ]),
        ],
      ),

      // Reports List Table
      reportedListingsAsync.when(
        data: (listings) {
          // Perform client-side filter
          final filtered = listings.where((item) {
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              final matchesTitle = item.title.toLowerCase().contains(q);
              final matchesOwner = item.owner.toLowerCase().contains(q);
              if (!matchesTitle && !matchesOwner) return false;
            }
            if (_typeFilter != 'all') {
              final colType = item.rawData['collectionType'] as String;
              if (_typeFilter == 'services' && colType != 'jobs') return false;
              if (_typeFilter == 'vehicles' && colType != 'rentals') return false;
              if (_typeFilter == 'properties' && colType != 'properties') return false;
            }
            return true;
          }).toList();

          if (filtered.isEmpty) {
            return div(
              classes: 'w-full bg-white border border-zinc-200/50 rounded-[28px] p-12 text-center flex flex-col items-center justify-center gap-3.5 shadow-[0_4px_20px_rgba(0,0,0,0.01)]',
              [
                span(classes: 'text-4xl animate-bounce', [Component.text('🛡️')]),
                h3(classes: 'text-sm font-black text-zinc-800', [Component.text('Inbox is clean')]),
                p(classes: 'text-xs text-zinc-400 max-w-xs leading-relaxed', [
                  Component.text('No listings matching active filters have reported flags at the moment.'),
                ]),
              ],
            );
          }

          return div(
            classes: 'bg-white rounded-[28px] border border-zinc-200/50 shadow-[0_4px_25px_rgba(0,0,0,0.01)] overflow-hidden',
            [
              div(classes: 'overflow-x-auto', [
                table(classes: 'w-full border-collapse text-left text-xs', [
                  thead(classes: 'bg-[#fafbfa] border-b border-zinc-150', [
                    tr([
                      th(classes: 'py-3.5 px-6 font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Type'),
                      ]),
                      th(classes: 'py-3.5 px-6 font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Listing Title'),
                      ]),
                      th(classes: 'py-3.5 px-6 font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Publisher'),
                      ]),
                      th(classes: 'py-3.5 px-6 font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Flags'),
                      ]),
                      th(classes: 'py-3.5 px-6 font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Report Log'),
                      ]),
                      th(classes: 'py-3.5 px-6 font-extrabold text-zinc-400 uppercase tracking-wider text-right', [
                        Component.text('Moderation'),
                      ]),
                    ]),
                  ]),
                  tbody(classes: 'divide-y divide-zinc-100', [
                    for (final item in filtered)
                      tr(classes: 'hover:bg-zinc-50/40 transition-colors', [
                        td(classes: 'py-4 px-6 font-black text-zinc-800 text-lg', [Component.text(item.icon)]),
                        td(classes: 'py-4 px-6 min-w-[200px]', [
                          span(
                            classes: 'font-black text-zinc-900 block hover:underline cursor-pointer',
                            events: {'click': (e) => setState(() => _detailsModalItem = item)},
                            [Component.text(item.title)],
                          ),
                          span(classes: 'text-[9px] text-zinc-400 font-bold block mt-0.5', [Component.text(item.id)]),
                        ]),
                        td(classes: 'py-4 px-6 font-bold text-zinc-700', [Component.text(item.owner)]),
                        td(classes: 'py-4 px-6', [
                          span(
                            classes: 'px-2 py-0.5 bg-red-50 text-red-500 border border-red-200 text-[10px] font-black rounded-full',
                            [Component.text('${item.reportCount} flags')],
                          ),
                        ]),
                        td(classes: 'py-4 px-6 max-w-[240px] truncate font-medium text-zinc-500', [
                          Component.text(
                            item.reports.isNotEmpty
                                ? (item.reports.first is Map
                                      ? item.reports.first['reason']?.toString() ?? ''
                                      : item.reports.first.toString())
                                : 'No log details',
                          ),
                        ]),
                        td(classes: 'py-4 px-6 text-right', [
                          button(
                            onClick: () => setState(() => _detailsModalItem = item),
                            classes: 'px-3 py-1.5 bg-black hover:bg-zinc-800 text-white text-[9px] font-black uppercase tracking-wider rounded-xl transition-all',
                            [Component.text('Moderate')],
                          ),
                        ]),
                      ]),
                  ]),
                ]),
              ]),
            ],
          );
        },
        loading: () => div(classes: 'py-16 flex justify-center items-center', [
          div(classes: 'animate-spin h-7 w-7 border-2 border-zinc-200 border-t-indigo-500 rounded-full', []),
        ]),
        error: (err, _) => div(
          classes: 'p-6 bg-red-50 text-red-500 rounded-2xl border border-red-200 font-mono text-xs',
          [Component.text('Failed loading reports: $err')],
        ),
      ),
    ]);
  }
}
