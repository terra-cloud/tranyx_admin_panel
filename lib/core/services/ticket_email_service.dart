import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'mailtrap_email_service.dart';

/// Service responsible for generating and dispatching support ticket email notifications.
class TicketEmailService {
  TicketEmailService._();

  /// Generates a standardized customer reference number in format `TKT-YYYY-XXXXX`
  static String generateReferenceNumber(String ticketId, [int? timestamp]) {
    final year = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp).year
        : DateTime.now().year;

    // Use deterministic hash of ticket ID for consistent 5-digit number
    final hash = ticketId.hashCode.abs() % 100000;
    final formattedNumber = hash.toString().padLeft(5, '0');
    return 'TKT-$year-$formattedNumber';
  }

  /// Formats unix milliseconds timestamp into human-readable date-time
  static String formatTimestamp(int? ms) {
    if (ms == null || ms <= 0) return 'Just now';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final month = months[dt.month - 1];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$month ${dt.day}, ${dt.year} at $hour:$minute $period';
  }

  /// Builds a responsive, branded HTML email template for Tranyx Support
  static String buildBrandedEmailHtml({
    required String title,
    required String subtitle,
    required String referenceNumber,
    required String status,
    required String recipientName,
    required String contentHtml,
  }) {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$title</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background-color: #f4f5f6;
      margin: 0;
      padding: 0;
      color: #18181b;
      -webkit-font-smoothing: antialiased;
    }
    .wrapper {
      width: 100%;
      background-color: #f4f5f6;
      padding: 40px 0;
    }
    .container {
      max-width: 600px;
      margin: 0 auto;
      background-color: #ffffff;
      border-radius: 20px;
      overflow: hidden;
      box-shadow: 0 10px 25px rgba(0, 0, 0, 0.05);
      border: 1px solid #e4e4e7;
    }
    .header {
      background: linear-gradient(135deg, #09090b 0%, #18181b 100%);
      padding: 32px 40px;
      text-align: left;
    }
    .brand-title {
      color: #ffffff;
      font-size: 22px;
      font-weight: 800;
      letter-spacing: -0.5px;
      margin: 0 0 6px 0;
    }
    .brand-subtitle {
      color: #a1a1aa;
      font-size: 13px;
      margin: 0;
    }
    .body {
      padding: 36px 40px;
    }
    .ticket-badge-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 24px;
      padding-bottom: 16px;
      border-bottom: 1px solid #f4f4f5;
    }
    .ref-badge {
      font-family: monospace;
      background-color: #eff2f0;
      color: #09090b;
      font-weight: 800;
      font-size: 13px;
      padding: 6px 14px;
      border-radius: 8px;
      letter-spacing: 0.5px;
    }
    .status-badge {
      font-size: 11px;
      font-weight: 800;
      text-transform: uppercase;
      padding: 6px 12px;
      border-radius: 20px;
      background-color: #ecfdf5;
      color: #047857;
    }
    .greeting {
      font-size: 15px;
      font-weight: 600;
      color: #27272a;
      margin-bottom: 16px;
    }
    .section-title {
      font-size: 11px;
      font-weight: 800;
      text-transform: uppercase;
      letter-spacing: 0.8px;
      color: #71717a;
      margin: 24px 0 8px 0;
    }
    .details-table {
      width: 100%;
      border-collapse: collapse;
      margin: 16px 0;
    }
    .details-table td {
      padding: 10px 14px;
      font-size: 13px;
      border-bottom: 1px solid #f4f4f5;
    }
    .details-table td.label {
      color: #71717a;
      font-weight: 600;
      width: 35%;
    }
    .details-table td.value {
      color: #09090b;
      font-weight: 600;
    }
    .content-box {
      background-color: #fbfcfb;
      border: 1px solid #e4e4e7;
      border-radius: 14px;
      padding: 18px 20px;
      font-size: 13px;
      line-height: 1.6;
      color: #27272a;
      white-space: pre-wrap;
      margin-top: 8px;
    }
    .agent-response-box {
      background-color: #f0fdf4;
      border: 1px solid #bbf7d0;
      border-radius: 14px;
      padding: 18px 20px;
      font-size: 13px;
      line-height: 1.6;
      color: #14532d;
      margin-top: 12px;
    }
    .footer {
      background-color: #fafafa;
      border-top: 1px solid #f4f4f5;
      padding: 24px 40px;
      text-align: center;
      font-size: 12px;
      color: #a1a1aa;
      line-height: 1.6;
    }
    .footer strong {
      color: #71717a;
    }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="container">
      <div class="header">
        <h1 class="brand-title">Tranyx Support Portal</h1>
        <p class="brand-subtitle">Automated Ticket Notification (No-Reply)</p>
      </div>
      <div class="body">
        <div class="ticket-badge-row">
          <span class="ref-badge">$referenceNumber</span>
          <span class="status-badge">$status</span>
        </div>
        <div class="greeting">Hello $recipientName,</div>
        $contentHtml
      </div>
      <div class="footer">
        <p>This is an automated notification from <strong>Tranyx Support (No-Reply)</strong>.<br>
        Please do not reply directly to this email as incoming messages to this address are not monitored.</p>
        <p style="margin-top: 8px; font-size: 11px;">To respond, provide additional details, or track your ticket, please open the <strong>Live Support</strong> section in your Tranyx app referencing <strong>$referenceNumber</strong>.</p>
        <p style="margin-top: 12px; font-size: 11px;">&copy; ${DateTime.now().year} Tranyx Technologies. All rights reserved.</p>
      </div>
    </div>
  </div>
</body>
</html>
''';
  }

  /// Alias for sendTicketCreationConfirmation
  static Future<void> sendTicketConfirmationEmail({
    required FirebaseFirestore firestore,
    required String ticketId,
    required String referenceNumber,
    required String recipientEmail,
    required String recipientName,
    required String uid,
    required String subject,
    required String description,
    required String category,
    required String status,
    int? submittedAt,
    int? createdAt,
  }) =>
      sendTicketCreationConfirmation(
        firestore: firestore,
        ticketId: ticketId,
        referenceNumber: referenceNumber,
        recipientEmail: recipientEmail,
        recipientName: recipientName,
        uid: uid,
        subject: subject,
        description: description,
        category: category,
        status: status,
        submittedAt: submittedAt ?? createdAt,
      );

  /// Dispatches the Initial Ticket Creation Confirmation Email.
  static Future<void> sendTicketCreationConfirmation({
    required FirebaseFirestore firestore,
    required String ticketId,
    required String referenceNumber,
    required String recipientEmail,
    required String recipientName,
    required String uid,
    required String subject,
    required String description,
    required String category,
    required String status,
    int? submittedAt,
    int? createdAt,
  }) async {
    if (recipientEmail.isEmpty || !recipientEmail.contains('@')) return;

    final effectiveTs = submittedAt ?? createdAt ?? DateTime.now().millisecondsSinceEpoch;
    final formattedDate = formatTimestamp(effectiveTs);

    final contentHtml = '''
      <p style="font-size: 13px; color: #52525b; line-height: 1.6;">
        Your support ticket has been registered with our support team. We have logged your concern and an assigned agent will attend to your request shortly.
      </p>

      <table class="details-table">
        <tr>
          <td class="label">Reference Number:</td>
          <td class="value"><strong>$referenceNumber</strong></td>
        </tr>
        <tr>
          <td class="label">Submission Date:</td>
          <td class="value">$formattedDate</td>
        </tr>
        <tr>
          <td class="label">Ticket Category:</td>
          <td class="value">$category</td>
        </tr>
        <tr>
          <td class="label">Initial Status:</td>
          <td class="value"><span style="color: #d97706; font-weight: 700;">$status</span></td>
        </tr>
      </table>

      <div class="section-title">Submitted Details</div>
      <div style="font-size: 14px; font-weight: 700; color: #09090b; margin-top: 4px;">$subject</div>
      <div class="content-box">$description</div>

      <p style="font-size: 12px; color: #71717a; margin-top: 24px; line-height: 1.5;">
        You will receive automated email updates whenever a support agent responds or updates the status of this ticket.
      </p>
    ''';

    final html = buildBrandedEmailHtml(
      title: 'Support Ticket Confirmation: #$referenceNumber',
      subtitle: 'Official confirmation of your submitted support request.',
      referenceNumber: referenceNumber,
      status: status,
      recipientName: recipientName.isNotEmpty ? recipientName : 'Valued Customer',
      contentHtml: contentHtml,
    );

    // 0. Direct Transactional Dispatch via Mailtrap API
    final mailtrapSuccess = await MailtrapEmailService.sendEmail(
      recipientEmail: recipientEmail,
      recipientName: recipientName,
      subject: '[Tranyx Support] Ticket Confirmation: #$referenceNumber - $subject',
      htmlContent: html,
      textContent: 'Your support ticket #$referenceNumber has been received.\n\n'
          'Reference: $referenceNumber\n'
          'Submitted At: $formattedDate\n'
          'Category: $category\n'
          'Status: $status\n'
          'Subject: $subject\n\n'
          'Details:\n$description\n\n'
          'Our support team will review your ticket and reply shortly.',
      category: 'Ticket Creation Confirmation',
      firestore: firestore,
    );

    final mailData = {
      'to': [recipientEmail],
      'message': {
        'subject': '[Tranyx Support] Ticket Confirmation: #$referenceNumber - $subject',
        'text': 'Your support ticket #$referenceNumber has been received.\n\n'
            'Reference: $referenceNumber\n'
            'Submitted At: $formattedDate\n'
            'Category: $category\n'
            'Status: $status\n'
            'Subject: $subject\n\n'
            'Details:\n$description\n\n'
            'Our support team will review your ticket and reply shortly.',
        'html': html,
      },
      'recipientEmail': recipientEmail,
      'recipientName': recipientName,
      'uid': uid,
      'ticketId': ticketId,
      'ticketRef': referenceNumber,
      'type': 'ticket_creation_confirmation',
      'mailtrapDirectSent': mailtrapSuccess,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };

    // 1. Write to mail queue (Firebase Trigger Email extension standard)
    await firestore.collection('mail').add(mailData).catchError((e) {
      print('[TicketEmailService] mail collection write error: $e');
      return firestore.collection('mail').doc();
    });

    // 2. Write to emails queue (backup)
    await firestore.collection('emails').add(mailData).catchError((_) => firestore.collection('emails').doc());

    // 3. Write in-app notification
    if (uid.isNotEmpty && uid != 'unknown') {
      await firestore.collection('notifications').add({
        'userId': uid,
        'uid': uid,
        'title': 'Support Ticket Received (#$referenceNumber)',
        'body': 'Your ticket "$subject" (#$referenceNumber) was submitted successfully and is now $status.',
        'ticketId': ticketId,
        'ticketRef': referenceNumber,
        'type': 'support_ticket',
        'isRead': false,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      }).catchError((_) => firestore.collection('notifications').doc());
    }

    // 4. Update audit log on the ticket document
    await firestore.collection('supportTickets').doc(ticketId).set({
      'ticketNumber': referenceNumber,
      'emailConfirmationSent': true,
      'emailConfirmationSentAt': DateTime.now().millisecondsSinceEpoch,
      'emailLogs': FieldValue.arrayUnion([
        {
          'type': 'CREATION_CONFIRMATION',
          'recipient': recipientEmail,
          'mailtrapDelivered': mailtrapSuccess,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      ]),
    }, SetOptions(merge: true)).catchError((e) => print('[TicketEmailService] Ticket doc log update error: $e'));
  }

  /// Dispatches a Status Update or Agent Response Notification Email.
  static Future<void> sendTicketStatusUpdateEmail({
    required FirebaseFirestore firestore,
    required String ticketId,
    required String referenceNumber,
    required String recipientEmail,
    required String recipientName,
    required String uid,
    required String subject,
    required String description,
    required String category,
    required String oldStatus,
    required String newStatus,
    required String agentName,
    String? agentResponse,
    int? submittedAt,
  }) async {
    if (recipientEmail.isEmpty || !recipientEmail.contains('@')) return;

    final isResolved = newStatus.toLowerCase() == 'resolved' || newStatus.toLowerCase() == 'closed';
    final updateTime = formatTimestamp(DateTime.now().millisecondsSinceEpoch);

    final contentHtml = '''
      <table class="details-table">
        <tr>
          <td class="label">Ticket Subject:</td>
          <td class="value">$subject</td>
        </tr>
        <tr>
          <td class="label">Status Changed:</td>
          <td class="value"><span style="color: #71717a; text-decoration: line-through;">$oldStatus</span> &rarr; <strong style="color: ${isResolved ? '#0fa958' : '#2563eb'}; font-size: 14px;">${newStatus.toUpperCase()}</strong></td>
        </tr>
        <tr>
          <td class="label">Handled By:</td>
          <td class="value">$agentName (Support Team)</td>
        </tr>
        <tr>
          <td class="label">Updated At:</td>
          <td class="value">$updateTime</td>
        </tr>
      </table>

      ${agentResponse != null && agentResponse.trim().isNotEmpty ? '''
        <div class="section-title">Message from Support Agent $agentName</div>
        <div class="agent-response-box">
          $agentResponse
        </div>
      ''' : ''}

      <div class="section-title">Original Submitted Concern</div>
      <div class="content-box">$description</div>

      <p style="font-size: 12px; color: #71717a; margin-top: 24px; line-height: 1.5;">
        If you have further questions or additional details, please visit the Live Support section in your Tranyx mobile app referencing <strong>$referenceNumber</strong>.
      </p>
    ''';

    final html = buildBrandedEmailHtml(
      title: 'Ticket #$referenceNumber Updated: $newStatus',
      subtitle: 'Your support ticket status has been updated by agent $agentName.',
      referenceNumber: referenceNumber,
      status: newStatus,
      recipientName: recipientName.isNotEmpty ? recipientName : 'Valued Customer',
      contentHtml: contentHtml,
    );

    // 0. Direct Transactional Dispatch via Mailtrap API
    final mailtrapSuccess = await MailtrapEmailService.sendEmail(
      recipientEmail: recipientEmail,
      recipientName: recipientName,
      subject: '[Tranyx Support] Update on Ticket #$referenceNumber - $newStatus',
      htmlContent: html,
      textContent: 'Your support ticket #$referenceNumber was updated.\n\n'
          'Reference: $referenceNumber\n'
          'Subject: $subject\n'
          'Status: $oldStatus -> $newStatus\n'
          'Handled By: $agentName\n\n'
          '${agentResponse != null && agentResponse.isNotEmpty ? "Agent Response:\n$agentResponse\n\n" : ""}'
          'Updated At: $updateTime',
      category: 'Ticket Status Update',
      firestore: firestore,
    );

    final mailData = {
      'to': [recipientEmail],
      'message': {
        'subject': '[Tranyx Support] Update on Ticket #$referenceNumber - $newStatus',
        'text': 'Your support ticket #$referenceNumber was updated to $newStatus by $agentName.\n\n'
            'Reference: $referenceNumber\n'
            'Subject: $subject\n'
            'Status: $newStatus\n\n'
            '${agentResponse != null && agentResponse.isNotEmpty ? "Response from $agentName:\n$agentResponse\n\n" : ""}'
            'Updated At: $updateTime',
        'html': html,
      },
      'recipientEmail': recipientEmail,
      'recipientName': recipientName,
      'uid': uid,
      'ticketId': ticketId,
      'ticketRef': referenceNumber,
      'type': 'ticket_status_update',
      'newStatus': newStatus,
      'mailtrapDirectSent': mailtrapSuccess,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };

    // Write to mail queue
    await firestore.collection('mail').add(mailData).catchError((e) {
      print('[TicketEmailService] mail update write error: $e');
      return firestore.collection('mail').doc();
    });

    // Write to backup emails
    await firestore.collection('emails').add(mailData).catchError((_) => firestore.collection('emails').doc());

    // Update in-app user notification
    if (uid.isNotEmpty) {
      await firestore.collection('notifications').add({
        'userId': uid,
        'uid': uid,
        'title': 'Ticket #$referenceNumber Updated',
        'body': 'Your ticket status is now $newStatus. Agent: $agentName.',
        'ticketId': ticketId,
        'ticketRef': referenceNumber,
        'status': newStatus,
        'read': false,
        'isRead': false,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'type': 'ticket_status_update',
      }).catchError((_) => firestore.collection('notifications').doc());
    }

    // Update audit log on the ticket document
    await firestore.collection('supportTickets').doc(ticketId).set({
      'emailLogs': FieldValue.arrayUnion([
        {
          'type': 'STATUS_UPDATE_$newStatus',
          'recipient': recipientEmail,
          'agent': agentName,
          'mailtrapDelivered': mailtrapSuccess,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      ]),
    }, SetOptions(merge: true)).catchError((e) => print('[TicketEmailService] Status log error: $e'));
  }
}
