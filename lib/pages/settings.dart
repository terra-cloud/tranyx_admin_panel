import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:web/web.dart' as web;

import '../app.dart';
import '../core/config/firebase_environments.dart';
import '../core/providers/environment_provider.dart';
import '../core/services/request_lock_service.dart';

class SettingsPage extends StatefulComponent {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _newStaffName = '';
  String _newStaffEmail = '';
  String _newStaffPassword = '';
  String _newStaffRole = 'staff'; // Default role to create
  String? _staffMessage;
  String? _staffError;
  bool _staffLoading = false;

  String _profileName = '';
  String? _profileMessage;
  String? _profileError;
  bool _profileLoading = false;

  String _newPassword = '';
  String? _passwordMessage;
  String? _passwordError;
  bool _passwordLoading = false;

  // System config lock & timeout state
  String _claimTimeoutStr = '180';
  String _heartbeatTimeoutStr = '600';
  String _mailtrapToken = const String.fromEnvironment(
    'MAIL_TRAP_TOKEN',
    defaultValue: String.fromEnvironment('MAILTRAP_TOKEN'),
  );
  String _mailtrapProxyUrl = const String.fromEnvironment(
    'MAIL_TRAP_PROXY_URL',
    defaultValue: String.fromEnvironment('MAILTRAP_PROXY_URL'),
  );
  String _mailtrapInboxId = const String.fromEnvironment(
    'MAIL_TRAP_INBOX_ID',
    defaultValue: '4886849',
  );
  String _mailtrapFromEmail = const String.fromEnvironment(
    'MAIL_TRAP_FROM_EMAIL',
    defaultValue: 'support@tranyx.com',
  );
  String _mailtrapFromName = const String.fromEnvironment(
    'MAIL_TRAP_FROM_NAME',
    defaultValue: 'Tranyx Support',
  );
  String? _configMessage;
  String? _configError;
  bool _configLoading = false;
  bool _configInitialized = false;

  Future<void> _updateSystemConfig(BuildContext context) async {
    final claimSec = int.tryParse(_claimTimeoutStr.trim()) ?? 180;
    final heartbeatSec = int.tryParse(_heartbeatTimeoutStr.trim()) ?? 600;

    if (claimSec < 10 || claimSec > 3600) {
      setState(() {
        _configError = 'Claim timeout must be between 10 and 3600 seconds.';
        _configMessage = null;
      });
      return;
    }

    if (heartbeatSec < 30 || heartbeatSec > 7200) {
      setState(() {
        _configError = 'Heartbeat timeout must be between 30 and 7200 seconds.';
        _configMessage = null;
      });
      return;
    }

    setState(() {
      _configLoading = true;
      _configError = null;
      _configMessage = null;
    });

    try {
      final adminFirestore = context.read(adminFirestoreProvider);
      final activeFirestore = context.read(firestoreProvider);

      final updateData = {
        'claimTimeoutSeconds': claimSec,
        'heartbeatTimeoutSeconds': heartbeatSec,
        'mailtrapToken': _mailtrapToken.trim(),
        'mailtrapProxyUrl': _mailtrapProxyUrl.trim(),
        'mailtrapInboxId': _mailtrapInboxId.trim(),
        'mailtrapFromEmail': _mailtrapFromEmail.trim(),
        'mailtrapFromName': _mailtrapFromName.trim(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      await adminFirestore.collection('system_config').doc('settings').set(updateData, SetOptions(merge: true));
      await activeFirestore
          .collection('system_config')
          .doc('settings')
          .set(updateData, SetOptions(merge: true))
          .catchError((e) {
            print('[Settings] Active firestore sync notice: $e');
          });

      setState(() {
        _configMessage = 'System request lock timeouts & Mailtrap email credentials updated!';
      });
    } catch (e) {
      print('[Settings] Failed to update system config: $e');
      setState(() {
        _configError = 'Failed to update system config: $e';
      });
    } finally {
      setState(() {
        _configLoading = false;
      });
    }
  }

  Future<void> _updateProfile(BuildContext context, fb.User user) async {
    if (_profileName.trim().isEmpty) {
      setState(() {
        _profileError = 'Please enter a valid display name to save.';
        _profileMessage = null;
      });
      return;
    }

    setState(() {
      _profileLoading = true;
      _profileError = null;
      _profileMessage = null;
    });

    try {
      final newName = _profileName.trim();
      await user.updateDisplayName(newName);
      await user.reload();

      // 1. Update in Admin Firestore
      final adminDb = context.read(adminFirestoreProvider);
      await adminDb
          .collection('users')
          .doc(user.uid)
          .set({
            'uid': user.uid,
            'name': newName,
            'displayName': newName,
            'email': user.email,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          }, SetOptions(merge: true))
          .catchError((_) {});

      // 2. Update in Active Environment Firestore
      final activeDb = context.read(firestoreProvider);
      await activeDb
          .collection('users')
          .doc(user.uid)
          .set({
            'uid': user.uid,
            'name': newName,
            'displayName': newName,
            'email': user.email,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          }, SetOptions(merge: true))
          .catchError((_) {});

      // Force refresh of providers to update UI immediately
      context.invalidate(adminCurrentUserProvider);
      context.invalidate(currentAdminProfileProvider);

      setState(() {
        _profileMessage = 'Display name successfully updated to "$newName".';
        _profileName = '';
      });
    } catch (e) {
      setState(() {
        _profileError = e.toString().replaceAll('Exception:', '').trim();
      });
    } finally {
      setState(() {
        _profileLoading = false;
      });
    }
  }

  Future<void> _updatePassword(BuildContext context, fb.User user) async {
    if (_newPassword.isEmpty) {
      setState(() {
        _passwordError = 'Please enter a new password.';
        _passwordMessage = null;
      });
      return;
    }

    if (_newPassword.length < 6) {
      setState(() {
        _passwordError = 'Password must be at least 6 characters.';
        _passwordMessage = null;
      });
      return;
    }

    setState(() {
      _passwordLoading = true;
      _passwordError = null;
      _passwordMessage = null;
    });

    try {
      try {
        await user.updatePassword(_newPassword);
      } on fb.FirebaseAuthException catch (authErr) {
        if (authErr.code == 'requires-recent-login' || authErr.code == 'invalid-credential') {
          final email = user.email ?? web.window.localStorage.getItem('tranyx_staff_email');
          final savedPass = web.window.localStorage.getItem('tranyx_staff_password');
          if (email != null && savedPass != null) {
            try {
              final cred = fb.EmailAuthProvider.credential(email: email, password: savedPass);
              await user.reauthenticateWithCredential(cred);
              await user.updatePassword(_newPassword);
              web.window.localStorage.setItem('tranyx_staff_password', _newPassword);
              setState(() {
                _passwordMessage = 'Password updated successfully.';
                _newPassword = '';
              });
              return;
            } catch (_) {}
          }
          throw Exception('For security, please log out and log in again before changing your password.');
        } else {
          rethrow;
        }
      }

      web.window.localStorage.setItem('tranyx_staff_password', _newPassword);
      await user.reload();

      setState(() {
        _passwordMessage = 'Password updated successfully.';
        _newPassword = '';
      });
    } catch (e) {
      setState(() {
        _passwordError = e.toString().replaceAll('Exception:', '').trim();
      });
    } finally {
      setState(() {
        _passwordLoading = false;
      });
    }
  }

  Future<void> _createStaffAccount(BuildContext context) async {
    if (_newStaffName.trim().isEmpty || _newStaffEmail.isEmpty || _newStaffPassword.isEmpty) {
      setState(() {
        _staffError = 'Please fill in all fields (Name, Email, and Password).';
        _staffMessage = null;
      });
      return;
    }

    setState(() {
      _staffLoading = true;
      _staffError = null;
      _staffMessage = null;
    });

    try {
      // Step 1: Create a temporary secondary Firebase app referencing the default project
      final appName = 'temp_staff_reg_${DateTime.now().millisecondsSinceEpoch}';
      final tempApp = await Firebase.initializeApp(
        name: appName,
        options: FirebaseEnv.adminOptions,
      );

      final tempAuth = fb.FirebaseAuth.instanceFor(app: tempApp);
      final credential = await tempAuth.createUserWithEmailAndPassword(
        email: _newStaffEmail,
        password: _newStaffPassword,
      );

      // Step 2: Register user metadata inside the selected environment's Firestore
      if (credential.user != null) {
        await credential.user!.updateDisplayName(_newStaffName.trim());

        // Save in Admin Firestore too so they exist in staff listings
        final adminFirestore = context.read(adminFirestoreProvider);
        await adminFirestore.collection('users').doc(credential.user!.uid).set({
          'uid': credential.user!.uid,
          'name': _newStaffName.trim(),
          'email': _newStaffEmail,
          'role': _newStaffRole,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // Step 3: Delete temporary App reference
      await tempApp.delete();

      setState(() {
        _staffMessage = 'Staff account ($_newStaffRole) created successfully!';
        _newStaffName = '';
        _newStaffEmail = '';
        _newStaffPassword = '';
      });
    } on fb.FirebaseAuthException catch (e) {
      setState(() {
        _staffError = e.message ?? 'Auth registration failed.';
      });
    } catch (e) {
      setState(() {
        _staffError = 'Failed to create account: $e';
      });
    } finally {
      setState(() {
        _staffLoading = false;
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final currentEnv = context.watch(activeEnvironmentProvider);
    final user = context.watch(adminCurrentUserProvider).value;
    final profile =
        context.watch(currentAdminProfileProvider).value ??
        const AdminStaffProfileModel(
          uid: '',
          name: 'Staff Member',
          displayName: 'Staff Member',
          email: '',
          role: 'staff',
        );
    final systemConfigAsync = context.watch(systemConfigStreamProvider);

    final userEmail = profile.email.isNotEmpty ? profile.email : (user?.email ?? '');
    final role = profile.role.toLowerCase();
    final isAdmin = role.contains('admin') || userEmail == 'admin@tranyx.app' || userEmail == 'admin@tranyx.com';

    // Populate initial system config values once loaded
    if (!_configInitialized && systemConfigAsync.hasValue) {
      final cfg = systemConfigAsync.value!;
      _claimTimeoutStr = cfg.claimTimeoutSeconds.toString();
      _heartbeatTimeoutStr = cfg.heartbeatTimeoutSeconds.toString();
      if (cfg.mailtrapToken.isNotEmpty) {
        _mailtrapToken = cfg.mailtrapToken;
      }
      if (cfg.mailtrapProxyUrl.isNotEmpty) {
        _mailtrapProxyUrl = cfg.mailtrapProxyUrl;
      }
      if (cfg.mailtrapInboxId.isNotEmpty) {
        _mailtrapInboxId = cfg.mailtrapInboxId;
      }
      if (cfg.mailtrapFromEmail.isNotEmpty) {
        _mailtrapFromEmail = cfg.mailtrapFromEmail;
      }
      if (cfg.mailtrapFromName.isNotEmpty) {
        _mailtrapFromName = cfg.mailtrapFromName;
      }
      _configInitialized = true;
    }

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0]', [
      // Modern Header block
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [
            Component.text('System Configuration Console'),
          ]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text(
              'Audit controls for staff roles, single-agent request lock timeouts, and platform constraints.',
            ),
          ]),
        ]),
      ]),

      div(classes: 'grid grid-cols-1 lg:grid-cols-2 gap-8', [
        // Left Column (Request Lock Timeouts & Profile Settings)
        div(classes: 'flex flex-col gap-8', [
          // Panel 1: Single-Agent Request Lock & Timeout Protocol Configuration (Admin only)
          if (isAdmin)
            div(
              classes: 'p-6 rounded-[28px] border border-zinc-200/50 bg-white flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
              [
                h4(classes: 'text-sm font-bold text-zinc-900 flex items-center gap-2 border-b border-zinc-50 pb-3', [
                  span([Component.text('⏱️')]),
                  Component.text('Single-Agent Request Lock & Timeouts'),
                ]),
                p(classes: 'text-xs text-zinc-500 leading-relaxed font-medium', [
                  Component.text(
                    'Configure the automated single-agent claim window and active session heartbeat expiration limits.',
                  ),
                ]),

                if (_configMessage != null)
                  div(
                    classes:
                        'p-3 rounded-xl bg-emerald-50 border border-emerald-200 text-[#0fa958] text-xs font-semibold',
                    [Component.text(_configMessage!)],
                  ),
                if (_configError != null)
                  div(classes: 'p-3 rounded-xl bg-red-50 border border-red-200 text-red-500 text-xs font-semibold', [
                    Component.text(_configError!),
                  ]),

                div(classes: 'flex flex-col gap-3.5', [
                  div(classes: 'flex flex-col gap-1.5', [
                    div(classes: 'flex items-center justify-between', [
                      label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                        Component.text('Claim Timeout Window (Seconds)'),
                      ]),
                      span(classes: 'text-[10px] font-mono text-zinc-400 font-bold', [
                        Component.text('Default: 180s (3 min)'),
                      ]),
                    ]),
                    input(
                      value: _claimTimeoutStr,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'number', 'placeholder': '180', 'min': '10', 'max': '3600'},
                      onInput: (dynamic value) => setState(() => _claimTimeoutStr = (value as String?) ?? ''),
                    ),
                    span(classes: 'text-[10px] text-zinc-400 font-medium leading-relaxed', [
                      Component.text(
                        'If assigned agent fails to accept/claim within this window, the lock automatically returns to PENDING queue.',
                      ),
                    ]),
                  ]),

                  div(classes: 'flex flex-col gap-1.5', [
                    div(classes: 'flex items-center justify-between', [
                      label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                        Component.text('Active Heartbeat Timeout (Seconds)'),
                      ]),
                      span(classes: 'text-[10px] font-mono text-zinc-400 font-bold', [
                        Component.text('Default: 600s (10 min)'),
                      ]),
                    ]),
                    input(
                      value: _heartbeatTimeoutStr,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'number', 'placeholder': '600', 'min': '30', 'max': '7200'},
                      onInput: (dynamic value) => setState(() => _heartbeatTimeoutStr = (value as String?) ?? ''),
                    ),
                    span(classes: 'text-[10px] text-zinc-400 font-medium leading-relaxed', [
                      Component.text(
                        'If an active agent becomes unresponsive longer than this duration, the request returns to PENDING queue.',
                      ),
                    ]),
                  ]),

                  div(classes: 'flex flex-col gap-1.5 border-t border-zinc-100 pt-3', [
                    div(classes: 'flex items-center justify-between', [
                      label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                        Component.text('Mailtrap API Token (Transactional Email)'),
                      ]),
                      span(
                        classes:
                            'text-[10px] font-mono ${_mailtrapToken.isNotEmpty ? 'text-emerald-600' : 'text-amber-500'} font-bold',
                        [
                          Component.text(_mailtrapToken.isNotEmpty ? 'Active / Configured' : 'Not Set (Optional)'),
                        ],
                      ),
                    ]),
                    input(
                      value: _mailtrapToken,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 font-mono focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'text', 'placeholder': 'Enter Mailtrap API Token'},
                      onInput: (dynamic value) => setState(() => _mailtrapToken = (value as String?) ?? ''),
                    ),
                    span(classes: 'text-[10px] text-zinc-400 font-medium leading-relaxed', [
                      Component.text(
                        'Token used to deliver ticket submission confirmations and response updates to user emails via Mailtrap.',
                      ),
                    ]),
                  ]),

                  div(classes: 'flex flex-col gap-1.5', [
                    div(classes: 'flex items-center justify-between', [
                      label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                        Component.text('Cloudflare CORS Proxy URL (Required for Browser)'),
                      ]),
                      span(
                        classes:
                            'text-[10px] font-mono ${_mailtrapProxyUrl.isNotEmpty ? 'text-emerald-600' : 'text-amber-500'} font-bold',
                        [
                          Component.text(_mailtrapProxyUrl.isNotEmpty ? 'Configured' : 'Optional / Direct'),
                        ],
                      ),
                    ]),
                    input(
                      value: _mailtrapProxyUrl,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 font-mono focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'text', 'placeholder': 'https://your-worker.workers.dev'},
                      onInput: (dynamic value) => setState(() => _mailtrapProxyUrl = (value as String?) ?? ''),
                    ),
                    span(classes: 'text-[10px] text-zinc-400 font-medium leading-relaxed', [
                      Component.text(
                        'Cloudflare Worker URL that relays email requests with CORS headers enabled.',
                      ),
                    ]),
                  ]),

                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Mailtrap Sandbox Inbox ID (For Testing)'),
                    ]),
                    input(
                      value: _mailtrapInboxId,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 font-mono focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'text', 'placeholder': '4886849'},
                      onInput: (dynamic value) => setState(() => _mailtrapInboxId = (value as String?) ?? ''),
                    ),
                    span(classes: 'text-[10px] text-zinc-400 font-medium leading-relaxed', [
                      Component.text(
                        'Inbox ID for Mailtrap Email Testing (Sandbox). Default: 4886849.',
                      ),
                    ]),
                  ]),

                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Mailtrap Sender Email'),
                    ]),
                    input(
                      value: _mailtrapFromEmail,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'text', 'placeholder': 'support@tranyx.com'},
                      onInput: (dynamic value) => setState(() => _mailtrapFromEmail = (value as String?) ?? ''),
                    ),
                    span(classes: 'text-[10px] text-zinc-400 font-medium leading-relaxed', [
                      Component.text(
                        'Verified sender address for automated ticket emails (e.g. support@tranyx.com).',
                      ),
                    ]),
                  ]),

                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Mailtrap Sender Name'),
                    ]),
                    input(
                      value: _mailtrapFromName,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'text', 'placeholder': 'Tranyx Support'},
                      onInput: (dynamic value) => setState(() => _mailtrapFromName = (value as String?) ?? ''),
                    ),
                    span(classes: 'text-[10px] text-zinc-400 font-medium leading-relaxed', [
                      Component.text(
                        'Display name on delivered outgoing emails (e.g. Tranyx Support).',
                      ),
                    ]),
                  ]),

                  button(
                    onClick: _configLoading ? null : () => _updateSystemConfig(context),
                    classes: 'w-full py-3 bg-black hover:bg-zinc-800 text-white text-xs font-bold rounded-xl transition-all shadow-md shadow-black/10 flex items-center justify-center gap-2 mt-1',
                    attributes: _configLoading ? {'disabled': 'true'} : {},
                    [
                      if (_configLoading)
                        span(
                          classes: 'inline-block animate-spin h-3.5 w-3.5 border-2 border-white/30 border-t-white rounded-full',
                          [],
                        )
                      else
                        Component.text('Save Settings & Credentials'),
                    ],
                  ),
                ]),
              ],
            ),

          // Panel 2: Environmental features/limits
          div(
            classes: 'p-6 rounded-[28px] border border-zinc-200/50 bg-white flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
            [
              h4(classes: 'text-sm font-bold text-zinc-900 flex items-center gap-2 border-b border-zinc-50 pb-3', [
                span([Component.text('⚡')]),
                Component.text('Feature Constraints (${currentEnv.name.toUpperCase()})'),
              ]),
              p(classes: 'text-xs text-zinc-500 leading-relaxed font-medium', [
                Component.text(
                  'System configuration parameters are loaded from public config documents. Modify threshold constraints below for reference.',
                ),
              ]),
              div(classes: 'flex flex-col gap-3 mt-1', [
                div(classes: 'flex items-center justify-between text-xs', [
                  span(classes: 'text-zinc-500 font-semibold', [Component.text('Daily Volume Cap')]),
                  span(classes: 'font-extrabold text-zinc-900', [
                    Component.text(currentEnv == Environment.production ? '₱500,000.00' : '₱50,000.00'),
                  ]),
                ]),
                div(classes: 'flex items-center justify-between text-xs border-t border-zinc-100 pt-3', [
                  span(classes: 'text-zinc-500 font-semibold', [Component.text('Auto-Lockout Threshold')]),
                  span(classes: 'font-extrabold text-zinc-900', [
                    Component.text(
                      currentEnv == Environment.production ? '5 verification failures' : '3 verification failures',
                    ),
                  ]),
                ]),
                div(classes: 'flex items-center justify-between text-xs border-t border-zinc-100 pt-3', [
                  span(classes: 'text-zinc-500 font-semibold', [Component.text('Supported ID Cards')]),
                  span(classes: 'font-extrabold text-indigo-500', [Component.text('Drivers License, Passport, UMID')]),
                ]),
              ]),
            ],
          ),

          // Panel 3: Admin Profile Settings
          if (user != null) ...[
            div(
              classes: 'p-6 rounded-[28px] border border-zinc-200/50 bg-white flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
              [
                div(classes: 'flex items-center justify-between border-b border-zinc-100 pb-3', [
                  h4(classes: 'text-sm font-bold text-zinc-900 flex items-center gap-2', [
                    span([Component.text('👤')]),
                    Component.text('Staff Profile & Display Name'),
                  ]),
                  span(
                    classes:
                        'text-[9px] font-extrabold uppercase px-2 py-0.5 rounded-full '
                        '${profile.role.toLowerCase().contains("admin") ? "bg-black text-white" : "bg-indigo-50 text-indigo-700 border border-indigo-200/60"}',
                    [Component.text(profile.roleDisplay)],
                  ),
                ]),
                p(classes: 'text-xs text-zinc-500 font-medium leading-relaxed', [
                  Component.text(
                    'Customize your staff display name shown to customers and fellow agents across the portal.',
                  ),
                ]),

                if (_profileMessage != null)
                  div(
                    classes:
                        'p-3 rounded-xl bg-emerald-50 border border-emerald-200 text-[#0fa958] text-xs font-semibold',
                    [Component.text(_profileMessage!)],
                  ),
                if (_profileError != null)
                  div(classes: 'p-3 rounded-xl bg-red-50 border border-red-200 text-red-500 text-xs font-semibold', [
                    Component.text(_profileError!),
                  ]),

                div(classes: 'flex flex-col gap-3.5', [
                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Full Name / Display Name'),
                    ]),
                    input(
                      value: _profileName,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all font-semibold',
                      attributes: {
                        'type': 'text',
                        'name': 'staff_display_name_field',
                        'autocomplete': 'off',
                        'placeholder': profile.name,
                      },
                      onInput: (value) => _profileName = value as String,
                    ),
                  ]),
                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Email Address'),
                    ]),
                    input(
                      value: profile.email.isNotEmpty ? profile.email : (user.email ?? ''),
                      classes: 'bg-zinc-100 border border-zinc-200 rounded-xl px-4 py-2.5 text-xs text-zinc-500 cursor-not-allowed focus:outline-none font-semibold',
                      attributes: {'type': 'email', 'disabled': 'true'},
                    ),
                  ]),
                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Role & Access Level'),
                    ]),
                    input(
                      value: profile.roleDisplay,
                      classes: 'bg-zinc-100 border border-zinc-200 rounded-xl px-4 py-2.5 text-xs text-zinc-500 cursor-not-allowed focus:outline-none font-semibold',
                      attributes: {'type': 'text', 'disabled': 'true'},
                    ),
                  ]),

                  button(
                    onClick: _profileLoading ? null : () => _updateProfile(context, user),
                    classes: 'w-full py-3 bg-black hover:bg-zinc-800 text-white text-xs font-bold rounded-xl transition-all shadow-md shadow-black/10 flex items-center justify-center gap-2 mt-1',
                    attributes: _profileLoading ? {'disabled': 'true'} : {},
                    [
                      if (_profileLoading)
                        span(
                          classes: 'inline-block animate-spin h-3.5 w-3.5 border-2 border-white/30 border-t-white rounded-full',
                          [],
                        )
                      else
                        Component.text('Save Display Name'),
                    ],
                  ),
                ]),
              ],
            ),

            // Panel 4: Password & Security
            div(
              classes: 'p-6 rounded-[28px] border border-zinc-200/50 bg-white flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
              [
                h4(classes: 'text-sm font-bold text-zinc-900 flex items-center gap-2 border-b border-zinc-100 pb-3', [
                  span([Component.text('🔒')]),
                  Component.text('Security & Password'),
                ]),
                p(classes: 'text-xs text-zinc-500 font-medium leading-relaxed', [
                  Component.text('Reset your staff account access password.'),
                ]),

                if (_passwordMessage != null)
                  div(
                    classes:
                        'p-3 rounded-xl bg-emerald-50 border border-emerald-200 text-[#0fa958] text-xs font-semibold',
                    [Component.text(_passwordMessage!)],
                  ),
                if (_passwordError != null)
                  div(classes: 'p-3 rounded-xl bg-red-50 border border-red-200 text-red-500 text-xs font-semibold', [
                    Component.text(_passwordError!),
                  ]),

                div(classes: 'flex flex-col gap-3.5', [
                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('New Password'),
                    ]),
                    input(
                      value: _newPassword,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {
                        'type': 'password',
                        'autocomplete': 'new-password',
                        'name': 'staff_new_password_field',
                        'placeholder': '••••••••',
                      },
                      onInput: (value) => _newPassword = value as String,
                    ),
                  ]),

                  button(
                    onClick: _passwordLoading ? null : () => _updatePassword(context, user),
                    classes: 'w-full py-3 bg-zinc-800 hover:bg-black text-white text-xs font-bold rounded-xl transition-all shadow-md shadow-black/10 flex items-center justify-center gap-2 mt-1',
                    attributes: _passwordLoading ? {'disabled': 'true'} : {},
                    [
                      if (_passwordLoading)
                        span(
                          classes: 'inline-block animate-spin h-3.5 w-3.5 border-2 border-white/30 border-t-white rounded-full',
                          [],
                        )
                      else
                        Component.text('Update Password'),
                    ],
                  ),
                ]),
              ],
            ),
          ],
        ]),

        // Right Column: Staff Registration or Privilege Information
        div(classes: 'flex flex-col gap-8', [
          if (isAdmin)
            div(
              classes: 'p-6 rounded-[28px] border border-zinc-200/50 bg-white flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
              [
                h4(classes: 'text-sm font-bold text-zinc-900 flex items-center gap-2 border-b border-zinc-50 pb-3', [
                  span([Component.text('👤')]),
                  Component.text('Register Staff / Customer Support Account'),
                ]),
                p(classes: 'text-xs text-zinc-500 font-medium leading-relaxed', [
                  Component.text(
                    'Only admins can create support or management accounts. New users are assigned roles and recorded in the active environment.',
                  ),
                ]),

                if (_staffMessage != null)
                  div(
                    classes:
                        'p-3 rounded-xl bg-emerald-50 border border-emerald-200 text-[#0fa958] text-xs font-semibold',
                    [Component.text(_staffMessage!)],
                  ),
                if (_staffError != null)
                  div(classes: 'p-3 rounded-xl bg-red-50 border border-red-200 text-red-500 text-xs font-semibold', [
                    Component.text(_staffError!),
                  ]),

                // Staff account fields
                div(classes: 'flex flex-col gap-3.5', [
                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Staff Name'),
                    ]),
                    input(
                      value: _newStaffName,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'text', 'placeholder': 'Jane Doe'},
                      onInput: (value) => _newStaffName = value as String,
                    ),
                  ]),
                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Staff Email'),
                    ]),
                    input(
                      value: _newStaffEmail,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'email', 'placeholder': 'agent@tranyx.com'},
                      onInput: (value) => _newStaffEmail = value as String,
                    ),
                  ]),
                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Staff Password'),
                    ]),
                    input(
                      value: _newStaffPassword,
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'password', 'placeholder': '••••••••'},
                      onInput: (value) => _newStaffPassword = value as String,
                    ),
                  ]),
                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Access Role'),
                    ]),
                    select(
                      classes: 'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-850 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      onChange: (value) => _newStaffRole = (value).isNotEmpty ? (value).first : 'staff',
                      [
                        option(value: 'staff', selected: _newStaffRole == 'staff', [
                          Component.text('Staff (Customer Service)'),
                        ]),
                        option(value: 'admin', selected: _newStaffRole == 'admin', [Component.text('Admin Manager')]),
                      ],
                    ),
                  ]),

                  button(
                    onClick: _staffLoading ? null : () => _createStaffAccount(context),
                    classes: 'w-full py-3 bg-black hover:bg-zinc-800 text-white text-xs font-bold rounded-xl transition-all shadow-md shadow-black/10 flex items-center justify-center gap-2 mt-1',
                    attributes: _staffLoading ? {'disabled': 'true'} : {},
                    [
                      if (_staffLoading)
                        span(
                          classes: 'inline-block animate-spin h-3.5 w-3.5 border-2 border-white/30 border-t-white rounded-full',
                          [],
                        )
                      else
                        Component.text('Create Account'),
                    ],
                  ),
                ]),
              ],
            )
          else
            // Privilege Info for non-admins
            div(
              classes: 'p-6 rounded-[28px] border border-zinc-200/50 bg-white flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
              [
                h4(classes: 'text-sm font-bold text-zinc-900 flex items-center gap-2 border-b border-zinc-50 pb-3', [
                  span([Component.text('🔒')]),
                  Component.text('Access Privilege Policy'),
                ]),
                p(classes: 'text-xs text-zinc-500 leading-relaxed font-medium', [
                  Component.text(
                    'Admins can view and escalate staff access privileges. Registered accounts default to support level. Audit configurations are logged.',
                  ),
                ]),
                div(classes: 'flex flex-col gap-2 mt-2', [
                  div(
                    classes: 'p-4 rounded-xl bg-[#f8faf9] border border-zinc-200/50 flex justify-between items-center text-xs',
                    [
                      span(classes: 'font-semibold text-zinc-600', [Component.text('Security Rules Status')]),
                      span(classes: 'text-[#0fa958] font-extrabold text-[10px] tracking-wider uppercase', [
                        Component.text('Active'),
                      ]),
                    ],
                  ),
                  div(
                    classes: 'p-4 rounded-xl bg-[#f8faf9] border border-zinc-200/50 flex justify-between items-center text-xs',
                    [
                      span(classes: 'font-semibold text-zinc-600', [Component.text('Single-Agent Lock Protocol')]),
                      span(classes: 'text-indigo-500 font-extrabold text-[10px] tracking-wider uppercase', [
                        Component.text('Active (3-Min Limit)'),
                      ]),
                    ],
                  ),
                ]),
              ],
            ),
        ]),
      ]),
    ]);
  }
}
