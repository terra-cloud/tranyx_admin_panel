import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:web/web.dart' as web;

import '../core/providers/environment_provider.dart';

class PromoItem {
  final String code;
  final String applicableTo;
  final String discountType;
  final double discountValue;
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

  PromoItem({
    required this.code,
    required this.applicableTo,
    required this.discountType,
    required this.discountValue,
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
      applicableTo: map['applicableTo'] ?? 'both',
      discountType: map['discountType'] ?? 'flat',
      discountValue: (map['discountValue'] as num?)?.toDouble() ?? 0.0,
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'applicableTo': applicableTo,
      'discountType': discountType,
      'discountValue': discountValue,
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
    };
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
        return snap.docs.map((doc) => PromoItem.fromMap(doc.id, doc.data())).toList();
      })
      .handleError((err) {
        print('[Promos] Stream failed: $err');
        return <PromoItem>[];
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

  // Form State
  String _code = '';
  String _applicableTo = 'both';
  String _discountType = 'flat';
  String _discountValueStr = '';
  String _expirationDateStr = '';
  String _maxUsersStr = '';
  bool _isSingleUsePerUser = false;
  bool _isAutoApply = false;
  String _eligibleUserUidsStr = '';
  bool _onlyForSubscribed = false;
  bool _onlyForHybrid = false;
  bool _isActive = true;

  // Targeted Roles
  bool _roleRenter = false;
  bool _roleHost = false;
  bool _roleEmployer = false;
  bool _roleNyxian = false;

  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;

  void _resetForm() {
    setState(() {
      _formVersion++;
      _code = '';
      _applicableTo = 'both';
      _discountType = 'flat';
      _discountValueStr = '';
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

  Future<void> _submitPromo(BuildContext context) async {
    final cleanCode = _code.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      setState(() => _errorMessage = 'Promo code is required.');
      return;
    }
    final discountValue = double.tryParse(_discountValueStr) ?? 0.0;
    if (discountValue <= 0) {
      setState(() => _errorMessage = 'Discount value must be greater than 0.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final firestore = context.read(firestoreProvider);

      // Parse dates and numbers
      DateTime? expirationDate;
      if (_expirationDateStr.isNotEmpty) {
        expirationDate = DateTime.tryParse(_expirationDateStr);
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

      final promoItem = PromoItem(
        code: cleanCode,
        applicableTo: _applicableTo,
        discountType: _discountType,
        discountValue: discountValue,
        expirationDate: expirationDate,
        maxUsers: maxUsers,
        isSingleUsePerUser: _isSingleUsePerUser,
        isAutoApply: _isAutoApply,
        eligibleUserUids: userUids,
        onlyForSubscribed: _onlyForSubscribed,
        onlyForHybrid: _onlyForHybrid,
        applicableRoles: roles,
        isActive: _isActive,
        usedCount: 0,
        usedBy: [],
      );

      await firestore.collection('promos').doc(cleanCode).set(promoItem.toMap());

      setState(() {
        _successMessage = 'Promo code $cleanCode successfully created!';
        _resetForm();
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to create promo code: $e');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deletePromo(BuildContext context, String code) async {
    if (!web.window.confirm('Are you sure you want to delete promo code $code?')) return;
    try {
      final firestore = context.read(firestoreProvider);

      // Delete the promo document
      await firestore.collection('promos').doc(code).delete();

      // Clear from all users currently using it
      final usersWithPromo = await firestore.collection('users').where('activePromoCode', isEqualTo: code).get();

      final batch = firestore.batch();
      for (final userDoc in usersWithPromo.docs) {
        batch.update(userDoc.reference, {
          'activePromoCode': null,
          'activePromoDiscountType': null,
          'activePromoDiscountValue': null,
        });
      }
      await batch.commit();
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
    } catch (e) {
      web.window.alert('Failed to toggle active state: $e');
    }
  }

  @override
  Component build(BuildContext context) {
    final promosAsync = context.watch(promosStreamProvider);

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0]', [
      // Header Block
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [Component.text('Promotions Console')]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text('Create and manage discount codes, user limits, and targeted role campaigns.'),
          ]),
        ]),
      ]),

      // Main content: Form on left, Promos list on right
      div(classes: 'grid grid-cols-1 lg:grid-cols-3 gap-6', [
        // Left Column: Create Form (Jaspr card style)
        div(
          key: ValueKey(_formVersion),
          classes:
              'lg:col-span-1 p-6 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm flex flex-col gap-5 h-fit',
          [
            h2(classes: 'text-sm font-black text-zinc-900 border-b border-zinc-150 pb-2', [
              Component.text('Create Promotion'),
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
              // Code Input
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Promo Code'),
                ]),
                input(
                  classes:
                      'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500 uppercase',
                  attributes: {
                    'type': 'text',
                    'placeholder': 'e.g., TYX50',
                    'value': _code,
                  },
                  events: {
                    'input': (e) => setState(() => _code = (e.target as dynamic).value as String),
                  },
                ),
              ]),

              // Applicable To (Target Category)
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Applicable To'),
                ]),
                select(
                  classes:
                      'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                  events: {
                    'change': (e) => setState(() => _applicableTo = (e.target as dynamic).value as String),
                  },
                  [
                    option(value: 'both', selected: _applicableTo == 'both', [
                      Component.text('Both Services & Rentals'),
                    ]),
                    option(value: 'rentals', selected: _applicableTo == 'rentals', [
                      Component.text('Rentals (Vehicles & Properties)'),
                    ]),
                    option(value: 'services', selected: _applicableTo == 'services', [
                      Component.text('Services (Gigs)'),
                    ]),
                  ],
                ),
              ]),

              // Discount Type & Value Grid
              div(classes: 'grid grid-cols-2 gap-3', [
                div(classes: 'flex flex-col gap-1', [
                  label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                    Component.text('Type'),
                  ]),
                  select(
                    classes:
                        'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                    events: {
                      'change': (e) => setState(() => _discountType = (e.target as dynamic).value as String),
                    },
                    [
                      option(value: 'flat', selected: _discountType == 'flat', [Component.text('Flat (₱)')]),
                      option(value: 'percentage', selected: _discountType == 'percentage', [
                        Component.text('Percentage (%)'),
                      ]),
                    ],
                  ),
                ]),
                div(classes: 'flex flex-col gap-1', [
                  label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                    Component.text('Value'),
                  ]),
                  input(
                    classes:
                        'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                    attributes: {
                      'type': 'number',
                      'step': 'any',
                      'placeholder': '0.00',
                      'value': _discountValueStr,
                    },
                    events: {
                      'input': (e) => setState(() => _discountValueStr = (e.target as dynamic).value as String),
                    },
                  ),
                ]),
              ]),

              // Expiration Date & Max Users Limit Grid
              div(classes: 'grid grid-cols-2 gap-3', [
                div(classes: 'flex flex-col gap-1', [
                  label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                    Component.text('Expiration Date'),
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
                div(classes: 'flex flex-col gap-1', [
                  label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                    Component.text('Max Users Limit'),
                  ]),
                  input(
                    classes:
                        'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-bold focus:outline-none focus:border-indigo-500',
                    attributes: {
                      'type': 'number',
                      'placeholder': 'Unlimited',
                      'value': _maxUsersStr,
                    },
                    events: {
                      'input': (e) => setState(() => _maxUsersStr = (e.target as dynamic).value as String),
                    },
                  ),
                ]),
              ]),

              // Targeted Roles (Checkbox row)
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Targeted Roles'),
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
                    span(classes: 'text-xs text-zinc-700 font-semibold', [Component.text('Renter')]),
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
                    span(classes: 'text-xs text-zinc-700 font-semibold', [Component.text('Host/Owner')]),
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
                    span(classes: 'text-xs text-zinc-700 font-semibold', [Component.text('Nyxian')]),
                  ]),
                ]),
              ]),

              // Eligible UIDs list (Comma separated)
              div(classes: 'flex flex-col gap-1', [
                label(classes: 'text-[10px] font-black text-zinc-400 uppercase tracking-wider', [
                  Component.text('Eligible User UIDs (Optional)'),
                ]),
                textarea(
                  placeholder: 'e.g., uid1, uid2, uid3 (leave empty for all)',
                  classes:
                      'w-full px-4 py-2.5 bg-zinc-50 border border-zinc-200 rounded-xl text-xs font-semibold focus:outline-none focus:border-indigo-500 h-16 resize-none',
                  events: {
                    'input': (e) => setState(() => _eligibleUserUidsStr = (e.target as dynamic).value as String),
                  },
                  [_eligibleUserUidsStr.isNotEmpty ? Component.text(_eligibleUserUidsStr) : Component.text('')],
                ),
              ]),

              // Configuration Switches / Checkboxes
              div(classes: 'flex flex-col gap-2.5 bg-zinc-50 p-4 border border-zinc-200 rounded-xl', [
                div(classes: 'flex items-center justify-between', [
                  div(classes: 'flex flex-col', [
                    span(classes: 'text-xs font-bold text-zinc-800', [Component.text('Auto Apply')]),
                    span(classes: 'text-[9px] text-zinc-400 font-medium', [
                      Component.text('Automatically apply at checkout'),
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
                div(classes: 'flex items-center justify-between border-t border-zinc-200/50 pt-2.5', [
                  div(classes: 'flex flex-col', [
                    span(classes: 'text-xs font-bold text-zinc-800', [Component.text('Single Use Only')]),
                    span(classes: 'text-[9px] text-zinc-400 font-medium', [
                      Component.text('Limit to one activation per user'),
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
                div(classes: 'flex items-center justify-between border-t border-zinc-200/50 pt-2.5', [
                  div(classes: 'flex flex-col', [
                    span(classes: 'text-xs font-bold text-zinc-800', [Component.text('Subscribed Users Only')]),
                    span(classes: 'text-[9px] text-zinc-400 font-medium', [
                      Component.text('Only premium subscribed accounts'),
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
                div(classes: 'flex items-center justify-between border-t border-zinc-200/50 pt-2.5', [
                  div(classes: 'flex flex-col', [
                    span(classes: 'text-xs font-bold text-zinc-800', [Component.text('Is Active')]),
                    span(classes: 'text-[9px] text-zinc-400 font-medium', [Component.text('Enable/disable globally')]),
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
                    'w-full py-3 bg-black hover:bg-zinc-800 disabled:bg-zinc-300 text-white rounded-2xl text-xs font-black tracking-wider uppercase transition-all shadow-md shadow-black/10 mt-2',
                [Component.text(_isSubmitting ? 'Posting...' : 'Create Promo Code')],
              ),
            ]),
          ],
        ),

        // Right Column: List of Promotions
        div(classes: 'lg:col-span-2 flex flex-col gap-4', [
          promosAsync.when(
            data: (promosList) {
              if (promosList.isEmpty) {
                return div(
                  classes:
                      'flex-grow flex flex-col items-center justify-center text-center p-16 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
                  [
                    span(classes: 'text-3xl mb-3', [Component.text('🎟️')]),
                    h3(classes: 'text-sm font-bold text-zinc-900', [Component.text('No Promotions Configured')]),
                    p(classes: 'text-xs text-zinc-500 mt-1', [
                      Component.text('Add your first promotion code using the creation form.'),
                    ]),
                  ],
                );
              }

              return div(classes: 'flex flex-col gap-4 overflow-y-auto max-h-[750px] pr-2 no-scrollbar', [
                for (final promo in promosList)
                  div(
                    classes:
                        'p-5 rounded-[24px] bg-white border border-zinc-200/50 flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.01)] hover:border-zinc-300 transition-all',
                    [
                      // Row 1: Code and Action Buttons
                      // Row 1: Code and Action Buttons
                      div(classes: 'flex items-center justify-between', [
                        div(classes: 'flex items-center gap-3', [
                          span(
                            classes:
                                'text-sm font-black tracking-wider px-3.5 py-1.5 rounded-xl border border-zinc-200/50 '
                                '${promo.isActive ? "bg-indigo-50/50 text-indigo-600 border-indigo-100" : "bg-zinc-50 text-zinc-400"}',
                            [Component.text(promo.code)],
                          ),
                          span(
                            classes:
                                'text-[10px] font-extrabold px-3 py-1 rounded-full border '
                                '${promo.applicableTo == 'both' ? "bg-purple-50 text-purple-600 border-purple-100" : (promo.applicableTo == 'rentals' ? "bg-amber-50 text-amber-600 border-amber-100" : "bg-blue-50 text-blue-600 border-blue-100")}',
                            [
                              Component.text(
                                promo.applicableTo == 'both'
                                    ? 'Both'
                                    : (promo.applicableTo == 'rentals' ? 'Rentals' : 'Services'),
                              ),
                            ],
                          ),
                        ]),
                        div(classes: 'flex items-center gap-1.5', [
                          button(
                            onClick: () => _toggleActivePromo(context, promo),
                            classes:
                                'px-3.5 py-1.5 rounded-lg border text-[10px] font-black transition-all '
                                '${promo.isActive ? "bg-zinc-50 hover:bg-zinc-150 border-zinc-200 text-zinc-600" : "bg-indigo-50 border-indigo-150 text-indigo-600"}',
                            [Component.text(promo.isActive ? 'Deactivate' : 'Activate')],
                          ),
                          button(
                            onClick: () => _deletePromo(context, promo.code),
                            classes:
                                'p-1.5 rounded-lg border border-red-200 bg-red-50/50 text-red-500 hover:bg-red-100/50 transition-all text-xs',
                            [Component.text('🗑️')],
                          ),
                        ]),
                      ]),

                      // Row 2: Discount & Usage Stats
                      div(
                        classes:
                            'grid grid-cols-2 sm:grid-cols-4 gap-4 bg-zinc-50 p-4 border border-zinc-150 rounded-2xl',
                        [
                          div(classes: 'flex flex-col gap-0.5', [
                            span(classes: 'text-[9px] font-bold text-zinc-400 uppercase tracking-wide', [
                              Component.text('Discount Value'),
                            ]),
                            span(classes: 'text-xs font-black text-zinc-800', [
                              Component.text(
                                promo.discountType == 'percentage'
                                    ? '${promo.discountValue.toStringAsFixed(0)}%'
                                    : '₱${promo.discountValue.toStringAsFixed(2)}',
                              ),
                            ]),
                          ]),
                          div(classes: 'flex flex-col gap-0.5', [
                            span(classes: 'text-[9px] font-bold text-zinc-400 uppercase tracking-wide', [
                              Component.text('Activations'),
                            ]),
                            span(classes: 'text-xs font-black text-zinc-800', [
                              Component.text(
                                '${promo.usedCount}${promo.maxUsers != null ? " / ${promo.maxUsers}" : ""}',
                              ),
                            ]),
                          ]),
                          div(classes: 'flex flex-col gap-0.5', [
                            span(classes: 'text-[9px] font-bold text-zinc-400 uppercase tracking-wide', [
                              Component.text('Expiration Date'),
                            ]),
                            span(classes: 'text-xs font-black text-zinc-800', [
                              Component.text(
                                promo.expirationDate != null
                                    ? '${promo.expirationDate!.year}-${promo.expirationDate!.month.toString().padLeft(2, '0')}-${promo.expirationDate!.day.toString().padLeft(2, '0')}'
                                    : 'Never',
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
                                  '${promo.isActive ? "text-[#0fa958]" : "text-zinc-450"}',
                              [Component.text(promo.isActive ? 'Active' : 'Disabled')],
                            ),
                          ]),
                        ],
                      ),

                      // Row 3: Constraints & Targeting
                      div(classes: 'flex flex-wrap gap-2', [
                        if (promo.isAutoApply)
                          span(
                            classes:
                                'text-[9px] font-bold px-2 py-0.5 bg-emerald-50 border border-emerald-100 rounded text-emerald-600',
                            [Component.text('Auto Apply')],
                          ),
                        if (promo.isSingleUsePerUser)
                          span(
                            classes:
                                'text-[9px] font-bold px-2 py-0.5 bg-blue-50 border border-blue-100 rounded text-blue-600',
                            [Component.text('Single Use')],
                          ),
                        if (promo.onlyForSubscribed)
                          span(
                            classes:
                                'text-[9px] font-bold px-2 py-0.5 bg-purple-50 border border-purple-100 rounded text-purple-600',
                            [Component.text('Premium Only')],
                          ),
                        if (promo.onlyForHybrid)
                          span(
                            classes:
                                'text-[9px] font-bold px-2 py-0.5 bg-amber-50 border border-amber-100 rounded text-amber-600',
                            [Component.text('Hybrid Only')],
                          ),
                        if (promo.applicableRoles.isNotEmpty)
                          span(
                            classes:
                                'text-[9px] font-bold px-2 py-0.5 bg-zinc-100 border border-zinc-200 rounded text-zinc-600',
                            [Component.text('Roles: ${promo.applicableRoles.join(', ')}')],
                          ),
                        if (promo.eligibleUserUids.isNotEmpty)
                          span(
                            classes:
                                'text-[9px] font-bold px-2 py-0.5 bg-zinc-100 border border-zinc-200 rounded text-zinc-600',
                            [Component.text('Targeted: ${promo.eligibleUserUids.length} users')],
                          ),
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
              classes:
                  'p-6 bg-red-50/5 border border-red-500/10 text-red-500 text-xs rounded-[20px] font-mono shadow-sm',
              [Component.text('Error loading Promos list: $err')],
            ),
          ),
        ]),
      ]),
    ]);
  }
}
