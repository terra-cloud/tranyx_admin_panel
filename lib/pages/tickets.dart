import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../app.dart';
import '../core/providers/environment_provider.dart';
import 'users.dart';

class TicketModel {
  final String id;
  final String uid;
  final String subject;
  final String description;
  final String category;
  final String status;
  final int createdAt;

  TicketModel({
    required this.id,
    required this.uid,
    required this.subject,
    required this.description,
    required this.category,
    required this.status,
    required this.createdAt,
  });

  factory TicketModel.fromMap(String id, Map<String, dynamic> map) {
    int parseDateTime(dynamic val) {
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    return TicketModel(
      id: id,
      uid: map['uid'] ?? 'unknown',
      subject: map['subject'] ?? 'No Subject',
      description: map['description'] ?? 'No Description',
      category: map['category'] ?? 'General',
      status: map['status'] ?? 'Open',
      createdAt: parseDateTime(map['createdAt']),
    );
  }
}

final ticketsStreamProvider = StreamProvider<List<TicketModel>>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(<TicketModel>[]);
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('supportTickets')
      .snapshots()
      .map((snap) {
        final list = snap.docs.map((doc) => TicketModel.fromMap(doc.id, doc.data())).toList();
        list.sort((ticketA, ticketB) => ticketB.createdAt.compareTo(ticketA.createdAt));
        return list;
      })
      .handleError((err) {
        print('[Tickets] Stream failed: $err');
        return <TicketModel>[];
      });
});

class TicketsPage extends StatelessComponent {
  const TicketsPage({super.key});

  @override
  Component build(BuildContext context) {
    final ticketsAsync = context.watch(ticketsStreamProvider);
    final users = context.watch(usersStreamProvider).value ?? [];
    final user = context.watch(adminCurrentUserProvider).value;

    final userEmail = (user as dynamic)?.email ?? '';
    final isAdmin = userEmail.toLowerCase().contains('admin') || userEmail == 'sarah.johnson@tranyx.com';

    String getUserName(String uid) {
      final match = users.firstWhere(
        (userItem) => userItem.uid == uid,
        orElse: () => UserProfileModel(
          uid: '',
          name: 'Unknown User',
          email: '',
          idVerified: false,
          bgChecked: false,
          verificationLevel: 0,
          banned: false,
        ),
      );
      return match.name;
    }

    String getUserEmail(String uid) {
      final match = users.firstWhere(
        (userItem) => userItem.uid == uid,
        orElse: () => UserProfileModel(
          uid: '',
          name: '',
          email: 'N/A',
          idVerified: false,
          bgChecked: false,
          verificationLevel: 0,
          banned: false,
        ),
      );
      return match.email;
    }

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-8 max-w-7xl mx-auto w-full bg-[#eff2f0]', [
      // Modern Header block
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [Component.text('Support Tickets Manager')]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text('Review, escalate, and resolve customer support and system troubleshooting tickets.'),
          ]),
        ]),
      ]),

      // Tickets List Card
      ticketsAsync.when(
        data: (tickets) {
          if (tickets.isEmpty) {
            return div(
              classes: 'flex-grow flex flex-col items-center justify-center text-center p-16 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
              [
                span(classes: 'text-3xl mb-3', [Component.text('🎟️')]),
                h3(classes: 'text-sm font-bold text-zinc-900', [Component.text('No tickets submitted')]),
                p(classes: 'text-xs text-zinc-500 mt-1', [
                  Component.text('No active support tickets exist in this environment database.'),
                ]),
              ],
            );
          }

          return div(
            classes: 'overflow-x-auto w-full rounded-[28px] border border-zinc-200/50 bg-white shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
            [
              table(classes: 'w-full text-left text-xs border-collapse', [
                thead(
                  classes: 'bg-[#f8faf9] text-zinc-500 font-bold border-b border-zinc-100 text-[10px] uppercase tracking-wider',
                  [
                    tr([
                      th(classes: 'p-5', [Component.text('Ticket ID')]),
                      th(classes: 'p-5', [Component.text('User / Reporter')]),
                      th(classes: 'p-5', [Component.text('Subject & Category')]),
                      th(classes: 'p-5', [Component.text('Description')]),
                      th(classes: 'p-5 text-center', [Component.text('Status')]),
                      th(classes: 'p-5 text-center', [Component.text('Created')]),
                      if (isAdmin) th(classes: 'p-5 text-right', [Component.text('Control')]),
                    ]),
                  ],
                ),
                tbody(classes: 'divide-y divide-zinc-50', [
                  for (final ticket in tickets)
                    tr(classes: 'hover:bg-[#fcfdfc] transition-colors', [
                      td(classes: 'p-5 font-mono text-[10px] text-zinc-400 font-bold', [
                        Component.text('#${ticket.id.substring(ticket.id.length > 6 ? ticket.id.length - 6 : 0)}'),
                      ]),
                      td(classes: 'p-5 font-bold text-zinc-900', [
                        div(classes: 'flex flex-col gap-0.5', [
                          span([Component.text(getUserName(ticket.uid))]),
                          span(classes: 'text-[9px] text-zinc-400 font-mono', [
                            Component.text(getUserEmail(ticket.uid)),
                          ]),
                        ]),
                      ]),
                      td(classes: 'p-5 text-zinc-700', [
                        div(classes: 'flex flex-col gap-0.5', [
                          span(classes: 'font-bold text-zinc-800', [Component.text(ticket.subject)]),
                          span(
                            classes: 'text-[8px] font-black uppercase tracking-wider text-indigo-500 bg-indigo-50 border border-indigo-500/10 px-1.5 py-0.5 rounded w-max mt-0.5',
                            [Component.text(ticket.category)],
                          ),
                        ]),
                      ]),
                      td(classes: 'p-5 text-zinc-500 font-medium max-w-xs leading-relaxed', [
                        Component.text(ticket.description),
                      ]),
                      td(classes: 'p-5 text-center', [
                        select(
                          classes:
                              'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-3 py-1.5 text-[10px] font-extrabold focus:outline-none transition-all '
                              '${ticket.status.toLowerCase() == 'open'
                                  ? 'text-amber-600 bg-amber-50'
                                  : ticket.status.toLowerCase() == 'in progress'
                                  ? 'text-blue-600 bg-blue-50'
                                  : 'text-[#0fa958] bg-[#e2f1e9]'}',
                          onChange: (value) async {
                            final list = value;
                            final statusVal = list.isNotEmpty ? list.first : 'Open';
                            final firestore = context.read(firestoreProvider);
                            await firestore.collection('supportTickets').doc(ticket.id).update({
                              'status': statusVal,
                            });
                          },
                          [
                            option(value: 'Open', selected: ticket.status == 'Open', [Component.text('OPEN')]),
                            option(value: 'In Progress', selected: ticket.status == 'In Progress', [
                              Component.text('IN PROGRESS'),
                            ]),
                            option(value: 'Resolved', selected: ticket.status == 'Resolved', [
                              Component.text('RESOLVED'),
                            ]),
                          ],
                        ),
                      ]),
                      td(classes: 'p-5 text-center text-zinc-400 font-semibold', [
                        Component.text(
                          ticket.createdAt > 0
                              ? '${DateTime.fromMillisecondsSinceEpoch(ticket.createdAt).year}-${DateTime.fromMillisecondsSinceEpoch(ticket.createdAt).month.toString().padLeft(2, "0")}-${DateTime.fromMillisecondsSinceEpoch(ticket.createdAt).day.toString().padLeft(2, "0")}'
                              : 'N/A',
                        ),
                      ]),
                      if (isAdmin)
                        td(classes: 'p-5 text-right', [
                          button(
                            onClick: () async {
                              final firestore = context.read(firestoreProvider);
                              await firestore.collection('supportTickets').doc(ticket.id).delete();
                            },
                            classes: 'px-3 py-1.5 bg-red-50 hover:bg-red-100/50 border border-red-200 text-red-500 text-[10px] font-extrabold uppercase rounded-full transition-all shadow-sm',
                            [Component.text('Delete')],
                          ),
                        ]),
                    ]),
                ]),
              ]),
            ],
          );
        },
        loading: () => div(
          classes: 'flex-grow flex justify-center items-center py-20 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
          [div(classes: 'animate-spin h-6 w-6 border-2 border-zinc-200 border-t-indigo-500 rounded-full', [])],
        ),
        error: (err, _) => div(
          classes: 'p-6 bg-red-50/5 border border-red-500/10 text-red-500 text-xs rounded-[20px] font-mono shadow-sm',
          [Component.text('Error loading tickets: $err')],
        ),
      ),
    ]);
  }
}
