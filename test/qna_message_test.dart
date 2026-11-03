import 'dart:io';

import 'package:tranyx_admin_portal/core/models/qna_message.dart';

/// Plain script test: `dart run test/qna_message_test.dart`.
void main() {
  var failed = 0;
  void check(String name, bool ok) {
    print('${ok ? 'PASS' : 'FAIL'}  $name');
    if (!ok) failed++;
  }

  final mobile = QnaMessage.fromMap('q1', {'uid': 'u1', 'name': 'Ana', 'text': 'Is the car available on Friday?', 'createdAt': 1700000000000, 'answer': 'Yes.'});
  check('mobile rental question (name/text/answer)', mobile.senderName == 'Ana' && mobile.text == 'Is the car available on Friday?' && mobile.reply == 'Yes.' && mobile.sub == 'questions');

  final web = QnaMessage.fromMap('q2', {'authorName': 'Ben', 'questionText': 'Bring your own paint?', 'answerText': '', 'createdAt': 5});
  check('web job question (authorName/questionText, empty answer is no reply)', web.senderName == 'Ben' && web.text == 'Bring your own paint?' && web.reply == null && web.createdAt == 5);

  final legacy = QnaMessage.fromMap('q3', {'senderName': 'Cy', 'question': 'Pets?', 'reply': 'No pets'}, sub: 'qna');
  check('legacy qna doc keeps its subcollection', legacy.sub == 'qna' && legacy.reply == 'No pets' && legacy.text == 'Pets?');

  final bare = QnaMessage.fromMap('q4', {});
  check('missing fields never invent content', bare.text == '' && bare.reply == null && bare.senderName == 'User' && bare.createdAt == 0);

  check('reply field matches the app that reads it',
      QnaMessage.replyField('rentals', 'questions') == 'answer' &&
          QnaMessage.replyField('properties', 'questions') == 'answer' &&
          QnaMessage.replyField('jobs', 'questions') == 'answerText' &&
          QnaMessage.replyField('rentals', 'qna') == 'reply');

  if (failed > 0) {
    print('$failed failed');
    exit(1);
  }
  print('All qna_message checks passed');
}
