import '../services/staff_ops_errors.dart';

/// Client contract for workspace `partnerAdmin` and `partnerDesk` (terra-cloud/tranyx
/// `docs/city_partner.md` at 394b30f). The portal sends these bodies. It does not write
/// partner, revenue, statement, or payout documents.

const String partnerAdminCallable = 'partnerAdmin';
const String partnerDeskCallable = 'partnerDesk';

const String statementCsvHeader =
    'period,source,sourceId,areaKey,status,gross,platformRevenue,partnerShare,tranyxShare';

const int partnerShareDefaultBps = 7000;

/// Same slug as `slugArea` in `functions/src/partner.ts`: lowercase, non-alphanumerics
/// become hyphens, edges trimmed, 80 characters. Province does not change the slug.
String slugArea(String? value) {
  final raw = (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  if (raw.length <= 80) return raw;
  return raw.substring(0, 80).replaceAll(RegExp(r'-+$'), '');
}

/// Asia/Manila calendar month, matching `periodOf` (UTC fields of `ms + 8h`).
String manilaPeriod(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs + 8 * 3600000, isUtc: true);
  final month = d.month.toString().padLeft(2, '0');
  return '${d.year}-$month';
}

bool validStatementPeriod(String period) => RegExp(r'^\d{4}-\d{2}$').hasMatch(period);

Map<String, dynamic> _areaMap(Map<String, String> row) {
  final city = (row['city'] ?? '').trim();
  final municipality = (row['municipality'] ?? '').trim();
  final name = municipality.isNotEmpty ? municipality : city;
  final key = slugArea(name);
  if (key.isEmpty || !RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,78}[a-z0-9])?$').hasMatch(key)) {
    throw const StaffOpsException('invalid-argument', 'Each area needs a city or municipality.');
  }
  return {
    'city': city.isNotEmpty ? city : municipality,
    if (municipality.isNotEmpty) 'municipality': municipality,
    if ((row['province'] ?? '').trim().isNotEmpty) 'province': row['province']!.trim(),
    if ((row['region'] ?? '').trim().isNotEmpty) 'region': row['region']!.trim(),
  };
}

/// One to ten areas. Two rows with the same slug are `already-exists` / `DUPLICATE_AREA`
/// before a request is sent. `Calbayog` and `Calbayog` in another province are one area.
List<Map<String, dynamic>> partnerAreas(List<Map<String, String>> rows) {
  final filled = rows.where((row) {
    final city = (row['city'] ?? '').trim();
    final municipality = (row['municipality'] ?? '').trim();
    return city.isNotEmpty || municipality.isNotEmpty;
  }).toList();
  if (filled.isEmpty || filled.length > 10) {
    throw const StaffOpsException('invalid-argument', 'Assign one to ten areas.');
  }
  final areas = filled.map(_areaMap).toList();
  final keys = areas.map((area) => slugArea((area['municipality'] ?? area['city']).toString())).toList();
  if (keys.toSet().length != keys.length) {
    throw const StaffOpsException(
      'already-exists',
      'That area is already on this partner.',
      detailCode: 'DUPLICATE_AREA',
    );
  }
  return areas;
}

Map<String, dynamic> partnerTargets({
  required int activeListings,
  required int activeProviders,
  required int byMonth,
}) {
  if (activeListings < 0 || activeProviders < 0 || byMonth < 1 || byMonth > 120) {
    throw const StaffOpsException('invalid-argument', 'Exclusivity targets are out of range.');
  }
  return {'activeListings': activeListings, 'activeProviders': activeProviders, 'byMonth': byMonth};
}

int partnerShareBpsOf(int bps) {
  if (bps < 0 || bps > 10000) {
    throw const StaffOpsException('invalid-argument', 'partnerShareBps must be an integer from 0 to 10000.');
  }
  return bps;
}

int tranyxShareBps(int partnerShareBps) => 10000 - partnerShareBpsOf(partnerShareBps);

Map<String, dynamic> partnerCreateData({
  required String callerEmail,
  required String email,
  required List<Map<String, String>> areas,
  int? licenseStart,
  int termMonths = 36,
  num licenseFeePaid = 0,
  int partnerShareBps = partnerShareDefaultBps,
  int activeListings = 30,
  int activeProviders = 30,
  int byMonth = 6,
}) {
  final staff = email.trim().toLowerCase();
  if (!staff.contains('@') || staff.startsWith('@') || staff.endsWith('@')) {
    throw const StaffOpsException('invalid-argument', 'A partner email is required.');
  }
  if (callerEmail.trim().toLowerCase() == staff) {
    throw const StaffOpsException(
      'permission-denied',
      'You cannot make your own account a partner.',
      detailCode: 'SELF_ROLE',
    );
  }
  if (termMonths < 1 || termMonths > 120) {
    throw const StaffOpsException('invalid-argument', 'termMonths must be from 1 to 120.');
  }
  if (licenseFeePaid < 0) {
    throw const StaffOpsException('invalid-argument', 'licenseFeePaid cannot be negative.');
  }
  return {
    'action': 'create',
    'email': staff,
    'areas': partnerAreas(areas),
    'licenseStart': ?licenseStart,
    'termMonths': termMonths,
    'licenseFeePaid': licenseFeePaid,
    'partnerShareBps': partnerShareBpsOf(partnerShareBps),
    'targets': partnerTargets(
      activeListings: activeListings,
      activeProviders: activeProviders,
      byMonth: byMonth,
    ),
  };
}

Map<String, dynamic> partnerUpdateData({
  required String partnerId,
  List<Map<String, String>>? areas,
  int? partnerShareBps,
  int? activeListings,
  int? activeProviders,
  int? byMonth,
  num? licenseFeePaid,
  int? licenseStart,
  int? termMonths,
}) {
  final id = partnerId.trim();
  if (id.isEmpty) throw const StaffOpsException('invalid-argument', 'partnerId is required.');
  final data = <String, dynamic>{'action': 'update', 'partnerId': id};
  if (areas != null) data['areas'] = partnerAreas(areas);
  if (partnerShareBps != null) data['partnerShareBps'] = partnerShareBpsOf(partnerShareBps);
  if (activeListings != null || activeProviders != null || byMonth != null) {
    data['targets'] = partnerTargets(
      activeListings: activeListings ?? 30,
      activeProviders: activeProviders ?? 30,
      byMonth: byMonth ?? 6,
    );
  }
  if (licenseFeePaid != null) {
    if (licenseFeePaid < 0) {
      throw const StaffOpsException('invalid-argument', 'licenseFeePaid cannot be negative.');
    }
    data['licenseFeePaid'] = licenseFeePaid;
  }
  if (termMonths != null) {
    if (termMonths < 1 || termMonths > 120) {
      throw const StaffOpsException('invalid-argument', 'termMonths must be from 1 to 120.');
    }
    data['termMonths'] = termMonths;
  }
  if (licenseStart != null) data['licenseStart'] = licenseStart;
  return data;
}

Map<String, dynamic> partnerStatusData({required String action, required String partnerId}) {
  if (action != 'suspend' && action != 'deactivate' && action != 'reinstate') {
    throw StaffOpsException('invalid-argument', 'Unknown partner action.', detailCode: 'invalid-argument');
  }
  final id = partnerId.trim();
  if (id.isEmpty) throw const StaffOpsException('invalid-argument', 'partnerId is required.');
  return {'action': action, 'partnerId': id};
}

Map<String, dynamic> partnerPayoutData({required String action, required String payoutId}) {
  if (action != 'approvePayout' && action != 'markPayoutPaid') {
    throw const StaffOpsException('invalid-argument', 'Unknown partner action.');
  }
  final id = payoutId.trim();
  if (id.isEmpty) throw const StaffOpsException('invalid-argument', 'payoutId is required.');
  return {'action': action, 'payoutId': id};
}

Map<String, dynamic> partnerRevenueConfigData({required bool includeSubscriptions}) {
  return {'action': 'setRevenueConfig', 'includeSubscriptions': includeSubscriptions};
}

Map<String, dynamic> partnerOverviewData() => {'action': 'overview'};

Map<String, dynamic> partnerDeskData({
  required String action,
  String? partnerId,
  String? period,
  String? areaKey,
  String? kind,
  String? id,
  String? decision,
  String? reason,
}) {
  const allowed = {'dashboard', 'statement', 'statementCsv', 'directory', 'review', 'overview'};
  if (!allowed.contains(action)) {
    throw const StaffOpsException('invalid-argument', 'Unknown partner desk action.');
  }
  final data = <String, dynamic>{'action': action};
  final pid = partnerId?.trim() ?? '';
  if (pid.isNotEmpty) data['partnerId'] = pid;
  if (action == 'statement' || action == 'statementCsv') {
    final month = (period ?? '').trim();
    if (!validStatementPeriod(month)) {
      throw const StaffOpsException('invalid-argument', 'period must be YYYY-MM.');
    }
    data['period'] = month;
  }
  if (action == 'directory') {
    final key = slugArea(areaKey);
    if (key.isEmpty) throw const StaffOpsException('invalid-argument', 'Each area needs a city or municipality.');
    const kinds = {'users', 'rentals', 'properties', 'jobs'};
    if (!kinds.contains(kind)) {
      throw const StaffOpsException('invalid-argument', 'kind must be users, rentals, properties, or jobs.');
    }
    data['areaKey'] = key;
    data['kind'] = kind;
  }
  if (action == 'review') {
    const decisions = {'approved', 'verified', 'flagged'};
    const kinds = {'rental', 'property', 'job', 'provider'};
    if (!decisions.contains(decision)) {
      throw const StaffOpsException('invalid-argument', 'decision must be approved, verified, or flagged.');
    }
    if (!kinds.contains(kind) || (id ?? '').trim().isEmpty) {
      throw const StaffOpsException('invalid-argument', 'kind and id are required.');
    }
    final why = (reason ?? '').trim();
    if (decision == 'flagged' && why.length < 3) {
      throw const StaffOpsException('invalid-argument', 'A flag needs a short reason.');
    }
    data['kind'] = kind;
    data['id'] = id!.trim();
    data['decision'] = decision;
    if (why.isNotEmpty) data['reason'] = why;
  }
  return data;
}

/// Text shown in place of a spinner. Keeps `OUTSIDE_AREA` and `already-exists` visible.
String partnerFacingError(StaffOpsException error) {
  final message = error.message.trim();
  final lower = message.toLowerCase();
  if (error.detailCode == 'MFA_REQUIRED' || lower.contains('second factor')) {
    return 'Enable 2FA. Partner sign-in requires a TOTP or phone second factor enrolled in Identity Platform. This portal cannot enroll it.';
  }
  if (error.detailCode == 'OUTSIDE_AREA' || lower.contains('outside this license')) {
    return 'OUTSIDE_AREA: $message';
  }
  if (error.code == 'already-exists' || error.detailCode == 'DUPLICATE_AREA') {
    return 'already-exists: $message';
  }
  if (error.detailCode == 'LICENSE_INACTIVE') return 'LICENSE_INACTIVE: $message';
  if (error.detailCode == 'LICENSE_EXPIRED') return 'LICENSE_EXPIRED: $message';
  if (error.detailCode == 'PAYOUT_STATUS') return 'PAYOUT_STATUS: $message';
  if (error.detailCode == 'SELF_ROLE') return message;
  if (error.detailCode != null && error.detailCode!.isNotEmpty) return '${error.detailCode}: $message';
  if (error.code == 'permission-denied' || error.code == 'failed-precondition' || error.code == 'not-found') {
    return message;
  }
  return message.isEmpty ? 'The partner request failed.' : message;
}

/// Client-rendered statement PDF. The server returns JSON; this is not a server file.
List<int> buildStatementPdf(Map<String, dynamic> statement) {
  final lines = <String>[
    'Tranyx city partner statement',
    'Period ${statement['period'] ?? ''}',
    'Partner ${statement['partnerId'] ?? ''}',
    'Gross ${statement['grossBookings'] ?? 0}',
    'Platform ${statement['platformRevenue'] ?? 0}',
    'Partner share ${statement['partnerShare'] ?? 0}',
    'Tranyx share ${statement['tranyxShare'] ?? 0}',
  ];
  final rows = statement['lines'];
  if (rows is List) {
    final shown = rows.take(40);
    for (final row in shown) {
      if (row is Map) {
        lines.add(
          '${row['source'] ?? ''} ${row['sourceId'] ?? ''} ${row['areaKey'] ?? ''} ${row['status'] ?? ''} share ${row['partnerShare'] ?? 0}',
        );
      }
    }
    if (rows.length > 40) lines.add('Further lines are in the CSV export.');
  }
  return _pdfDocument(lines);
}

List<int> _pdfDocument(List<String> lines) {
  final commands = StringBuffer('BT /F1 11 Tf 48 760 Td 14 TL\n');
  for (final line in lines) {
    commands.write('(${_pdfEscape(line)}) Tj T*\n');
  }
  commands.write('ET');
  final stream = commands.toString();
  final objects = <String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Count 1 /Kids [3 0 R] >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n',
    '4 0 obj << /Length ${stream.length} >> stream\n$stream\nendstream endobj\n',
    '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n',
  ];
  final body = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (final object in objects) {
    offsets.add(body.length);
    body.write(object);
  }
  final xref = body.length;
  body.write('xref\n0 ${objects.length + 1}\n');
  body.write('0000000000 65535 f \n');
  for (var i = 1; i < offsets.length; i++) {
    body.write('${offsets[i].toString().padLeft(10, '0')} 00000 n \n');
  }
  body.write('trailer << /Size ${objects.length + 1} /Root 1 0 R >>\n');
  body.write('startxref\n$xref\n%%EOF');
  return body.toString().codeUnits;
}

String _pdfEscape(String raw) {
  final ascii = raw.replaceAll(RegExp(r'[^\x20-\x7E]'), ' ');
  return ascii.replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)');
}
