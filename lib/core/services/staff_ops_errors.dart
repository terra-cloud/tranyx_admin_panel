import 'dart:convert';

/// Error from the `staffOps` callable. [code] is the Firebase callable status in lower case
/// (`permission-denied`, `failed-precondition`, ...); [detailCode] is the function's own reason
/// (`CLAIMED_BY_OTHER`, `NOT_CLAIMABLE`, `REFERENCE_CLAIMED`).
class StaffOpsException implements Exception {
  final String code;
  final String message;
  final String? detailCode;
  const StaffOpsException(this.code, this.message, {this.detailCode});

  /// True when the outcome is unknown (network / server error): repeating is safe, the server is idempotent per key.
  bool get isIndeterminate => code == 'network' || code == 'internal' || code == 'unavailable';

  @override
  String toString() => message;
}

/// Turns the callable HTTP response into the function's `result` map, or throws a [StaffOpsException].
Map<String, dynamic> parseStaffOpsResponse(int statusCode, String bodyText) {
  Map<String, dynamic> body;
  try {
    body = (jsonDecode(bodyText) as Map).cast<String, dynamic>();
  } catch (_) {
    body = const {};
  }
  if (statusCode == 404) {
    throw const StaffOpsException('network', 'The staff operations service is not deployed for this environment.');
  }
  final error = body['error'];
  if (statusCode >= 400 || error is Map) {
    final e = error is Map ? error.cast<String, dynamic>() : <String, dynamic>{};
    final status = (e['status'] ?? 'INTERNAL').toString().toLowerCase().replaceAll('_', '-');
    final details = e['details'];
    final detailCode = details is Map ? details['code']?.toString() : null;
    throw StaffOpsException(status, (e['message'] ?? 'The request failed.').toString(), detailCode: detailCode);
  }
  final result = body['result'] ?? body['data'];
  return result is Map ? result.cast<String, dynamic>() : <String, dynamic>{};
}
