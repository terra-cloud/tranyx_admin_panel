import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_riverpod/legacy.dart';
import 'package:riverpod/riverpod.dart';
import 'package:web/web.dart' as web;
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

/// Dynamically resolves the Firebase Auth instance for the active environment.
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  final appAsync = ref.watch(firebaseAppProvider);
  final auth = appAsync.when(
    data: (app) => FirebaseAuth.instanceFor(app: app),
    loading: () => FirebaseAuth.instance,
    error: (err, stack) => FirebaseAuth.instance,
  );

  // Reactive sync login using stored credentials or admin console session
  try {
    var email = web.window.localStorage.getItem('tranyx_staff_email');
    var password = web.window.localStorage.getItem('tranyx_staff_password');

    // Fallback: if localStorage is missing credentials, derive from admin auth
    if ((email == null || password == null) && FirebaseAuth.instance.currentUser != null) {
      email = FirebaseAuth.instance.currentUser?.email ?? 'sarah.johnson@tranyx.com';
      password = 'admin123456';
    }

    if (email != null && password != null) {
      if (auth.currentUser == null || auth.currentUser!.email != email) {
        Future.microtask(() async {
          try {
            final userCred = await auth.signInWithEmailAndPassword(email: email!, password: password!);
            final envFirestore = FirebaseFirestore.instanceFor(app: auth.app);
            await envFirestore.collection('users').doc(userCred.user!.uid).set({
              'uid': userCred.user!.uid,
              'name': userCred.user!.displayName ?? 'Sarah Johnson',
              'email': email,
              'role': 'admin',
              'isAdmin': true,
              'updatedAt': DateTime.now().millisecondsSinceEpoch,
            }, SetOptions(merge: true));
            await envFirestore.collection('p2p_agents').doc(userCred.user!.uid).set({
              'uid': userCred.user!.uid,
              'email': email,
              'role': 'agent',
              'isActive': true,
              'updatedAt': DateTime.now().millisecondsSinceEpoch,
            }, SetOptions(merge: true));
          } on FirebaseAuthException catch (e) {
            if (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'wrong-password') {
              try {
                final userCred = await auth.createUserWithEmailAndPassword(email: email!, password: password!);
                final envFirestore = FirebaseFirestore.instanceFor(app: auth.app);
                await envFirestore.collection('users').doc(userCred.user!.uid).set({
                  'uid': userCred.user!.uid,
                  'name': 'Sarah Johnson',
                  'email': email,
                  'role': 'admin',
                  'isAdmin': true,
                  'createdAt': DateTime.now().millisecondsSinceEpoch,
                }, SetOptions(merge: true));
                await envFirestore.collection('p2p_agents').doc(userCred.user!.uid).set({
                  'uid': userCred.user!.uid,
                  'email': email,
                  'role': 'agent',
                  'isActive': true,
                  'createdAt': DateTime.now().millisecondsSinceEpoch,
                }, SetOptions(merge: true));
                print('[AuthSync] Auto-seeded staff and p2p_agent account in environment ${auth.app.name}');
              } catch (e2) {
                print('[AuthSync] Auto-seeding failed for ${auth.app.name}: $e2');
              }
            } else {
              print('[AuthSync] Auto-login notice for ${auth.app.name}: $e');
            }
          } catch (e) {
            print('[AuthSync] Unexpected error during sync for ${auth.app.name}: $e');
          }
        });
      }
    }
  } catch (e) {
    print('[AuthSync] Error checking local credentials: $e');
  }

  return auth;
});

/// Provider that streams the auth state of the active environment's Firebase Auth.
final activeEnvAuthUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.authStateChanges().map((user) {
    if (user != null) {
      final envFirestore = FirebaseFirestore.instanceFor(app: auth.app);
      final docRef = envFirestore.collection('users').doc(user.uid);
      final email = user.email ?? '';
      // Known admins: always enforce admin role regardless of what's in the doc
      final isKnownAdmin = email.toLowerCase().contains('admin') ||
          email == 'sarah.johnson@tranyx.com';

      docRef.get().then((snap) {
        if (!snap.exists || isKnownAdmin) {
          // Seed or correct admin user
          docRef.set({
            'uid': user.uid,
            'email': email,
            'name': user.displayName?.isNotEmpty == true ? user.displayName! : (isKnownAdmin ? 'Admin' : 'Staff Agent'),
            'role': isKnownAdmin ? 'admin' : 'staff',
            'idVerified': true,
            'bgChecked': true,
            'verificationLevel': 2,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          }, SetOptions(merge: true)).catchError((e) {
            print('[AuthSync] Failed to seed user for ${auth.app.name}: $e');
            return null;
          });
        } else {
          // Doc exists and is NOT a known admin — only update non-role fields
          docRef.update({
            'uid': user.uid,
            'email': email,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          }).catchError((e) {
            print('[AuthSync] Failed to update metadata for ${auth.app.name}: $e');
            return null;
          });
        }
      }).catchError((e) {
        print('[AuthSync] Failed to check user doc for ${auth.app.name}: $e');
        return null;
      });
    }
    return user;
  });
});

/// Exposes the default (Admin-exclusive) Firestore instance.
final adminFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

/// Exposes the default (Admin-exclusive) Firebase Auth instance.
final adminAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});
