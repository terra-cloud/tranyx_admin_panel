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
                    div(classes: 'flex-1 flex flex-col min-h-screen overflow-y-auto max-h-screen', [
                      const HeaderPanel(),
                      div(classes: 'flex-1 page-transition', key: ValueKey(state.location), [child]),
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
                  Route(path: '/withdrawals', builder: (context, state) => const WithdrawalsPage()),
                  Route(path: '/promos', builder: (context, state) => const AdminGuard(child: PromosPage())),
                  Route(path: '/news', builder: (context, state) => const AdminGuard(child: NewsPage())),
                  Route(path: '/reports', builder: (context, state) => const ReportsPage()),
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
    final isAdmin = email.toLowerCase().contains('admin') || email == 'admin@tranyx.app' || role.contains('admin');

    if (!isAdmin) {
      return div(classes: 'flex-1 p-8 flex flex-col items-center justify-center text-center gap-4 min-h-[60vh]', [
        div(classes: 'w-16 h-16 rounded-3xl bg-amber-50 border border-amber-200 flex items-center justify-center text-2xl shadow-sm', [
          Component.text('🔒'),
        ]),
        h2(classes: 'text-lg font-black text-zinc-900', [Component.text('Administrator Access Required')]),
        p(classes: 'text-xs text-zinc-500 max-w-sm font-medium leading-relaxed', [
          Component.text('This console section contains platform configuration, fee settings, and sensitive controls restricted to administrators.'),
        ]),
        a(
          href: '/',
          classes: 'px-5 py-2.5 bg-black text-white text-xs font-extrabold rounded-full shadow-md shadow-black/10 hover:bg-zinc-800 transition-all no-underline',
          [Component.text('Return to Dashboard')],
        ),
      ]);
    }
    return child;
  }
}

class HeaderPanel extends StatelessComponent {
  const HeaderPanel({super.key});

  @override
  Component build(BuildContext context) {
    final currentEnv = context.watch(activeEnvironmentProvider);
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

    Component buildEnvCapsule(String label, Environment value) {
      final isActive = currentEnv == value;
      return button(
        onClick: () {
          context.read(activeEnvironmentProvider.notifier).state = value;
        },
        classes:
            'px-5 py-1.5 text-xs font-bold transition-all duration-200 '
            '${isActive ? 'bg-black text-white rounded-full' : 'text-zinc-500 hover:text-zinc-900'}',
        [Component.text(label)],
      );
    }

    return div(classes: 'px-8 py-5 flex items-center justify-between border-b border-zinc-200/50 bg-[#eff2f0]', [
      // Left: Logo and name
      div(classes: 'flex items-center gap-2.5', [
        img(
          src: '/images/logo.png',
          classes: 'w-7 h-7 object-contain flex-shrink-0',
          alt: 'Tranyx Logo',
        ),
        span(classes: 'font-black text-sm tracking-wide text-zinc-900 uppercase', [Component.text('Tranyx')]),
      ]),

      // Center: Capsules (Overview/Env selector style + Online Presence Counter)
      div(classes: 'hidden lg:flex items-center gap-3', [
        div(
          classes:
              'flex items-center gap-1 bg-white p-1 border border-zinc-200/50 rounded-full shadow-[0_2px_8px_rgba(0,0,0,0.01)]',
          [
            buildEnvCapsule('Development', Environment.development),
            buildEnvCapsule('Staging (UAT)', Environment.staging),
            buildEnvCapsule('Production', Environment.production),
          ],
        ),

        // Live Online Agents Count Capsule
        div(
          classes:
              'flex items-center gap-2 px-3 py-1.5 bg-white border border-zinc-200/50 rounded-full shadow-[0_2px_8px_rgba(0,0,0,0.01)] text-[11px] font-bold text-zinc-700',
          [
            span(classes: 'w-2 h-2 rounded-full bg-[#0fa958] animate-pulse', []),
            Component.text('${onlineAgents.length} ${onlineAgents.length == 1 ? "Agent" : "Agents"} Online'),
          ],
        ),
      ]),

      // Right: Sound chime toggle + Logged Staff / Admin Profile Pill
      div(classes: 'flex items-center gap-3.5', [
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
              'flex items-center gap-3 bg-white pl-2 pr-3.5 py-1.5 rounded-full border border-zinc-200/60 shadow-[0_2px_8px_rgba(0,0,0,0.02)] hover:border-zinc-300 transition-all no-underline cursor-pointer',
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
    ]);
  }
}
