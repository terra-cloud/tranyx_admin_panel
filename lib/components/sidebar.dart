import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'package:web/web.dart' as web;
import '../app.dart';
import '../core/providers/environment_provider.dart';
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
    final fb.User? user = context.watch(adminCurrentUserProvider).value;
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
          data: (list) => list.where((t) => t.status.toLowerCase() != 'resolved').length,
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
              icon.endsWith('.png')
                  ? img(
                      src: icon,
                      classes:
                          'w-4.5 h-4.5 object-contain transition-all '
                          '${isActive ? "invert brightness-0" : "opacity-60 hover:opacity-100"}',
                      alt: label,
                    )
                  : Component.text(icon),
              if (_isCollapsed && badgeCount != null && badgeCount > 0)
                span(
                  classes:
                      'absolute -top-1.5 -right-1.5 w-4 h-4 rounded-full bg-rose-500 text-white text-[9px] font-black flex items-center justify-center border border-white shadow-sm',
                  [Component.text('$badgeCount')],
                ),
            ]),
            if (!_isCollapsed) span(classes: 'truncate font-bold ml-1', [Component.text(label)]),
            if (!_isCollapsed && badgeCount != null && badgeCount > 0)
              span(
                classes:
                    'ml-auto px-1.5 py-0.5 rounded-full bg-rose-500 text-white text-[9px] font-black leading-none flex items-center justify-center min-w-[16px] h-4',
                [Component.text('$badgeCount')],
              ),
          ],
        ),
      ]);
    }

    Component buildMobileMenuItem(String label, String path, String icon, {int? badgeCount}) {
      final isActive = currentPath == path || (path != '/' && currentPath.startsWith(path));
      return li([
        a(
          href: 'javascript:void(0);',
          onClick: () {
            setState(() {
              _isMobileMenuOpen = false;
            });
            Router.of(context).push(path);
          },
          classes:
              'flex items-center gap-3 px-4 py-3 rounded-xl text-xs font-bold '
              '${isActive ? "bg-black text-white" : "text-zinc-650 hover:bg-zinc-50"}',
          [
            span(classes: 'text-base flex-shrink-0 flex items-center justify-center w-5 h-5', [
              icon.endsWith('.png')
                  ? img(
                      src: icon,
                      classes:
                          'w-4.5 h-4.5 object-contain transition-all '
                          '${isActive ? "invert brightness-0" : "opacity-60"}',
                      alt: label,
                    )
                  : Component.text(icon),
            ]),
            span(classes: 'ml-1', [Component.text(label)]),
            if (badgeCount != null && badgeCount > 0)
              span(
                classes:
                    'ml-auto px-1.5 py-0.5 rounded-full bg-rose-500 text-white text-[9px] font-black leading-none flex items-center justify-center min-w-[16px] h-4',
                [Component.text('$badgeCount')],
              ),
          ],
        ),
      ]);
    }

    return .fragment([
      // Desktop Sidebar Dock (Expandable matching reference design)
      aside(
        classes:
            'hidden md:flex flex-col bg-white border-r border-zinc-200/50 p-4 min-h-screen sticky top-0 justify-between items-center transition-all duration-300 '
            '${_isCollapsed ? "w-20" : "w-64"}',
        [
          // Top: Brand logo
          div(classes: 'w-full flex flex-col gap-8', [
            div(
              classes:
                  'flex items-center justify-between gap-2.5 w-full '
                  '${_isCollapsed ? "justify-center" : "px-2"}',
              [
                div(classes: 'flex items-center gap-3', [
                  img(
                    src: '/images/logo.png',
                    alt: 'Tranyx Logo',
                    classes: 'w-10 h-10 object-contain flex-shrink-0 drop-shadow-sm',
                  ),
                  if (!_isCollapsed)
                    h2(classes: 'text-sm font-black tracking-wide text-zinc-900 uppercase', [
                      Component.text('Tranyx Admin'),
                    ]),
                ]),
              ],
            ),

            // Menu list
            ul(classes: 'flex flex-col gap-1.5 list-none p-0 m-0 w-full', [
              buildMenuItem('Dashboard', '/', '/images/icon_dashboard.png'),
              buildMenuItem('P2P Deposits', '/deposits', '💳', badgeCount: pendingDepositsCount),
              buildMenuItem('P2P Cashouts', '/withdrawals', '💸', badgeCount: pendingWithdrawalsCount),
              buildMenuItem('Listings', '/listings', '/images/icon_listings.png'),
              buildMenuItem('Bookings', '/bookings', '/images/icon_bookings.png'),
              buildMenuItem('KYC Verification', '/kyc', '/images/icon_kyc.png', badgeCount: pendingKycCount),
              buildMenuItem('Live Support', '/chats', '/images/icon_chats.png'),
              buildMenuItem('Support Tickets', '/tickets', '/images/icon_tickets.png', badgeCount: openTicketsCount),
              buildMenuItem('User Accounts', '/users', '/images/icon_users.png'),
              buildMenuItem('Promotions', '/promos', '/images/icon_promos.png'),
              buildMenuItem('News & Banners', '/news', '📰'),
              buildMenuItem('Abuse Reports', '/reports', '🚩', badgeCount: pendingReportsCount),
              buildMenuItem('System Console', '/settings', '/images/icon_settings.png'),
            ]),
          ]),

          // Bottom Area: Staff user info + Log out + Toggle Collapse
          div(classes: 'w-full flex flex-col gap-3 pt-4 border-t border-zinc-150/60', [
            // User Avatar and info
            if (!_isCollapsed)
              div(classes: 'px-2 flex items-center gap-3 w-full min-w-0', [
                div(
                  classes:
                      'w-8 h-8 rounded-full bg-zinc-100 border border-zinc-200 flex items-center justify-center font-bold text-xs text-zinc-700 flex-shrink-0',
                  [
                    Component.text(
                      user?.displayName != null && user!.displayName!.isNotEmpty
                          ? (user.displayName!.length > 1
                                ? user.displayName!.substring(0, 2).toUpperCase()
                                : user.displayName!.substring(0, 1).toUpperCase())
                          : ((user as dynamic)?.email != null
                                ? (user as dynamic).email!.substring(0, 1).toUpperCase()
                                : 'A'),
                    ),
                  ],
                ),
                div(classes: 'flex flex-col min-w-0 flex-1', [
                  span(classes: 'text-[11px] font-black text-zinc-800 truncate', [
                    Component.text(
                      user?.displayName != null && user!.displayName!.isNotEmpty ? user.displayName! : 'Staff Agent',
                    ),
                  ]),
                  span(classes: 'text-[9px] text-zinc-400 font-semibold truncate', [
                    Component.text((user as dynamic)?.email ?? 'Staff Agent'),
                  ]),
                ]),
              ]),

            // Log out Button
            button(
              onClick: () async {
                try {
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
              buildMobileMenuItem('Promotions', '/promos', '/images/icon_promos.png'),
              buildMobileMenuItem('News & Banners', '/news', '📰'),
              buildMobileMenuItem('Abuse Reports', '/reports', '🚩', badgeCount: pendingReportsCount),
              buildMobileMenuItem('System Console', '/settings', '/images/icon_settings.png'),
            ]),
            div(classes: 'border-t border-zinc-200 pt-4 flex justify-between items-center', [
              span(classes: 'text-[10px] text-zinc-500 font-semibold truncate', [
                Component.text((user as dynamic)?.email ?? 'Staff Agent'),
              ]),
              button(
                onClick: () async {
                  try {
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
