import 'package:firebase_auth/firebase_auth.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:web/web.dart' as web;

import 'components/global_p2p_alert_manager.dart';
import 'components/sidebar.dart';
import 'core/config/firebase_environments.dart';
import 'core/providers/environment_provider.dart';
import 'core/services/presence_service.dart';
import 'pages/dashboard.dart';
import 'pages/listings.dart';
import 'pages/bookings.dart';
import 'pages/kyc.dart';
import 'pages/chats.dart';
import 'pages/users.dart';
import 'pages/settings.dart';
import 'pages/login.dart';
import 'pages/tickets.dart';
import 'pages/promos.dart';
import 'pages/news.dart';
import 'pages/reports.dart';
import 'pages/deposits.dart';
import 'pages/withdrawals.dart';
import 'pages/subscriptions.dart';
import 'pages/disputes.dart';

/// Provider that streams the currently logged-in Admin staff member.
final adminCurrentUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(adminAuthProvider);
  return auth.userChanges();
});

// The main component of your application.
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) {
    return ProviderScope(
      child: const AppShell(),
    );
  }
}

class AppShell extends StatelessComponent {
  const AppShell({super.key});

  @override
  Component build(BuildContext context) {
    final userAsync = context.watch(adminCurrentUserProvider);

    return div(classes: 'flex min-h-screen flex-col bg-[#eff2f0] text-zinc-900', [
      userAsync.when(
        data: (user) {
          if (user == null) {
            return const LoginPage();
          }

          // Start agent real-time presence heartbeat
          final firestore = context.watch(firestoreProvider);
          final adminFirestore = context.watch(adminFirestoreProvider);
          final profile = context.watch(currentAdminProfileProvider).value;
          final role = profile?.role ?? 'staff';
          final name = (profile?.name.isNotEmpty == true)
              ? profile!.name
              : (user.displayName ?? (user.email?.split('@').first ?? 'Staff'));
          final photo = profile?.photoUrl ?? user.photoURL;

          PresenceService.startPresenceHeartbeat(
            firestore: firestore,
            adminFirestore: adminFirestore,
            agentUid: user.uid,
            agentName: name,
            email: user.email,
            role: role,
            photoUrl: photo,
          );

          return Router(
            routes: [
              ShellRoute(
                builder: (context, state, child) {
                  return div(classes: 'relative flex flex-col md:flex-row min-h-screen w-full bg-[#eff2f0]', [
                    const Sidebar(),
                    div(classes: 'flex-1 flex flex-col min-h-screen min-w-0 w-full', [
                      const HeaderPanel(),
                      div(classes: 'flex-1 page-transition w-full min-w-0', key: ValueKey(state.location), [child]),
                    ]),

                    // Global Real-Time P2P Alert & Sound Interrupt Manager (Topmost DOM layer)
                    const GlobalP2PAlertManager(),
                  ]);
                },
                routes: [
                  Route(path: '/', builder: (context, state) => const Dashboard()),
                  Route(path: '/listings', builder: (context, state) => const ListingsPage()),
                  Route(path: '/bookings', builder: (context, state) => const BookingsPage()),
                  Route(path: '/kyc', builder: (context, state) => const KycPage()),
                  Route(path: '/chats', builder: (context, state) => const ChatsPage()),
                  Route(path: '/tickets', builder: (context, state) => const TicketsPage()),
                  Route(path: '/deposits', builder: (context, state) => const DepositsPage()),
                  Route(path: '/subscriptions', builder: (context, state) => const SubscriptionsPage()),
                  Route(path: '/withdrawals', builder: (context, state) => const WithdrawalsPage()),
                  Route(path: '/promos', builder: (context, state) => const AdminGuard(child: PromosPage())),
                  Route(path: '/news', builder: (context, state) => const AdminGuard(child: NewsPage())),
                  Route(path: '/reports', builder: (context, state) => const ReportsPage()),
                  Route(path: '/disputes', builder: (context, state) => const AdminGuard(child: DisputesPage())),
                  Route(path: '/users', builder: (context, state) => const UsersPage()),
                  Route(path: '/settings', builder: (context, state) => const AdminGuard(child: SettingsPage())),
                ],
              ),
            ],
          );
        },
        error: (error, stack) => div(
          classes: 'w-full min-h-screen flex justify-center items-center p-8 text-red-500 font-bold',
          [Component.text('Error loading portal: $error')],
        ),
        loading: () => div(classes: 'w-full min-h-screen flex justify-center items-center', [
          div(classes: 'animate-spin h-8 w-8 border-4 border-zinc-200 border-t-indigo-500 rounded-full', []),
        ]),
      ),
    ]);
  }
}

class AdminGuard extends StatelessComponent {
  final Component child;
  const AdminGuard({required this.child, super.key});

  @override
  Component build(BuildContext context) {
    final profile = context.watch(currentAdminProfileProvider).value;
    final user = context.watch(adminCurrentUserProvider).value;
    final email = (profile?.email.isNotEmpty == true ? profile!.email : user?.email) ?? '';
    final role = profile?.role.toLowerCase() ?? '';
    final isAdmin = role.contains('admin') || email == 'admin@tranyx.app' || email == 'admin@tranyx.com';

    if (!isAdmin) {
      return div(classes: 'flex-1 p-8 flex flex-col items-center justify-center text-center gap-4 min-h-[60vh]', [
        div(classes: 'w-16 h-16 rounded-3xl bg-amber-50 border border-amber-200 flex items-center justify-center text-2xl shadow-sm', [
          Component.text('🔒'),
        ]),
        h2(classes: 'text-lg font-black text-zinc-900', [Component.text('Administrator Access Required')]),
        p(classes: 'text-xs text-zinc-500 max-w-sm font-medium leading-relaxed', [
          Component.text('This console section contains platform configuration, fee settings, and sensitive controls restricted to administrators.'),
        ]),
        button(
          onClick: () => Router.of(context).push('/'),
          classes: 'px-5 py-2.5 bg-black text-white rounded-xl text-xs font-bold transition-all hover:bg-zinc-800 cursor-pointer border-0 outline-none mt-2',
          [Component.text('Return to Dashboard')],
        ),
      ]);
    }
    return child;
  }
}

class HeaderPanel extends StatefulComponent {
  const HeaderPanel({super.key});

  @override
  State<HeaderPanel> createState() => _HeaderPanelState();
}

class _HeaderPanelState extends State<HeaderPanel> {
  bool _showAuthModal = false;
  String _authPassword = '';
  bool _isAuthenticating = false;
  String? _authError;

  @override
  Component build(BuildContext context) {
    final currentEnv = context.watch(activeEnvironmentProvider);
    final envUser = context.watch(activeEnvAuthUserProvider).value;
    final adminUser = context.watch(adminCurrentUserProvider).value;
    final profile = context.watch(currentAdminProfileProvider).value ??
        const AdminStaffProfileModel(
          uid: '',
          name: 'Staff Member',
          displayName: 'Staff Member',
          email: 'agent@tranyx.com',
          role: 'staff',
        );
    final soundEnabled = context.watch(globalAlertSoundEnabledProvider);
    final onlineAgents = context.watch(onlineAgentsStreamProvider).value ?? [];
    final isEnvAuthPending = envUser == null && adminUser != null;

    final userEmail = profile.email.isNotEmpty ? profile.email : (adminUser?.email ?? '');
    final role = profile.role.toLowerCase();
    final isAdmin = role.contains('admin') || role.contains('superadmin') || userEmail == 'admin@tranyx.app' || userEmail == 'admin@tranyx.com';

    // Staff and Agents are locked to Production only
    if (!isAdmin && currentEnv != Environment.production) {
      Future.microtask(() {
        context.read(activeEnvironmentProvider.notifier).state = Environment.production;
      });
    }

    Component buildEnvCapsule(String label, Environment value) {
      final isActive = currentEnv == value;
      return button(
        onClick: () {
          context.read(activeEnvironmentProvider.notifier).state = value;
        },
        classes:
            'px-3 sm:px-5 py-1 text-xs font-bold transition-all duration-200 '
            '${isActive ? 'bg-black text-white rounded-full' : 'text-zinc-500 hover:text-zinc-900'}',
        [Component.text(label)],
      );
    }

    return div(
      classes:
          'px-4 sm:px-6 md:px-8 py-3 sm:py-4 flex items-center justify-between border-b border-zinc-200/50 bg-[#eff2f0] w-full min-w-0 gap-3 relative',
      [
        // Left: Logo and name (Hidden on small mobile since mobile header is above)
        div(classes: 'hidden sm:flex items-center gap-2.5 flex-shrink-0', [
          img(
            src: '/images/logo.png',
            classes: 'w-7 h-7 object-contain flex-shrink-0',
            alt: 'Tranyx Logo',
          ),
          span(classes: 'font-black text-sm tracking-wide text-zinc-900 uppercase', [Component.text('Tranyx')]),
        ]),

        // Center: Capsules (Env selector if Admin + Online Presence Counter + Env Auth status)
        div(classes: 'flex items-center gap-2 sm:gap-3 flex-wrap min-w-0', [
          // Environment Selector: ONLY visible to Administrators
          if (isAdmin)
            div(
              classes:
                  'flex items-center gap-1 bg-white p-1 border border-zinc-200/50 rounded-full shadow-[0_2px_8px_rgba(0,0,0,0.01)] text-xs overflow-x-auto max-w-full',
              [
                buildEnvCapsule('Dev', Environment.development),
                buildEnvCapsule('Staging', Environment.staging),
                buildEnvCapsule('Prod', Environment.production),
              ],
            ),

          // Environment Authentication Status Capsule
          if (isEnvAuthPending)
            button(
              onClick: () {
                setState(() {
                  _showAuthModal = true;
                  _authError = null;
                  _authPassword = '';
                });
              },
              classes:
                  'flex items-center gap-1.5 px-3 py-1.5 bg-amber-500 hover:bg-amber-600 text-white rounded-full shadow-sm text-[11px] font-bold transition-all border-0 cursor-pointer animate-pulse flex-shrink-0',
              [
                span([Component.text('🔑')]),
                Component.text(isAdmin ? 'Connect ${currentEnv.name.toUpperCase()}' : 'Connect Live System'),
              ],
            )
          else if (isAdmin)
            div(
              classes:
                  'hidden lg:flex items-center gap-1.5 px-2.5 py-1 bg-emerald-50 border border-emerald-200/70 rounded-full text-[10px] font-bold text-emerald-700 flex-shrink-0',
              [
                span(classes: 'w-1.5 h-1.5 rounded-full bg-emerald-500', []),
                Component.text('${currentEnv.name.toUpperCase()} Connected'),
              ],
            ),

          // Live Online Agents Count Capsule: ONLY visible to Administrators
          if (isAdmin)
            div(
              classes:
                  'hidden md:flex items-center gap-2 px-3 py-1.5 bg-white border border-zinc-200/50 rounded-full shadow-[0_2px_8px_rgba(0,0,0,0.01)] text-[11px] font-bold text-zinc-700 flex-shrink-0',
              [
                span(classes: 'w-2 h-2 rounded-full bg-[#0fa958] animate-pulse', []),
                Component.text('${onlineAgents.length} ${onlineAgents.length == 1 ? "Agent" : "Agents"} Online'),
              ],
            ),
        ]),

        // Right: Sound chime toggle + Logged Staff / Admin Profile Pill
        div(classes: 'flex items-center gap-2 sm:gap-3.5 flex-shrink-0', [
          button(
            onClick: () {
              final nextVal = !soundEnabled;
              context.read(globalAlertSoundEnabledProvider.notifier).state = nextVal;
              try {
                web.window.localStorage.setItem('tranyx_global_sound_enabled', nextVal.toString());
              } catch (_) {}
            },
            classes:
                'p-2 bg-white border border-zinc-200/50 rounded-full text-zinc-700 hover:text-black shadow-sm transition-all focus:outline-none cursor-pointer flex items-center justify-center text-sm',
            attributes: {
              'title': soundEnabled ? 'Audio Alerts: Enabled (Click to Mute)' : 'Audio Alerts: Muted (Click to Enable)'
            },
            [Component.text(soundEnabled ? '🔔' : '🔕')],
          ),

          // Logged-in Staff Profile Pill
          a(
            href: '/settings',
            attributes: {'title': 'View Profile Settings'},
            classes:
                'flex items-center gap-2 sm:gap-3 bg-white p-1 sm:pl-2 sm:pr-3.5 sm:py-1.5 rounded-full border border-zinc-200/60 shadow-[0_2px_8px_rgba(0,0,0,0.02)] hover:border-zinc-300 transition-all no-underline cursor-pointer',
            [
              div(classes: 'relative', [
                div(
                  classes:
                      'w-8 h-8 rounded-full bg-indigo-50 border border-indigo-100 flex items-center justify-center text-xs font-bold text-indigo-700 overflow-hidden shrink-0 relative',
                  attributes: {'style': 'width: 32px; height: 32px; min-width: 32px; min-height: 32px; max-width: 32px; max-height: 32px;'},
                  [
                    if (profile.photoUrl != null && profile.photoUrl!.isNotEmpty)
                      img(
                        src: profile.photoUrl!,
                        classes: 'w-full h-full object-cover block',
                        attributes: {'style': 'width: 32px; height: 32px; object-fit: cover;'},
                        alt: 'Avatar',
                      )
                    else
                      Component.text(profile.initials),
                  ],
                ),
                // Real-time online presence dot
                span(classes: 'absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full bg-[#0fa958] border-2 border-white', []),
              ]),
              div(classes: 'hidden sm:flex flex-col min-w-0 text-left', [
                div(classes: 'flex items-center gap-1.5', [
                  span(classes: 'text-xs font-black text-zinc-900 leading-none truncate max-w-[130px]', [
                    Component.text(profile.name),
                  ]),
                  span(
                    classes:
                        'text-[8px] font-extrabold uppercase px-1.5 py-0.2 rounded-md '
                        '${profile.role.toLowerCase().contains("admin") ? "bg-black text-white" : "bg-indigo-50 text-indigo-700 border border-indigo-200/60"}',
                    [
                      Component.text(profile.roleDisplay),
                    ],
                  ),
                ]),
                span(classes: 'text-[10px] text-zinc-400 font-semibold leading-tight truncate max-w-[140px]', [
                  Component.text(profile.email),
                ]),
              ]),
            ],
          ),
        ]),

        // Interactive Environment Connection Modal
        if (_showAuthModal)
          div(
            classes: 'fixed inset-0 bg-black/60 backdrop-blur-sm z-[9999] flex items-center justify-center p-4',
            [
              div(
                classes:
                    'bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl flex flex-col gap-4 border border-zinc-200 text-left animate-in fade-in zoom-in-95',
                [
                  div(classes: 'flex items-center justify-between border-b border-zinc-100 pb-3', [
                    div(classes: 'flex items-center gap-2', [
                      span(classes: 'text-xl', [Component.text('🔐')]),
                      h3(classes: 'text-sm font-black text-zinc-900', [Component.text('Connect to ${currentEnv.name.toUpperCase()}')]),
                    ]),
                    button(
                      onClick: () => setState(() => _showAuthModal = false),
                      classes: 'text-zinc-400 hover:text-zinc-700 text-sm font-bold border-0 bg-transparent cursor-pointer',
                      [Component.text('✕')],
                    ),
                  ]),
                  p(classes: 'text-xs text-zinc-600 leading-relaxed m-0', [
                    Component.text('Enter your staff account password to link your session with ${currentEnv.name.toUpperCase()} (Firebase Project: ${FirebaseEnv.optionsFor(currentEnv).projectId}):'),
                  ]),
                  div(classes: 'flex flex-col gap-2', [
                    div(classes: 'flex justify-between items-center text-[11px]', [
                      span(classes: 'font-bold text-zinc-700', [Component.text('Staff Email:')]),
                      span(classes: 'font-semibold text-zinc-500', [Component.text(adminUser?.email ?? 'Staff')]),
                    ]),
                    input(
                      value: _authPassword,
                      classes: 'w-full px-3 py-2 text-xs border border-zinc-300 rounded-xl focus:outline-none focus:border-black transition-all box-border',
                      attributes: {'type': 'password', 'placeholder': 'Enter your staff password'},
                      onInput: (val) => setState(() => _authPassword = val.toString()),
                    ),
                    if (_authError != null)
                      p(classes: 'text-[11px] text-red-500 font-bold m-0', [Component.text(_authError!)]),
                  ]),
                  div(classes: 'flex items-center justify-end gap-2 pt-2 border-t border-zinc-100', [
                    button(
                      onClick: () => setState(() => _showAuthModal = false),
                      classes: 'px-4 py-2 text-xs font-bold text-zinc-600 hover:bg-zinc-100 rounded-xl border-0 bg-transparent cursor-pointer',
                      [Component.text('Cancel')],
                    ),
                    button(
                      onClick: () async {
                        if (_authPassword.isEmpty) {
                          setState(() => _authError = 'Please enter your password.');
                          return;
                        }
                        setState(() {
                          _isAuthenticating = true;
                          _authError = null;
                        });
                        try {
                          final app = await context.read(firebaseAppProvider.future);
                          final user = await syncEnvAuth(app, adminUser, explicitPassword: _authPassword);
                          if (user != null) {
                            setState(() {
                              _isAuthenticating = false;
                              _showAuthModal = false;
                            });
                            context.invalidate(activeEnvAuthUserProvider);
                          } else {
                            setState(() {
                              _isAuthenticating = false;
                              _authError = 'Authentication failed. Please verify your password.';
                            });
                          }
                        } catch (e) {
                          setState(() {
                            _isAuthenticating = false;
                            _authError = e.toString();
                          });
                        }
                      },
                      classes:
                          'px-5 py-2 text-xs font-bold bg-black text-white rounded-xl border-0 cursor-pointer shadow-md hover:bg-zinc-800 transition-all flex items-center gap-1.5 ${_isAuthenticating ? "opacity-50 pointer-events-none" : ""}',
                      [
                        if (_isAuthenticating)
                          div(classes: 'animate-spin h-3 w-3 border-2 border-white/30 border-t-white rounded-full', []),
                        Component.text(_isAuthenticating ? 'Connecting...' : 'Connect Environment'),
                      ],
                    ),
                  ]),
                ],
              ),
            ],
          ),
      ],
    );
  }
}
