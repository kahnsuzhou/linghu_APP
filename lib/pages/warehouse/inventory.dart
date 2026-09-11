import 'package:flutter/material.dart';
import '../../services/api_service.dart';

/// 仓主库存页
class WarehouseInventoryPage extends StatefulWidget {
  const WarehouseInventoryPage({super.key});

  @override
  State<WarehouseInventoryPage> createState() => _WarehouseInventoryPageState();
}

class _WarehouseInventoryPageState extends State<WarehouseInventoryPage> {
  List<Map<String, dynamic>> _inventory = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await ApiService().getWarehouseInventory();
      if (response['code'] == 200) {
        setState(() => _inventory = (response['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
      }
    } catch (_) {
      setState(() => _inventory = [
        {'productName': '灵狐有机牛奶250ml', 'barcode': '6901234567890', 'quantity': 100, 'lockedQuantity': 5, 'availableQuantity': 95},
        {'productName': '灵狐坚果混合装200g', 'barcode': '6901234567891', 'quantity': 50, 'lockedQuantity': 0, 'availableQuantity': 50},
        {'productName': '灵狐矿泉水500ml', 'barcode': '6901234567892', 'quantity': 200, 'lockedQuantity': 10, 'availableQuantity': 190},
      ]);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('库存管理'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _inventory.isEmpty
                  ? const Center(child: Text('暂无库存记录'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _inventory.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _inventory[index];
                        final available = (item['availableQuantity'] as num? ?? 0).toInt();
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['productName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text('条码：${item['barcode']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('$available 件', style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: available > 10 ? Colors.green : Colors.red,
                                    )),
                                    Text('锁定：${item['lockedQuantity']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// 仓主收益页
class EarningsPage extends StatefulWidget {
  const EarningsPage({super.key});

  @override
  State<EarningsPage> createState() => _EarningsPageState();
}

class _EarningsPageState extends State<EarningsPage> {
  Map<String, dynamic> _earnings = {};
  List<Map<String, dynamic>> _details = [];
  bool _loading = true;
  String _period = 'month';

  static const _blue = Color(0xFF2196F3);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await ApiService().getWarehouseEarnings(period: _period);
      if (response['code'] == 200) {
        final data = Map<String, dynamic>.from(response['data'] ?? {});
        final rawDetails = data['details'];
        setState(() {
          _earnings = data;
          _details = (rawDetails as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    } catch (_) {
      // 保持空状态
    } finally {
      setState(() => _loading = false);
    }
  }

  String get _periodLabel {
    switch (_period) {
      case 'week': return '本周';
      case 'year': return '本年';
      default:     return '本月';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收益明细'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _blue))
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 周期切换
                    _buildPeriodSelector(),
                    const SizedBox(height: 14),
                    // 收益汇总卡片
                    _buildSummaryCard(),
                    const SizedBox(height: 14),
                    // 收益拆分卡片（服务费 + 销售激励）
                    _buildBreakdownCard(),
                    const SizedBox(height: 14),
                    // 流水明细
                    _buildDetailsCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  // ─── 周期切换 ─────────────────────────────────────────────────────────────

  Widget _buildPeriodSelector() {
    return Row(
      children: ['month', 'week', 'year'].map((p) {
        final label = {'month': '本月', 'week': '本周', 'year': '本年'}[p]!;
        final selected = _period == p;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () {
              if (_period != p) {
                setState(() => _period = p);
                _load();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? _blue : Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey[600],
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── 汇总卡片 ─────────────────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    final totalEarnings = (_earnings['totalEarnings'] as num?) ?? 0;
    final totalOrders   = (_earnings['totalOrders'] as num?) ?? 0;
    final walletBalance = (_earnings['walletBalance'] as num?) ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: _blue.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        children: [
          Text('$_periodLabel总收益', style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            '¥${(totalEarnings as num).toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTopStat('已完成订单', '$totalOrders 单'),
              Container(width: 1, height: 36, color: Colors.white30),
              _buildTopStat('钱包余额', '¥${(walletBalance as num).toStringAsFixed(2)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  // ─── 拆分卡片 ─────────────────────────────────────────────────────────────

  Widget _buildBreakdownCard() {
    final totalServiceFee  = (_earnings['totalServiceFee']  as num?) ?? 0;
    final totalSalesBonus  = (_earnings['totalSalesBonus']  as num?) ?? 0;
    final serviceFeeRate   = (_earnings['serviceFeeRate']   as num?) ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_outline, color: _blue, size: 18),
              SizedBox(width: 6),
              Text('收益构成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // 仓库服务费
              Expanded(
                child: _buildBreakdownItem(
                  icon: Icons.warehouse_outlined,
                  label: '仓库服务费',
                  value: '¥${(totalServiceFee as num).toStringAsFixed(2)}',
                  sub: '¥${(serviceFeeRate as num).toStringAsFixed(2)}/单',
                  color: const Color(0xFF1976D2),
                  bgColor: const Color(0xFFE3F2FD),
                ),
              ),
              const SizedBox(width: 12),
              // 销售激励
              Expanded(
                child: _buildBreakdownItem(
                  icon: Icons.trending_up_rounded,
                  label: '销售激励',
                  value: '¥${(totalSalesBonus as num).toStringAsFixed(2)}',
                  sub: '销售额 × 1%',
                  color: const Color(0xFF2E7D32),
                  bgColor: const Color(0xFFE8F5E9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownItem({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 3),
          Text(sub, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  // ─── 流水明细 ─────────────────────────────────────────────────────────────

  Widget _buildDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: _blue, size: 18),
              SizedBox(width: 6),
              Text('收益流水', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          if (_details.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('暂无收益记录', style: TextStyle(color: Colors.grey))),
            )
          else
            ..._details.map((tx) => _buildTxItem(tx)),
        ],
      ),
    );
  }

  Widget _buildTxItem(Map<String, dynamic> tx) {
    final amount     = (tx['amount'] as num?) ?? 0;
    final serviceFee = (tx['serviceFee'] as num?) ?? 0;
    final salesBonus = (tx['salesBonus'] as num?) ?? 0;
    final remark     = tx['remark'] as String? ?? '';
    final createTime = tx['createTime'] as String? ?? '';

    // 简化时间显示 "2024-05-16T10:30:00" → "05-16 10:30"
    String timeLabel = createTime.length >= 16
        ? createTime.substring(5, 16).replaceFirst('T', ' ')
        : createTime;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          // 左侧图标
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined, color: _blue, size: 20),
          ),
          const SizedBox(width: 10),
          // 中部：备注 + 时间 + 拆分
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 拆分标签行
                Row(
                  children: [
                    if (serviceFee > 0)
                      _miniTag('服务费 ¥${(serviceFee as num).toStringAsFixed(2)}', const Color(0xFF1976D2)),
                    if (salesBonus > 0) ...[
                      const SizedBox(width: 4),
                      _miniTag('激励 ¥${(salesBonus as num).toStringAsFixed(2)}', const Color(0xFF2E7D32)),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  timeLabel,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          // 右侧金额
          Text(
            '+¥${(amount as num).toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }
}

/// 仓主个人中心
class WarehouseProfilePage extends StatelessWidget {
  const WarehouseProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
      ),
      body: const Center(child: Text('仓主个人信息、仓库配置等')),
    );
  }
}
