import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:web/web.dart' as web;

import '../core/providers/environment_provider.dart';
import '../core/config/firebase_environments.dart';

class LoginPage extends StatefulComponent {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String _email = '';
  String _password = '';
  String? _error;
  bool _loading = false;

  Future<void> _handleSubmit(BuildContext context) async {
    if (_email.isEmpty || _password.isEmpty) {
      setState(() {
        _error = 'Please fill in all fields.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read(adminAuthProvider);
      // Sign in staff to admin console project
      await auth.signInWithEmailAndPassword(
        email: _email,
        password: _password,
      );

      // Save credentials for cross-environment authentication synchronization
      try {
        web.window.localStorage.setItem('tranyx_staff_email', _email);
        web.window.localStorage.setItem('tranyx_staff_password', _password);
      } catch (e) {
        print('[Login] Failed to store credentials locally: $e');
      }

      // Simultaneously sign in to all three environment Firebase apps
      for (final env in Environment.values) {
        try {
          FirebaseApp app;
          try {
            app = Firebase.app(env.name);
          } catch (_) {
            app = await Firebase.initializeApp(
              name: env.name,
              options: FirebaseEnv.optionsFor(env),
            );
          }
          final envAuth = FirebaseAuth.instanceFor(app: app);
          try {
            await envAuth.signInWithEmailAndPassword(
              email: _email,
              password: _password,
            );
          } on FirebaseAuthException catch (e) {
            if (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'wrong-password') {
              // Self-healing: register the staff account in this environment auth
              final userCred = await envAuth.createUserWithEmailAndPassword(
                email: _email,
                password: _password,
              );

              // Seed their admin user document in the environment's Firestore
              final envFirestore = FirebaseFirestore.instanceFor(app: app);
              await envFirestore.collection('users').doc(userCred.user!.uid).set({
                'name': 'Sarah Johnson',
                'email': _email,
                'role': 'admin',
                'createdAt': DateTime.now().millisecondsSinceEpoch,
              }, SetOptions(merge: true));
              print('[Login] Auto-seeded staff account in environment ${env.name}');
            } else {
              rethrow;
            }
          }
        } catch (e) {
          print('[Login] Sync login/seeding to environment ${env.name} failed: $e');
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message ?? 'Authentication failed.';
      });
    } catch (e) {
      setState(() {
        _error = 'An unexpected error occurred: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'w-full min-h-screen bg-[#eff2f0] flex flex-col justify-center items-center p-4 relative overflow-hidden', [
      // Decorative top/bottom elements matching light theme
      div(
        classes:
            'absolute top-1/4 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[400px] h-[400px] rounded-full bg-emerald-500/5 blur-[120px] pointer-events-none',
        [],
      ),
      div(
        classes:
            'absolute bottom-1/4 left-1/3 w-[300px] h-[300px] rounded-full bg-indigo-500/5 blur-[100px] pointer-events-none',
        [],
      ),

      // White Minimalist Card container
      div(
        classes:
            'w-full max-w-md bg-white border border-zinc-200/60 p-8 rounded-[28px] shadow-[0_8px_40px_rgba(0,0,0,0.02)] relative z-10 flex flex-col gap-6',
        [
          // Brand Header
          div(classes: 'flex flex-col items-center text-center gap-2', [
            div(
              classes:
                  'w-16 h-16 p-2 bg-[#f3f6f4] border border-zinc-200/50 rounded-2xl flex items-center justify-center mb-1 shadow-sm',
              [
                img(
                  src: '/images/logo.png',
                  alt: 'Tranyx Logo',
                  classes: 'w-12 h-12 object-contain drop-shadow-sm',
                ),
              ],
            ),
            h2(classes: 'text-xl font-black text-zinc-900 tracking-tight', [Component.text('TRANYX PORTAL')]),
            p(classes: 'text-xs text-zinc-400 font-semibold max-w-xs', [
              Component.text('Administrative & Customer Support Console'),
            ]),
          ]),

          // Error message banner
          if (_error != null)
            div(
              classes:
                  'p-3.5 rounded-xl border border-red-200 bg-red-50 text-red-500 text-xs font-semibold flex items-center gap-2.5',
              [
                span(classes: 'text-base', [Component.text('⚠️')]),
                span([Component.text(_error!)]),
              ],
            ),

          // Form Fields
          div(classes: 'flex flex-col gap-4', [
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                Component.text('Email Address'),
              ]),
              input(
                classes:
                    'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-3 text-xs text-zinc-800 placeholder-zinc-400 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                attributes: {'type': 'email', 'placeholder': 'staff@tranyx.com'},
                onInput: (value) => _email = value as String,
              ),
            ]),
            div(classes: 'flex flex-col gap-1.5', [
              label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                Component.text('Password'),
              ]),
              input(
                classes:
                    'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-3 text-xs text-zinc-800 placeholder-zinc-400 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                attributes: {'type': 'password', 'placeholder': '••••••••'},
                onInput: (value) => _password = value as String,
              ),
            ]),

            // Submit Button (Black minimalist pill)
            button(
              onClick: _loading ? null : () => _handleSubmit(context),
              classes:
                  'w-full py-3.5 bg-black hover:bg-zinc-800 disabled:bg-zinc-700 text-white text-xs font-bold rounded-xl transition-all duration-300 shadow-md shadow-black/10 flex items-center justify-center gap-2 mt-2',
              attributes: _loading ? {'disabled': 'true'} : {},
              [
                if (_loading)
                  span(
                    classes:
                        'inline-block animate-spin h-3.5 w-3.5 border-2 border-white/30 border-t-white rounded-full',
                    [],
                  )
                else
                  Component.text('Authenticate & Enter'),
              ],
            ),
          ]),

          // Footer disclaimer
          p(classes: 'text-[10px] text-zinc-400 text-center leading-normal mt-2 font-medium', [
            Component.text('Authorized staff only. Public sign-up is disabled.'),
          ]),
        ],
      ),
    ]);
  }
}
