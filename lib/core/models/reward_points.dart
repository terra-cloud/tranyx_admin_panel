/// Largest manual Terra Points award in one go (guards typos such as an extra zero).
const int kMaxManualAwardPoints = 100000;

/// Parses the "Points" box of the manual award form. Returns null unless it is a whole number in
/// 1..[kMaxManualAwardPoints] (digits only, surrounding spaces and thousands commas tolerated).
int? parseAwardPoints(String raw, {int max = kMaxManualAwardPoints}) {
  final cleaned = raw.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+$').hasMatch(cleaned)) return null;
  final n = int.tryParse(cleaned);
  if (n == null || n < 1 || n > max) return null;
  return n;
}
