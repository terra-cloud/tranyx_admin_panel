/// A public question on a listing. Rentals / properties / jobs store questions in the `questions` subcollection
/// (that is what the web and mobile apps write); `qna` is the legacy name some older docs still use.
class QnaMessage {
  final String id;
  final String senderName;
  final String text;
  final int createdAt;
  final String? reply;

  /// Subcollection this message lives in (`questions` or `qna`), so replies and removals hit the right record.
  final String sub;

  QnaMessage({
    required this.id,
    required this.senderName,
    required this.text,
    required this.createdAt,
    this.reply,
    this.sub = 'questions',
  });

  /// Field the app that owns [sub] reads the answer from.
  static String replyField(String collection, String sub) =>
      sub == 'qna' ? 'reply' : (collection == 'jobs' ? 'answerText' : 'answer');

  factory QnaMessage.fromMap(String id, Map<String, dynamic> map, {String sub = 'questions'}) {
    String firstText(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v is String && v.trim().isNotEmpty) return v;
      }
      return '';
    }

    int ts(dynamic v) {
      if (v is num) return v.toInt();
      try {
        // Firestore Timestamp (duck-typed so this file stays free of Firebase imports)
        final ms = (v as dynamic).millisecondsSinceEpoch;
        return ms is int ? ms : 0;
      } catch (_) {
        return 0;
      }
    }

    final reply = firstText(['answerText', 'answer', 'reply']);
    return QnaMessage(
      id: id,
      senderName: firstText(['authorName', 'name', 'senderName', 'userName']).ifEmpty('User'),
      text: firstText(['questionText', 'text', 'question']),
      createdAt: ts(map['createdAt']),
      reply: reply.isEmpty ? null : reply,
      sub: sub,
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

