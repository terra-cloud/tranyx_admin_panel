import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_riverpod/legacy.dart';
import 'package:riverpod/riverpod.dart';

import '../config/firebase_environments.dart';

/// Provider holding the selected active environment.
final activeEnvironmentProvider = StateProvider<Environment>((ref) {
  return Environment.development;
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
final activeEnvAuthUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(adminAuthProvider);
  return auth.userChanges();
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
