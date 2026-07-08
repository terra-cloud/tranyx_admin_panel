import 'package:firebase_auth/firebase_auth.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'components/sidebar.dart';
import 'core/config/firebase_environments.dart';
import 'core/providers/environment_provider.dart';
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
          return Router(
            routes: [
              ShellRoute(
                builder: (context, state, child) {
                  final envUserAsync = context.watch(activeEnvAuthUserProvider);
                  return div(classes: 'flex flex-col md:flex-row min-h-screen w-full bg-[#eff2f0]', [
                    const Sidebar(),
                    div(classes: 'flex-1 flex flex-col min-h-screen overflow-y-auto max-h-screen', [
                      const HeaderPanel(),
                      envUserAsync.when(
                        data: (envUser) {
                          if (envUser == null) {
                            return div(
                              classes: 'flex-1 flex flex-col items-center justify-center p-12 text-center',
                              [
                                div(
                                  classes:
                                      'animate-spin h-8 w-8 border-2 border-zinc-200 border-t-indigo-500 rounded-full mb-4',
                                  [],
                                ),
                                h3(classes: 'text-sm font-bold text-zinc-800', [
                                  Component.text('Synchronizing Authentication'),
                                ]),
                                p(classes: 'text-xs text-zinc-400 mt-1 max-w-xs leading-relaxed', [
                                  Component.text(
                                    'Establishing secure connection with the active database environment...',
                                  ),
                                ]),
                              ],
                            );
                          }
                          return div(classes: 'flex-1 page-transition', key: ValueKey(state.location), [child]);
                        },
                        loading: () => div(
                          classes: 'flex-1 flex flex-col items-center justify-center p-12',
                          [
                            div(
                              classes: 'animate-spin h-6 w-6 border-2 border-zinc-200 border-t-indigo-500 rounded-full',
                              [],
                            ),
                          ],
                        ),
                        error: (err, _) => div(
                          classes: 'flex-1 p-8 text-red-500 font-mono text-xs',
                          [Component.text('Auth sync failed: $err')],
                        ),
                      ),
                    ]),
                  ]);
                },
                routes: [
                  Route(path: '/', title: 'Dashboard', builder: (context, state) => const Dashboard()),
                  Route(path: '/listings', title: 'Listings', builder: (context, state) => const ListingsPage()),
                  Route(path: '/bookings', title: 'Bookings', builder: (context, state) => const BookingsPage()),
                  Route(path: '/kyc', title: 'KYC queue', builder: (context, state) => const KycPage()),
                  Route(path: '/chats', title: 'Live Support', builder: (context, state) => const ChatsPage()),
                  Route(path: '/tickets', title: 'Support Tickets', builder: (context, state) => const TicketsPage()),
                  Route(path: '/users', title: 'Users directory', builder: (context, state) => const UsersPage()),
                  Route(path: '/promos', title: 'Promotions', builder: (context, state) => const PromosPage()),
                  Route(path: '/news', title: 'News & Banners', builder: (context, state) => const NewsPage()),
                  Route(path: '/reports', title: 'Abuse reports', builder: (context, state) => const ReportsPage()),
                  Route(
                    path: '/settings',
                    title: 'Settings console',
                    builder: (context, state) => const SettingsPage(),
                  ),
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

class HeaderPanel extends StatelessComponent {
  const HeaderPanel({super.key});

  @override
  Component build(BuildContext context) {
    final currentEnv = context.watch(activeEnvironmentProvider);
    final user = context.watch(adminCurrentUserProvider).value;

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
      div(classes: 'flex items-center gap-3', [
        div(
          classes: 'bg-[#0fa958] text-white w-9 h-9 rounded-full flex items-center justify-center font-black text-sm',
          [Component.text('T')],
        ),
        span(classes: 'font-black text-sm tracking-wide text-zinc-900 uppercase', [Component.text('Tranyx')]),
      ]),

      // Center: Capsules (Overview/Env selector style)
      div(
        classes:
            'hidden lg:flex items-center gap-1 bg-white p-1 border border-zinc-200/50 rounded-full shadow-[0_2px_8px_rgba(0,0,0,0.01)]',
        [
          buildEnvCapsule('Development', Environment.development),
          buildEnvCapsule('Staging (UAT)', Environment.staging),
          buildEnvCapsule('Production', Environment.production),
        ],
      ),

      // Right: Bell + Profile avatar
      div(classes: 'flex items-center gap-4.5', [
        button(
          classes:
              'p-2 bg-white border border-zinc-200/50 rounded-full text-zinc-700 hover:text-black shadow-sm transition-all focus:outline-none',
          [Component.text('🔔')],
        ),
        div(classes: 'flex items-center gap-2.5', [
          div(
            classes:
                'w-8.5 h-8.5 rounded-full bg-zinc-200 border border-zinc-300 flex items-center justify-center text-xs font-bold text-zinc-700 overflow-hidden',
            [
              if ((user as dynamic)?.photoURL != null)
                img(src: (user as dynamic).photoURL!, classes: 'w-full h-full object-cover', alt: 'Avatar')
              else
                Component.text(
                  (user as dynamic)?.email != null ? (user as dynamic).email!.substring(0, 1).toUpperCase() : 'A',
                ),
            ],
          ),
        ]),
      ]),
    ]);
  }
}
