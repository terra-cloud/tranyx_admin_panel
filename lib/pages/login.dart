import 'package:firebase_auth/firebase_auth.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:web/web.dart' as web;

import '../core/providers/environment_provider.dart';

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
      final userCred = await auth.signInWithEmailAndPassword(
        email: _email.trim(),
        password: _password,
      );

      final user = userCred.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'user-not-found', message: 'User not found.');
      }

      // Verify the user exists in tranyx-admin-portal staff directory or is an admin
      final adminFirestore = context.read(adminFirestoreProvider);
      final userDoc = await adminFirestore.collection('users').doc(user.uid).get();
      final email = user.email?.toLowerCase().trim() ?? '';
      final isKnownAdmin = email.contains('admin') || email == 'admin@tranyx.app';

      if (!userDoc.exists && !isKnownAdmin) {
        await auth.signOut();
        try {
          web.window.localStorage.removeItem('tranyx_staff_email');
          web.window.localStorage.removeItem('tranyx_staff_password');
        } catch (_) {}
        setState(() {
          _error = 'Unauthorized: This account is not registered as authorized staff in the Tranyx Admin Portal.';
        });
        return;
      }

      // Save credentials for quick session persistence
      try {
        web.window.localStorage.setItem('tranyx_staff_email', _email.trim());
        web.window.localStorage.setItem('tranyx_staff_password', _password);
      } catch (e) {
        print('[Login] Failed to store credentials locally: $e');
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No staff account found with this email in the admin portal.';
          break;
        case 'wrong-password':
        case 'invalid-credential':
          errorMessage = 'Incorrect password or invalid credentials.';
          break;
        case 'user-disabled':
          errorMessage = 'This staff account has been disabled. Please contact an administrator.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many failed login attempts. Please try again later.';
          break;
        case 'invalid-email':
          errorMessage = 'Please enter a valid email address.';
          break;
        default:
          errorMessage = e.message ?? 'Authentication failed.';
      }
      setState(() {
        _error = errorMessage;
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
    return div(
      classes:
          'w-full min-h-screen bg-[#eff2f0] flex flex-col justify-center items-center p-4 relative overflow-hidden',
      [
        // Decorative top/bottom elements matching light theme
        div(
          classes: 'absolute top-1/4 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[400px] h-[400px] rounded-full bg-emerald-500/5 blur-[120px] pointer-events-none',
          [],
        ),
        div(
          classes: 'absolute bottom-1/4 left-1/3 w-[300px] h-[300px] rounded-full bg-indigo-500/5 blur-[100px] pointer-events-none',
          [],
        ),

        // White Minimalist Card container
        div(
          classes: 'w-full max-w-md bg-white border border-zinc-200/60 p-8 rounded-[28px] shadow-[0_8px_40px_rgba(0,0,0,0.02)] relative z-10 flex flex-col gap-6',
          [
            // Brand Header
            div(classes: 'flex flex-col items-center text-center gap-2', [
              div(
                classes: 'w-16 h-16 p-2 bg-[#f3f6f4] border border-zinc-200/50 rounded-2xl flex items-center justify-center mb-1 shadow-sm',
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
                classes: 'p-3.5 rounded-xl border border-red-200 bg-red-50 text-red-500 text-xs font-semibold flex items-center gap-2.5',
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
                  id: 'login-email-input',
                  classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-3 text-xs text-zinc-800 placeholder-zinc-400 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                  attributes: {'type': 'email', 'placeholder': 'staff@tranyx.com'},
                  onInput: (value) => _email = value as String,
                ),
              ]),
              div(classes: 'flex flex-col gap-1.5', [
                label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                  Component.text('Password'),
                ]),
                input(
                  id: 'login-password-input',
                  classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-3 text-xs text-zinc-800 placeholder-zinc-400 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                  attributes: {'type': 'password', 'placeholder': '••••••••'},
                  onInput: (value) => _password = value as String,
                ),
              ]),

              // Submit Button (Black minimalist pill)
              button(
                id: 'login-submit-button',
                onClick: _loading ? null : () => _handleSubmit(context),
                classes: 'w-full py-3.5 bg-black hover:bg-zinc-800 disabled:bg-zinc-700 text-white text-xs font-bold rounded-xl transition-all duration-300 shadow-md shadow-black/10 flex items-center justify-center gap-2 mt-2 cursor-pointer',
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
      ],
    );
  }
}
