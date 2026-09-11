import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart';
import '../../services/api_service.dart';
import 'payment_account_page.dart';

/// 三端通用钱包页面
/// - 消费者（role=0）：余额卡 + 充值 + 流水
/// - 仓主（role=1）：收入余额卡 + 提现 + 流水
/// - 品牌方（role=2）：收入余额卡 + 提现 + 流水
class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  Map<String, dynamic> _walletInfo = {};
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  bool _hasMore = true;

  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100 &&
        !_loadingMore &&
        _hasMore) {
      _loadMoreTransactions();
    }
  }

  Future<void> _loadWallet() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().getWalletInfo(),
        ApiService().getWalletTransactions(page: 1, size: _pageSize),
      ]);
      if (mounted) {
        setState(() {
          _walletInfo = Map<String, dynamic>.from(results[0]['data'] ?? {});
          final txData = results[1]['data'] as Map<String, dynamic>? ?? {};
          _transactions = (txData['list'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          final total = (txData['total'] as num?)?.toInt() ?? 0;
          _hasMore = _transactions.length < total;
          _page = 1;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMoreTransactions() async {
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final resp = await ApiService()
          .getWalletTransactions(page: nextPage, size: _pageSize);
      if (resp['code'] == 200 && mounted) {
        final txData = resp['data'] as Map<String, dynamic>? ?? {};
        final newItems =
            (txData['list'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        final total = (txData['total'] as num?)?.toInt() ?? 0;
        setState(() {
          _transactions.addAll(newItems);
          _page = nextPage;
          _hasMore = _transactions.length < total;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  double get _balance =>
      ((_walletInfo['balance'] as num?) ?? 0).toDouble();

  // ── 充值弹窗（消费者）─────────────────────────────────────

  void _showRechargeDialog() {
    final ctrl = TextEditingController();
    final presets = [10.0, 50.0, 100.0, 200.0, 500.0];
    double? selected;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setLocalState) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(ctx2).viewInsets.bottom + 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: const [
                Icon(Icons.account_balance_wallet,
                    color: Color(0xFFFF6B35), size: 22),
                SizedBox(width: 8),
                Text('钱包充值',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 16),
              // 快捷金额
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets.map((amt) {
                  final isSel = selected == amt;
                  return GestureDetector(
                    onTap: () {
                      setLocalState(() {
                        selected = amt;
                        ctrl.text = amt.toStringAsFixed(0);
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFFFF6B35)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '¥${amt.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: isSel ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '自定义金额（元）',
                  border: OutlineInputBorder(),
                  prefixText: '¥ ',
                ),
                onChanged: (v) => setLocalState(() => selected = null),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final text = ctrl.text.trim();
                    final amount = double.tryParse(text);
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入有效的充值金额')));
                      return;
                    }
                    Navigator.pop(ctx2);
                    await _doRecharge(amount);
                  },
                  child: const Text('确认充值',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _doRecharge(double amount) async {
    try {
      final resp = await ApiService().rechargeWallet(amount);
      if (resp['code'] == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('充值成功 ¥${amount.toStringAsFixed(2)}'),
          backgroundColor: Colors.green,
        ));
        _loadWallet();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp['msg'] ?? '充值失败'), backgroundColor: Colors.red));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('网络错误'), backgroundColor: Colors.red));
      }
    }
  }

  // ── 提现弹窗（三端）───────────────────────────────────────

  void _showWithdrawDialog() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: const [
              Icon(Icons.outbox, color: Color(0xFF2196F3), size: 22),
              SizedBox(width: 8),
              Text('申请提现',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            Text('当前余额：¥${_balance.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '提现金额（元）',
                border: OutlineInputBorder(),
                prefixText: '¥ ',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final amount = double.tryParse(ctrl.text.trim());
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请输入有效的提现金额')));
                    return;
                  }
                  Navigator.pop(ctx);
                  await _doWithdraw(amount);
                },
                child: const Text('确认提现',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            Text('* 模拟提现，预计1-3个工作日到账',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Future<void> _doWithdraw(double amount) async {
    try {
      final resp = await ApiService().withdrawWallet(amount);
      if (resp['code'] == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('提现申请成功 ¥${amount.toStringAsFixed(2)}'),
          backgroundColor: Colors.green,
        ));
        _loadWallet();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp['msg'] ?? '提现失败'), backgroundColor: Colors.red));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('网络错误'), backgroundColor: Colors.red));
      }
    }
  }

  // ── UI ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AppState>().role;
    final isConsumer = role == 0;
    final themeColor = isConsumer
        ? const Color(0xFFFF6B35)
        : role == 1
            ? const Color(0xFF2196F3)
            : const Color(0xFF4CAF50);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('我的钱包'),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadWallet),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadWallet,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // ── 余额卡 ──
                  SliverToBoxAdapter(
                    child: _buildBalanceCard(themeColor, isConsumer, role),
                  ),

                  // ── 流水标题 ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Row(children: [
                        Container(
                            width: 4,
                            height: 18,
                            color: themeColor,
                            margin: const EdgeInsets.only(right: 8)),
                        const Text('资金流水',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),

                  // ── 流水列表 ──
                  _transactions.isEmpty
                      ? const SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long,
                                    size: 56, color: Colors.grey),
                                SizedBox(height: 12),
                                Text('暂无流水记录',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 14)),
                              ],
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, index) {
                              if (index < _transactions.length) {
                                return _buildTransactionItem(
                                    _transactions[index]);
                              }
                              return _hasMore
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                          child: CircularProgressIndicator()),
                                    )
                                  : const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                          child: Text('— 已加载全部 —',
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12))),
                                    );
                            },
                            childCount: _transactions.length + 1,
                          ),
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildBalanceCard(Color themeColor, bool isConsumer, int role) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [themeColor, themeColor.withOpacity(0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: themeColor.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isConsumer ? '钱包余额' : '可提现余额',
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            '¥${_balance.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (isConsumer) ...[
                Expanded(
                  child: _buildActionBtn(
                    label: '充值',
                    icon: Icons.add_circle_outline,
                    onTap: _showRechargeDialog,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: _buildActionBtn(
                  label: '提现',
                  icon: Icons.outbox_outlined,
                  onTap: _showWithdrawDialog,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionBtn(
                  label: '绑定账号',
                  icon: Icons.link,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => PaymentAccountPage())),
                ),
              ),
            ],
          ),
          if (!isConsumer) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: Colors.white.withOpacity(0.8), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    role == 1
                        ? '消费者确认收货后，服务费自动到账'
                        : '消费者确认收货后，货款自动到账',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 11),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionBtn(
      {required String label,
      required IconData icon,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    final type = tx['type'] as String? ?? '';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final typeText = tx['typeText'] as String? ?? type;
    final remark = tx['remark'] as String? ?? '';
    final createTime = tx['createTime'] as String? ?? '';
    final isPositive = amount >= 0;

    IconData icon;
    Color iconColor;
    switch (type) {
      case 'RECHARGE':
        icon = Icons.add_circle;
        iconColor = Colors.green;
        break;
      case 'PAY':
        icon = Icons.shopping_cart;
        iconColor = Colors.orange;
        break;
      case 'INCOME':
        icon = Icons.moving;
        iconColor = Colors.blue;
        break;
      case 'WITHDRAW':
        icon = Icons.outbox;
        iconColor = Colors.purple;
        break;
      case 'REFUND':
        icon = Icons.undo;
        iconColor = const Color(0xFF00ACC1);
        break;
      default:
        icon = Icons.swap_horiz;
        iconColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(typeText,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (remark.isNotEmpty)
              Text(remark,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            Text(
              createTime.length > 16 ? createTime.substring(0, 16) : createTime,
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ),
        trailing: Text(
          '${isPositive ? '+' : ''}${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isPositive ? Colors.green[600] : Colors.red[500],
          ),
        ),
        isThreeLine: remark.isNotEmpty,
      ),
    );
  }
}
