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
  String? _editingId;
  String? _setupEmail;
  String? _setupLink;
  List<Map<String, dynamic>> _partners = [];

  String _email = '';
  String _licenseStart = '';
  String _termMonths = '36';
  String _fee = '0';
  List<Map<String, String>> _areas = [_blankArea()];

  static Map<String, String> _blankArea() => {'city': '', 'municipality': '', 'province': '', 'region': ''};

  @override
  Component build(BuildContext context) {
    if (!_started) {
      _started = true;
      Future.microtask(_load);
    }
    return div(classes: 'p-4 sm:p-8 flex flex-col gap-5 max-w-5xl', [
      div(classes: 'flex flex-wrap items-end justify-between gap-3', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-lg font-black text-zinc-900', [Component.text('City partners')]),
          p(classes: 'text-xs text-zinc-500 max-w-xl', [
            Component.text(
              'Create a license, assign areas, and suspend or deactivate the account. An area with an active partner cannot be assigned again. No password is created here.',
            ),
          ]),
        ]),
        button(onClick: _busy ? null : () => setState(_openCreate), classes: _primary, [Component.text('Create partner')]),
      ]),
      if (_error != null) _banner(_error!, danger: true),
      if (_notice != null) _banner(_notice!, danger: false),
      if (_setupLink != null && _setupLink!.isNotEmpty) _setupPanel(),
      if (_loading)
        p(classes: 'text-xs font-semibold text-zinc-400', [Component.text('Loading city partners...')])
      else ...[
        if (_showForm) _form(),
        if (_partners.isEmpty)
          p(classes: 'text-xs text-zinc-500', [Component.text('No partners on this environment yet.')])
        else
          div(classes: 'flex flex-col gap-3', _partners.map(_card).toList()),
      ],
    ]);
  }

  void _openCreate() {
    _editingId = null;
    _email = '';
    _licenseStart = '';
    _termMonths = '36';
    _fee = '0';
    _areas = [_blankArea()];
    _showForm = true;
    _error = null;
  }

  void _openEdit(Map<String, dynamic> row) {
    _editingId = '${row['partnerId'] ?? ''}';
    _fee = '${row['licenseFeePaid'] ?? 0}';
    _termMonths = '${row['termMonths'] ?? 36}';
    final start = row['licenseStart'];
    _licenseStart = start is num && start > 0 ? _dateInput(start.toInt()) : '';
    final areas = row['areas'];
    _areas = areas is List && areas.isNotEmpty
        ? areas.whereType<Map>().map((area) => {
            'city': '${area['city'] ?? ''}',
            'municipality': '${area['municipality'] ?? ''}',
            'province': '${area['province'] ?? ''}',
            'region': '${area['region'] ?? ''}',
          }).toList()
        : [_blankArea()];
    _showForm = true;
    _error = null;
  }

  Component _form() {
    final editing = _editingId != null;
    return div(classes: 'bg-white border border-zinc-200 rounded-2xl p-4 flex flex-col gap-3', [
      h2(classes: 'text-sm font-black', [Component.text(editing ? 'Edit ${_editingId!}' : 'New partner')]),
      if (!editing) _field('Email', _email, (value) => setState(() => _email = value), type: 'email'),
      _field('License start', _licenseStart, (value) => setState(() => _licenseStart = value), type: 'date'),
      div(classes: 'grid gap-3 sm:grid-cols-2', [
        _field('Term months', _termMonths, (value) => setState(() => _termMonths = value), type: 'number'),
        _field('License fee paid', _fee, (value) => setState(() => _fee = value), type: 'number'),
      ]),
      p(classes: 'text-[11px] text-zinc-500', [
        Component.text('The area slug uses the municipality, otherwise the city. Province does not split the lock. Default term is 36 months.'),
      ]),
      ..._areas.asMap().entries.map((entry) => _areaRow(entry.key, entry.value)),
      div(classes: 'flex flex-wrap gap-2', [
        if (_areas.length < 10)
          button(classes: _secondary, onClick: () => setState(() => _areas = [..._areas, _blankArea()]), [Component.text('Add area')]),
        button(classes: _primary, onClick: _busy ? null : _save, [Component.text(_busy ? 'Saving...' : 'Save license')]),
        button(classes: _secondary, onClick: () => setState(() => _showForm = false), [Component.text('Close')]),
      ]),
    ]);
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
        button(classes: _secondary, onClick: () => setState(() => _areas = [..._areas]..removeAt(index)), [Component.text('Remove area')]),
    ]);
  }

  Component _card(Map<String, dynamic> row) {
    final id = '${row['partnerId'] ?? ''}';
    return article(classes: 'bg-white border border-zinc-200 rounded-2xl p-4 flex flex-col gap-2', [
      div(classes: 'flex flex-wrap justify-between gap-2', [
        div(classes: 'flex flex-col', [
          h3(classes: 'text-sm font-black', [Component.text('${row['email'] ?? id}')]),
          span(classes: 'text-[11px] text-zinc-500', [
            Component.text('$id · ${row['status'] ?? 'unknown'} · ${_areaText(row['areas'])}'),
          ]),
        ]),
        span(classes: 'text-[11px] text-zinc-500', [
          Component.text('Starts ${_when(row['licenseStart'])} · ${row['termMonths'] ?? 36} months · renews ${_when(row['renewalDate'])} · fee ${_money(row['licenseFeePaid'])}'),
        ]),
      ]),
      div(classes: 'flex flex-wrap gap-2', [
        button(classes: _secondary, onClick: _busy ? null : () => setState(() => _openEdit(row)), [Component.text('Edit')]),
        button(classes: _secondary, onClick: _busy ? null : () => _status('suspend', id), [Component.text('Suspend')]),
        button(classes: _secondary, onClick: _busy ? null : () => _status('deactivate', id), [Component.text('Deactivate')]),
        button(classes: _secondary, onClick: _busy ? null : () => _status('reinstate', id), [Component.text('Reinstate')]),
      ]),
    ]);
  }

  Future<void> _load() => _run(() async {
        final result = await _call(partnerAdminCallable, partnerAccountsData());
        _partners = _rows(result['partners']);
        _loading = false;
      });

  Future<void> _save() => _run(() async {
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
              )
            : partnerUpdateData(
                partnerId: _editingId!,
                areas: _areas,
                licenseStart: start,
                termMonths: int.tryParse(_termMonths),
                licenseFeePaid: num.tryParse(_fee),
              );
        if (_editingId == null) data['portalOrigin'] = web.window.location.origin;
        final saved = await _call(partnerAdminCallable, data);
        _showForm = false;
        if (_editingId == null) {
          _setupEmail = '${saved['email'] ?? _email}';
          _setupLink = saved['passwordSetupLink']?.toString();
          _notice = _setupLink == null || _setupLink!.isEmpty
              ? 'Partner requested, but no set-password link came back. Use Resend after portal provisioning is configured.'
              : 'The portal role is partner. Copy the set-password link. No password was created or shown.';
        } else {
          _notice = 'License update requested.';
        }
        final result = await _call(partnerAdminCallable, partnerAccountsData());
        _partners = _rows(result['partners']);
        _loading = false;
      });

  Component _setupPanel() {
    return div(classes: 'bg-white border border-zinc-200 rounded-2xl p-4 flex flex-col gap-2', [
      h2(classes: 'text-sm font-black', [Component.text('Set-password link')]),
      p(classes: 'text-[11px] text-zinc-500', [
        Component.text('Give this link to ${_setupEmail ?? 'the partner'}. It opens the portal sign-in page so they can choose a password. It is not a password.'),
      ]),
      input(
        value: _setupLink ?? '',
        classes: 'bg-zinc-50 border border-zinc-200 rounded-xl px-3 py-2 text-[11px] text-zinc-800',
        attributes: {'readonly': 'true'},
      ),
      div(classes: 'flex flex-wrap gap-2', [
        button(classes: _secondary, onClick: _copySetupLink, [Component.text('Copy link')]),
        button(classes: _secondary, onClick: _busy ? null : _resendSetupLink, [Component.text('Resend link')]),
      ]),
    ]);
  }

  Future<void> _copySetupLink() async {
    final link = _setupLink ?? '';
    if (link.isEmpty) return;
    try {
      web.window.navigator.clipboard.writeText(link);
      if (mounted) setState(() => _notice = 'Set-password link copied.');
    } catch (_) {
      if (mounted) setState(() => _notice = 'Select the link and copy it.');
    }
  }

  Future<void> _resendSetupLink() => _run(() async {
        final email = _setupEmail ?? '';
        final result = await _call(
          partnerAdminCallable,
          partnerPasswordSetupData(email: email, portalOrigin: web.window.location.origin),
        );
        _setupLink = result['passwordSetupLink']?.toString();
        _notice = 'A new set-password link is ready. No password was created.';
      });

  Future<void> _status(String action, String partnerId) => _run(() async {
        await _call(partnerAdminCallable, partnerStatusData(action: action, partnerId: partnerId));
        _notice = '$action requested for $partnerId.';
        final result = await _call(partnerAdminCallable, partnerAccountsData());
        _partners = _rows(result['partners']);
        _loading = false;
      });

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
  bool _mfaHardStop = false;
  String? _error;
  String _kind = 'overview';
  String _areaKey = '';
  String _flagReason = '';
  Map<String, dynamic> _profile = {};
  List<Map<String, dynamic>> _records = [];

  static const _lists = {
    'hosts': 'Hosts',
    'renters': 'Renters',
    'rentals': 'Vehicle listings',
    'properties': 'Property listings',
    'providers': 'Service providers',
    'gigs': 'Gig jobs',
    'bookings': 'Bookings',
    'tickets': 'Support tickets',
  };

  @override
  Component build(BuildContext context) {
    if (!_started) {
      _started = true;
      Future.microtask(_loadProfile);
    }
    if (_mfaHardStop) {
      return div(classes: 'p-8 max-w-xl flex flex-col gap-3', [
        h1(classes: 'text-lg font-black', [Component.text('Enable 2FA')]),
        p(classes: 'text-sm text-zinc-700', [Component.text(_error ?? 'Enable 2FA before opening this area.')]),
      ]);
    }
    final keys = _profile['areaKeys'];
    final areas = keys is List ? keys.map((key) => '$key').where((key) => key.isNotEmpty).toList() : <String>[];
    return div(classes: 'p-4 sm:p-8 flex flex-col gap-4 max-w-5xl', [
      h1(classes: 'text-lg font-black text-zinc-900', [Component.text('Your area')]),
      if (_profile['mfaEnrolled'] != true)
        _banner(
          'Enable 2FA. This desk is open before Identity Platform MFA is enforced. Zeus still needs to turn on TOTP or phone for this project and enroll this partner. Direct area reads stay denied until that second factor is on the token.',
          danger: true,
        ),
      if (_error != null) _banner(_error!, danger: true),
      if (_loading)
        p(classes: 'text-xs font-semibold text-zinc-400', [Component.text('Loading your area...')])
      else
        div(classes: 'bg-white border border-zinc-200 rounded-2xl p-4 text-xs text-zinc-600', [
          Component.text(
            '${_profile['status'] ?? ''} · ${_areaText(_profile['areas'])} · renews ${_when(_profile['renewalDate'])} · fee ${_money(_profile['licenseFeePaid'])}',
          ),
        ]),
      div(classes: 'flex flex-wrap gap-2', [
        _tab('Overview', 'overview'),
        for (final entry in _lists.entries) _tab(entry.value, entry.key),
      ]),
      if (areas.isNotEmpty && _kind != 'overview')
        div(classes: 'flex flex-wrap gap-2', [
          for (final key in areas)
            button(
              classes: key == _areaKey ? _primary : _secondary,
              onClick: () => setState(() => _areaKey = key),
              [Component.text(key)],
            ),
          button(classes: _primary, onClick: _busy ? null : _loadList, [Component.text('Load')]),
        ]),
      if (reviewKindForDirectory(_kind).isNotEmpty)
        _field('Flag reason', _flagReason, (value) => setState(() => _flagReason = value), placeholder: 'Required to flag'),
      if (_kind != 'overview' && _records.isEmpty && !_loading)
        p(classes: 'text-xs text-zinc-500', [Component.text('No rows in this area.')])
      else if (_kind != 'overview')
        div(classes: 'flex flex-col gap-2', _records.map(_record).toList()),
    ]);
  }

  Component _record(Map<String, dynamic> row) {
    final id = '${row['uid'] ?? row['id'] ?? ''}';
    final title = '${row['displayName'] ?? row['title'] ?? row['subject'] ?? id}';
    final review = row['partnerReview'];
    final reviewText = review is Map ? '${review['status'] ?? ''}' : '';
    final kind = reviewKindForDirectory(_kind);
    return article(classes: 'bg-white border border-zinc-200 rounded-2xl p-3 flex flex-col gap-2', [
      div(classes: 'flex flex-wrap justify-between gap-2', [
        span(classes: 'text-xs font-black', [Component.text(title)]),
        span(classes: 'text-[11px] text-zinc-500', [
          Component.text('${row['status'] ?? ''} ${row['areaKey'] ?? _areaKey} $reviewText'),
        ]),
      ]),
      if (kind.isNotEmpty)
        div(classes: 'flex flex-wrap gap-2', [
          button(classes: _secondary, onClick: _busy ? null : () => _review(kind, id, 'approved'), [Component.text('Approve')]),
          button(classes: _secondary, onClick: _busy ? null : () => _review(kind, id, 'verified'), [Component.text('Verify')]),
          button(classes: _secondary, onClick: _busy ? null : () => _review(kind, id, 'flagged'), [Component.text('Flag')]),
        ]),
    ]);
  }

  Component _tab(String label, String id) {
    return button(
      classes: _kind == id ? _primary : _secondary,
      onClick: () {
        setState(() {
          _kind = id;
          _records = [];
          _error = null;
        });
        if (id != 'overview') Future.microtask(_loadList);
      },
      [Component.text(label)],
    );
  }

  Future<void> _loadProfile() => _run(() async {
        _profile = await _call(partnerDeskCallable, partnerProfileData());
        final keys = _profile['areaKeys'];
        if (_areaKey.isEmpty && keys is List && keys.isNotEmpty) _areaKey = '${keys.first}';
        _loading = false;
      });

  Future<void> _loadList() => _run(() async {
        final result = await _call(partnerDeskCallable, partnerDirectoryData(areaKey: _areaKey, kind: _kind));
        _records = _rows(result['records']);
      });

  Future<void> _review(String kind, String id, String decision) => _run(() async {
        await _call(
          partnerDeskCallable,
          partnerReviewData(kind: kind, id: id, decision: decision, reason: _flagReason),
        );
        await _loadList();
      });

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
      final hard = error.detailCode == 'MFA_REQUIRED';
      setState(() {
        _busy = false;
        _loading = false;
        _error = partnerFacingError(error);
        _mfaHardStop = hard;
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
}

List<Map<String, dynamic>> _rows(dynamic raw) {
  if (raw is! List) return [];
  return raw.whereType<Map>().map((row) => row.cast<String, dynamic>()).toList();
}

Component _field(String caption, String value, void Function(String value) onValue, {String type = 'text', String? placeholder}) {
  return label(classes: 'flex flex-col gap-1 text-[10px] font-bold uppercase tracking-wider text-zinc-400', [
    Component.text(caption),
    input(
      value: value,
      classes: 'bg-white border border-zinc-200 rounded-xl px-3 py-2 text-xs text-zinc-800 normal-case font-medium',
      attributes: {'type': type, 'placeholder': ?placeholder},
      onInput: (dynamic next) => onValue((next as String?) ?? ''),
    ),
  ]);
}

Component _banner(String text, {required bool danger}) {
  return div(
    classes: 'rounded-2xl px-4 py-3 text-xs font-semibold ${danger ? 'bg-rose-50 text-rose-700 border border-rose-200' : 'bg-emerald-50 text-emerald-800 border border-emerald-200'}',
    [Component.text(text)],
  );
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

String _dateInput(int ms) {
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

const String _primary = 'px-3 py-2 rounded-full bg-black text-white text-[11px] font-extrabold cursor-pointer border-0 disabled:opacity-40';
const String _secondary = 'px-3 py-2 rounded-full border border-zinc-200 bg-white text-zinc-800 text-[11px] font-extrabold cursor-pointer';
