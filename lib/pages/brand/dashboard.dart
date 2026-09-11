import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../main.dart';
import '../consumer/profile.dart' show ConsumerProfilePage;
import '../wallet/wallet_page.dart';
import 'heatmap.dart';

/// 品牌方数据看板页
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<Map<String, dynamic>> _inventory = [];
  Map<String, dynamic> _aiSuggestion = {};
  // 外单统计
  int _externalTotal = 0;
  int _externalLocked = 0;   // status=1
  int _externalShipped = 0;  // status=3
  int _externalException = 0;// status=4
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().getBrandInventoryOverview(),
        ApiService().getReplenishmentSuggestion(),
        ApiService().getBrandExternalOrders(status: null, size: 1),      // 全部
        ApiService().getBrandExternalOrders(status: '1', size: 1),     // 库存锁定
        ApiService().getBrandExternalOrders(status: '3', size: 1),     // 已发货
        ApiService().getBrandExternalOrders(status: '4', size: 1),     // 异常
      ]);
      setState(() {
        _inventory = (results[0]['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _aiSuggestion = Map<String, dynamic>.from(results[1]['data'] ?? {});
        // 外单统计
        final _extAll = results[2]['data'];
        _externalTotal = (_extAll is Map ? (_extAll['total'] as num?)?.toInt() : null) ?? 0;
        final _extLocked = results[3]['data'];
        _externalLocked = (_extLocked is Map ? (_extLocked['total'] as num?)?.toInt() : null) ?? 0;
        final _extShipped = results[4]['data'];
        _externalShipped = (_extShipped is Map ? (_extShipped['total'] as num?)?.toInt() : null) ?? 0;
        final _extException = results[5]['data'];
        _externalException = (_extException is Map ? (_extException['total'] as num?)?.toInt() : null) ?? 0;
      });
    } catch (e) {
      // 库存降级数据
      if (_inventory.isEmpty) {
        setState(() {
          _inventory = [
            {'warehouseName': '朝阳区望京Mini仓', 'productName': '灵狐有机牛奶250ml', 'quantity': 95, 'lockedQuantity': 5},
            {'warehouseName': '朝阳区望京Mini仓', 'productName': '灵狐坚果混合装200g', 'quantity': 50, 'lockedQuantity': 0},
            {'warehouseName': '海淀区中关村Mini仓', 'productName': '灵狐矿泉水500ml', 'quantity': 140, 'lockedQuantity': 10},
          ];
          _aiSuggestion = {'recommendedQuantity': 100, 'reason': '根据历史销售数据建议补货100件', 'nextReplenishDate': '3天后'};
        });
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据看板'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: '仓库热力图',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BrandHeatmapPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: '品牌方钱包',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WalletPage()),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '退出登录',
            onPressed: () => ConsumerProfilePage.logout(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 概览统计
                    Row(
                      children: [
                        _buildOverviewCard('商品总数', '${_inventory.map((i) => i['productName']).toSet().length}', Icons.inventory_2, Colors.green),
                        const SizedBox(width: 12),
                        _buildOverviewCard('覆盖仓库', '${_inventory.map((i) => i['warehouseName']).toSet().length}', Icons.warehouse, Colors.blue),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 外单统计
                    const Text('外单数据', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(children: [
                      _buildExternalStatCard('总外单', _externalTotal, Icons.receipt_long, Colors.purple),
                      const SizedBox(width: 8),
                      _buildExternalStatCard('库存锁定', _externalLocked, Icons.lock_clock, const Color(0xFF7B1FA2)),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      _buildExternalStatCard('已发货', _externalShipped, Icons.local_shipping, Colors.green),
                      const SizedBox(width: 8),
                      _buildExternalStatCard('异常', _externalException, Icons.error_outline, Colors.red),
                    ]),
                    const SizedBox(height: 16),

                    // AI补货建议
                    if (_aiSuggestion.isNotEmpty)
                      Card(
                        color: Colors.green[50],
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.lightbulb, color: Colors.amber),
                                  const SizedBox(width: 8),
                                  const Text('AI 补货建议', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(8)),
                                    child: const Text('MVP', style: TextStyle(color: Colors.white, fontSize: 11)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text('建议补货：${_aiSuggestion['recommendedQuantity']}件', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('${_aiSuggestion['reason']}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text('建议时间：${_aiSuggestion['nextReplenishDate']}', style: const TextStyle(color: Colors.green)),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    // 库存分布
                    const Text('各仓库库存分布', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ..._inventory.map((item) => _buildInventoryRow(item)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildExternalStatCard(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildOverviewCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryRow(Map<String, dynamic> item) {
    final qty = (item['quantity'] as num? ?? 0).toInt();
    final maxQty = 200;
    final progress = (qty / maxQty).clamp(0.0, 1.0);
    final isLow = qty < 30;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(item['productName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                if (isLow)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(6)),
                    child: const Text('库存偏低', style: TextStyle(fontSize: 10, color: Colors.red)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(item['warehouseName'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.grey[200],
                      color: isLow ? Colors.red : const Color(0xFF4CAF50),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('$qty 件', style: TextStyle(fontWeight: FontWeight.bold, color: isLow ? Colors.red : Colors.green)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
