import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'package:web/web.dart' as web;
import '../app.dart';
import '../core/providers/environment_provider.dart';
import '../core/services/presence_service.dart';
import '../pages/kyc.dart';
import '../pages/tickets.dart';
import '../pages/reports.dart';
import '../pages/deposits.dart';
import '../pages/withdrawals.dart';

class Sidebar extends StatefulComponent {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  bool _isMobileMenuOpen = false;
  bool _isCollapsed = false; // Expanding/collapsing state

  void _toggleMobileMenu() {
    setState(() {
      _isMobileMenuOpen = !_isMobileMenuOpen;
    });
  }

  void _toggleCollapse() {
    setState(() {
      _isCollapsed = !_isCollapsed;
    });
  }

  @override
  Component build(BuildContext context) {
    final profile = context.watch(currentAdminProfileProvider).value ??
        const AdminStaffProfileModel(
          uid: '',
          name: 'Staff Member',
          displayName: 'Staff Member',
          email: 'agent@tranyx.com',
          role: 'staff',
        );
    final isAdmin = profile.role.toLowerCase().contains('admin') ||
        profile.email == 'admin@tranyx.app' ||
        profile.email == 'admin@tranyx.com';
    final currentPath = Router.of(context).matchList.uri.path;

    final pendingKycCount = context
        .watch(kycQueueStreamProvider)
        .maybeWhen(
          data: (list) => list.where((k) => k.status.toLowerCase() == 'pending').length,
          orElse: () => 0,
        );

    final pendingDepositsCount = context
        .watch(depositRequestsStreamProvider)
        .maybeWhen(
          data: (list) => list.where((d) => d.status == 'PENDING_VERIFICATION' || d.status == 'PENDING_AGENT').length,
          orElse: () => 0,
        );

    final pendingWithdrawalsCount = context
        .watch(withdrawalRequestsStreamProvider)
        .maybeWhen(
          data: (list) => list.where((w) => w.status == 'WAITING_FOR_AGENT' || w.status == 'AWAITING_AGENT_PAYMENT').length,
          orElse: () => 0,
        );

    final openTicketsCount = context
        .watch(ticketsStreamProvider)
        .maybeWhen(
          data: (list) => list.where((t) {
            if (t.isResolved) return false;
            final isUnassigned = t.assignedAgentId == null || t.assignedAgentId!.isEmpty;
            final isPendingOrOpen = t.isPending || t.status.toLowerCase() == 'open' || t.status.toLowerCase() == 'pending';
            return isUnassigned || isPendingOrOpen;
          }).length,
          orElse: () => 0,
        );

    final pendingReportsCount = context
        .watch(combinedReportedListingsProvider)
        .maybeWhen(
          data: (list) => list.length,
          orElse: () => 0,
        );

    // Helper to build a menu link item
    Component buildMenuItem(String label, String path, String icon, {int? badgeCount}) {
      final isActive = currentPath == path || (path != '/' && currentPath.startsWith(path));
      return li(classes: 'w-full', [
        a(
          href: 'javascript:void(0);',
          attributes: {'title': label},
          onClick: () {
            Router.of(context).push(path);
          },
          classes:
              'flex items-center gap-3.5 px-4 py-3 rounded-2xl text-xs font-bold transition-all duration-300 '
              '${isActive ? "bg-black text-white shadow-md shadow-black/10 scale-[1.02]" : "text-zinc-500 hover:text-zinc-900 hover:bg-zinc-100/50"} '
              '${_isCollapsed ? "justify-center px-0 w-11 h-11 mx-auto relative" : "w-full"}',
          [
            span(classes: 'text-base flex-shrink-0 flex items-center justify-center w-5 h-5 relative', [
              if (icon.startsWith('/'))
                img(
                  src: icon,
                  classes:
                      'w-4.5 h-4.5 transition-all duration-200 '
                      '${isActive ? "brightness-0 invert drop-shadow-[0_2px_4px_rgba(255,255,255,0.3)]" : "opacity-40 grayscale group-hover:opacity-100 group-hover:grayscale-0"}',
                  alt: label,
                )
              else
                Component.text(icon),
              if (_isCollapsed && badgeCount != null && badgeCount > 0)
                span(
                  classes:
                      'absolute -top-1.5 -right-1.5 min-w-[14px] h-[14px] px-1 bg-red-500 text-white rounded-full text-[8px] font-black flex items-center justify-center border border-white animate-pulse',
                  [Component.text(badgeCount > 99 ? '99+' : badgeCount.toString())],
                ),
            ]),
            if (!_isCollapsed) ...[
              span(classes: 'flex-1 text-left whitespace-nowrap', [Component.text(label)]),
              if (badgeCount != null && badgeCount > 0)
                span(
                  classes:
                      'px-2 py-0.5 rounded-full text-[10px] font-extrabold '
                      '${isActive ? "bg-white/20 text-white" : "bg-red-50 text-red-600 border border-red-200/60"}',
                  [Component.text(badgeCount > 99 ? '99+' : badgeCount.toString())],
                ),
            ],
          ],
        ),
      ]);
    }

    // Helper for mobile menu items
    Component buildMobileMenuItem(String label, String path, String icon, {int? badgeCount}) {
      final isActive = currentPath == path || (path != '/' && currentPath.startsWith(path));
      return li(classes: 'w-full', [
        a(
          href: 'javascript:void(0);',
          onClick: () {
            _toggleMobileMenu();
            Router.of(context).push(path);
          },
          classes:
              'flex items-center justify-between px-4 py-3 rounded-xl text-xs font-bold transition-all duration-200 '
              '${isActive ? "bg-black text-white shadow-sm" : "text-zinc-600 hover:text-zinc-900 hover:bg-zinc-100"}',
          [
            div(classes: 'flex items-center gap-3', [
              span(classes: 'text-base flex-shrink-0 flex items-center justify-center w-5 h-5', [
                if (icon.startsWith('/'))
                  img(
                    src: icon,
                    classes: 'w-4 h-4 ${isActive ? "brightness-0 invert" : "opacity-50"}',
                    alt: label,
                  )
                else
                  Component.text(icon),
              ]),
              span([Component.text(label)]),
            ]),
            if (badgeCount != null && badgeCount > 0)
              span(
                classes:
                    'px-2 py-0.5 rounded-full text-[10px] font-extrabold '
                    '${isActive ? "bg-white/20 text-white" : "bg-red-50 text-red-600 border border-red-200/60"}',
                [Component.text(badgeCount > 99 ? '99+' : badgeCount.toString())],
              ),
          ],
        ),
      ]);
    }

    return div(classes: 'relative z-50 flex-shrink-0', [
      // Desktop Sidebar
      aside(
        classes:
            'hidden md:flex flex-col justify-between h-screen bg-white border-r border-zinc-150/80 p-5 sticky top-0 transition-all duration-300 select-none shadow-[2px_0_12px_rgba(0,0,0,0.015)] '
            '${_isCollapsed ? "w-24 items-center" : "w-64"}',
        [
          // Top: App branding + navigation list
          div(classes: 'flex flex-col gap-6 w-full', [
            // Logo & Title
            div(classes: 'flex items-center gap-3 px-1', [
              img(
                src: '/images/logo.png',
                classes: 'w-8 h-8 object-contain flex-shrink-0',
                alt: 'Tranyx Admin Logo',
              ),
              if (!_isCollapsed)
                div(classes: 'flex flex-col', [
                  h1(classes: 'text-sm font-black tracking-tight text-zinc-900 leading-none', [Component.text('TRANYX')]),
                  span(classes: 'text-[9px] font-extrabold tracking-widest text-[#0fa958] uppercase mt-0.5', [
                    Component.text('Admin Portal'),
                  ]),
                ]),
            ]),

            // Main Nav Items (Grouped)
            nav(classes: 'w-full overflow-y-auto max-h-[calc(100vh-230px)] no-scrollbar pr-0.5', [
              ul(classes: 'flex flex-col gap-1.5 list-none p-0 m-0 w-full', [
                // SECTION: Operations & Core
                if (!_isCollapsed)
                  li(classes: 'px-3 pt-2 pb-1 text-[9px] font-black tracking-wider text-zinc-400 uppercase', [
                    Component.text('Operations'),
                  ]),
                buildMenuItem('Dashboard', '/', '/images/icon_dashboard.png'),
                buildMenuItem('P2P Deposits', '/deposits', '💳', badgeCount: pendingDepositsCount),
                buildMenuItem('P2P Cashouts', '/withdrawals', '💸', badgeCount: pendingWithdrawalsCount),
                buildMenuItem('Listings', '/listings', '/images/icon_listings.png'),
                buildMenuItem('Bookings', '/bookings', '/images/icon_bookings.png'),
                buildMenuItem('KYC Verification', '/kyc', '/images/icon_kyc.png', badgeCount: pendingKycCount),

                // SECTION: Support & Assistance
                if (!_isCollapsed)
                  li(classes: 'px-3 pt-3 pb-1 text-[9px] font-black tracking-wider text-zinc-400 uppercase', [
                    Component.text('Support & CRM'),
                  ]),
                buildMenuItem('Live Support', '/chats', '/images/icon_chats.png'),
                buildMenuItem('Support Tickets', '/tickets', '/images/icon_tickets.png', badgeCount: openTicketsCount),
                buildMenuItem('User Accounts', '/users', '/images/icon_users.png'),

                // SECTION: Growth & Governance
                if (isAdmin) ...[
                  if (!_isCollapsed)
                    li(classes: 'px-3 pt-3 pb-1 text-[9px] font-black tracking-wider text-zinc-400 uppercase', [
                      Component.text('Growth & System'),
                    ]),
                  buildMenuItem('Promotions', '/promos', '/images/icon_promos.png'),
                  buildMenuItem('News & Banners', '/news', '📰'),
                  buildMenuItem('Abuse Reports', '/reports', '🚩', badgeCount: pendingReportsCount),
                  buildMenuItem('System Console', '/settings', '/images/icon_settings.png'),
                ] else ...[
                  if (!_isCollapsed)
                    li(classes: 'px-3 pt-3 pb-1 text-[9px] font-black tracking-wider text-zinc-400 uppercase', [
                      Component.text('Compliance'),
                    ]),
                  buildMenuItem('Abuse Reports', '/reports', '🚩', badgeCount: pendingReportsCount),
                ],
              ]),
            ]),
          ]),

          // Bottom Area: Staff user info + Log out + Toggle Collapse
          div(classes: 'w-full flex flex-col gap-3 pt-4 border-t border-zinc-150/60', [
            // User Avatar and info
            if (_isCollapsed)
              div(
                classes:
                    'w-8 h-8 mx-auto rounded-full bg-indigo-50 border border-indigo-100 flex items-center justify-center font-bold text-xs text-indigo-700 flex-shrink-0 overflow-hidden relative',
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
              )
            else
              div(classes: 'px-2 flex items-center gap-3 w-full min-w-0', [
                div(
                  classes:
                      'w-8 h-8 rounded-full bg-indigo-50 border border-indigo-100 flex items-center justify-center font-bold text-xs text-indigo-700 flex-shrink-0 overflow-hidden relative',
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
                div(classes: 'flex flex-col min-w-0 flex-1', [
                  div(classes: 'flex items-center gap-1.5', [
                    span(classes: 'text-[11px] font-black text-zinc-900 truncate', [
                      Component.text(profile.name),
                    ]),
                    span(
                      classes:
                          'text-[8px] font-extrabold uppercase px-1 rounded '
                          '${profile.role.toLowerCase().contains("admin") ? "bg-black text-white" : "bg-indigo-50 text-indigo-700 border border-indigo-200/50"}',
                      [
                        Component.text(profile.roleDisplay),
                      ],
                    ),
                  ]),
                  span(classes: 'text-[9px] text-zinc-400 font-semibold truncate', [
                    Component.text(profile.email),
                  ]),
                ]),
              ]),
            
            // Log out Button
            button(
              onClick: () async {
                try {
                  final currentUser = context.read(adminCurrentUserProvider).value;
                  if (currentUser != null) {
                    final firestore = context.read(firestoreProvider);
                    await PresenceService.markOffline(firestore: firestore, agentUid: currentUser.uid);
                  }
                  web.window.localStorage.removeItem('tranyx_staff_email');
                  web.window.localStorage.removeItem('tranyx_staff_password');
                } catch (_) {}
                await context.read(adminAuthProvider).signOut();
              },
              attributes: {'title': 'Log Out'},
              classes:
                  'flex items-center gap-3.5 px-4 py-3 rounded-2xl text-xs font-bold text-zinc-500 hover:text-red-500 hover:bg-red-50 transition-all duration-300 '
                  '${_isCollapsed ? "justify-center px-0 w-11 h-11 mx-auto" : "w-full border border-zinc-200/40 hover:border-red-100/50 shadow-sm bg-[#fafbfa]"}',
              [
                span(classes: 'text-base flex-shrink-0', [Component.text('🚪')]),
                if (!_isCollapsed) span([Component.text('LOG OUT')]),
              ],
            ),

            // Collapse Toggle Button
            button(
              onClick: _toggleCollapse,
              attributes: {'title': _isCollapsed ? 'Expand menu' : 'Collapse menu'},
              classes:
                  'flex items-center gap-3.5 px-4 py-2.5 rounded-2xl text-[10px] font-extrabold tracking-wide uppercase text-zinc-400 hover:text-zinc-800 hover:bg-zinc-50 transition-all duration-200 '
                  '${_isCollapsed ? "justify-center px-0 w-11 h-9 mx-auto" : "w-full justify-between"}',
              [
                if (!_isCollapsed) ...[
                  span([Component.text('Collapse Menu')]),
                  span(classes: 'text-xs', [Component.text('◀')]),
                ] else ...[
                  span(classes: 'text-xs', [Component.text('▶')]),
                ],
              ],
            ),
          ]),
        ],
      ),

      // Mobile Navbar Header (Matching theme color scheme)
      header(
        classes:
            'flex md:hidden items-center justify-between px-6 py-4 bg-white border-b border-zinc-200 sticky top-0 z-50 shadow-sm',
        [
          div(classes: 'flex items-center gap-2.5', [
            img(
              src: '/images/logo.png',
              alt: 'Tranyx Logo',
              classes: 'w-8 h-8 object-contain flex-shrink-0 drop-shadow-sm',
            ),
            h2(classes: 'text-xs font-black tracking-wider text-zinc-900 uppercase', [Component.text('Tranyx Admin')]),
          ]),
          button(
            onClick: _toggleMobileMenu,
            classes: 'p-1.5 text-zinc-500 hover:text-zinc-900 focus:outline-none text-lg',
            [Component.text(_isMobileMenuOpen ? '✕' : '☰')],
          ),
        ],
      ),

      // Mobile Menu drawer overlay
      if (_isMobileMenuOpen)
        div(
          classes:
              'md:hidden fixed inset-x-0 top-[53px] bg-white border-b border-zinc-200 z-40 p-5 flex flex-col gap-5 shadow-2xl transition-all duration-300',
          [
            ul(classes: 'flex flex-col gap-2.5 list-none p-0 m-0', [
              buildMobileMenuItem('Dashboard', '/', '/images/icon_dashboard.png'),
              buildMobileMenuItem('P2P Deposits', '/deposits', '💳', badgeCount: pendingDepositsCount),
              buildMobileMenuItem('P2P Cashouts', '/withdrawals', '💸', badgeCount: pendingWithdrawalsCount),
              buildMobileMenuItem('Listings', '/listings', '/images/icon_listings.png'),
              buildMobileMenuItem('Bookings', '/bookings', '/images/icon_bookings.png'),
              buildMobileMenuItem('KYC Verification', '/kyc', '/images/icon_kyc.png', badgeCount: pendingKycCount),
              buildMobileMenuItem('Live Support', '/chats', '/images/icon_chats.png'),
              buildMobileMenuItem(
                'Support Tickets',
                '/tickets',
                '/images/icon_tickets.png',
                badgeCount: openTicketsCount,
              ),
              buildMobileMenuItem('User Accounts', '/users', '/images/icon_users.png'),
              buildMobileMenuItem('Abuse Reports', '/reports', '🚩', badgeCount: pendingReportsCount),
              if (isAdmin) ...[
                buildMobileMenuItem('Promotions', '/promos', '/images/icon_promos.png'),
                buildMobileMenuItem('News & Banners', '/news', '📰'),
                buildMobileMenuItem('System Console', '/settings', '/images/icon_settings.png'),
              ],
            ]),
            div(classes: 'border-t border-zinc-200 pt-4 flex justify-between items-center', [
              div(classes: 'flex items-center gap-2.5 min-w-0 pr-2', [
                div(
                  classes:
                      'w-8 h-8 rounded-full bg-indigo-50 border border-indigo-100 flex items-center justify-center font-bold text-xs text-indigo-700 flex-shrink-0 overflow-hidden relative',
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
                div(classes: 'flex flex-col min-w-0', [
                  div(classes: 'flex items-center gap-1.5', [
                    span(classes: 'text-xs font-black text-zinc-900 truncate', [
                      Component.text(profile.name),
                    ]),
                    span(
                      classes:
                          'text-[8px] font-extrabold uppercase px-1 rounded '
                          '${profile.role.toLowerCase().contains("admin") ? "bg-black text-white" : "bg-indigo-50 text-indigo-700 border border-indigo-200/50"}',
                      [
                        Component.text(profile.roleDisplay),
                      ],
                    ),
                  ]),
                  span(classes: 'text-[9px] text-zinc-400 font-semibold truncate', [
                    Component.text(profile.email),
                  ]),
                ]),
              ]),
              button(
                onClick: () async {
                  try {
                    final currentUser = context.read(adminCurrentUserProvider).value;
                    if (currentUser != null) {
                      final firestore = context.read(firestoreProvider);
                      await PresenceService.markOffline(firestore: firestore, agentUid: currentUser.uid);
                    }
                    web.window.localStorage.removeItem('tranyx_staff_email');
                    web.window.localStorage.removeItem('tranyx_staff_password');
                  } catch (_) {}
                  await context.read(adminAuthProvider).signOut();
                },
                classes:
                    'px-4 py-2 bg-zinc-100 hover:bg-zinc-200 text-zinc-700 hover:text-black rounded-xl text-[9px] font-bold border border-zinc-200 transition-all',
                [Component.text('LOG OUT')],
              ),
            ]),
          ],
        ),
    ]);
  }
}
