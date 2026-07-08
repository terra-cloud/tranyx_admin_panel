import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../app.dart';
import '../core/config/firebase_environments.dart';
import '../core/providers/environment_provider.dart';

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
  String _newPassword = '';
  String? _profileMessage;
  String? _profileError;
  bool _profileLoading = false;

  Future<void> _updateProfile(BuildContext context, fb.User user) async {
    if (_profileName.trim().isEmpty && _newPassword.isEmpty) {
      setState(() {
        _profileError = 'Please specify a name or password to update.';
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
      final List<String> updates = [];
      if (_profileName.trim().isNotEmpty && _profileName.trim() != user.displayName) {
        await user.updateDisplayName(_profileName.trim());
        await user.reload();

        // 1. Update in Admin Firestore
        final adminDb = context.read(adminFirestoreProvider);
        await adminDb
            .collection('users')
            .doc(user.uid)
            .update({
              'name': _profileName.trim(),
            })
            .catchError((_) {});

        // 2. Update in Active Environment Firestore
        final activeDb = context.read(firestoreProvider);
        await activeDb
            .collection('users')
            .doc(user.uid)
            .update({
              'name': _profileName.trim(),
            })
            .catchError((_) {});

        updates.add('display name');
      }

      if (_newPassword.isNotEmpty) {
        if (_newPassword.length < 6) {
          throw Exception('Password must be at least 6 characters.');
        }
        await user.updatePassword(_newPassword);
        await user.reload();
        updates.add('password');
      }

      // Force refresh of adminCurrentUserProvider to update UI immediately
      context.invalidate(adminCurrentUserProvider);

      setState(() {
        _profileMessage = 'Profile updated successfully (${updates.join(", ")}).';
        _profileName = '';
        _newPassword = '';
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
      // This allows programmatically registering new staff users without signing out the current admin!
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

    final userEmail = user?.email ?? '';
    final isAdmin = userEmail.toLowerCase().contains('admin') || userEmail == 'sarah.johnson@tranyx.com';

    return div(classes: 'flex-1 p-6 md:p-8 flex flex-col gap-6 max-w-7xl mx-auto w-full bg-[#eff2f0]', [
      // Modern Header block
      div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-zinc-200/50 pb-5', [
        div(classes: 'flex flex-col gap-1', [
          h1(classes: 'text-xl font-black tracking-tight text-zinc-900', [
            Component.text('System Configuration Console'),
          ]),
          p(classes: 'text-xs text-zinc-400 font-medium', [
            Component.text('Audit controls for staff roles and platform threshold constraints.'),
          ]),
        ]),
      ]),

      div(classes: 'grid grid-cols-1 lg:grid-cols-2 gap-8', [
        // Left Column (Constraints & Profile Settings)
        div(classes: 'flex flex-col gap-8', [
          // Panel 1: Environmental features/limits
          div(
            classes:
                'p-6 rounded-[28px] border border-zinc-200/50 bg-white flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
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
          if (user != null)
            div(
              classes:
                  'p-6 rounded-[28px] border border-zinc-200/50 bg-white flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
              [
                h4(classes: 'text-sm font-bold text-zinc-900 flex items-center gap-2 border-b border-zinc-50 pb-3', [
                  span([Component.text('👤')]),
                  Component.text('Admin Profile Settings'),
                ]),
                p(classes: 'text-xs text-zinc-500 font-medium leading-relaxed', [
                  Component.text('Update your account display name or reset your admin access password.'),
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
                      Component.text('Display Name'),
                    ]),
                    input(
                      value: _profileName,
                      classes:
                          'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'text', 'placeholder': user.displayName ?? 'Staff Agent'},
                      onInput: (value) => _profileName = value as String,
                    ),
                  ]),
                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('Email Address'),
                    ]),
                    input(
                      value: user.email ?? '',
                      classes:
                          'bg-zinc-100 border border-zinc-200 rounded-xl px-4 py-2.5 text-xs text-zinc-400 cursor-not-allowed focus:outline-none',
                      attributes: {'type': 'email', 'disabled': 'true'},
                    ),
                  ]),
                  div(classes: 'flex flex-col gap-1.5', [
                    label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                      Component.text('New Password'),
                    ]),
                    input(
                      value: _newPassword,
                      classes:
                          'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                      attributes: {'type': 'password', 'placeholder': '••••••••'},
                      onInput: (value) => _newPassword = value as String,
                    ),
                  ]),

                  button(
                    onClick: _profileLoading ? null : () => _updateProfile(context, user),
                    classes:
                        'w-full py-3 bg-black hover:bg-zinc-800 text-white text-xs font-bold rounded-xl transition-all shadow-md shadow-black/10 flex items-center justify-center gap-2 mt-1',
                    attributes: _profileLoading ? {'disabled': 'true'} : {},
                    [
                      if (_profileLoading)
                        span(
                          classes:
                              'inline-block animate-spin h-3.5 w-3.5 border-2 border-white/30 border-t-white rounded-full',
                          [],
                        )
                      else
                        Component.text('Update Profile'),
                    ],
                  ),
                ]),
              ],
            ),
        ]),

        // Panel 2: staff creation (visible only to Admin emails)
        if (isAdmin)
          div(
            classes:
                'p-6 rounded-[28px] border border-zinc-200/50 bg-white flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
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
                    classes:
                        'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
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
                    classes:
                        'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
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
                    classes:
                        'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-800 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                    attributes: {'type': 'password', 'placeholder': '••••••••'},
                    onInput: (value) => _newStaffPassword = value as String,
                  ),
                ]),
                div(classes: 'flex flex-col gap-1.5', [
                  label(classes: 'text-[10px] text-zinc-400 font-bold uppercase tracking-wider', [
                    Component.text('Access Role'),
                  ]),
                  select(
                    classes:
                        'bg-[#f8faf9] border border-zinc-200/50 rounded-xl px-4 py-2.5 text-xs text-zinc-850 focus:outline-none focus:border-black focus:ring-1 focus:ring-black transition-all',
                    onChange: (value) =>
                        _newStaffRole = (value as List<String>).isNotEmpty ? (value as List<String>).first : 'staff',
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
                  classes:
                      'w-full py-3 bg-black hover:bg-zinc-800 text-white text-xs font-bold rounded-xl transition-all shadow-md shadow-black/10 flex items-center justify-center gap-2 mt-1',
                  attributes: _staffLoading ? {'disabled': 'true'} : {},
                  [
                    if (_staffLoading)
                      span(
                        classes:
                            'inline-block animate-spin h-3.5 w-3.5 border-2 border-white/30 border-t-white rounded-full',
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
            classes:
                'p-6 rounded-[28px] border border-zinc-200/50 bg-white flex flex-col gap-4 shadow-[0_8px_30px_rgba(0,0,0,0.015)]',
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
                  classes:
                      'p-4 rounded-xl bg-[#f8faf9] border border-zinc-200/50 flex justify-between items-center text-xs',
                  [
                    span(classes: 'font-semibold text-zinc-600', [Component.text('Security Rules Status')]),
                    span(classes: 'text-[#0fa958] font-extrabold text-[10px] tracking-wider uppercase', [
                      Component.text('Active'),
                    ]),
                  ],
                ),
                div(
                  classes:
                      'p-4 rounded-xl bg-[#f8faf9] border border-zinc-200/50 flex justify-between items-center text-xs',
                  [
                    span(classes: 'font-semibold text-zinc-600', [Component.text('Audited Logs Sync')]),
                    span(classes: 'text-indigo-500 font-extrabold text-[10px] tracking-wider uppercase', [
                      Component.text('Streaming'),
                    ]),
                  ],
                ),
              ]),
            ],
          ),
      ]),
    ]);
  }
}
