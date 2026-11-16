import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:web/web.dart' as web;

import '../core/access/partner_contract.dart';
import '../core/access/portal_role.dart';
import '../core/providers/environment_provider.dart';
import '../core/services/staff_ops_service.dart';

class PartnersPage extends StatelessComponent {
  const PartnersPage({super.key});

  @override
  Component build(BuildContext context) {
    final role = context.watch(currentAdminProfileProvider).value?.role;
    if (portalRoleIsPartner(role)) return const PartnerDeskPage();
    if (portalRoleIsAdmin(role)) return const PartnerAdminPage();
    return div(classes: 'p-8 text-sm text-zinc-600', [
      Component.text('City partner tools are available to a super admin or a partner.'),
    ]);
  }
}

class PartnerAdminPage extends StatefulComponent {
  const PartnerAdminPage({super.key});

  @override
  State<PartnerAdminPage> createState() => _PartnerAdminPageState();
}

class _PartnerAdminPageState extends State<PartnerAdminPage> {
  bool _started = false;
  bool _loading = true;
  bool _busy = false;
  bool _showForm = false;
  String? _error;
  String? _notice;
  Map<String, dynamic>? _overview;
  String? _editingId;

  String _email = '';
  String _licenseStart = '';
  String _termMonths = '36';
  String _fee = '0';
  String _share = '7000';
  String _targetListings = '30';
  String _targetProviders = '30';
  String _targetMonths = '6';
  List<Map<String, String>> _areas = [_blankArea()];

  static Map<String, String> _blankArea() => {'city': '', 'municipality': '', 'province': '', 'region': ''};

  @override
  Component build(BuildContext context) {
    if (!_started) {
      _started = true;
      Future.microtask(_loadOverview);
    }
    final partners = _partnerRows();
    final behind = partners.where((row) => row['behindTarget'] == true).toList();
    final expiring = partners.where((row) => row['licenseExpiring'] == true).toList();
    final includeSubscriptions = _overview?['includeSubscriptions'] == true;

    return div(classes: 'p-4 sm:p-8 flex flex-col gap-5 max-w-6xl', [
      div(classes: 'flex flex-wrap items-end justify-between gap-3', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-lg font-black text-zinc-900', [Component.text('City partners')]),
          p(classes: 'text-xs text-zinc-500 max-w-xl', [
            Component.text(
              'Licenses, areas, and payouts go through partnerAdmin on the selected environment. This screen does not write those documents and does not create a password.',
            ),
          ]),
        ]),
        button(
          onClick: _busy ? null : () => setState(() => _openCreate()),
          classes: _primaryButton,
          [Component.text('Create partner')],
        ),
      ]),
      if (_error != null) _banner(_error!, danger: true),
      if (_notice != null) _banner(_notice!, danger: false),
      if (_loading)
        p(classes: 'text-xs font-semibold text-zinc-400', [Component.text('Loading city partners...')])
      else ...[
        if (behind.isNotEmpty || expiring.isNotEmpty)
          div(classes: 'grid gap-3 md:grid-cols-2', [
            _alertCard(
              'Behind on targets',
              behind.isEmpty
                  ? 'No active partner is past the target month with listings or providers still short.'
                  : behind.map((row) => '${row['partnerId']} · listings ${row['activeListings']}/${_targetOf(row, 'activeListings')}').join('\n'),
            ),
            _alertCard(
              'Licenses expiring within 30 days',
              expiring.isEmpty
                  ? 'No license renewal date falls inside the next 30 days.'
                  : expiring.map((row) => '${row['partnerId']} · renews ${_when(row['renewalDate'])}').join('\n'),
            ),
          ]),
        div(classes: 'flex items-center justify-between gap-3 bg-white border border-zinc-200 rounded-2xl px-4 py-3', [
          div(classes: 'flex flex-col', [
            span(classes: 'text-xs font-black text-zinc-900', [Component.text('Subscription revenue')]),
            span(classes: 'text-[11px] text-zinc-500', [
              Component.text(includeSubscriptions
                  ? 'Subscription settlements are included in partner revenue.'
                  : 'Subscription settlements are off. Only rentals and jobs are tagged.'),
            ]),
          ]),
          button(
            onClick: _busy ? null : () => _setSubscriptions(!includeSubscriptions),
            classes: _secondaryButton,
            [Component.text(includeSubscriptions ? 'Turn subscriptions off' : 'Turn subscriptions on')],
          ),
        ]),
        if (_showForm) _form(),
        if (partners.isEmpty)
          p(classes: 'text-xs text-zinc-500', [Component.text('No partners on this environment yet.')])
        else
          div(classes: 'flex flex-col gap-3', partners.map(_partnerCard).toList()),
      ],
    ]);
  }

  List<Map<String, dynamic>> _partnerRows() {
    final raw = _overview?['partners'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((row) => row.cast<String, dynamic>()).toList();
  }

  void _openCreate() {
    _editingId = null;
    _email = '';
    _licenseStart = '';
    _termMonths = '36';
    _fee = '0';
    _share = '7000';
    _targetListings = '30';
    _targetProviders = '30';
    _targetMonths = '6';
    _areas = [_blankArea()];
    _showForm = true;
    _error = null;
  }

  void _openEdit(Map<String, dynamic> row) {
    _editingId = row['partnerId']?.toString();
    _share = '${row['partnerShareBps'] ?? 7000}';
    final targets = row['targets'];
    if (targets is Map) {
      _targetListings = '${targets['activeListings'] ?? 30}';
      _targetProviders = '${targets['activeProviders'] ?? 30}';
      _targetMonths = '${targets['byMonth'] ?? 6}';
    }
    final areas = row['areas'];
    if (areas is List && areas.isNotEmpty) {
      _areas = areas.whereType<Map>().map((area) {
        return {
          'city': '${area['city'] ?? ''}',
          'municipality': '${area['municipality'] ?? ''}',
          'province': '${area['province'] ?? ''}',
          'region': '${area['region'] ?? ''}',
        };
      }).toList();
    } else {
      _areas = [_blankArea()];
    }
    _showForm = true;
    _error = null;
  }

  Component _form() {
    final editing = _editingId != null;
    return div(
      classes: 'bg-white border border-zinc-200 rounded-2xl p-4 flex flex-col gap-3',
      [
        h2(classes: 'text-sm font-black', [Component.text(editing ? 'Edit ${_editingId!}' : 'New partner')]),
        if (!editing)
          _field('Email', _email, (value) => setState(() => _email = value), type: 'email', placeholder: 'partner@example.com'),
        _field('License start', _licenseStart, (value) => setState(() => _licenseStart = value), type: 'date'),
        div(classes: 'grid gap-3 sm:grid-cols-3', [
          _field('Term months', _termMonths, (value) => setState(() => _termMonths = value), type: 'number'),
          _field('License fee paid', _fee, (value) => setState(() => _fee = value), type: 'number'),
          _field('Partner share bps', _share, (value) => setState(() => _share = value), type: 'number'),
        ]),
        p(classes: 'text-[11px] text-zinc-500', [
          Component.text('Tranyx share is ${10000 - (int.tryParse(_share) ?? 7000)} bps. The area slug uses municipality, otherwise city. Province does not split the lock.'),
        ]),
        div(classes: 'grid gap-3 sm:grid-cols-3', [
          _field('Listing target', _targetListings, (value) => setState(() => _targetListings = value), type: 'number'),
          _field('Provider target', _targetProviders, (value) => setState(() => _targetProviders = value), type: 'number'),
          _field('Target by month', _targetMonths, (value) => setState(() => _targetMonths = value), type: 'number'),
        ]),
        ..._areas.asMap().entries.map((entry) => _areaRow(entry.key, entry.value)),
        div(classes: 'flex flex-wrap gap-2', [
          if (_areas.length < 10)
            button(
              classes: _secondaryButton,
              onClick: () => setState(() => _areas = [..._areas, _blankArea()]),
              [Component.text('Add area')],
            ),
          button(
            classes: _primaryButton,
            onClick: _busy ? null : _save,
            [Component.text(_busy ? 'Saving...' : (editing ? 'Save partner' : 'Create partner'))],
          ),
          button(
            classes: _secondaryButton,
            onClick: () => setState(() => _showForm = false),
            [Component.text('Close')],
          ),
        ]),
      ],
    );
  }

  Component _areaRow(int index, Map<String, String> area) {
    final slug = slugArea(area['municipality']!.trim().isNotEmpty ? area['municipality'] : area['city']);
    return div(classes: 'grid gap-2 sm:grid-cols-4 border border-zinc-100 rounded-xl p-3', [
      _field('City', area['city']!, (value) => setState(() => _areas[index]['city'] = value)),
      _field('Municipality', area['municipality']!, (value) => setState(() => _areas[index]['municipality'] = value)),
      _field('Province', area['province']!, (value) => setState(() => _areas[index]['province'] = value)),
      _field('Region', area['region']!, (value) => setState(() => _areas[index]['region'] = value)),
      span(classes: 'text-[11px] text-zinc-500 sm:col-span-3', [
        Component.text(slug.isEmpty ? 'Slug appears when a city or municipality is entered.' : 'Slug $slug'),
      ]),
      if (_areas.length > 1)
        button(
          classes: _secondaryButton,
          onClick: () => setState(() => _areas = [..._areas]..removeAt(index)),
          [Component.text('Remove area')],
        ),
    ]);
  }

  Component _partnerCard(Map<String, dynamic> row) {
    final id = '${row['partnerId'] ?? ''}';
    final payouts = row['unpaidPayouts'];
    final payoutList = payouts is List ? payouts.whereType<Map>().map((item) => item.cast<String, dynamic>()).toList() : <Map<String, dynamic>>[];
    return article(classes: 'bg-white border border-zinc-200 rounded-2xl p-4 flex flex-col gap-3', [
      div(classes: 'flex flex-wrap items-start justify-between gap-2', [
        div(classes: 'flex flex-col', [
          h3(classes: 'text-sm font-black', [Component.text(id)]),
          span(classes: 'text-[11px] text-zinc-500', [
            Component.text('${row['status'] ?? 'unknown'} · ${_areaText(row['areas'])} · renews ${_when(row['renewalDate'])}'),
          ]),
        ]),
        div(classes: 'flex flex-wrap gap-2', [
          if (row['behindTarget'] == true) _chip('Behind target'),
          if (row['licenseExpiring'] == true) _chip('Expiring'),
          if (row['licenseExpired'] == true) _chip('Expired'),
        ]),
      ]),
      div(classes: 'grid grid-cols-2 md:grid-cols-4 gap-2 text-[11px]', [
        _kpi('Listings', '${row['activeListings'] ?? 0}'),
        _kpi('Providers', '${row['activeProviders'] ?? 0}'),
        _kpi('Bookings', '${row['bookings'] ?? 0}'),
        _kpi('Completed jobs', '${row['completedJobs'] ?? 0}'),
        _kpi('Gross', _money(row['grossVolume'])),
        _kpi('This month', _money(row['earningsThisMonth'])),
        _kpi('Earnings', _money(row['earningsToDate'])),
        _kpi('New users', '${row['newUsers'] ?? 0}'),
      ]),
      div(classes: 'flex flex-wrap gap-2', [
        button(classes: _secondaryButton, onClick: _busy ? null : () => setState(() => _openEdit(row)), [Component.text('Edit')]),
        button(classes: _secondaryButton, onClick: _busy ? null : () => _status('suspend', id), [Component.text('Suspend')]),
        button(classes: _secondaryButton, onClick: _busy ? null : () => _status('deactivate', id), [Component.text('Deactivate')]),
        button(classes: _secondaryButton, onClick: _busy ? null : () => _status('reinstate', id), [Component.text('Reinstate')]),
      ]),
      if (payoutList.isEmpty)
        span(classes: 'text-[11px] text-zinc-400', [Component.text('No unpaid payouts.')])
      else
        div(classes: 'flex flex-col gap-2', [
          for (final payout in payoutList)
            div(classes: 'flex flex-wrap items-center justify-between gap-2 text-[11px]', [
              span([
                Component.text('${payout['id']} · ${payout['status']} · ${_money(payout['amount'])}'),
              ]),
              if (payout['status'] == 'pending')
                button(
                  classes: _secondaryButton,
                  onClick: _busy ? null : () => _payout('approvePayout', '${payout['id']}'),
                  [Component.text('Approve payout')],
                ),
              if (payout['status'] == 'approved')
                button(
                  classes: _secondaryButton,
                  onClick: _busy ? null : () => _payout('markPayoutPaid', '${payout['id']}'),
                  [Component.text('Mark paid')],
                ),
            ]),
        ]),
    ]);
  }

  Future<void> _loadOverview() async {
    await _run(() async {
      final result = await _call(partnerAdminCallable, partnerOverviewData());
      _overview = result;
      _loading = false;
    }, keepLoading: true);
  }

  Future<void> _save() async {
    await _run(() async {
      final caller = context.read(adminAuthProvider).currentUser?.email ?? '';
      final start = _licenseStart.trim().isEmpty ? null : DateTime.tryParse(_licenseStart)?.millisecondsSinceEpoch;
      final data = _editingId == null
          ? partnerCreateData(
              callerEmail: caller,
              email: _email,
              areas: _areas,
              licenseStart: start,
              termMonths: int.tryParse(_termMonths) ?? 36,
              licenseFeePaid: num.tryParse(_fee) ?? 0,
              partnerShareBps: int.tryParse(_share) ?? partnerShareDefaultBps,
              activeListings: int.tryParse(_targetListings) ?? 30,
              activeProviders: int.tryParse(_targetProviders) ?? 30,
              byMonth: int.tryParse(_targetMonths) ?? 6,
            )
          : partnerUpdateData(
              partnerId: _editingId!,
              areas: _areas,
              partnerShareBps: int.tryParse(_share),
              activeListings: int.tryParse(_targetListings),
              activeProviders: int.tryParse(_targetProviders),
              byMonth: int.tryParse(_targetMonths),
              licenseFeePaid: num.tryParse(_fee),
              licenseStart: start,
              termMonths: int.tryParse(_termMonths),
            );
      await _call(partnerAdminCallable, data);
      _showForm = false;
      _notice = _editingId == null
          ? 'Partner requested. No password was created. Enroll TOTP or phone in Identity Platform, and set the portal role to partner if this person should see only the desk.'
          : 'Partner update requested.';
      final result = await _call(partnerAdminCallable, partnerOverviewData());
      _overview = result;
      _loading = false;
    });
  }

  Future<void> _status(String action, String partnerId) async {
    await _run(() async {
      await _call(partnerAdminCallable, partnerStatusData(action: action, partnerId: partnerId));
      _notice = '$action requested for $partnerId.';
      _overview = await _call(partnerAdminCallable, partnerOverviewData());
      _loading = false;
    });
  }

  Future<void> _payout(String action, String payoutId) async {
    await _run(() async {
      await _call(partnerAdminCallable, partnerPayoutData(action: action, payoutId: payoutId));
      _notice = action == 'approvePayout' ? 'Payout approved.' : 'Payout marked paid.';
      _overview = await _call(partnerAdminCallable, partnerOverviewData());
      _loading = false;
    });
  }

  Future<void> _setSubscriptions(bool include) async {
    await _run(() async {
      await _call(partnerAdminCallable, partnerRevenueConfigData(includeSubscriptions: include));
      _notice = include ? 'Subscription revenue is on.' : 'Subscription revenue is off.';
      _overview = await _call(partnerAdminCallable, partnerOverviewData());
      _loading = false;
    });
  }

  Future<void> _run(Future<void> Function() body, {bool keepLoading = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      if (!keepLoading) _notice = null;
    });
    try {
      await body();
      if (mounted) setState(() => _busy = false);
    } on StaffOpsException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _loading = false;
        _error = partnerFacingError(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    final FirebaseApp app = await context.read(firebaseAppProvider.future);
    return callWorkspaceCallable(app, name, data);
  }
}

class PartnerDeskPage extends StatefulComponent {
  const PartnerDeskPage({super.key});

  @override
  State<PartnerDeskPage> createState() => _PartnerDeskPageState();
}

class _PartnerDeskPageState extends State<PartnerDeskPage> {
  bool _started = false;
  bool _loading = true;
  bool _busy = false;
  bool _mfaRequired = false;
  String? _error;
  String _tab = 'dashboard';
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _statement;
  String _period = manilaPeriod(DateTime.now().millisecondsSinceEpoch);
  String _areaKey = '';
  String _kind = 'users';
  String _flagReason = '';
  List<Map<String, dynamic>> _records = [];

  @override
  Component build(BuildContext context) {
    if (!_started) {
      _started = true;
      Future.microtask(_loadDashboard);
    }
    if (_mfaRequired) {
      return div(classes: 'p-8 max-w-xl flex flex-col gap-3', [
        h1(classes: 'text-lg font-black', [Component.text('Enable 2FA')]),
        p(classes: 'text-sm text-zinc-700', [
          Component.text(
            _error ??
                'Enable 2FA. Partner sign-in requires a TOTP or phone second factor enrolled in Identity Platform. This portal cannot enroll it.',
          ),
        ]),
      ]);
    }
    return div(classes: 'p-4 sm:p-8 flex flex-col gap-5 max-w-6xl', [
      h1(classes: 'text-lg font-black text-zinc-900', [Component.text('City partner desk')]),
      if (_error != null) _banner(_error!, danger: true),
      div(classes: 'flex gap-2', [
        _tabButton('Dashboard', 'dashboard'),
        _tabButton('Statement', 'statement'),
        _tabButton('Directory', 'directory'),
      ]),
      if (_loading)
        p(classes: 'text-xs font-semibold text-zinc-400', [Component.text('Loading partner desk...')])
      else if (_tab == 'dashboard')
        _dashboardView()
      else if (_tab == 'statement')
        _statementView()
      else
        _directoryView(),
    ]);
  }

  Component _dashboardView() {
    final row = _dashboard ?? {};
    return div(classes: 'flex flex-col gap-3', [
      p(classes: 'text-xs text-zinc-500', [
        Component.text('${row['status'] ?? ''} · ${_areaText(row['areas'])} · month ${row['monthsElapsed'] ?? 0} · renews ${_when(row['renewalDate'])}'),
      ]),
      if (row['behindTarget'] == true) _banner('Behind target. Listings or providers are still short of the exclusivity target.', danger: true),
      if (row['licenseExpiring'] == true) _banner('This license expires within 30 days.', danger: true),
      div(classes: 'grid grid-cols-2 md:grid-cols-4 gap-2', [
        _kpi('Listings', '${row['activeListings'] ?? 0} / ${_targetOf(row, 'activeListings')}'),
        _kpi('Providers', '${row['activeProviders'] ?? 0} / ${_targetOf(row, 'activeProviders')}'),
        _kpi('Bookings', '${row['bookings'] ?? 0}'),
        _kpi('Completed jobs', '${row['completedJobs'] ?? 0}'),
        _kpi('Gross', _money(row['grossVolume'])),
        _kpi('This month', _money(row['earningsThisMonth'])),
        _kpi('Earnings', _money(row['earningsToDate'])),
        _kpi('New users', '${row['newUsers'] ?? 0}'),
      ]),
    ]);
  }

  Component _statementView() {
    return div(classes: 'flex flex-col gap-3', [
      div(classes: 'flex flex-wrap gap-2 items-end', [
        _field('Period', _period, (value) => setState(() => _period = value), placeholder: 'YYYY-MM'),
        button(classes: _primaryButton, onClick: _busy ? null : _loadStatement, [Component.text('Load statement')]),
        button(classes: _secondaryButton, onClick: _busy ? null : _downloadCsv, [Component.text('CSV')]),
        button(classes: _secondaryButton, onClick: _busy ? null : _downloadPdf, [Component.text('PDF')]),
      ]),
      if (_statement != null) ...[
        p(classes: 'text-xs text-zinc-600', [
          Component.text(
            'Gross ${_money(_statement!['grossBookings'])} · partner ${_money(_statement!['partnerShare'])} · Tranyx ${_money(_statement!['tranyxShare'])}',
          ),
        ]),
        _lines(_statement!['lines']),
      ],
    ]);
  }

  Component _directoryView() {
    final keys = _dashboard?['areaKeys'];
    final known = keys is List ? keys.map((key) => '$key').where((key) => key.isNotEmpty).toList() : <String>[];
    return div(classes: 'flex flex-col gap-3', [
      div(classes: 'flex flex-wrap gap-2 items-end', [
        if (known.isNotEmpty)
          div(classes: 'flex flex-col gap-1', [
            span(classes: 'text-[10px] font-bold uppercase text-zinc-400', [Component.text('Area')]),
            div(classes: 'flex flex-wrap gap-1', [
              for (final key in known)
                button(
                  classes: key == _areaKey ? _primaryButton : _secondaryButton,
                  onClick: () => setState(() => _areaKey = key),
                  [Component.text(key)],
                ),
            ]),
          ])
        else
          _field('Area', _areaKey, (value) => setState(() => _areaKey = value)),
        for (final kind in ['users', 'rentals', 'properties', 'jobs'])
          button(
            classes: _kind == kind ? _primaryButton : _secondaryButton,
            onClick: () => setState(() => _kind = kind),
            [Component.text(kind)],
          ),
        button(classes: _primaryButton, onClick: _busy ? null : _loadDirectory, [Component.text('Load directory')]),
      ]),
      _field('Flag reason', _flagReason, (value) => setState(() => _flagReason = value), placeholder: 'Required to flag'),
      if (_records.isEmpty)
        p(classes: 'text-xs text-zinc-500', [Component.text('No directory rows loaded.')])
      else
        div(classes: 'flex flex-col gap-2', _records.map(_recordCard).toList()),
    ]);
  }

  Component _recordCard(Map<String, dynamic> row) {
    final directoryKind = '${row['_kind'] ?? _kind}';
    final id = '${row['uid'] ?? row['id'] ?? ''}';
    final review = row['partnerReview'];
    final reviewText = review is Map ? '${review['status'] ?? ''}' : '';
    final title = directoryKind == 'users' ? '${row['displayName'] ?? 'Member'}' : '${row['title'] ?? id}';
    return article(classes: 'bg-white border border-zinc-200 rounded-2xl p-3 flex flex-col gap-2', [
      div(classes: 'flex flex-wrap justify-between gap-2', [
        span(classes: 'text-xs font-black', [Component.text(title)]),
        span(classes: 'text-[11px] text-zinc-500', [
          Component.text('${row['city'] ?? row['areaKey'] ?? ''} ${row['status'] ?? ''} ${row['accountType'] ?? ''} $reviewText'),
        ]),
      ]),
      div(classes: 'flex flex-wrap gap-2', [
        button(classes: _secondaryButton, onClick: _busy ? null : () => _review(directoryKind, id, 'approved'), [Component.text('Approve')]),
        button(classes: _secondaryButton, onClick: _busy ? null : () => _review(directoryKind, id, 'verified'), [Component.text('Verify')]),
        button(classes: _secondaryButton, onClick: _busy ? null : () => _review(directoryKind, id, 'flagged'), [Component.text('Flag')]),
      ]),
    ]);
  }

  Component _lines(dynamic lines) {
    if (lines is! List || lines.isEmpty) {
      return p(classes: 'text-xs text-zinc-500', [Component.text('No revenue lines in this period.')]);
    }
    return div(classes: 'overflow-x-auto bg-white border border-zinc-200 rounded-2xl', [
      table(classes: 'w-full text-[11px]', [
        thead([
          tr([
            for (final heading in ['Source', 'Id', 'Area', 'Status', 'Gross', 'Partner'])
              th(classes: 'text-left p-2', [Component.text(heading)]),
          ]),
        ]),
        tbody([
          for (final line in lines.whereType<Map>())
            tr([
              td(classes: 'p-2', [Component.text('${line['source'] ?? ''}')]),
              td(classes: 'p-2', [Component.text('${line['sourceId'] ?? ''}')]),
              td(classes: 'p-2', [Component.text('${line['areaKey'] ?? ''}')]),
              td(classes: 'p-2', [Component.text('${line['status'] ?? ''}')]),
              td(classes: 'p-2', [Component.text(_money(line['gross']))]),
              td(classes: 'p-2', [Component.text(_money(line['partnerShare']))]),
            ]),
        ]),
      ]),
    ]);
  }

  Future<void> _loadDashboard() async {
    await _run(() async {
      _dashboard = await _call(partnerDeskCallable, partnerDeskData(action: 'dashboard'));
      final keys = _dashboard?['areaKeys'];
      if (_areaKey.isEmpty && keys is List && keys.isNotEmpty) _areaKey = '${keys.first}';
      _loading = false;
    });
  }

  Future<void> _loadStatement() async {
    await _run(() async {
      _statement = await _call(partnerDeskCallable, partnerDeskData(action: 'statement', period: _period));
      _tab = 'statement';
    });
  }

  Future<void> _downloadCsv() async {
    await _run(() async {
      final result = await _call(partnerDeskCallable, partnerDeskData(action: 'statementCsv', period: _period));
      final csv = result['csv']?.toString() ?? '';
      if (!csv.startsWith(statementCsvHeader)) {
        throw const StaffOpsException('internal', 'The statement CSV did not include the expected header.');
      }
      _saveFile('partner-$_period.csv', 'text/csv;charset=utf-8', utf8.encode(csv));
    });
  }

  Future<void> _downloadPdf() async {
    await _run(() async {
      final statement = _statement ?? await _call(partnerDeskCallable, partnerDeskData(action: 'statement', period: _period));
      _statement = statement;
      _saveFile('partner-$_period.pdf', 'application/pdf', buildStatementPdf(statement));
    });
  }

  Future<void> _loadDirectory() async {
    await _run(() async {
      final result = await _call(
        partnerDeskCallable,
        partnerDeskData(action: 'directory', areaKey: _areaKey, kind: _kind),
      );
      final records = result['records'];
      _records = records is List
          ? records.whereType<Map>().map((row) => {...row.cast<String, dynamic>(), '_kind': _kind}).toList()
          : [];
      _tab = 'directory';
    });
  }

  Future<void> _review(String directoryKind, String id, String decision) async {
    final kind = switch (directoryKind) {
      'properties' => 'property',
      'jobs' => 'job',
      'users' => 'provider',
      _ => 'rental',
    };
    await _run(() async {
      await _call(
        partnerDeskCallable,
        partnerDeskData(action: 'review', kind: kind, id: id, decision: decision, reason: _flagReason),
      );
      await _loadDirectory();
    });
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
      if (mounted) setState(() => _busy = false);
    } on StaffOpsException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _loading = false;
        _error = partnerFacingError(error);
        _mfaRequired = error.detailCode == 'MFA_REQUIRED' || error.message.toLowerCase().contains('second factor');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    final app = await context.read(firebaseAppProvider.future);
    return callWorkspaceCallable(app, name, data);
  }

  Component _tabButton(String label, String id) {
    return button(
      classes: _tab == id ? _primaryButton : _secondaryButton,
      onClick: () => setState(() => _tab = id),
      [Component.text(label)],
    );
  }
}

Component _field(String caption, String value, void Function(String value) onValue, {String type = 'text', String? placeholder}) {
  return label(classes: 'flex flex-col gap-1 text-[10px] font-bold uppercase tracking-wider text-zinc-400', [
    Component.text(caption),
    input(
      value: value,
      classes: 'bg-white border border-zinc-200 rounded-xl px-3 py-2 text-xs text-zinc-800 normal-case font-medium',
      attributes: {'type': type == 'text' ? 'text' : type, 'placeholder': ?placeholder},
      onInput: (dynamic next) => onValue((next as String?) ?? ''),
    ),
  ]);
}

Component _banner(String text, {required bool danger}) {
  return div(
    classes: 'rounded-2xl px-4 py-3 text-xs font-semibold whitespace-pre-line ${danger ? 'bg-rose-50 text-rose-700 border border-rose-200' : 'bg-emerald-50 text-emerald-800 border border-emerald-200'}',
    [Component.text(text)],
  );
}

Component _alertCard(String title, String body) {
  return div(classes: 'bg-amber-50 border border-amber-200 rounded-2xl p-4 flex flex-col gap-1', [
    h2(classes: 'text-xs font-black text-amber-900', [Component.text(title)]),
    p(classes: 'text-[11px] text-amber-800 whitespace-pre-line', [Component.text(body)]),
  ]);
}

Component _kpi(String label, String value) {
  return div(classes: 'bg-zinc-50 border border-zinc-100 rounded-xl p-3', [
    div(classes: 'text-[10px] uppercase tracking-wider text-zinc-400 font-bold', [Component.text(label)]),
    div(classes: 'text-sm font-black text-zinc-900', [Component.text(value)]),
  ]);
}

Component _chip(String label) {
  return span(classes: 'px-2 py-1 rounded-full bg-amber-100 text-amber-800 text-[10px] font-extrabold', [Component.text(label)]);
}

String _money(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  return number.toStringAsFixed(2);
}

String _when(dynamic value) {
  final ms = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  if (ms <= 0) return 'unset';
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _areaText(dynamic areas) {
  if (areas is! List || areas.isEmpty) return 'No area';
  return areas.map((area) {
    if (area is Map) return '${area['municipality'] ?? area['city'] ?? area['areaKey'] ?? ''}'.trim();
    return '$area';
  }).where((text) => text.isNotEmpty).join(', ');
}

String _targetOf(Map<String, dynamic> row, String key) {
  final targets = row['targets'];
  if (targets is Map && targets[key] != null) return '${targets[key]}';
  return '30';
}

const String _primaryButton =
    'px-3 py-2 rounded-full bg-black text-white text-[11px] font-extrabold cursor-pointer border-0 disabled:opacity-40';
const String _secondaryButton =
    'px-3 py-2 rounded-full border border-zinc-200 bg-white text-zinc-800 text-[11px] font-extrabold cursor-pointer';

void _saveFile(String filename, String mime, List<int> bytes) {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).buffer.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
