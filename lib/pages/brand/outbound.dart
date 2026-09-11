import 'package:flutter/material.dart';
import '../../services/api_service.dart';

/// 品牌方出库管理页（调拨单 + 退货单）
class OutboundPage extends StatefulWidget {
  const OutboundPage({super.key});

  @override
  State<OutboundPage> createState() => _OutboundPageState();
}

class _OutboundPageState extends State<OutboundPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('出库管理'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '发起出库', icon: Icon(Icons.outbox_outlined, size: 18)),
            Tab(text: '出库记录', icon: Icon(Icons.history_outlined, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _CreateOutboundTab(),
          _OutboundHistoryTab(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Tab 1：发起出库（选仓库 → 选商品 → 填数量 → 提交）
// ═══════════════════════════════════════════════
class _CreateOutboundTab extends StatefulWidget {
  const _CreateOutboundTab();
  @override
  State<_CreateOutboundTab> createState() => _CreateOutboundTabState();
}

class _CreateOutboundTabState extends State<_CreateOutboundTab> {
  // 出库类型：transfer=调拨, return=退货
  String _outboundType = 'transfer';

  List<Map<String, dynamic>> _warehouses = [];
  Map<String, dynamic>? _selectedWarehouse;
  List<Map<String, dynamic>> _inventory = [];
  bool _loadingWarehouses = true;
  bool _loadingInventory = false;
  bool _submitting = false;

  // 各商品选择的数量
  Map<int, int> _selectedQty = {};

  final _remarkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _loadWarehouses() async {
    setState(() => _loadingWarehouses = true);
    try {
      final resp = await ApiService().getBrandWarehouseList();
      if (resp['code'] == 200) {
        final list = (resp['data'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() {
          _warehouses = list;
          if (list.isNotEmpty && _selectedWarehouse == null) {
            _selectedWarehouse = list.first;
            _loadInventory((list.first['id'] as num).toInt());
          }
        });
      }
    } catch (_) {} finally {
      setState(() => _loadingWarehouses = false);
    }
  }

  Future<void> _loadInventory(int warehouseId) async {
    setState(() {
      _loadingInventory = true;
      _inventory = [];
      _selectedQty = {};
    });
    try {
      final resp = await ApiService().getBrandOutboundInventory(warehouseId);
      if (resp['code'] == 200) {
        final list = (resp['data'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() {
          _inventory = list;
          _selectedQty = {
            for (final item in list)
              (item['productId'] as num).toInt(): 0,
          };
        });
      }
    } catch (_) {} finally {
      setState(() => _loadingInventory = false);
    }
  }

  int get _totalSelectedQty =>
      _selectedQty.values.fold(0, (s, q) => s + q);

  double get _totalEstFee {
    double total = 0;
    for (final item in _inventory) {
      final pid = (item['productId'] as num).toInt();
      final qty = _selectedQty[pid] ?? 0;
      if (qty <= 0) continue;
      final feePerUnit =
          double.tryParse(item['feePerUnit']?.toString() ?? '0') ?? 0;
      total += feePerUnit * qty;
    }
    return total;
  }

  Future<void> _submit() async {
    if (_selectedWarehouse == null) {
      _showSnack('请选择出库仓库', Colors.orange);
      return;
    }
    final selectedItems = _selectedQty.entries
        .where((e) => e.value > 0)
        .map((e) => {'productId': e.key, 'quantity': e.value})
        .toList();
    if (selectedItems.isEmpty) {
      _showSnack('请选择至少一件商品', Colors.orange);
      return;
    }

    setState(() => _submitting = true);
    try {
      final warehouseId =
          (_selectedWarehouse!['id'] as num).toInt();
      final body = {
        'warehouseId': warehouseId,
        'items': selectedItems,
        if (_outboundType == 'transfer')
          'remark': _remarkController.text.trim().isEmpty
              ? '品牌方调拨出库'
              : _remarkController.text.trim(),
        if (_outboundType == 'return')
          'reason': _remarkController.text.trim().isEmpty
              ? '品牌方退货'
              : _remarkController.text.trim(),
      };

      final Map<String, dynamic> resp;
      if (_outboundType == 'transfer') {
        resp = await ApiService().createTransferOrder(body);
      } else {
        resp = await ApiService().createReturnOrder(body);
      }

      if (resp['code'] == 200) {
        final data = resp['data'] as Map<String, dynamic>? ?? {};
        _showResultDialog(data);
        // 重置
        setState(() {
          for (final k in _selectedQty.keys) _selectedQty[k] = 0;
          _remarkController.clear();
        });
      } else {
        _showSnack(resp['msg'] ?? '提交失败', Colors.red);
      }
    } catch (_) {
      _showSnack('网络错误，请重试', Colors.red);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showResultDialog(Map<String, dynamic> data) {
    final outboundNo = data['outboundNo'] as String? ?? '--';
    final warehouseName = data['warehouseName'] as String? ?? '';
    final totalQty = data['totalPlanQty'] ?? 0;
    final storageFee =
        double.tryParse(data['totalStorageFee']?.toString() ?? '0') ?? 0;
    final typeText = _outboundType == 'transfer' ? '调拨出库' : '退货出库';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 24),
          const SizedBox(width: 8),
          Text('$typeText单已提交'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('出库单号', outboundNo, bold: true),
            _infoRow('仓库', warehouseName),
            _infoRow('出库数量', '$totalQty 件'),
            _infoRow('仓储操作费',
                '¥${storageFee.toStringAsFixed(2)}',
                color: storageFee > 0 ? Colors.red : Colors.green),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 16),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      '等待仓主完成出库操作后，仓储费将从您的钱包扣除',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.grey))),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingWarehouses) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_warehouses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warehouse_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('暂无可用仓库', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 出库类型选择 ──
          _buildSectionHeader('📋 出库类型', ''),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TypeCard(
                  icon: Icons.swap_horiz_outlined,
                  label: '调拨出库',
                  subtitle: '将商品从仓库调出（调往其他仓或自取）',
                  selected: _outboundType == 'transfer',
                  color: const Color(0xFF2196F3),
                  onTap: () => setState(() => _outboundType = 'transfer'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TypeCard(
                  icon: Icons.keyboard_return_outlined,
                  label: '退货出库',
                  subtitle: '将商品退出仓库，返还给品牌方',
                  selected: _outboundType == 'return',
                  color: const Color(0xFFFF9800),
                  onTap: () => setState(() => _outboundType = 'return'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── 选择仓库 ──
          _buildSectionHeader('🏪 选择仓库', ''),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _warehouses.length,
              itemBuilder: (_, i) {
                final w = _warehouses[i];
                final selected = _selectedWarehouse != null &&
                    (_selectedWarehouse!['id'] as num).toInt() ==
                        (w['id'] as num).toInt();
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedWarehouse = w);
                    _loadInventory((w['id'] as num).toInt());
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF4CAF50)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: selected
                              ? const Color(0xFF4CAF50)
                              : Colors.grey[300]!),
                    ),
                    child: Text(
                      w['name'] as String? ?? '仓库',
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.black87,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // ── 商品列表 ──
          _buildSectionHeader('📦 选择商品',
              _totalSelectedQty > 0 ? '已选 $_totalSelectedQty 件' : ''),
          const SizedBox(height: 8),

          if (_loadingInventory)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator()))
          else if (_inventory.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: const Center(
                child: Text('该仓库暂无可出库的商品',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: _inventory.map((inv) {
                  final pid = (inv['productId'] as num).toInt();
                  final available =
                      ((inv['availableQuantity'] ?? 0) as num).toInt();
                  final qty = _selectedQty[pid] ?? 0;
                  final storageDays =
                      ((inv['storageDays'] ?? 0) as num).toInt();
                  final billableDays =
                      ((inv['billableDays'] ?? 0) as num).toInt();
                  final feePerUnit = double.tryParse(
                          inv['feePerUnit']?.toString() ?? '0') ??
                      0;

                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    inv['productName'] as String? ?? '--',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '可用：$available 件  · 在库 $storageDays 天',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey),
                                  ),
                                  if (billableDays > 0)
                                    Text(
                                      '计费 $billableDays 天 · 单件仓储费 ¥${feePerUnit.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFE65100)),
                                    )
                                  else
                                    const Text(
                                      '入库不足7天，暂无仓储费',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF4CAF50)),
                                    ),
                                ],
                              ),
                            ),
                            // 数量控制
                            Row(
                              children: [
                                _QtyBtn(
                                  icon: Icons.remove,
                                  onTap: qty > 0
                                      ? () => setState(
                                          () => _selectedQty[pid] = qty - 1)
                                      : null,
                                ),
                                Container(
                                  width: 42,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$qty',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: qty > 0
                                          ? const Color(0xFF4CAF50)
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                                _QtyBtn(
                                  icon: Icons.add,
                                  onTap: qty < available
                                      ? () => setState(
                                          () => _selectedQty[pid] = qty + 1)
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (qty > 0) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '此商品仓储费：¥${(feePerUnit * qty).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFE65100),
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                        if (inv != _inventory.last)
                          const Divider(height: 16),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 20),

          // ── 备注/原因 ──
          _buildSectionHeader(
              _outboundType == 'transfer' ? '📝 调拨备注' : '📝 退货原因',
              '（选填）'),
          const SizedBox(height: 8),
          TextField(
            controller: _remarkController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: _outboundType == 'transfer'
                  ? '请描述调拨目的或目标仓库...'
                  : '请描述退货原因...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),

          const SizedBox(height: 20),

          // ── 费用预估汇总 ──
          if (_totalSelectedQty > 0)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _totalEstFee > 0
                    ? Colors.orange[50]
                    : Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _totalEstFee > 0
                        ? Colors.orange[200]!
                        : Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(
                      _totalEstFee > 0
                          ? Icons.account_balance_wallet_outlined
                          : Icons.check_circle_outline,
                      color: _totalEstFee > 0
                          ? Colors.orange[700]
                          : Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '出库摘要',
                          style: TextStyle(
                              color: _totalEstFee > 0
                                  ? Colors.orange[800]
                                  : Colors.green[800],
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '共 $_totalSelectedQty 件 · '
                          '预计仓储操作费：¥${_totalEstFee.toStringAsFixed(2)}',
                          style: TextStyle(
                              color: _totalEstFee > 0
                                  ? Colors.orange[700]
                                  : Colors.green[700],
                              fontSize: 12),
                        ),
                        if (_totalEstFee > 0)
                          Text(
                            '费用说明：0.2元/件/天，入库后第7天开始计算',
                            style: TextStyle(
                                color: Colors.orange[600], fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: (_submitting || _totalSelectedQty == 0)
                  ? null
                  : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Icon(_outboundType == 'transfer'
                      ? Icons.swap_horiz
                      : Icons.keyboard_return),
              label: Text(
                _submitting
                    ? '提交中...'
                    : (_outboundType == 'transfer' ? '提交调拨单' : '提交退货单'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _outboundType == 'transfer'
                    ? const Color(0xFF2196F3)
                    : const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold)),
        Text(subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// Tab 2：出库记录列表
// ═══════════════════════════════════════════════
class _OutboundHistoryTab extends StatefulWidget {
  const _OutboundHistoryTab();
  @override
  State<_OutboundHistoryTab> createState() => _OutboundHistoryTabState();
}

class _OutboundHistoryTabState extends State<_OutboundHistoryTab> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ApiService().getBrandOutboundList();
      if (resp['code'] == 200) {
        setState(() {
          _orders = (resp['data'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      } else {
        setState(() => _error = resp['msg'] ?? '加载失败');
      }
    } catch (e) {
      setState(() => _error = '网络错误，请下拉刷新重试');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _cancel(int workOrderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('取消出库单'),
        content: const Text('确认取消此出库单？取消后库存锁定将被释放。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('确认取消')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final resp = await ApiService().cancelOutboundOrder(workOrderId);
      if (resp['code'] == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('出库单已取消'), backgroundColor: Colors.green));
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp['msg'] ?? '取消失败'), backgroundColor: Colors.red));
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络错误'), backgroundColor: Colors.red));
    }
  }

  String _formatTime(String? t) {
    if (t == null || t.isEmpty) return '--';
    return t.replaceFirst('T', ' ').split('.').first;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }
    if (_orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Column(
                children: [
                  Icon(Icons.outbox_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('暂无出库单',
                      style: TextStyle(color: Colors.grey, fontSize: 15)),
                  SizedBox(height: 6),
                  Text('提交调拨单或退货单后，记录将显示在这里',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        itemBuilder: (ctx, i) => _buildOrderCard(_orders[i]),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final outboundNo = order['outboundNo'] as String? ?? '--';
    final typeText = order['typeText'] as String? ?? '--';
    final isTransfer = (order['type'] as num?)?.toInt() == 6;
    final typeColor =
        isTransfer ? const Color(0xFF2196F3) : const Color(0xFFFF9800);
    final status = order['status'] as String?;
    final statusStyle = _getStatusStyle(status);
    final warehouseName = order['warehouseName'] as String? ?? '--';
    final totalQty = order['totalPlanQty'] ?? 0;
    final totalFee = double.tryParse(
            order['totalStorageFee']?.toString() ?? '0') ??
        0;
    final createTime = _formatTime(order['createTime'] as String?);
    final remark = order['remark'] as String? ?? '';
    final products = (order['products'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final canCancel = status == 'PENDING';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：单号 + 类型 + 状态
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(typeText,
                      style: TextStyle(
                          color: typeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    outboundNo,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusStyle.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: statusStyle.color.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusStyle.icon,
                          size: 12, color: statusStyle.color),
                      const SizedBox(width: 3),
                      Text(statusStyle.label,
                          style: TextStyle(
                              color: statusStyle.color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // 仓库 + 数量 + 费用
            Row(children: [
              const Icon(Icons.warehouse_outlined,
                  size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(warehouseName,
                      style: const TextStyle(fontSize: 13))),
              Text('$totalQty 件',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                '仓储操作费：¥${totalFee.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 12,
                    color:
                        totalFee > 0 ? Colors.red[700] : Colors.green[600]),
              ),
            ]),
            if (remark.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.notes_outlined,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(remark,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
              ]),
            ],
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.access_time, size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text('创建：$createTime',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),

            // 商品明细（可展开）
            if (products.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text('查看商品明细（${products.length} 种）',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4CAF50),
                        fontWeight: FontWeight.w500)),
                children: products
                    .map((p) => Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.circle,
                                  size: 6, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(
                                      p['productName'] as String? ?? '--',
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis)),
                              Text(
                                  '${(p['planQuantity'] ?? 0)} 件  ¥${double.tryParse(p['storageFee']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00'}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],

            // 取消按钮
            if (canCancel) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _cancel(
                      ((order['workOrderId'] as num?)?.toInt() ?? 0)),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('取消出库单', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _StatusStyle _getStatusStyle(String? status) {
    switch (status) {
      case 'PENDING':
        return _StatusStyle('待出库', Colors.orange, Icons.hourglass_empty);
      case 'PROCESSING':
        return _StatusStyle(
            '出库中', const Color(0xFF2196F3), Icons.outbox_outlined);
      case 'COMPLETED':
        return _StatusStyle(
            '已完成', const Color(0xFF4CAF50), Icons.check_circle_outline);
      case 'CANCELLED':
        return _StatusStyle('已取消', Colors.grey, Icons.cancel_outlined);
      default:
        return _StatusStyle(status ?? '未知', Colors.grey, Icons.help_outline);
    }
  }
}

// ── 辅助 Widgets ──────────────────────────────────────────

class _TypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? color : Colors.grey[300]!, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? color : Colors.grey, size: 28),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: selected ? color : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(
                    color: selected ? color.withOpacity(0.8) : Colors.grey,
                    fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 2),
          ],
        ),
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QtyBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: onTap != null ? Colors.grey[100] : Colors.grey[50],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size: 16,
            color: onTap != null ? Colors.grey[700] : Colors.grey[300]),
      ),
    );
  }
}

class _StatusStyle {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusStyle(this.label, this.color, this.icon);
}
