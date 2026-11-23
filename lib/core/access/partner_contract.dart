import '../services/staff_ops_errors.dart';

/// Phase 1 city-partner contract (TRAD-15 sections 1, 2, and 7).
///
/// `partnerAdmin` creates and changes the license. `partnerDesk` `profile` and `directory`
/// are the partner's area monitor. Revenue, statements, payouts, and earnings KPIs are not sent.

const String partnerAdminCallable = 'partnerAdmin';
const String partnerDeskCallable = 'partnerDesk';

const Set<String> partnerDirectoryKinds = {
  'hosts',
  'renters',
  'rentals',
  'properties',
  'providers',
  'gigs',
  'bookings',
  'tickets',
};

const Set<String> partnerReviewKinds = {'rental', 'property', 'job', 'provider'};

/// Same slug as `slugArea` in workspace `functions/src/partner.ts`.
String slugArea(String? value) {
  final raw = (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  if (raw.length <= 80) return raw;
  return raw.substring(0, 80).replaceAll(RegExp(r'-+$'), '');
}

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

/// One to ten areas. A repeated slug is `already-exists` / `DUPLICATE_AREA` before a request.
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

Map<String, dynamic> partnerCreateData({
  required String callerEmail,
  required String email,
  required List<Map<String, String>> areas,
  int? licenseStart,
  int termMonths = 36,
  num licenseFeePaid = 0,
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
  };
}

Map<String, dynamic> partnerUpdateData({
  required String partnerId,
  List<Map<String, String>>? areas,
  num? licenseFeePaid,
  int? licenseStart,
  int? termMonths,
}) {
  final id = partnerId.trim();
  if (id.isEmpty) throw const StaffOpsException('invalid-argument', 'partnerId is required.');
  final data = <String, dynamic>{'action': 'update', 'partnerId': id};
  if (areas != null) data['areas'] = partnerAreas(areas);
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
    throw const StaffOpsException('invalid-argument', 'Unknown partner action.');
  }
  final id = partnerId.trim();
  if (id.isEmpty) throw const StaffOpsException('invalid-argument', 'partnerId is required.');
  return {'action': action, 'partnerId': id};
}

Map<String, dynamic> partnerAccountsData() => {'action': 'accounts'};

Map<String, dynamic> partnerProfileData() => {'action': 'profile'};

Map<String, dynamic> partnerDirectoryData({required String areaKey, required String kind}) {
  final key = slugArea(areaKey);
  if (key.isEmpty) throw const StaffOpsException('invalid-argument', 'Each area needs a city or municipality.');
  if (!partnerDirectoryKinds.contains(kind)) {
    throw const StaffOpsException('invalid-argument', 'kind must be hosts, renters, rentals, properties, providers, gigs, bookings, or tickets.');
  }
  return {'action': 'directory', 'areaKey': key, 'kind': kind};
}

Map<String, dynamic> partnerReviewData({
  required String kind,
  required String id,
  required String decision,
  String? reason,
}) {
  if (!partnerReviewKinds.contains(kind)) {
    throw const StaffOpsException('invalid-argument', 'kind and id are required.');
  }
  final record = id.trim();
  if (record.isEmpty) throw const StaffOpsException('invalid-argument', 'kind and id are required.');
  if (decision != 'approved' && decision != 'verified' && decision != 'flagged') {
    throw const StaffOpsException('invalid-argument', 'decision must be approved, verified, or flagged.');
  }
  final why = (reason ?? '').trim();
  if (decision == 'flagged' && why.length < 3) {
    throw const StaffOpsException('invalid-argument', 'A flag needs a short reason.');
  }
  return {
    'action': 'review',
    'kind': kind,
    'id': record,
    'decision': decision,
    if (why.isNotEmpty) 'reason': why,
  };
}

/// Shown instead of a spinner. Keeps `OUTSIDE_AREA` and `already-exists` visible.
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
  if (error.detailCode == 'SELF_ROLE') return message;
  return message.isEmpty ? 'The partner request failed.' : message;
}

String reviewKindForDirectory(String directoryKind) {
  return switch (directoryKind) {
    'properties' => 'property',
    'gigs' => 'job',
    'hosts' || 'providers' => 'provider',
    'rentals' => 'rental',
    _ => '',
  };
}
