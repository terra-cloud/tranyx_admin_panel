import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:riverpod/legacy.dart';
import 'package:web/web.dart' as web;

import '../pages/deposits.dart' show depositRequestsStreamProvider;
import '../pages/withdrawals.dart' show withdrawalRequestsStreamProvider;

/// Global sound notification state provider
final globalAlertSoundEnabledProvider = StateProvider<bool>((ref) {
  try {
    final saved = web.window.localStorage.getItem('tranyx_global_sound_enabled');
    if (saved != null) {
      return saved == 'true';
    }
  } catch (_) {}
  return true;
});

/// Unified model representing an active unhandled P2P interrupt event.
class P2PInterruptItem {
  final String id;
  final String type; // 'deposit' or 'withdrawal'
  final String userName;
  final String userId;
  final double amount;
  final String paymentMethod;
  final String status;
  final DateTime createdAt;

  const P2PInterruptItem({
    required this.id,
    required this.type,
    required this.userName,
    required this.userId,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
  });
}

/// Global P2P Alert Manager Component.
/// Stays permanently mounted in the AppShell so audio chimes and interrupt
/// modals trigger on ANY page (Dashboard, Users, KYC, Chats, etc.).
class GlobalP2PAlertManager extends StatefulComponent {
  const GlobalP2PAlertManager({super.key});

  @override
  State<GlobalP2PAlertManager> createState() => _GlobalP2PAlertManagerState();
}

class _GlobalP2PAlertManagerState extends State<GlobalP2PAlertManager> {
  final Set<String> _seenRequestIds = {};
  final Set<String> _acknowledgedInterruptIds = {};
  P2PInterruptItem? _activeInterruptItem;

  void _playAlertChime() {
    final soundEnabled = context.read(globalAlertSoundEnabledProvider);
    if (!soundEnabled) return;
    try {
      final ctx = web.AudioContext();
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);

      // Play urgent high-low alert tone (880Hz -> 1320Hz)
      osc.frequency.setValueAtTime(880, ctx.currentTime);
      osc.frequency.setValueAtTime(1320, ctx.currentTime + 0.12);
      gain.gain.setValueAtTime(0.35, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.45);

      osc.start(ctx.currentTime);
      osc.stop(ctx.currentTime + 0.45);
    } catch (_) {}
  }

  @override
  Component build(BuildContext context) {
    final depositsAsync = context.watch(depositRequestsStreamProvider);
    final withdrawalsAsync = context.watch(withdrawalRequestsStreamProvider);

    final deposits = depositsAsync.value ?? [];
    final withdrawals = withdrawalsAsync.value ?? [];

    bool isOnChainCrypto(String method) {
      final m = method.toLowerCase();
      return m.contains('usdt') ||
          m.contains('crypto') ||
          m.contains('onchain') ||
          m.contains('trc20') ||
          m.contains('erc20') ||
          m.contains('bep20') ||
          m.contains('polygon') ||
          m.contains('sol') ||
          m.contains('btc') ||
          m.contains('eth') ||
          m.contains('blockchain');
    }

    // 1. Gather all unassigned deposit requests needing immediate attention (Excluding On-Chain Crypto/USDT)
    final unhandledDeposits = deposits.where((d) {
      if (isOnChainCrypto(d.paymentMethod)) return false;
      final isActionable = ((d.status == 'PENDING_AGENT' && (d.assignedAgentId == null || d.assignedAgentId!.isEmpty)) ||
              d.status == 'PENDING_VERIFICATION' ||
              d.status == 'AWAITING_QR' ||
              d.status == 'WAITING_FOR_QR' ||
              d.status == 'REQUESTED' ||
              d.status == 'OPEN' ||
              d.status == 'PENDING') &&
          d.status != 'APPROVED' &&
          d.status != 'REJECTED' &&
          d.status != 'CANCELLED';
      return isActionable && !_acknowledgedInterruptIds.contains(d.id);
    }).toList();

    // 2. Gather all unassigned cashout requests needing immediate attention (Excluding On-Chain Crypto/USDT)
    final unhandledWithdrawals = withdrawals.where((w) {
      if (isOnChainCrypto(w.paymentMethod)) return false;
      final isActionable = (w.status == 'WAITING_FOR_AGENT' ||
              w.status == 'PENDING_CONFIRMATION' ||
              w.status == 'PENDING_AGENT' ||
              w.status == 'REQUESTED' ||
              w.status == 'OPEN' ||
              w.status == 'PENDING' ||
              (w.agentId == null || w.agentId!.isEmpty)) &&
          w.status != 'APPROVED' &&
          w.status != 'REJECTED' &&
          w.status != 'CANCELLED';
      return isActionable && !_acknowledgedInterruptIds.contains(w.id);
    }).toList();

    // Check if new items arrived
    final List<P2PInterruptItem> actionableItems = [
      ...unhandledDeposits.map((d) => P2PInterruptItem(
            id: d.id,
            type: 'deposit',
            userName: d.userName,
            userId: d.userId,
            amount: d.amount,
            paymentMethod: d.paymentMethod,
            status: d.status,
            createdAt: DateTime.fromMillisecondsSinceEpoch(d.submittedAt),
          )),
      ...unhandledWithdrawals.map((w) => P2PInterruptItem(
            id: w.id,
            type: 'withdrawal',
            userName: w.userAccountName.isNotEmpty ? w.userAccountName : w.userName,
            userId: w.uid,
            amount: w.amount,
            paymentMethod: w.paymentMethod,
            status: w.status,
            createdAt: DateTime.fromMillisecondsSinceEpoch(w.createdAt),
          )),
    ];

    // Detect brand-new items to trigger audio chime
    for (final item in actionableItems) {
      if (!_seenRequestIds.contains(item.id)) {
        _seenRequestIds.add(item.id);
        _playAlertChime();
      }
    }

    // Set active interrupt item if not currently displaying or current is resolved
    if (actionableItems.isNotEmpty) {
      if (_activeInterruptItem == null ||
          !actionableItems.any((item) => item.id == _activeInterruptItem!.id)) {
        _activeInterruptItem = actionableItems.first;
      }
    } else {
      _activeInterruptItem = null;
    }

    if (_activeInterruptItem == null) {
      return const Component.empty();
    }

    return _buildInterruptModal(_activeInterruptItem!, actionableItems.length);
  }

  Component _buildInterruptModal(P2PInterruptItem item, int totalActionableCount) {
    final isDeposit = item.type == 'deposit';
    final isGcash = item.paymentMethod.toLowerCase().contains('gcash');
    final isMaya = item.paymentMethod.toLowerCase().contains('maya');

    String formatTimeAgo(DateTime dt) {
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 45) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    }

    final initialLetter = item.userName.isNotEmpty ? item.userName[0].toUpperCase() : 'U';

    return div(
      classes:
          'fixed inset-0 bg-black/40 backdrop-blur-sm z-[9999] flex items-center justify-center p-4 md:p-6 animate-fade-in',
      [
        div(
          classes:
              'bg-white text-zinc-900 rounded-[28px] border border-zinc-200/80 shadow-[0_25px_60px_-15px_rgba(0,0,0,0.15)] w-full max-w-md overflow-hidden flex flex-col animate-scale-up',
          [
            // Minimalist Top Header with generous padding
            div(
              classes:
                  'px-7 pt-6 pb-5 md:px-8 md:pt-7 md:pb-6 flex items-center justify-between border-b border-zinc-100 bg-[#eff2f0]/40',
              [
                div(classes: 'flex items-center gap-3.5', [
                  div(
                    classes:
                        'w-10 h-10 rounded-2xl flex items-center justify-center text-lg font-black shrink-0 '
                        '${isDeposit ? "bg-emerald-50 text-[#0fa958] border border-emerald-200/60" : "bg-zinc-900 text-white shadow-sm"}',
                    [Component.text(isDeposit ? '↓' : '↑')],
                  ),
                  div(classes: 'flex flex-col gap-0.5', [
                    div(classes: 'flex items-center gap-2 flex-wrap', [
                      h2(classes: 'text-sm font-black tracking-tight text-zinc-900', [
                        Component.text(isDeposit ? 'New Deposit Request' : 'New Cashout Request'),
                      ]),
                      span(
                        classes:
                            'inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[10px] font-extrabold '
                            '${isDeposit ? "bg-emerald-50 text-[#0fa958] border border-emerald-200/60" : "bg-amber-50 text-amber-700 border border-amber-200/60"}',
                        [
                          span(classes: 'w-1.5 h-1.5 rounded-full ${isDeposit ? "bg-[#0fa958] animate-pulse" : "bg-amber-500 animate-pulse"}', []),
                          Component.text('Action Needed'),
                        ],
                      ),
                    ]),
                    span(classes: 'text-[11px] text-zinc-400 font-medium leading-relaxed', [
                      Component.text(isDeposit ? 'Customer waiting for payment QR / verification' : 'Customer waiting for agent payout disbursement'),
                    ]),
                  ]),
                ]),

                button(
                  onClick: () {
                    setState(() {
                      _acknowledgedInterruptIds.add(item.id);
                      _activeInterruptItem = null;
                    });
                  },
                  classes:
                      'w-8 h-8 rounded-full bg-zinc-100 hover:bg-zinc-200/80 text-zinc-400 hover:text-zinc-700 transition-all flex items-center justify-center text-xs font-bold cursor-pointer border-0 outline-none shrink-0 ml-2',
                  attributes: {'title': 'Dismiss modal'},
                  [Component.text('✕')],
                ),
              ],
            ),

            // Content Body with balanced spacing
            div(classes: 'p-7 md:p-8 flex flex-col gap-4.5', [
              // Hero Amount & Rail Display
              div(
                classes:
                    'p-5 rounded-2xl bg-white border border-zinc-200/80 shadow-sm flex items-center justify-between gap-4',
                [
                  div(classes: 'flex flex-col gap-0.5', [
                    span(classes: 'text-[10px] font-bold text-zinc-400 uppercase tracking-wider', [
                      Component.text(isDeposit ? 'Deposit Amount' : 'Disbursement Amount'),
                    ]),
                    span(classes: 'text-2xl font-black text-zinc-900 tracking-tight', [
                      Component.text('₱${item.amount.toStringAsFixed(2)}'),
                    ]),
                  ]),

                  div(classes: 'flex flex-col items-end gap-1.5', [
                    span(
                      classes:
                          'px-3 py-1 rounded-full text-[11px] font-extrabold flex items-center gap-1.5 '
                          '${isGcash ? "bg-blue-50 text-[#007DFE] border border-blue-200/60" : (isMaya ? "bg-emerald-50 text-[#0fa958] border border-emerald-200/60" : "bg-zinc-100 text-zinc-700 border border-zinc-200")}',
                      [
                        span([Component.text(isGcash ? '🔵' : (isMaya ? '🟢' : '💳'))]),
                        Component.text(item.paymentMethod),
                      ],
                    ),
                    span(classes: 'text-[10px] text-zinc-400 font-medium', [
                      Component.text(formatTimeAgo(item.createdAt)),
                    ]),
                  ]),
                ],
              ),

              // Customer Details Inset
              div(classes: 'p-4 rounded-2xl bg-[#eff2f0]/60 border border-zinc-200/50 flex flex-col gap-2', [
                div(classes: 'flex items-center justify-between gap-2', [
                  div(classes: 'flex items-center gap-2.5 min-w-0', [
                    div(
                      classes:
                          'w-7.5 h-7.5 rounded-full bg-zinc-200 border border-zinc-300 flex items-center justify-center text-xs font-bold text-zinc-700 shrink-0',
                      [Component.text(initialLetter)],
                    ),
                    div(classes: 'flex flex-col min-w-0', [
                      span(classes: 'text-xs font-bold text-zinc-800 truncate', [Component.text(item.userName)]),
                      span(classes: 'text-[10px] font-mono text-zinc-400 truncate', [
                        Component.text('UID: ${item.userId.substring(0, item.userId.length > 10 ? 10 : item.userId.length)}...'),
                      ]),
                    ]),
                  ]),

                  if (totalActionableCount > 1)
                    span(
                      classes: 'px-2.5 py-1 rounded-full bg-zinc-200 text-zinc-600 text-[10px] font-bold shrink-0',
                      [Component.text('+${totalActionableCount - 1} more in queue')],
                    ),
                ]),
              ]),
            ]),

            // Minimal Footer
            div(
              classes:
                  'px-7 py-4.5 md:px-8 md:py-5 border-t border-zinc-100 bg-[#eff2f0]/40 flex items-center justify-between gap-3',
              [
                button(
                  onClick: () {
                    setState(() {
                      _acknowledgedInterruptIds.add(item.id);
                      _activeInterruptItem = null;
                    });
                  },
                  classes:
                      'px-4.5 py-2.5 rounded-xl bg-zinc-100 hover:bg-zinc-200/80 text-zinc-600 hover:text-zinc-900 text-xs font-bold transition-all cursor-pointer border-0 outline-none',
                  [Component.text('Snooze')],
                ),

                button(
                  onClick: () {
                    setState(() {
                      _acknowledgedInterruptIds.add(item.id);
                      _activeInterruptItem = null;
                    });
                    if (isDeposit) {
                      Router.of(context).push('/deposits');
                    } else {
                      Router.of(context).push('/withdrawals');
                    }
                  },
                  classes:
                      'px-5.5 py-2.5 rounded-xl bg-black hover:bg-zinc-800 text-white text-xs font-black transition-all shadow-sm cursor-pointer border-0 outline-none flex items-center gap-2',
                  [
                    Component.text(isDeposit ? 'Open Deposit Queue' : 'Open Cashout Queue'),
                    span(classes: 'text-xs font-bold', [Component.text('→')]),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
