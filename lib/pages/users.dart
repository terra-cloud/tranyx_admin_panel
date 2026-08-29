import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_riverpod/legacy.dart';

import '../app.dart';
import '../core/providers/environment_provider.dart';
import '../core/config/firebase_environments.dart';

import 'dart:async';

final usersTabProvider = StateProvider<String>((ref) => 'platform');
final usersMainTabProvider = StateProvider<String>((ref) => 'directory');

// Toast notification state: null = hidden, String = message
final toastMessageProvider = StateProvider<String?>((ref) => null);

int getTimestamp(dynamic val) {
  if (val is num) return val.toInt();
  if (val is Timestamp) return val.millisecondsSinceEpoch;
  if (val is String) return int.tryParse(val) ?? 0;
  return 0;
}

class ActivityEvent {
  final String type;
  final String title;
  final int timestamp;
  ActivityEvent({required this.type, required this.title, required this.timestamp});
}

final userTransactionsProvider = StreamProvider.family<List<TxModel>, String>((ref, uid) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(<TxModel>[]);
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('transactions')
      .snapshots()
      .map((snap) => snap.docs.map((doc) => TxModel.fromMap(doc.id, doc.data())).where((tx) => tx.uid == uid).toList())
      .handleError((err) {
        print('[UserTx] failed: $err');
        return <TxModel>[];
      });
});

final userActivityHistoryProvider = StreamProvider.family<List<ActivityEvent>, String>((ref, uid) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(<ActivityEvent>[]);
  }
  final firestore = ref.watch(firestoreProvider);
  final controller = StreamController<List<ActivityEvent>>();

  final Map<String, List<ActivityEvent>> subEvents = {};

  void emitMerged() {
    final all = <ActivityEvent>[];
    for (final list in subEvents.values) {
      all.addAll(list);
    }
    all.sort((evA, evB) => evB.timestamp.compareTo(evA.timestamp));
    if (!controller.isClosed) controller.add(all);
  }

  // 1. Signup
  final userSub = firestore.collection('users').doc(uid).snapshots().listen((snap) {
    if (snap.exists) {
      final data = snap.data()!;
      final ts = getTimestamp(data['createdAt'] ?? data['timestamp']);
      if (ts > 0) {
        subEvents['signup'] = [ActivityEvent(type: 'signup', title: 'Joined Tranyx platform', timestamp: ts)];
      }
    }
    emitMerged();
  });

  // 2. Service listings published
  final jobsSub = firestore.collection('jobs').where('creatorId', isEqualTo: uid).snapshots().listen((snap) {
    subEvents['jobs'] = snap.docs
        .map(
          (d) => ActivityEvent(
            type: 'listing_created',
            title: 'Published Service listing: "${d.data()['title'] ?? 'Gig'}"',
            timestamp: getTimestamp(d.data()['createdAt']),
          ),
        )
        .toList();
    emitMerged();
  });

  // 3. Vehicle listings published
  final rentalsSub = firestore.collection('rentals').where('hostId', isEqualTo: uid).snapshots().listen((snap) {
    subEvents['rentals'] = snap.docs
        .map(
          (d) => ActivityEvent(
            type: 'listing_created',
            title: 'Published Vehicle rental: "${d.data()['brand'] ?? ''} ${d.data()['model'] ?? ''}"',
            timestamp: getTimestamp(d.data()['createdAt']),
          ),
        )
        .toList();
    emitMerged();
  });

  // 4. Property listings published
  final propertiesSub = firestore.collection('properties').where('hostId', isEqualTo: uid).snapshots().listen((snap) {
    subEvents['properties'] = snap.docs
        .map(
          (d) => ActivityEvent(
            type: 'listing_created',
            title: 'Published Property rental: "${d.data()['title'] ?? ''}"',
            timestamp: getTimestamp(d.data()['createdAt']),
          ),
        )
        .toList();
    emitMerged();
  });

  // 5. Bookings made (as renter)
  final rentalReqSub = firestore.collection('rental_requests').where('renteeId', isEqualTo: uid).snapshots().listen((
    snap,
  ) {
    subEvents['rental_requests'] = snap.docs
        .map(
          (d) => ActivityEvent(
            type: 'booking_made',
            title:
                'Booked Vehicle: "${d.data()['brand'] ?? ''} ${d.data()['model'] ?? ''}" (Status: ${d.data()['status'] ?? 'Pending'})',
            timestamp: getTimestamp(d.data()['createdAt']),
          ),
        )
        .toList();
    emitMerged();
  });

  final propertyReqSub = firestore.collection('property_requests').where('renteeId', isEqualTo: uid).snapshots().listen(
    (snap) {
      subEvents['property_requests'] = snap.docs
          .map(
            (d) => ActivityEvent(
              type: 'booking_made',
              title: 'Booked Property: "${d.data()['title'] ?? ''}" (Status: ${d.data()['status'] ?? 'Pending'})',
              timestamp: getTimestamp(d.data()['createdAt']),
            ),
          )
          .toList();
      emitMerged();
    },
  );

  // 6. Support Tickets submitted
  final ticketsSub = firestore.collection('supportTickets').where('uid', isEqualTo: uid).snapshots().listen((snap) {
    subEvents['tickets'] = snap.docs
        .map(
          (d) => ActivityEvent(
            type: 'ticket_submitted',
            title: 'Submitted Support Ticket: "${d.data()['subject'] ?? ''}" (Status: ${d.data()['status'] ?? 'Open'})',
            timestamp: getTimestamp(d.data()['createdAt']),
          ),
        )
        .toList();
    emitMerged();
  });

  ref.onDispose(() {
    userSub.cancel();
    jobsSub.cancel();
    rentalsSub.cancel();
    propertiesSub.cancel();
    rentalReqSub.cancel();
    propertyReqSub.cancel();
    ticketsSub.cancel();
    controller.close();
  });

  return controller.stream;
});

class QuestDefinition {
  final String id;
  final String title;
  final String category;
  final int points;

  const QuestDefinition({
    required this.id,
    required this.title,
    required this.category,
    required this.points,
  });
}

const List<QuestDefinition> standardQuests = [
  QuestDefinition(id: 'register_account', title: 'Register Account', category: 'Onboarding', points: 500),
  QuestDefinition(id: 'verify_account', title: 'Verify Account', category: 'Onboarding', points: 500),
  QuestDefinition(
    id: 'complete_profile_trust',
    title: 'Complete Profile Trust & Verification',
    category: 'Onboarding',
    points: 2000,
  ),
  QuestDefinition(id: 'add_skills_bio', title: 'Add Skills & Bio', category: 'Onboarding', points: 100),
  QuestDefinition(id: 'deposit_any_amount', title: 'Deposit any amount to Wallet', category: 'Onboarding', points: 500),
  QuestDefinition(id: 'connect_solana_wallet', title: 'Connect Any Solana Wallet', category: 'Onboarding', points: 200),
  QuestDefinition(id: 'post_first_service', title: 'Post First Service', category: 'Services', points: 500),
  QuestDefinition(id: 'hire_applicant', title: 'Hire an Applicant', category: 'Services', points: 500),
  QuestDefinition(
    id: 'employer_complete_transaction',
    title: 'Complete transaction as employer',
    category: 'Services',
    points: 500,
  ),
  QuestDefinition(id: 'apply_first_job', title: 'Apply First Job', category: 'Services', points: 500),
  QuestDefinition(id: 'be_hired', title: 'Be hired', category: 'Services', points: 500),
  QuestDefinition(
    id: 'jobseeker_complete_transaction',
    title: 'Complete transaction as Nyxian',
    category: 'Services',
    points: 500,
  ),
  QuestDefinition(id: 'post_property', title: 'Post Property', category: 'Rental', points: 500),
  QuestDefinition(
    id: 'host_complete_transaction',
    title: 'Complete Transaction as a Lessor/Host',
    category: 'Rental',
    points: 500,
  ),
  QuestDefinition(id: 'rent_property', title: 'Rent property', category: 'Rental', points: 500),
  QuestDefinition(
    id: 'client_complete_transaction',
    title: 'Complete transaction as a Lessee/Renter',
    category: 'Rental',
    points: 500,
  ),
];

class PointsHistoryModel {
  final String id;
  final String uid;
  final String questId;
  final int points;
  final String title;
  final String category;
  final int createdAt;

  PointsHistoryModel({
    required this.id,
    required this.uid,
    required this.questId,
    required this.points,
    required this.title,
    required this.category,
    required this.createdAt,
  });

  factory PointsHistoryModel.fromMap(String id, Map<String, dynamic> map) {
    return PointsHistoryModel(
      id: id,
      uid: map['uid'] ?? '',
      questId: map['questId'] ?? '',
      points: (map['points'] as num?)?.toInt() ?? 0,
      title: map['title'] ?? '',
      category: map['category'] ?? '',
      createdAt: getTimestamp(map['createdAt']),
    );
  }
}

final userPointsHistoryProvider = StreamProvider.family<List<PointsHistoryModel>, String>((ref, uid) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(<PointsHistoryModel>[]);
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('points_history')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((snap) {
        final list = snap.docs.map((doc) => PointsHistoryModel.fromMap(doc.id, doc.data())).toList();
        list.sort((itemA, itemB) => itemB.createdAt.compareTo(itemA.createdAt));
        return list;
      })
      .handleError((err) {
        print('[UserPointsHistory] Stream failed: $err');
        return <PointsHistoryModel>[];
      });
});

class UserProfileModel {
  final String uid;
  final String name;
  final String email;
  final String? phoneNumber;
  final bool idVerified;
  final bool bgChecked;
  final int verificationLevel;
  final String? walletPublicKey;
  final String? connectedWalletType;
  final String? role;
  final bool banned;
  final int? suspendedUntil;
  final int terraPoints;
  final List<String> earnedRewards;
  final double availableBalance;

  UserProfileModel({
    required this.uid,
    required this.name,
    required this.email,
    this.phoneNumber,
    required this.idVerified,
    required this.bgChecked,
    required this.verificationLevel,
    this.walletPublicKey,
    this.connectedWalletType,
    this.role,
    required this.banned,
    this.suspendedUntil,
    this.terraPoints = 0,
    this.earnedRewards = const [],
    this.availableBalance = 0.0,
  });

  factory UserProfileModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserProfileModel(
      uid: uid,
      name: map['name'] ?? 'Unknown User',
      email: map['email'] ?? 'No Email',
      phoneNumber: map['phoneNumber'],
      idVerified: map['idVerified'] ?? false,
      bgChecked: map['bgChecked'] ?? false,
      verificationLevel: map['verificationLevel'] ?? 0,
      walletPublicKey: map['walletPublicKey'],
      connectedWalletType: map['connectedWalletType'],
      role: map['role'],
      banned: map['banned'] ?? false,
      suspendedUntil: map['suspendedUntil'] as int?,
      terraPoints: map['terraPoints'] ?? 0,
      earnedRewards: map['earnedRewards'] != null ? List<String>.from(map['earnedRewards']) : const [],
      availableBalance:
          (map['tyxBalance'] as num?)?.toDouble() ??
          (map['availableBalance'] as num?)?.toDouble() ??
          (map['walletBalance'] as num?)?.toDouble() ??
          (map['balance'] as num?)?.toDouble() ??
          0.0,
    );
  }
}

String getExplorerUrl(String address, bool isTx, Environment env) {
  final cluster = env == Environment.production ? '' : '?cluster=devnet';
  final path = isTx ? 'tx' : 'address';
  return 'https://explorer.solana.com/$path/$address$cluster';
}

class TxModel {
  final String id;
  final String uid;
  final String type;
  final double amount;
  final String status;
  final String signature; // tx hash
  final int createdAt;

  TxModel({
    required this.id,
    required this.uid,
    required this.type,
    required this.amount,
    required this.status,
    required this.signature,
    required this.createdAt,
  });

  factory TxModel.fromMap(String id, Map<String, dynamic> map) {
    int parseDateTime(dynamic val) {
      if (val is num) return val.toInt();
      if (val is Timestamp) return val.millisecondsSinceEpoch;
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    return TxModel(
      id: id,
      uid: map['uid'] ?? map['renteeId'] ?? map['applicantId'] ?? 'unknown',
      type: map['type'] ?? 'payment',
      amount: (map['amount'] as num?)?.toDouble() ?? (map['totalCost'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] ?? 'success',
      signature: map['signature'] ?? map['txHash'] ?? '0x${id.substring(0, mathMin(id.length, 12))}',
      createdAt: parseDateTime(map['createdAt'] ?? map['timestamp']),
    );
  }
}

int mathMin(int a, int b) => a < b ? a : b;

final usersStreamProvider = StreamProvider<List<UserProfileModel>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('users')
      .snapshots()
      .map((snap) {
        return snap.docs.map((doc) => UserProfileModel.fromMap(doc.id, doc.data())).toList();
      })
      .handleError((err) {
        print('[Users] Stream failed: $err');
        return <UserProfileModel>[];
      });
});

final adminUsersStreamProvider = StreamProvider<List<UserProfileModel>>((ref) {
  final firestore = ref.watch(adminFirestoreProvider);
  return firestore
      .collection('users')
      .snapshots()
      .map((snap) {
        return snap.docs.map((doc) => UserProfileModel.fromMap(doc.id, doc.data())).toList();
      })
      .handleError((err) {
        print('[AdminUsers] Stream failed: $err');
        return <UserProfileModel>[];
      });
});

final blockchainTxStreamProvider = StreamProvider<List<TxModel>>((ref) {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  if (userAsync.value == null) {
    return Stream.value(<TxModel>[]);
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('transactions')
      .orderBy('createdAt', descending: true)
      .limit(10)
      .snapshots()
      .map((snap) => snap.docs.map((doc) => TxModel.fromMap(doc.id, doc.data())).toList())
      .handleError((err) {
        print('[Blockchain] Ledger failed: $err');
        return <TxModel>[];
      });
});

class UsersPage extends StatefulComponent {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  // Agent creation form state
  bool _showAddAgentForm = false;
  bool _isCreatingAgent = false;
  String _agentName = '';
  String _agentEmail = '';
  String _agentPassword = '';

  // User detail modal state
  UserProfileModel? _selectedUser;
  String _userModalTab = 'details'; // 'details', 'transactions', 'activity', 'rewards'

  // Custom rewards form state
  String _customRewardTitle = '';
  int _customRewardPoints = 100;

  Future<void> _awardQuest(UserProfileModel user, String questId, String title, String category, int points) async {
    final firestore = context.read(firestoreProvider);
    final historyId = '${user.uid}_${questId}_${DateTime.now().millisecondsSinceEpoch}';

    try {
      // 1. Log to points_history
      await firestore.collection('points_history').doc(historyId).set({
        'uid': user.uid,
        'questId': questId,
        'points': points,
        'title': title,
        'category': category,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 2. Update User Profile
      final updatedRewards = List<String>.from(user.earnedRewards)..add(questId);
      await firestore.collection('users').doc(user.uid).update({
        'terraPoints': user.terraPoints + points,
        'earnedRewards': updatedRewards,
      });

      setState(() {
        _selectedUser = UserProfileModel(
          uid: user.uid,
          name: user.name,
          email: user.email,
          phoneNumber: user.phoneNumber,
          idVerified: user.idVerified,
          bgChecked: user.bgChecked,
          verificationLevel: user.verificationLevel,
          walletPublicKey: user.walletPublicKey,
          connectedWalletType: user.connectedWalletType,
          role: user.role,
          banned: user.banned,
          suspendedUntil: user.suspendedUntil,
          terraPoints: user.terraPoints + points,
          earnedRewards: updatedRewards,
        );
      });

      _showToast('🪙 Awarded $points TP to ${user.name} for "$title"');
    } catch (e) {
      _showToast('❌ Failed to award points: $e');
    }
  }

  void _showToast(String msg) {
    context.read(toastMessageProvider.notifier).state = msg;
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) context.read(toastMessageProvider.notifier).state = null;
    });
  }

  Future<void> _createAgent() async {
    final name = _agentName.trim();
    final email = _agentEmail.trim().toLowerCase();
    final password = _agentPassword.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showToast('⚠️ Please fill in all fields.');
      return;
    }
    if (password.length < 6) {
      _showToast('⚠️ Password must be at least 6 characters.');
      return;
    }

    setState(() => _isCreatingAgent = true);
    try {
      // Use a temporary secondary Firebase app — same pattern as System Console
      // This creates a real Firebase Auth account without signing out the current admin
      final appName = 'temp_agent_reg_${DateTime.now().millisecondsSinceEpoch}';
      final tempApp = await Firebase.initializeApp(
        name: appName,
        options: FirebaseEnv.adminOptions,
      );
      final tempAuth = fb.FirebaseAuth.instanceFor(app: tempApp);
      final credential = await tempAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        await credential.user!.updateDisplayName(name);
        final uid = credential.user!.uid;
        final now = DateTime.now().millisecondsSinceEpoch;
        final currentTab = context.read(usersTabProvider);
        final targetRole = currentTab == 'admin' ? 'admin' : 'staff';

        // Write to Admin Firestore (always)
        final adminFirestore = context.read(adminFirestoreProvider);
        await adminFirestore.collection('users').doc(uid).set({
          'uid': uid,
          'name': name,
          'email': email,
          'role': targetRole,
          'createdAt': now,
        });
      }

      await tempApp.delete();

      final createdRoleTitle = context.read(usersTabProvider) == 'admin' ? 'Administrator' : 'Agent';
      setState(() {
        _showAddAgentForm = false;
        _isCreatingAgent = false;
        _agentName = '';
        _agentEmail = '';
        _agentPassword = '';
      });
      _showToast('✅ $createdRoleTitle "$name" created successfully!');
    } on fb.FirebaseAuthException catch (e) {
      setState(() => _isCreatingAgent = false);
      _showToast('❌ ${e.message ?? 'Auth registration failed.'}');
    } catch (e) {
      setState(() => _isCreatingAgent = false);
      _showToast('❌ Failed to create agent: $e');
    }
  }

  @override
  Component build(BuildContext context) {
    final currentEnv = context.watch(activeEnvironmentProvider);
    final mainTab = context.watch(usersMainTabProvider);
    final activeTab = context.watch(usersTabProvider);
    final usersAsync = context.watch(usersStreamProvider);
    final adminUsersAsync = context.watch(adminUsersStreamProvider);
    final txsAsync = context.watch(blockchainTxStreamProvider);
    final profile = context.watch(currentAdminProfileProvider).value;
    final user = context.watch(adminCurrentUserProvider).value;
    final toast = context.watch(toastMessageProvider);

    final userEmail = (profile?.email.isNotEmpty == true ? profile!.email : user?.email) ?? '';
    final userRole = profile?.role.toLowerCase() ?? '';
    final isAdmin = userEmail.toLowerCase().contains('admin') || userEmail == 'admin@tranyx.app' || userRole.contains('admin');

    if (!isAdmin && (activeTab == 'support' || activeTab == 'admin')) {
      Future.microtask(() => context.read(usersTabProvider.notifier).state = 'platform');
    }

    Component buildTabButton(String label, String value) {
      final isActive = activeTab == value;
      return button(
        onClick: () {
          context.read(usersTabProvider.notifier).state = value;
        },
        classes:
            'px-5 py-2 text-xs font-bold transition-all duration-200 '
            '${isActive ? 'bg-black text-white rounded-full shadow-md shadow-black/10' : 'text-zinc-500 hover:text-zinc-900'}',
        [Component.text(label)],
      );
    }

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0] relative', [
      // Top Level Main Tabs Switcher
      div(classes: 'flex items-center gap-2 border-b border-zinc-200/60 pb-3', [
        button(
          onClick: () => context.read(usersMainTabProvider.notifier).state = 'directory',
          classes:
              'px-5 py-2 text-xs font-black transition-all border-b-2 duration-200 '
              '${mainTab == 'directory' ? 'border-black text-black' : 'border-transparent text-zinc-400 hover:text-zinc-650'}',
          [Component.text('📇 User Accounts Directory')],
        ),
        button(
          onClick: () => context.read(usersMainTabProvider.notifier).state = 'rewards',
          classes:
              'px-5 py-2 text-xs font-black transition-all border-b-2 duration-200 '
              '${mainTab == 'rewards' ? 'border-black text-black' : 'border-transparent text-zinc-400 hover:text-zinc-650'}',
          [Component.text('🪙 User Rewards Center')],
        ),
      ]),
      // User details modal overlay
      if (_selectedUser != null)
        div(
          classes:
              'fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4 animate-fade-in',
          events: {
            'click': (e) {
              setState(() => _selectedUser = null);
            },
          },
          [
            div(
              classes: 'bg-white rounded-[28px] max-w-2xl w-full max-h-[85vh] overflow-y-auto p-7 shadow-2xl flex flex-col gap-5 border border-zinc-200/50 transform scale-100 transition-all',
              events: {
                'click': (e) {
                  e.stopPropagation();
                },
              },
              [
                // Modal Header
                div(classes: 'flex items-start justify-between border-b border-zinc-100 pb-4', [
                  div(classes: 'flex items-center gap-3', [
                    div(
                      classes: 'w-11 h-11 rounded-full bg-zinc-100 border border-zinc-200 flex items-center justify-center font-bold text-zinc-700 text-sm flex-shrink-0',
                      [
                        Component.text(
                          _selectedUser!.name.length >= 2
                              ? _selectedUser!.name.substring(0, 2).toUpperCase()
                              : _selectedUser!.name.toUpperCase(),
                        ),
                      ],
                    ),
                    div(classes: 'flex flex-col', [
                      h2(classes: 'text-base font-black text-zinc-950 leading-tight', [
                        Component.text(_selectedUser!.name),
                        if (_selectedUser!.banned)
                          span(
                            classes: 'ml-2 px-2 py-0.5 rounded bg-red-100 text-red-500 font-extrabold text-[8px] tracking-wider uppercase align-middle',
                            [Component.text('Banned')],
                          ),
                      ]),
                      span(classes: 'text-[9px] text-zinc-400 font-mono mt-0.5', [
                        Component.text('UID: ${_selectedUser!.uid}'),
                      ]),
                    ]),
                  ]),
                  button(
                    onClick: () => setState(() => _selectedUser = null),
                    classes: 'w-7 h-7 rounded-full bg-zinc-100 text-zinc-500 font-bold hover:bg-zinc-200 text-xs flex items-center justify-center',
                    [Component.text('✕')],
                  ),
                ]),

                // Modal Tabs Selector
                div(
                  classes: 'flex items-center gap-1 bg-zinc-50 p-1 border border-zinc-200/50 rounded-full shadow-inner w-max',
                  [
                    button(
                      onClick: () => setState(() => _userModalTab = 'details'),
                      classes:
                          'px-4 py-1.5 rounded-full text-[10px] font-black transition-all '
                          '${_userModalTab == 'details' ? "bg-black text-white" : "text-zinc-500 hover:text-zinc-800"}',
                      [Component.text('Profile Details')],
                    ),
                    button(
                      onClick: () => setState(() => _userModalTab = 'transactions'),
                      classes:
                          'px-4 py-1.5 rounded-full text-[10px] font-black transition-all '
                          '${_userModalTab == 'transactions' ? "bg-black text-white" : "text-zinc-500 hover:text-zinc-800"}',
                      [Component.text('Transactions ledger')],
                    ),
                    button(
                      onClick: () => setState(() => _userModalTab = 'activity'),
                      classes:
                          'px-4 py-1.5 rounded-full text-[10px] font-black transition-all '
                          '${_userModalTab == 'activity' ? "bg-black text-white" : "text-zinc-500 hover:text-zinc-800"}',
                      [Component.text('Activity feed')],
                    ),
                    button(
                      onClick: () => setState(() => _userModalTab = 'rewards'),
                      classes:
                          'px-4 py-1.5 rounded-full text-[10px] font-black transition-all '
                          '${_userModalTab == 'rewards' ? "bg-black text-white" : "text-zinc-500 hover:text-zinc-800"}',
                      [Component.text('Terra Points & Quests')],
                    ),
                  ],
                ),

                // Tab Content
                if (_userModalTab == 'details') ...[
                  div(classes: 'flex flex-col gap-4 text-xs text-zinc-700 pt-2', [
                    div(classes: 'grid grid-cols-2 gap-4', [
                      div(classes: 'bg-[#f8faf9] p-3.5 rounded-2xl border border-zinc-200/20', [
                        span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                          Component.text('Contact Email'),
                        ]),
                        p(classes: 'text-sm font-black text-zinc-900 mt-1', [Component.text(_selectedUser!.email)]),
                      ]),
                      div(classes: 'bg-[#f8faf9] p-3.5 rounded-2xl border border-zinc-200/20', [
                        span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                          Component.text('Phone Number'),
                        ]),
                        p(classes: 'text-sm font-black text-zinc-900 mt-1', [
                          Component.text(_selectedUser!.phoneNumber ?? 'N/A'),
                        ]),
                      ]),
                    ]),

                    div(classes: 'grid grid-cols-4 gap-3', [
                      div(classes: 'bg-zinc-50/50 p-3 rounded-xl border border-zinc-100 flex flex-col gap-1', [
                        span(classes: 'text-[8px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                          Component.text('ID Verified'),
                        ]),
                        span(
                          classes:
                              'px-2 py-0.5 rounded text-[8px] font-black w-max border '
                              '${_selectedUser!.idVerified ? "bg-emerald-50 text-[#0fa958] border-emerald-100" : "bg-zinc-100 text-zinc-400 border-zinc-200"}',
                          [Component.text(_selectedUser!.idVerified ? 'YES' : 'NO')],
                        ),
                      ]),
                      div(classes: 'bg-zinc-50/50 p-3 rounded-xl border border-zinc-100 flex flex-col gap-1', [
                        span(classes: 'text-[8px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                          Component.text('Background Checked'),
                        ]),
                        span(
                          classes:
                              'px-2 py-0.5 rounded text-[8px] font-black w-max border '
                              '${_selectedUser!.bgChecked ? "bg-emerald-50 text-[#0fa958] border-emerald-100" : "bg-zinc-100 text-zinc-400 border-zinc-200"}',
                          [Component.text(_selectedUser!.bgChecked ? 'YES' : 'NO')],
                        ),
                      ]),
                      div(classes: 'bg-zinc-50/50 p-3 rounded-xl border border-zinc-100 flex flex-col gap-1', [
                        span(classes: 'text-[8px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                          Component.text('Trust Level'),
                        ]),
                        span(classes: 'text-xs font-black text-zinc-900', [
                          Component.text('Level ${_selectedUser!.verificationLevel}'),
                        ]),
                      ]),
                      div(classes: 'bg-zinc-50/50 p-3 rounded-xl border border-zinc-100 flex flex-col gap-1', [
                        span(classes: 'text-[8px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                          Component.text('Terra Points'),
                        ]),
                        span(classes: 'text-xs font-black text-amber-600 flex items-center gap-1', [
                          Component.text('🪙 ${_selectedUser!.terraPoints} TP'),
                        ]),
                      ]),
                    ]),

                    div(classes: 'flex flex-col gap-1 border-t border-zinc-100 pt-3', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Linked Web3 Solana Wallet Address'),
                      ]),
                      if (_selectedUser!.walletPublicKey != null && _selectedUser!.walletPublicKey!.isNotEmpty) ...[
                        a(
                          href: getExplorerUrl(_selectedUser!.walletPublicKey!, false, currentEnv),
                          classes: 'font-mono text-[11px] text-indigo-500 font-black hover:underline mt-1 bg-indigo-50/30 p-2.5 rounded-xl border border-indigo-100/50 w-max',
                          attributes: {'target': '_blank'},
                          events: {'click': (e) => e.stopPropagation()},
                          [Component.text(_selectedUser!.walletPublicKey!)],
                        ),
                        span(classes: 'text-[8px] text-zinc-400 uppercase font-black ml-1 mt-0.5', [
                          Component.text(_selectedUser!.connectedWalletType ?? 'solana'),
                        ]),
                      ] else
                        span(classes: 'text-zinc-400 font-semibold mt-1', [Component.text('Not Linked')]),
                    ]),

                    // Account Status Block
                    div(classes: 'bg-zinc-50/50 p-3.5 rounded-2xl border border-zinc-200/20 flex flex-col gap-1.5', [
                      span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                        Component.text('Account Status'),
                      ]),
                      (() {
                        final nowMs = DateTime.now().millisecondsSinceEpoch;
                        if (_selectedUser!.banned) {
                          return span(
                            classes: 'px-2 py-0.5 rounded text-[10px] font-black w-max bg-red-50 text-red-500 border border-red-200',
                            [Component.text('🚫 Permanent Ban')],
                          );
                        } else if (_selectedUser!.suspendedUntil != null && _selectedUser!.suspendedUntil! > nowMs) {
                          final date = DateTime.fromMillisecondsSinceEpoch(_selectedUser!.suspendedUntil!);
                          return span(
                            classes: 'px-2 py-0.5 rounded text-[10px] font-black w-max bg-amber-50 text-amber-600 border border-amber-200',
                            [
                              Component.text(
                                '⏳ Suspended until ${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                              ),
                            ],
                          );
                        } else {
                          return span(
                            classes: 'px-2 py-0.5 rounded text-[10px] font-black w-max bg-emerald-50 text-[#0fa958] border border-emerald-200',
                            [Component.text('✅ Active')],
                          );
                        }
                      }()),
                    ]),

                    div(
                      classes: 'flex flex-wrap gap-4 border-t border-zinc-100 pt-4 mt-2 justify-between items-center',
                      [
                        div(classes: 'flex gap-2.5 items-center', [
                          if (!_selectedUser!.idVerified)
                            button(
                              onClick: () async {
                                final firestore = context.read(firestoreProvider);
                                await firestore.collection('users').doc(_selectedUser!.uid).update({
                                  'idVerified': true,
                                  'verificationLevel': _selectedUser!.bgChecked ? 2 : 1,
                                });
                                _showToast('✅ Identity approved.');
                                setState(() => _selectedUser = null);
                              },
                              classes: 'px-4 py-2 bg-indigo-500 hover:bg-indigo-600 text-white text-[10px] font-black uppercase tracking-wide rounded-xl shadow-sm transition-all',
                              [Component.text('Approve KYC ID')],
                            )
                          else
                            button(
                              onClick: () async {
                                final firestore = context.read(firestoreProvider);
                                await firestore.collection('users').doc(_selectedUser!.uid).update({
                                  'idVerified': false,
                                  'verificationLevel': 0,
                                });
                                _showToast('⚠️ Identity revoked.');
                                setState(() => _selectedUser = null);
                              },
                              classes: 'px-4 py-2 border border-zinc-200 hover:bg-zinc-50 text-zinc-700 text-[10px] font-black uppercase tracking-wide rounded-xl transition-all',
                              [Component.text('Revoke KYC ID')],
                            ),

                          // Manage Penalty Dropdown
                          div(
                            classes:
                                'flex items-center gap-2 bg-[#fafbfa] border border-zinc-200 rounded-xl px-3 py-1.5',
                            [
                              span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                                Component.text('Penalty:'),
                              ]),
                              select(
                                classes: 'bg-transparent border-0 text-[10px] font-black text-zinc-700 focus:outline-none cursor-pointer',
                                onChange: (v) async {
                                  if (v.isEmpty) return;
                                  final firestore = context.read(firestoreProvider);
                                  final selection = v.first;

                                  bool isBanned = false;
                                  int? suspendUntil;
                                  String msg = 'Status updated.';

                                  final nowMs = DateTime.now().millisecondsSinceEpoch;
                                  if (selection == 'ban') {
                                    isBanned = true;
                                    msg = '🚫 User permanently banned.';
                                  } else if (selection == '3d') {
                                    suspendUntil = nowMs + (3 * 24 * 60 * 60 * 1000);
                                    msg = '⏳ User suspended for 3 days.';
                                  } else if (selection == '7d') {
                                    suspendUntil = nowMs + (7 * 24 * 60 * 60 * 1000);
                                    msg = '⏳ User suspended for 7 days.';
                                  } else if (selection == '14d') {
                                    suspendUntil = nowMs + (14 * 24 * 60 * 60 * 1000);
                                    msg = '⏳ User suspended for 14 days.';
                                  } else {
                                    msg = '✅ User account activated.';
                                  }

                                  await firestore.collection('users').doc(_selectedUser!.uid).update({
                                    'banned': isBanned,
                                    'suspendedUntil': suspendUntil,
                                  });

                                  _showToast(msg);
                                  setState(() => _selectedUser = null);
                                },
                                [
                                  option(
                                    value: 'active',
                                    selected:
                                        !_selectedUser!.banned &&
                                        (_selectedUser!.suspendedUntil == null ||
                                            _selectedUser!.suspendedUntil! <= DateTime.now().millisecondsSinceEpoch),
                                    [Component.text('Active')],
                                  ),
                                  option(
                                    value: '3d',
                                    selected:
                                        _selectedUser!.suspendedUntil != null &&
                                        _selectedUser!.suspendedUntil! > DateTime.now().millisecondsSinceEpoch &&
                                        _selectedUser!.suspendedUntil! <=
                                            DateTime.now().millisecondsSinceEpoch + (4 * 24 * 60 * 60 * 1000),
                                    [Component.text('Suspend 3 Days')],
                                  ),
                                  option(
                                    value: '7d',
                                    selected:
                                        _selectedUser!.suspendedUntil != null &&
                                        _selectedUser!.suspendedUntil! >
                                            DateTime.now().millisecondsSinceEpoch + (4 * 24 * 60 * 60 * 1000) &&
                                        _selectedUser!.suspendedUntil! <=
                                            DateTime.now().millisecondsSinceEpoch + (8 * 24 * 60 * 60 * 1000),
                                    [Component.text('Suspend 1 Week')],
                                  ),
                                  option(
                                    value: '14d',
                                    selected:
                                        _selectedUser!.suspendedUntil != null &&
                                        _selectedUser!.suspendedUntil! >
                                            DateTime.now().millisecondsSinceEpoch + (8 * 24 * 60 * 60 * 1000) &&
                                        _selectedUser!.suspendedUntil! <=
                                            DateTime.now().millisecondsSinceEpoch + (15 * 24 * 60 * 60 * 1000),
                                    [Component.text('Suspend 2 Weeks')],
                                  ),
                                  option(value: 'ban', selected: _selectedUser!.banned, [
                                    Component.text('Ban Account'),
                                  ]),
                                ],
                              ),
                            ],
                          ),
                        ]),

                        if (isAdmin)
                          button(
                            onClick: () async {
                              if (web.window.confirm(
                                'PERMANENTLY DELETE account for ${_selectedUser!.name}? This cannot be undone.',
                              )) {
                                final firestore = context.read(firestoreProvider);
                                await firestore.collection('users').doc(_selectedUser!.uid).delete();
                                _showToast('🗑️ User account deleted.');
                                setState(() => _selectedUser = null);
                              }
                            },
                            classes: 'px-4 py-2 bg-red-600 hover:bg-red-700 text-white text-[10px] font-black uppercase tracking-wide rounded-xl shadow-md shadow-red-500/10 transition-all',
                            [Component.text('Delete Account')],
                          ),
                      ],
                    ),
                  ]),
                ] else if (_userModalTab == 'transactions') ...[
                  div(classes: 'flex flex-col gap-3.5 pt-2', [
                    context
                        .watch(userTransactionsProvider(_selectedUser!.uid))
                        .when(
                          data: (txs) {
                            if (txs.isEmpty) {
                              return div(classes: 'py-10 text-center text-xs text-zinc-400 font-semibold', [
                                Component.text('No transactions found for this user.'),
                              ]);
                            }
                            return div(classes: 'overflow-x-auto w-full rounded-2xl border border-zinc-150', [
                              table(classes: 'w-full text-left text-[11px] border-collapse', [
                                thead(
                                  classes: 'bg-zinc-50 border-b border-zinc-150 text-[9px] font-bold text-zinc-400 uppercase tracking-wider',
                                  [
                                    tr([
                                      th(classes: 'p-3.5', [Component.text('Tx Hash')]),
                                      th(classes: 'p-3.5', [Component.text('Type')]),
                                      th(classes: 'p-3.5 text-center', [Component.text('Status')]),
                                      th(classes: 'p-3.5 text-right', [Component.text('Amount')]),
                                    ]),
                                  ],
                                ),
                                tbody(classes: 'divide-y divide-zinc-50', [
                                  for (final tx in txs)
                                    tr(classes: 'hover:bg-zinc-50/50 transition-colors', [
                                      td(classes: 'p-3.5 font-mono text-[9px]', [
                                        a(
                                          href: getExplorerUrl(tx.signature, true, currentEnv),
                                          classes: 'text-indigo-500 font-bold hover:underline',
                                          attributes: {'target': '_blank'},
                                          events: {'click': (e) => e.stopPropagation()},
                                          [
                                            Component.text(
                                              tx.signature.length > 10
                                                  ? '${tx.signature.substring(0, 5)}...${tx.signature.substring(tx.signature.length - 5)}'
                                                  : tx.signature,
                                            ),
                                          ],
                                        ),
                                      ]),
                                      td(classes: 'p-3.5 uppercase text-[9px] font-extrabold text-zinc-400', [
                                        Component.text(tx.type),
                                      ]),
                                      td(classes: 'p-3.5 text-center', [
                                        span(
                                          classes:
                                              'px-2 py-0.5 rounded text-[8px] font-black border '
                                              '${tx.status.toLowerCase() == 'success' ? "bg-[#e2f1e9] text-[#0fa958] border-emerald-100" : "bg-red-50 text-red-500 border-red-100"}',
                                          [Component.text(tx.status.toUpperCase())],
                                        ),
                                      ]),
                                      td(classes: 'p-3.5 text-right font-black text-zinc-850', [
                                        Component.text('₱${tx.amount.toStringAsFixed(2)}'),
                                      ]),
                                    ]),
                                ]),
                              ]),
                            ]);
                          },
                          loading: () => div(classes: 'flex justify-center py-10', [
                            div(
                              classes: 'animate-spin h-5 w-5 border-2 border-zinc-200 border-t-indigo-500 rounded-full',
                              [],
                            ),
                          ]),
                          error: (e, _) => div(classes: 'p-4 bg-red-50 text-red-500 rounded-xl text-xs font-mono', [
                            Component.text('Error: $e'),
                          ]),
                        ),
                  ]),
                ] else if (_userModalTab == 'activity') ...[
                  div(classes: 'flex flex-col gap-4 pt-2', [
                    context
                        .watch(userActivityHistoryProvider(_selectedUser!.uid))
                        .when(
                          data: (events) {
                            if (events.isEmpty) {
                              return div(classes: 'py-10 text-center text-xs text-zinc-400 font-semibold', [
                                Component.text('No activities recorded in ledger.'),
                              ]);
                            }
                            return div(
                              classes: 'flex flex-col gap-3.5 pl-4 border-l border-zinc-250 relative ml-2 text-left',
                              [
                                for (final ev in events)
                                  div(classes: 'relative flex flex-col gap-1 pb-1 text-left', [
                                    div(
                                      classes: 'absolute -left-[21.5px] top-1 w-2.5 h-2.5 rounded-full border-2 border-white bg-indigo-500 shadow-sm',
                                      [],
                                    ),
                                    div(classes: 'flex justify-between items-start text-[10px] text-left', [
                                      span(classes: 'font-black text-zinc-800 leading-snug', [
                                        Component.text(ev.title),
                                      ]),
                                      span(classes: 'text-[8px] font-mono text-zinc-400 whitespace-nowrap ml-3', [
                                        Component.text(
                                          ev.timestamp > 0
                                              ? DateTime.fromMillisecondsSinceEpoch(
                                                  ev.timestamp,
                                                ).toString().split('.').first
                                              : 'N/A',
                                        ),
                                      ]),
                                    ]),
                                    span(classes: 'text-[8px] font-black uppercase tracking-wider text-indigo-400', [
                                      Component.text(ev.type.replaceAll('_', ' ')),
                                    ]),
                                  ]),
                              ],
                            );
                          },
                          loading: () => div(classes: 'flex justify-center py-10', [
                            div(
                              classes: 'animate-spin h-5 w-5 border-2 border-zinc-200 border-t-indigo-500 rounded-full',
                              [],
                            ),
                          ]),
                          error: (e, _) => div(classes: 'p-4 bg-red-50 text-red-500 rounded-xl text-xs font-mono', [
                            Component.text('Error: $e'),
                          ]),
                        ),
                  ]),
                ] else ...[
                  div(classes: 'flex flex-col gap-5 pt-2 text-left', [
                    // Points Summary Card
                    div(
                      classes:
                          'bg-[#fafbfa] p-4.5 rounded-2xl border border-zinc-200/50 flex items-center justify-between',
                      [
                        div(classes: 'flex flex-col gap-1', [
                          span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                            Component.text('Total Balance'),
                          ]),
                          p(classes: 'text-xl font-black text-amber-600 flex items-center gap-1.5', [
                            Component.text('🪙 ${_selectedUser!.terraPoints} TP'),
                          ]),
                        ]),
                        div(classes: 'flex flex-col gap-1 text-right', [
                          span(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                            Component.text('Quests Completed'),
                          ]),
                          p(classes: 'text-sm font-black text-zinc-800', [
                            Component.text('${_selectedUser!.earnedRewards.length} Completed'),
                          ]),
                        ]),
                      ],
                    ),

                    // Points History Log
                    div(classes: 'flex flex-col gap-2', [
                      h4(classes: 'text-xs font-black text-zinc-900', [Component.text('Points History Log')]),
                      context
                          .watch(userPointsHistoryProvider(_selectedUser!.uid))
                          .when(
                            data: (history) {
                              if (history.isEmpty) {
                                return div(
                                  classes: 'py-8 text-center text-xs text-zinc-400 font-semibold bg-zinc-50/50 border border-dashed border-zinc-200 rounded-xl',
                                  [
                                    Component.text('No points logged in history yet.'),
                                  ],
                                );
                              }
                              return div(
                                classes: 'overflow-x-auto w-full rounded-xl border border-zinc-200/50 bg-white max-h-[220px] overflow-y-auto',
                                [
                                  table(classes: 'w-full text-left text-[11px] border-collapse', [
                                    thead(
                                      classes: 'bg-zinc-50 border-b border-zinc-150 text-[9px] font-bold text-zinc-400 uppercase tracking-wider sticky top-0',
                                      [
                                        tr([
                                          th(classes: 'p-3.5', [Component.text('Quest / Title')]),
                                          th(classes: 'p-3.5', [Component.text('Category')]),
                                          th(classes: 'p-3.5 text-right', [Component.text('Points')]),
                                          th(classes: 'p-3.5 text-right', [Component.text('Date')]),
                                        ]),
                                      ],
                                    ),
                                    tbody(classes: 'divide-y divide-zinc-50', [
                                      for (final log in history)
                                        tr([
                                          td(classes: 'p-3 font-bold text-zinc-800', [Component.text(log.title)]),
                                          td(classes: 'p-3 text-zinc-400 uppercase text-[9px] font-extrabold', [
                                            Component.text(log.category),
                                          ]),
                                          td(classes: 'p-3 text-right font-black text-[#0fa958]', [
                                            Component.text('+${log.points}'),
                                          ]),
                                          td(classes: 'p-3 text-right text-zinc-400 font-mono text-[9px]', [
                                            Component.text(
                                              DateTime.fromMillisecondsSinceEpoch(log.createdAt)
                                                  .toString()
                                                  .split('.')
                                                  .first,
                                            ),
                                          ]),
                                        ]),
                                    ]),
                                  ]),
                                ],
                              );
                            },
                            loading: () => div(classes: 'flex justify-center py-6', [
                              div(
                                classes:
                                    'animate-spin h-5 w-5 border-2 border-zinc-200 border-t-indigo-500 rounded-full',
                                [],
                              ),
                            ]),
                            error: (e, _) => div(classes: 'p-3 bg-red-50 text-red-500 rounded-xl text-xs font-mono', [
                              Component.text('Error loading rewards history: $e'),
                            ]),
                          ),
                    ]),

                    // Standard Quests List (Status + Manual Award)
                    div(classes: 'flex flex-col gap-2.5 border-t border-zinc-100 pt-4', [
                      h4(classes: 'text-xs font-black text-zinc-900', [
                        Component.text('Quest Milestones Checklist & Admin Actions'),
                      ]),
                      p(classes: 'text-[10px] text-zinc-400 font-medium', [
                        Component.text(
                          'View completed status and click on any pending quest to manually award/credit it to this user.',
                        ),
                      ]),

                      div(classes: 'grid grid-cols-1 sm:grid-cols-2 gap-2 max-h-[250px] overflow-y-auto pr-1', [
                        for (final quest in standardQuests)
                          () {
                            final isCompleted = _selectedUser!.earnedRewards.contains(quest.id);
                            return div(
                              classes:
                                  'p-3 rounded-xl border flex items-center justify-between gap-3 transition-all '
                                  '${isCompleted ? "bg-[#e2f1e9]/10 border-emerald-100 text-emerald-800" : "bg-[#f8faf9] border-zinc-200 text-zinc-650"}',
                              [
                                div(classes: 'flex flex-col gap-0.5 min-w-0', [
                                  span(classes: 'text-[10px] font-black truncate', [Component.text(quest.title)]),
                                  span(classes: 'text-[8px] text-zinc-400 font-extrabold uppercase tracking-wider', [
                                    Component.text('${quest.category} • ${quest.points} TP'),
                                  ]),
                                ]),
                                if (isCompleted)
                                  span(
                                    classes: 'px-2 py-0.5 rounded text-[8px] font-black bg-emerald-50 text-[#0fa958] border border-emerald-100/50 flex-shrink-0',
                                    [
                                      Component.text('COMPLETED'),
                                    ],
                                  )
                                else if (isAdmin)
                                  button(
                                    onClick: () => _awardQuest(
                                      _selectedUser!,
                                      quest.id,
                                      quest.title,
                                      quest.category,
                                      quest.points,
                                    ),
                                    classes: 'px-2.5 py-1 bg-black hover:bg-zinc-800 text-white text-[8px] font-black uppercase tracking-wider rounded-lg transition-all flex-shrink-0',
                                    [Component.text('Award')],
                                  )
                                else
                                  span(classes: 'text-[8px] font-bold text-zinc-400', [Component.text('Pending')]),
                              ],
                            );
                          }(),
                      ]),
                    ]),

                    // Award Custom Points Section (Admin Only)
                    if (isAdmin)
                      div(classes: 'flex flex-col gap-3 border-t border-zinc-100 pt-4', [
                        h4(classes: 'text-xs font-black text-zinc-900', [
                          Component.text('Award Custom Rewards & Bonuses'),
                        ]),
                        div(classes: 'grid grid-cols-1 sm:grid-cols-3 gap-2.5', [
                          div(classes: 'flex flex-col gap-1', [
                            label(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                              Component.text('Reward Title'),
                            ]),
                            input(
                              value: _customRewardTitle,
                              onInput: (v) => setState(() => _customRewardTitle = v as String),
                              classes: 'px-3 py-2 bg-[#f3f6f4] border border-zinc-200 rounded-lg text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black/20',
                              attributes: {'placeholder': 'e.g. Community Bonus'},
                            ),
                          ]),
                          div(classes: 'flex flex-col gap-1', [
                            label(classes: 'text-[9px] font-extrabold text-zinc-400 uppercase tracking-wider', [
                              Component.text('Points'),
                            ]),
                            input(
                              value: _customRewardPoints.toString(),
                              onInput: (v) {
                                final val = int.tryParse(v as String) ?? 0;
                                setState(() => _customRewardPoints = val);
                              },
                              classes: 'px-3 py-2 bg-[#f3f6f4] border border-zinc-200 rounded-lg text-xs text-zinc-900 focus:outline-none focus:ring-1 focus:ring-black/20',
                              attributes: {'type': 'number'},
                            ),
                          ]),
                          div(classes: 'flex flex-col gap-1 justify-end', [
                            button(
                              onClick: () {
                                final title = _customRewardTitle.trim();
                                if (title.isEmpty || _customRewardPoints <= 0) {
                                  _showToast('⚠️ Please enter a title and points value > 0.');
                                  return;
                                }
                                final questId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                                _awardQuest(_selectedUser!, questId, title, 'Custom', _customRewardPoints);
                                setState(() {
                                  _customRewardTitle = '';
                                  _customRewardPoints = 100;
                                });
                              },
                              classes: 'w-full py-2 bg-indigo-500 hover:bg-indigo-600 text-white text-[10px] font-black uppercase tracking-wider rounded-lg shadow-md shadow-indigo-500/10 transition-all text-center',
                              [Component.text('Award Custom')],
                            ),
                          ]),
                        ]),
                      ]),
                  ]),
                ],
              ],
            ),
          ],
        ),

      // Toast notification
      if (toast != null)
        div(
          classes:
              'fixed top-6 right-6 z-50 px-5 py-3 rounded-2xl shadow-xl text-xs font-bold '
              '${toast.startsWith("✅")
                  ? "bg-[#0fa958] text-white"
                  : toast.startsWith("⚠️")
                  ? "bg-amber-500 text-white"
                  : "bg-red-500 text-white"}'
              ' transition-all animate-bounce',
          [Component.text(toast)],
        ),

      if (mainTab == 'directory') ...[
        // Modern Header block
        div(
          classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5',
          [
            div(classes: 'flex flex-col gap-1', [
              h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [
                Component.text('User Accounts Directory'),
              ]),
              p(classes: 'text-xs text-zinc-400 font-medium', [
                Component.text('Audit user profiles, trust badges, and run background check clearance.'),
              ]),
            ]),
            div(classes: 'flex items-center gap-3', [
              // Tabs styled in capsules
              div(classes: 'flex items-center gap-1 bg-white p-1 border border-zinc-200/50 rounded-full shadow-sm', [
                buildTabButton('👥 Users', 'platform'),
                if (isAdmin) ...[
                  buildTabButton('🛡️ Agents / Staff', 'support'),
                  buildTabButton('🔑 Admins', 'admin'),
                ],
              ]),
              // Add Agent / Admin button (on support and admin tabs)
              if ((activeTab == 'support' || activeTab == 'admin') && isAdmin)
                button(
                  onClick: () => setState(() => _showAddAgentForm = !_showAddAgentForm),
                  classes:
                      'px-4 py-2.5 bg-black hover:bg-zinc-800 text-white text-xs font-extrabold rounded-full '
                      'shadow-md shadow-black/10 transition-all flex items-center gap-2',
                  [
                    span(classes: 'text-sm', [Component.text(_showAddAgentForm ? '✕' : '+')]),
                    Component.text(_showAddAgentForm ? 'Cancel' : (activeTab == 'admin' ? 'Add Admin' : 'Add Agent')),
                  ],
                ),
            ]),
          ],
        ),

        // Add Agent / Admin Form Card
        if (_showAddAgentForm && (activeTab == 'support' || activeTab == 'admin'))
          div(classes: 'w-full bg-white border border-zinc-200/50 rounded-[24px] p-6 shadow-sm flex flex-col gap-4', [
            div(classes: 'flex flex-col gap-0.5', [
              h3(classes: 'text-sm font-black text-zinc-900', [
                Component.text(activeTab == 'admin' ? 'Create Administrator' : 'Create Support Agent'),
              ]),
              p(classes: 'text-xs text-zinc-400 font-medium', [
                Component.text(
                  activeTab == 'admin'
                      ? 'New administrators will receive full privileges across the admin console.'
                      : 'New agents will be added to the support queue and visible in Live Customer Service.',
                ),
              ]),
            ]),
            div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-3', [
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-[10px] font-extrabold text-zinc-500 uppercase tracking-wider', [
                  Component.text('Full Name'),
                ]),
                input(
                  value: _agentName,
                  onInput: (v) => setState(() => _agentName = v as String),
                  classes:
                      'px-4 py-2.5 bg-[#f3f6f4] border border-zinc-200 rounded-xl text-xs text-zinc-900 '
                      'focus:outline-none focus:ring-2 focus:ring-black/10',
                  attributes: {'placeholder': 'e.g. Juan dela Cruz'},
                ),
              ]),
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-[10px] font-extrabold text-zinc-500 uppercase tracking-wider', [
                  Component.text('Email Address'),
                ]),
                input(
                  value: _agentEmail,
                  onInput: (v) => setState(() => _agentEmail = v as String),
                  classes:
                      'px-4 py-2.5 bg-[#f3f6f4] border border-zinc-200 rounded-xl text-xs text-zinc-900 '
                      'focus:outline-none focus:ring-2 focus:ring-black/10',
                  attributes: {'placeholder': activeTab == 'admin' ? 'admin@tranyx.com' : 'agent@tranyx.com', 'type': 'email'},
                ),
              ]),
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-[10px] font-extrabold text-zinc-500 uppercase tracking-wider', [
                  Component.text('Temporary Password'),
                ]),
                input(
                  value: _agentPassword,
                  onInput: (v) => setState(() => _agentPassword = v as String),
                  classes:
                      'px-4 py-2.5 bg-[#f3f6f4] border border-zinc-200 rounded-xl text-xs text-zinc-900 '
                      'focus:outline-none focus:ring-2 focus:ring-black/10',
                  attributes: {'placeholder': '••••••••', 'type': 'password'},
                ),
              ]),
            ]),
            div(classes: 'flex justify-end', [
              button(
                onClick: _isCreatingAgent ? null : () async => _createAgent(),
                classes:
                    'px-6 py-2.5 rounded-xl text-xs font-extrabold transition-all '
                    '${_isCreatingAgent ? "bg-zinc-300 text-zinc-500 cursor-not-allowed" : "bg-black hover:bg-zinc-800 text-white shadow-md shadow-black/10"}',
                [
                  if (_isCreatingAgent)
                    div(classes: 'flex items-center gap-2', [
                      div(
                        classes: 'w-3.5 h-3.5 border-2 border-zinc-400 border-t-zinc-200 rounded-full animate-spin',
                        [],
                      ),
                      Component.text('Creating...'),
                    ])
                  else
                    Component.text(activeTab == 'admin' ? 'Create Admin' : 'Create Agent'),
                ],
              ),
            ]),
          ]),

        // Directory Table Card
        (activeTab == 'platform' ? usersAsync : adminUsersAsync).when(
          data: (allUsers) {
            final users = allUsers.where((userModel) {
              final r = userModel.role?.toLowerCase().trim() ?? '';
              if (activeTab == 'support') {
                // Rule: anything that is NOT admin and NOT a plain platform user is an agent
                return r.isNotEmpty && r != 'admin' && r != 'user';
              } else if (activeTab == 'admin') {
                return r == 'admin';
              } else {
                // Platform users: no role, or explicitly 'user'
                return r.isEmpty || r == 'user';
              }
            }).toList();

            if (users.isEmpty) {
              return div(
                classes: 'flex-grow flex flex-col items-center justify-center text-center p-16 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
                [
                  span(classes: 'text-3xl mb-3', [Component.text(activeTab == 'support' ? '🛡️' : (activeTab == 'admin' ? '🔑' : '👥'))]),
                  h3(classes: 'text-sm font-bold text-zinc-900', [
                    Component.text(activeTab == 'support' ? 'No support agents found' : (activeTab == 'admin' ? 'No administrators found' : 'No accounts found')),
                  ]),
                  p(classes: 'text-xs text-zinc-500 mt-1', [
                    Component.text(
                      activeTab == 'support'
                          ? 'Click "Add Agent" above to create your first support agent.'
                          : (activeTab == 'admin'
                              ? 'Click "Add Admin" above to register an administrator.'
                              : 'No accounts matching this category exist in this environment.'),
                    ),
                  ]),
                ],
              );
            }

            // Support and Admin tabs have the same staff table view (Name, Email, Role, Status, Actions)
            if (activeTab == 'support' || activeTab == 'admin') {
              return div(
                classes: 'overflow-x-auto w-full rounded-[28px] border border-zinc-200/50 bg-white shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
                [
                  table(classes: 'w-full text-left text-xs border-collapse', [
                    thead(
                      classes: 'bg-[#f8faf9] text-zinc-500 font-bold border-b border-zinc-100 text-[10px] uppercase tracking-wider',
                      [
                        tr([
                          th(classes: 'p-5', [Component.text(activeTab == 'admin' ? 'Admin Name' : 'Agent Name')]),
                          th(classes: 'p-5', [Component.text('Email')]),
                          th(classes: 'p-5 text-center', [Component.text('Role')]),
                          th(classes: 'p-5 text-center', [Component.text('Status')]),
                          th(classes: 'p-5 text-right', [Component.text('Actions')]),
                        ]),
                      ],
                    ),
                    tbody(classes: 'divide-y divide-zinc-50', [
                      for (final u in users)
                        tr(classes: 'hover:bg-[#fcfdfc] transition-colors', [
                          td(classes: 'p-5 font-bold text-zinc-900', [
                            div(classes: 'flex items-center gap-2.5', [
                              div(
                                classes: 'w-7 h-7 rounded-full ${activeTab == "admin" ? "bg-amber-50 border-amber-200 text-amber-800" : "bg-indigo-50 border-indigo-100 text-zinc-700"} border flex items-center justify-center text-[10px] font-extrabold flex-shrink-0',
                                [
                                  Component.text(
                                    u.name.length >= 2 ? u.name.substring(0, 2).toUpperCase() : u.name.toUpperCase(),
                                  ),
                                ],
                              ),
                              div(classes: 'flex flex-col', [
                                span([Component.text(u.name)]),
                                span(classes: 'text-[9px] text-zinc-400 font-mono', [
                                  Component.text('UID: ${u.uid.substring(0, mathMin(u.uid.length, 10))}...'),
                                ]),
                              ]),
                            ]),
                          ]),
                          td(classes: 'p-5 text-zinc-650 font-medium', [Component.text(u.email)]),
                          td(classes: 'p-5 text-center', [
                            span(
                              classes: 'px-2.5 py-0.5 rounded-full text-[10px] font-extrabold border ${activeTab == "admin" ? "bg-amber-50 text-amber-700 border-amber-200" : "bg-indigo-50 text-indigo-600 border-indigo-100"}',
                              [
                                Component.text((u.role ?? (activeTab == 'admin' ? 'admin' : 'support')).toUpperCase()),
                              ],
                            ),
                          ]),
                          td(classes: 'p-5 text-center', [
                            span(
                              classes: 'px-2.5 py-0.5 rounded-full text-[10px] font-extrabold border bg-[#e2f1e9] text-[#0fa958] border-emerald-100',
                              [
                                Component.text('ACTIVE'),
                              ],
                            ),
                          ]),
                          td(classes: 'p-5 text-right', [
                            if (u.email.toLowerCase() == 'admin@tranyx.app')
                              span(classes: 'text-[10px] font-bold text-zinc-400 px-3 py-1.5', [Component.text('Protected Root')])
                            else
                              button(
                                onClick: () async {
                                  final adminFirestore = context.read(adminFirestoreProvider);
                                  await adminFirestore.collection('users').doc(u.uid).delete();
                                  _showToast('🗑️ ${activeTab == 'admin' ? 'Admin' : 'Agent'} "${u.name}" removed.');
                                },
                                classes: 'px-3 py-1.5 border border-red-200 bg-red-50 hover:bg-red-100 text-red-500 text-[10px] font-extrabold rounded-full transition-all',
                                [Component.text(activeTab == 'admin' ? 'Remove Admin' : 'Remove Agent')],
                              ),
                          ]),
                        ]),
                    ]),
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
                        th(classes: 'p-5', [Component.text('User / ID')]),
                        th(classes: 'p-5', [Component.text('Contact Info')]),
                        th(classes: 'p-5', [Component.text('Web3 Wallet')]),
                        th(classes: 'p-5 text-center', [Component.text('ID Checked')]),
                        th(classes: 'p-5 text-center', [Component.text('Background Checked')]),
                        th(classes: 'p-5 text-center', [Component.text('Verification Level')]),
                        th(classes: 'p-5 text-right', [Component.text('Clearance Control')]),
                      ]),
                    ],
                  ),
                  tbody(classes: 'divide-y divide-zinc-50', [
                    for (final user in users)
                      tr(
                        classes: 'hover:bg-[#fcfdfc] transition-colors cursor-pointer',
                        events: {
                          'click': (e) {
                            setState(() {
                              _selectedUser = user;
                              _userModalTab = 'details';
                            });
                          },
                        },
                        [
                          td(classes: 'p-5 font-bold text-zinc-900', [
                            div(classes: 'flex flex-col gap-0.5', [
                              span([
                                Component.text(user.name),
                                if (user.banned)
                                  span(
                                    classes: 'ml-2 px-1.5 py-0.5 rounded bg-red-100 text-red-500 font-black text-[8px] uppercase tracking-wider',
                                    [Component.text('Banned')],
                                  ),
                              ]),
                              span(classes: 'text-[9px] text-zinc-400 font-mono', [Component.text('UID: ${user.uid}')]),
                            ]),
                          ]),
                          td(classes: 'p-5 text-zinc-655 font-medium', [
                            div(classes: 'flex flex-col gap-0.5', [
                              span([Component.text(user.email)]),
                              span(classes: 'text-[10px] text-zinc-400', [
                                Component.text(user.phoneNumber ?? 'No Phone'),
                              ]),
                            ]),
                          ]),
                          td(classes: 'p-5 text-zinc-655 font-medium', [
                            div(classes: 'flex flex-col gap-0.5', [
                              if (user.walletPublicKey != null && user.walletPublicKey!.isNotEmpty) ...[
                                a(
                                  href: getExplorerUrl(user.walletPublicKey!, false, currentEnv),
                                  classes: 'font-mono text-[10px] text-indigo-500 font-bold hover:underline',
                                  attributes: {'target': '_blank'},
                                  events: {'click': (e) => e.stopPropagation()},
                                  [
                                    Component.text(
                                      '${user.walletPublicKey!.substring(0, 6)}...${user.walletPublicKey!.substring(user.walletPublicKey!.length - 4)}',
                                    ),
                                  ],
                                ),
                                span(classes: 'text-[9px] text-zinc-400 uppercase font-black', [
                                  Component.text(user.connectedWalletType ?? 'solana'),
                                ]),
                              ] else ...[
                                span(classes: 'text-zinc-400 font-semibold', [Component.text('Not Linked')]),
                              ],
                            ]),
                          ]),
                          td(classes: 'p-5 text-center', [
                            span(
                              classes:
                                  'px-2.5 py-0.5 rounded-full text-[10px] font-extrabold border '
                                  '${user.idVerified ? 'bg-[#e2f1e9] text-[#0fa958] border-emerald-500/10' : 'bg-zinc-100 text-zinc-400 border-zinc-200'}',
                              [Component.text(user.idVerified ? 'VERIFIED' : 'UNVERIFIED')],
                            ),
                          ]),
                          td(classes: 'p-5 text-center', [
                            span(
                              classes:
                                  'px-2.5 py-0.5 rounded-full text-[10px] font-extrabold border '
                                  '${user.bgChecked ? 'bg-[#e2f1e9] text-[#0fa958] border-emerald-500/10' : 'bg-zinc-100 text-zinc-400 border-zinc-200'}',
                              [Component.text(user.bgChecked ? 'CLEARED' : 'UNCLEARED')],
                            ),
                          ]),
                          td(classes: 'p-5 text-center', [
                            span(
                              classes:
                                  'px-3 py-1 rounded-full text-[10px] font-extrabold border '
                                  '${user.verificationLevel == 2
                                      ? 'bg-[#e2f1e9] text-[#0fa958] border-emerald-500/10'
                                      : user.verificationLevel == 1
                                      ? 'bg-indigo-50 text-indigo-500 border-indigo-500/10'
                                      : 'bg-zinc-100 text-zinc-400 border-zinc-200'}',
                              [Component.text('LEVEL ${user.verificationLevel}')],
                            ),
                          ]),
                          td(classes: 'p-5 text-right', [
                            if (!user.bgChecked)
                              button(
                                onClick: () async {
                                  final firestore = context.read(firestoreProvider);
                                  await firestore.collection('users').doc(user.uid).update({
                                    'bgChecked': true,
                                    'verificationLevel': 2,
                                  });
                                },
                                events: {'click': (e) => e.stopPropagation()},
                                classes: 'px-4 py-2 bg-black hover:bg-zinc-800 text-white text-[10px] font-extrabold tracking-wide uppercase rounded-full transition-all shadow-md shadow-black/10',
                                [Component.text('Clear BG Record')],
                              )
                            else
                              button(
                                onClick: () async {
                                  final firestore = context.read(firestoreProvider);
                                  await firestore.collection('users').doc(user.uid).update({
                                    'bgChecked': false,
                                    'verificationLevel': user.idVerified ? 1 : 0,
                                  });
                                },
                                events: {'click': (e) => e.stopPropagation()},
                                classes: 'px-4 py-2 border border-red-200 bg-red-50 hover:bg-red-100/50 text-red-500 text-[10px] font-extrabold tracking-wide uppercase rounded-full transition-all',
                                [Component.text('Revoke BG')],
                              ),
                          ]),
                        ],
                      ),
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
            [Component.text('Error loading users: $err')],
          ),
        ),

        // Live Blockchain Ledger Panel (Visible ONLY to Admin accounts)
        if (isAdmin) ...[
          div(classes: 'flex flex-col gap-3.5', [
            div(classes: 'flex flex-col gap-1', [
              h3(classes: 'text-sm font-bold text-zinc-900 flex items-center gap-2', [
                span([Component.text('⛓️')]),
                Component.text('Live Blockchain Ledger Transactions'),
              ]),
              p(classes: 'text-xs text-zinc-400 font-semibold', [
                Component.text('Real-time updates of digital wallet escrow and settlement hashes.'),
              ]),
            ]),

            txsAsync.when(
              data: (txs) {
                if (txs.isEmpty) {
                  return div(classes: 'p-10 bg-white border border-zinc-200/50 rounded-[28px] text-center shadow-sm', [
                    span(classes: 'text-2xl mb-2', [Component.text('🕸️')]),
                    h4(classes: 'text-xs font-bold text-zinc-800', [Component.text('No transactions detected')]),
                    p(classes: 'text-[10px] text-zinc-400 font-semibold mt-1', [
                      Component.text('Awaiting real-time blocks from the environment database ledger.'),
                    ]),
                  ]);
                }

                return div(
                  classes: 'overflow-x-auto w-full rounded-[28px] border border-zinc-200/50 bg-white shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
                  [
                    table(classes: 'w-full text-left text-xs border-collapse', [
                      thead(
                        classes: 'bg-[#f8faf9] text-zinc-500 font-bold border-b border-zinc-100 text-[10px] uppercase tracking-wider',
                        [
                          tr([
                            th(classes: 'p-5', [Component.text('Tx Hash / Signature')]),
                            th(classes: 'p-5', [Component.text('Account Owner')]),
                            th(classes: 'p-5', [Component.text('Type')]),
                            th(classes: 'p-5 text-center', [Component.text('Status')]),
                            th(classes: 'p-5 text-right', [Component.text('Amount Value')]),
                          ]),
                        ],
                      ),
                      tbody(classes: 'divide-y divide-zinc-50 font-medium', [
                        for (final tx in txs)
                          tr(classes: 'hover:bg-[#fcfdfc] transition-colors', [
                            td(classes: 'p-5 font-mono text-[10px]', [
                              if (tx.signature.startsWith('0x') && tx.signature.length <= 14)
                                span(classes: 'text-zinc-500 font-bold', [Component.text(tx.signature)])
                              else
                                a(
                                  href: getExplorerUrl(tx.signature, true, currentEnv),
                                  classes: 'text-indigo-500 font-bold hover:underline',
                                  attributes: {'target': '_blank'},
                                  [
                                    Component.text(
                                      tx.signature.length > 12
                                          ? '${tx.signature.substring(0, 6)}...${tx.signature.substring(tx.signature.length - 6)}'
                                          : tx.signature,
                                    ),
                                  ],
                                ),
                            ]),
                            td(classes: 'p-5 text-zinc-700', [
                              span([Component.text('User: ${tx.uid.substring(0, mathMin(tx.uid.length, 12))}')]),
                            ]),
                            td(classes: 'p-5 uppercase text-[10px] font-extrabold tracking-wide text-zinc-400', [
                              Component.text(tx.type),
                            ]),
                            td(classes: 'p-5 text-center', [
                              span(
                                classes:
                                    "px-2 py-0.5 rounded-full text-[9px] font-black border "
                                    "${(tx.status.toLowerCase() == 'success' || tx.status.toLowerCase() == 'completed' || tx.status.toLowerCase() == 'approved')
                                        ? 'bg-[#e2f1e9] text-[#0fa958] border-emerald-500/10'
                                        : (tx.status.toLowerCase() == 'pending')
                                        ? 'bg-amber-50 text-amber-600 border-amber-500/10'
                                        : 'bg-red-50 text-red-500 border-red-500/10'}",
                                [Component.text(tx.status.toUpperCase())],
                              ),
                            ]),
                            td(classes: 'p-5 text-right font-black text-zinc-800 text-xs', [
                              Component.text('₱${tx.amount.toStringAsFixed(2)}'),
                            ]),
                          ]),
                      ]),
                    ]),
                  ],
                );
              },
              loading: () => div(
                classes: 'flex justify-center items-center py-10 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
                [div(classes: 'animate-spin h-5 w-5 border-2 border-zinc-200 border-t-emerald-500 rounded-full', [])],
              ),
              error: (err, _) => div(
                classes:
                    'p-6 bg-red-50/5 border border-red-500/10 text-red-500 text-xs rounded-[20px] font-mono shadow-sm',
                [Component.text('Error loading ledger: $err')],
              ),
            ),
          ]),
        ],
      ] else ...[
        // User Rewards View
        div(
          classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5',
          [
            div(classes: 'flex flex-col gap-1', [
              h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [Component.text('User Rewards Center')]),
              p(classes: 'text-xs text-zinc-400 font-medium', [
                Component.text(
                  'Track user quest milestones, total Terra Points (TP) balances, and award points manually.',
                ),
              ]),
            ]),
          ],
        ),

        // Rewards Leaderboard Table
        usersAsync.when(
          data: (allUsers) {
            final rewardUsers = allUsers.where((userModel) {
              final r = userModel.role?.toLowerCase().trim() ?? '';
              return r.isEmpty || r == 'user';
            }).toList()..sort((userA, userB) => userB.terraPoints.compareTo(userA.terraPoints));

            if (rewardUsers.isEmpty) {
              return div(
                classes: 'flex-grow flex flex-col items-center justify-center text-center p-16 bg-white border border-zinc-200/50 rounded-[28px] shadow-sm',
                [
                  span(classes: 'text-3xl mb-3', [Component.text('🪙')]),
                  h3(classes: 'text-sm font-bold text-zinc-900', [Component.text('No user rewards profiles found')]),
                  p(classes: 'text-xs text-zinc-500 mt-1', [
                    Component.text('User rewards accounts will appear here once they register and earn points.'),
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
                        th(classes: 'p-5 w-16 text-center', [Component.text('Rank')]),
                        th(classes: 'p-5', [Component.text('User / ID')]),
                        th(classes: 'p-5', [Component.text('Contact Info')]),
                        th(classes: 'p-5 text-center', [Component.text('Quests Completed')]),
                        th(classes: 'p-5 text-center', [Component.text('Terra Points')]),
                        th(classes: 'p-5 text-right', [Component.text('Actions')]),
                      ]),
                    ],
                  ),
                  tbody(classes: 'divide-y divide-zinc-50', [
                    ...rewardUsers.asMap().entries.map((entry) {
                      final i = entry.key;
                      final u = entry.value;
                      final rankStr = (i == 0)
                          ? '🥇 1'
                          : (i == 1)
                          ? '🥈 2'
                          : (i == 2)
                          ? '🥉 3'
                          : '${i + 1}';
                      return tr(
                        classes: 'hover:bg-[#fcfdfc] transition-colors cursor-pointer',
                        events: {
                          'click': (e) {
                            setState(() {
                              _selectedUser = u;
                              _userModalTab = 'rewards';
                            });
                          },
                        },
                        [
                          td(classes: 'p-5 text-center font-black text-zinc-550 text-[13px]', [
                            Component.text(rankStr),
                          ]),
                          td(classes: 'p-5 font-bold text-zinc-900', [
                            div(classes: 'flex flex-col gap-0.5', [
                              span([Component.text(u.name)]),
                              span(classes: 'text-[9px] text-zinc-400 font-mono', [Component.text('UID: ${u.uid}')]),
                            ]),
                          ]),
                          td(classes: 'p-5 text-zinc-650 font-medium', [
                            div(classes: 'flex flex-col gap-0.5', [
                              span([Component.text(u.email)]),
                              span(classes: 'text-[10px] text-zinc-400', [Component.text(u.phoneNumber ?? 'No Phone')]),
                            ]),
                          ]),
                          td(classes: 'p-5 text-center font-bold text-zinc-700', [
                            Component.text('${u.earnedRewards.length} / ${standardQuests.length}'),
                          ]),
                          td(classes: 'p-5 text-center', [
                            span(
                              classes: 'px-3 py-1.5 rounded-full text-xs font-black bg-amber-50 text-amber-700 border border-amber-500/10 flex items-center gap-1 w-max mx-auto',
                              [
                                Component.text('🪙 ${u.terraPoints} TP'),
                              ],
                            ),
                          ]),
                          td(classes: 'p-5 text-right', [
                            button(
                              onClick: () {
                                setState(() {
                                  _selectedUser = u;
                                  _userModalTab = 'rewards';
                                });
                              },
                              events: {'click': (e) => e.stopPropagation()},
                              classes: 'px-4 py-2 bg-black hover:bg-zinc-800 text-white text-[10px] font-extrabold tracking-wide uppercase rounded-full transition-all shadow-md shadow-black/10',
                              [Component.text('View Quest History')],
                            ),
                          ]),
                        ],
                      );
                    }),
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
            [Component.text('Error loading users: $err')],
          ),
        ),
      ],
    ]);
  }
}
