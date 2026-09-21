import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_riverpod/legacy.dart';
import 'package:riverpod/riverpod.dart';
import 'package:web/web.dart' as web;

import '../config/firebase_environments.dart';

/// Provider holding the selected active environment.
/// Defaults to production so staff and agents are connected to live data by default.
final activeEnvironmentProvider = StateProvider<Environment>((ref) {
  return Environment.production;
});

/// Dynamically resolves the Firebase App instance based on the active environment.
/// Lazily initializes the named app if it wasn't pre-initialized at startup.
final firebaseAppProvider = FutureProvider<FirebaseApp>((ref) async {
  final env = ref.watch(activeEnvironmentProvider);
  try {
    return Firebase.app(env.name);
  } on FirebaseException catch (_) {
    // App not found — initialize it now (lazy fallback)
    return Firebase.initializeApp(
      name: env.name,
      options: FirebaseEnv.optionsFor(env),
    );
  }
});

/// Dynamically resolves the Firestore instance for the active environment.
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  final appAsync = ref.watch(firebaseAppProvider);
  return appAsync.when(
    data: (app) => FirebaseFirestore.instanceFor(app: app),
    loading: () => FirebaseFirestore.instance,
    error: (err, stack) => FirebaseFirestore.instance,
  );
});

/// Exposes the default (Admin-exclusive / tranyx-admin-portal) Firebase Auth instance.
final adminAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Exposes the default (Admin-exclusive / tranyx-admin-portal) Firestore instance for portal config and staff management.
final adminFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

/// Resolves the Firebase Auth instance for portal users (always tranyx-admin-portal).
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return ref.watch(adminAuthProvider);
});

/// Provider that streams the auth state of the authenticated Admin / Staff member from tranyx-admin-portal.
final adminAuthUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(adminAuthProvider);
  return auth.userChanges();
});

/// Synchronizes admin authentication into the selected environment so that
/// security rules recognizing `isAdminOrStaff()` succeed without 403 PERMISSION_DENIED.
Future<User?> syncEnvAuth(FirebaseApp app, User? adminUser, {String? explicitPassword}) async {
  if (adminUser == null) return null;
  try {
    final envAuth = FirebaseAuth.instanceFor(app: app);

    // If already authenticated on this environment app, bootstrap records and return immediately
    if (envAuth.currentUser != null) {
      final currentUser = envAuth.currentUser;
      final envUid = currentUser?.uid;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final firestore = FirebaseFirestore.instanceFor(app: app);

      if (envUid != null) {
        final staffEmail = currentUser?.email ?? adminUser.email ?? 'admin@tranyx.app';
        try {
          await firestore.collection('p2p_agents').doc(envUid).set({
            'uid': envUid,
            'email': staffEmail,
            'role': 'agent',
            'isActive': true,
            'updatedAt': nowMs,
          }, SetOptions(merge: true));
          await firestore.collection('users').doc(envUid).set({
            'uid': envUid,
            'email': staffEmail,
            'role': 'admin',
            'isAdmin': true,
            'isP2pAgent': true,
            'name': adminUser.displayName ?? 'Staff Admin',
            'updatedAt': nowMs,
          }, SetOptions(merge: true));
        } catch (docErr) {
          print('[EnvAuthSync] Document bootstrap notice on ${app.name}: $docErr');
        }
      }
      return currentUser;
    }

    final savedEmail = web.window.localStorage.getItem('tranyx_staff_email') ?? adminUser.email;
    final savedPass = explicitPassword ?? web.window.localStorage.getItem('tranyx_staff_password');

    // Sign in using staff credentials
    if (savedEmail != null && savedEmail.isNotEmpty && savedPass != null && savedPass.isNotEmpty) {
      try {
        await envAuth.signInWithEmailAndPassword(
          email: savedEmail.trim(),
          password: savedPass,
        );
        print('[EnvAuthSync] Signed in to ${app.name} as ${envAuth.currentUser?.email}');
        if (explicitPassword != null && explicitPassword.isNotEmpty) {
          try {
            web.window.localStorage.setItem('tranyx_staff_password', explicitPassword);
            web.window.localStorage.setItem('tranyx_staff_email', savedEmail.trim());
          } catch (_) {}
        }
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          // Auto-provision staff account on this environment project!
          try {
            print('[EnvAuthSync] Account not present in ${app.name}. Auto-provisioning staff account...');
            await envAuth.createUserWithEmailAndPassword(
              email: savedEmail.trim(),
              password: savedPass,
            );
            if (adminUser.displayName != null && adminUser.displayName!.isNotEmpty) {
              await envAuth.currentUser?.updateDisplayName(adminUser.displayName);
            }
            print('[EnvAuthSync] Auto-provisioned staff account in ${app.name}: ${envAuth.currentUser?.email}');
            if (explicitPassword != null && explicitPassword.isNotEmpty) {
              try {
                web.window.localStorage.setItem('tranyx_staff_password', explicitPassword);
                web.window.localStorage.setItem('tranyx_staff_email', savedEmail.trim());
              } catch (_) {}
            }
          } catch (createErr) {
            print('[EnvAuthSync] Auto-provision notice on ${app.name}: $createErr');
          }
        } else {
          print('[EnvAuthSync] Sign-in notice on ${app.name} (${e.code}): ${e.message}');
        }
      } catch (e) {
        print('[EnvAuthSync] Sign-in error on ${app.name}: $e');
      }
    } else if (savedPass == null || savedPass.isEmpty) {
      print('[EnvAuthSync] Staff password not in local session on ${app.name}. User: ${adminUser.email}.');
    }

    final currentUser = envAuth.currentUser;
    final envUid = currentUser?.uid;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final firestore = FirebaseFirestore.instanceFor(app: app);

    if (envUid != null) {
      final staffEmail = currentUser?.email ?? adminUser.email ?? 'admin@tranyx.app';
      try {
        await firestore.collection('p2p_agents').doc(envUid).set({
          'uid': envUid,
          'email': staffEmail,
          'role': 'agent',
          'isActive': true,
          'updatedAt': nowMs,
        }, SetOptions(merge: true));
        await firestore.collection('users').doc(envUid).set({
          'uid': envUid,
          'email': staffEmail,
          'role': 'admin',
          'isAdmin': true,
          'isP2pAgent': true,
          'name': adminUser.displayName ?? 'Staff Admin',
          'updatedAt': nowMs,
        }, SetOptions(merge: true));
      } catch (docErr) {
        print('[EnvAuthSync] Document bootstrap notice on ${app.name}: $docErr');
      }
    }

    return currentUser;
  } catch (e) {
    print('[EnvAuthSync] Sync notice on ${app.name}: $e');
    return null;
  }
}

/// Provider that streams the auth state of the authenticated Admin / Staff member for the active environment.
final activeEnvAuthUserProvider = StreamProvider<User?>((ref) {
  final adminAuth = ref.watch(adminAuthProvider);
  final adminUser = adminAuth.currentUser;

  final appAsync = ref.watch(firebaseAppProvider);
  return appAsync.when(
    data: (app) {
      final envAuth = FirebaseAuth.instanceFor(app: app);
      final controller = StreamController<User?>();

      // CRITICAL: Always emit the initial auth state immediately (even if null)
      // so downstream providers never deadlock in Riverpod AsyncLoading!
      controller.add(envAuth.currentUser);

      // Listen to auth state changes on the active environment app
      final sub = envAuth.authStateChanges().listen((user) {
        if (!controller.isClosed) {
          controller.add(user);
        }
      });

      // Synchronize staff authentication into this environment
      if (adminUser != null) {
        syncEnvAuth(app, adminUser).then((user) {
          if (!controller.isClosed) {
            controller.add(user ?? envAuth.currentUser);
          }
        }).catchError((err) {
          print('[ActiveEnvAuth] Sync error on ${app.name}: $err');
          if (!controller.isClosed) {
            controller.add(envAuth.currentUser);
          }
        });
      }

      ref.onDispose(() {
        sub.cancel();
        controller.close();
      });

      return controller.stream;
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

/// Provider signaling when target environment authentication has completed successfully
final targetEnvAuthReadyProvider = FutureProvider<bool>((ref) async {
  final userAsync = ref.watch(activeEnvAuthUserProvider);
  return userAsync.value != null;
});


/// Structured profile model for the currently authenticated Admin/Staff/Agent user.
class AdminStaffProfileModel {
  final String uid;
  final String name;
  final String displayName;
  final String email;
  final String role;
  final String? photoUrl;

  const AdminStaffProfileModel({
    required this.uid,
    required this.name,
    required this.displayName,
    required this.email,
    required this.role,
    this.photoUrl,
  });

  String get initials {
    if (name.isNotEmpty && name != 'Unknown' && name != 'Staff Agent') {
      final parts = name.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
    }
    if (displayName.isNotEmpty && displayName != 'Staff Agent') {
      return displayName.substring(0, displayName.length >= 2 ? 2 : 1).toUpperCase();
    }
    if (email.isNotEmpty) {
      return email.substring(0, email.length >= 2 ? 2 : 1).toUpperCase();
    }
    return 'AD';
  }

  String get roleDisplay {
    final r = role.toLowerCase().trim();
    if (r == 'admin' || r == 'superadmin') return 'Administrator';
    if (r == 'support' || r == 'support_agent') return 'Support Agent';
    if (r == 'agent' || r == 'p2p_agent') return 'P2P Agent';
    if (r == 'staff') return 'Staff Member';
    if (r.isNotEmpty) return role.toUpperCase();
    return 'Staff';
  }
}

String _formatHumanStaffName(String? raw, String email) {
  if (raw != null && raw.trim().isNotEmpty) {
    var cleaned = raw.trim();
    // If it's a full custom name without emails/dots (e.g. "Zeus Cajurao"), return as is
    if (!cleaned.contains('@') && !cleaned.contains('.') && !cleaned.contains('_')) {
      return cleaned;
    }
    // If it contains an email (e.g. "zeus.agent@tranyx.app" or "admin@tranyx.com")
    if (cleaned.contains('@')) {
      cleaned = cleaned.split('@').first;
    }
    // Format dotted/underscored handles into Title Case words (e.g. "zeus.agent" -> "Zeus Agent")
    return cleaned
        .replaceAll('.', ' ')
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + (s.length > 1 ? s.substring(1) : ''))
        .join(' ');
  }

  if (email.isNotEmpty && email.contains('@')) {
    final prefix = email.split('@').first;
    return prefix
        .replaceAll('.', ' ')
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + (s.length > 1 ? s.substring(1) : ''))
        .join(' ');
  }

  return 'Staff Member';
}

/// Provider streaming the full, real-time profile of the currently logged-in Admin/Staff/Agent.
final currentAdminProfileProvider = StreamProvider<AdminStaffProfileModel>((ref) {
  final auth = ref.watch(adminAuthProvider);
  final adminFirestore = ref.watch(adminFirestoreProvider);
  final firestore = ref.watch(firestoreProvider);

  return auth.userChanges().asyncExpand((user) {
    if (user == null) {
      return Stream.value(
        const AdminStaffProfileModel(
          uid: '',
          name: 'Logged Out',
          displayName: 'Logged Out',
          email: '',
          role: 'guest',
        ),
      );
    }

    final email = user.email ?? '';
    final defaultName = _formatHumanStaffName(user.displayName, email);
    final isExplicitAdmin = email == 'admin@tranyx.app' || email == 'admin@tranyx.com';
    final defaultRole = isExplicitAdmin ? 'Admin' : 'Staff';

    return adminFirestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .asyncMap((doc) async {
          Map<String, dynamic> d = {};
          if (doc.exists && doc.data() != null) {
            d = doc.data()!;
          } else {
            try {
              final userDoc = await firestore.collection('users').doc(user.uid).get();
              if (userDoc.exists && userDoc.data() != null) {
                d = userDoc.data()!;
              }
            } catch (_) {}
          }

          if (d.isNotEmpty) {
            final docName = d['name'] ?? d['displayName'] ?? d['agentName'];
            final docRole = d['role'] ?? d['position'] ?? d['staffRole'] ?? defaultRole;
            final docEmail = d['email'] ?? email;
            final photo = d['photoURL'] ?? d['photoUrl'] ?? d['avatarUrl'] ?? d['avatar'] ?? user.photoURL;

            final resolvedName = _formatHumanStaffName(
              docName?.toString(),
              docEmail.toString(),
            );

            return AdminStaffProfileModel(
              uid: user.uid,
              name: resolvedName,
              displayName: user.displayName?.isNotEmpty == true ? user.displayName! : resolvedName,
              email: docEmail.toString().trim().isNotEmpty ? docEmail.toString().trim() : email,
              role: docRole.toString(),
              photoUrl: photo?.toString(),
            );
          }

          return AdminStaffProfileModel(
            uid: user.uid,
            name: defaultName,
            displayName: defaultName,
            email: email,
            role: defaultRole,
            photoUrl: user.photoURL,
          );
        })
        .handleError(
          (_) => AdminStaffProfileModel(
            uid: user.uid,
            name: defaultName,
            displayName: defaultName,
            email: email,
            role: defaultRole,
            photoUrl: user.photoURL,
          ),
        );
  });
});
