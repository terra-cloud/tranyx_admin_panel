import '../services/staff_ops_errors.dart';

/// Largest custom bonus `staffAwardPoints` will accept. Named quests do not use this cap.
const int staffAwardCustomPointsCap = 1000;

/// Body for the workspace callable `staffAwardPoints`.
///
/// Named quests send only the target and the quest id. The amount is the server quest
/// table, so this map does not include `points`. A custom award sends a positive integer
/// at or under [staffAwardCustomPointsCap] and the title as `reason`.
Map<String, dynamic> buildStaffAwardPointsData({
  required String targetUid,
  required String questId,
  required String category,
  required String title,
  required int points,
}) {
  final uid = targetUid.trim();
  final id = questId.trim();
  if (uid.isEmpty || id.isEmpty) {
    throw const StaffOpsException('invalid-argument', 'A user and a quest are required.');
  }
  if (category == 'Custom') {
    final reason = title.trim();
    if (reason.isEmpty || reason.length > 200) {
      throw const StaffOpsException('invalid-argument', 'A custom award needs a reason.');
    }
    if (points < 1 || points > staffAwardCustomPointsCap) {
      throw const StaffOpsException(
        'invalid-argument',
        'Custom points must be an integer from 1 to 1000.',
      );
    }
    return {'targetUid': uid, 'questId': id, 'points': points, 'reason': reason};
  }
  return {'targetUid': uid, 'questId': id};
}
