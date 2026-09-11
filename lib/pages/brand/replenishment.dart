import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import 'outbound.dart';

/// 品牌方铺货计划 + 入库进度 + 出库管理页（TabBar）
class ReplenishmentPage extends StatefulWidget {
  const ReplenishmentPage({super.key});

  @override
  State<ReplenishmentPage> createState() => _ReplenishmentPageState();
}

class _ReplenishmentPageState extends State<ReplenishmentPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        title: const Text('铺货管理'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '提交铺货计划', icon: Icon(Icons.add_box_outlined, size: 18)),
            Tab(text: '入库进度', icon: Icon(Icons.inventory_2_outlined, size: 18)),
            Tab(text: '出库管理', icon: Icon(Icons.outbox_outlined, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _PlanFormTab(),
          _InboundProgressTab(),
          _OutboundManagementTab(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Tab 1：提交铺货计划（原有逻辑，保持完整）
// ═══════════════════════════════════════════════
class _PlanFormTab extends StatefulWidget {
  const _PlanFormTab();

  @override
  State<_PlanFormTab> createState() => _PlanFormTabState();
}

class _PlanFormTabState extends State<_PlanFormTab> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _warehouses = [];
  bool _loading = true;
  bool _submitting = false;

  List<int> _selectedProductIds = [];
  Map<int, int> _warehouseQuantities = {};
  final int _defaultQty = 100;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().getBrandProducts(),
        ApiService().getBrandWarehouseList(),
      ]);

      final productsResp = results[0];
      final warehousesResp = results[1];

      setState(() {
        if (productsResp['code'] == 200) {
          _products = (productsResp['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        } else {
          _products = _mockProducts();
        }

        if (warehousesResp['code'] == 200) {
          _warehouses = (warehousesResp['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        } else {
          _warehouses = _mockWarehouses();
        }

        _warehouseQuantities = {
          for (final w in _warehouses)
            (w['id'] as num).toInt(): _defaultQty,
        };
      });
    } catch (_) {
      setState(() {
        _products = _mockProducts();
        _warehouses = _mockWarehouses();
        _warehouseQuantities = {1: _defaultQty, 2: _defaultQty};
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _mockProducts() => [
    {'id': 1, 'name': '灵狐有机牛奶250ml', 'retailPrice': 5.9},
    {'id': 2, 'name': '灵狐坚果混合装200g', 'retailPrice': 29.9},
  ];

  List<Map<String, dynamic>> _mockWarehouses() => [
    {'id': 1, 'name': '朝阳区望京Mini仓', 'address': '北京市朝阳区望京街道5号', 'type': 'MINI'},
    {'id': 2, 'name': '海淀区中关村Mini仓', 'address': '北京市海淀区中关村南大街27号', 'type': 'MINI'},
  ];

  String _warehouseTypeLabel(String? type) {
    switch (type) {
      case 'STANDARD': return '标准仓';
      case 'LARGE':    return '大型仓';
      default:         return 'Mini仓';
    }
  }

  Color _warehouseTypeColor(String? type) {
    switch (type) {
      case 'STANDARD': return const Color(0xFF2196F3);
      case 'LARGE':    return const Color(0xFF9C27B0);
      default:         return const Color(0xFF4CAF50);
    }
  }

  int get _totalQuantity => _warehouseQuantities.values.fold(0, (s, q) => s + q);

  Future<void> _submitPlan() async {
    if (_selectedProductIds.isEmpty) {
      _showSnack('请选择至少一个铺货商品', Colors.orange);
      return;
    }
    final selectedWarehouses = _warehouseQuantities.entries
        .where((e) => e.value > 0)
        .toList();
    if (selectedWarehouses.isEmpty) {
      _showSnack('请为至少一个仓库设置铺货数量', Colors.orange);
      return;
    }

    setState(() => _submitting = true);
    try {
      final response = await ApiService().createReplenishmentPlan({
        'productIds': _selectedProductIds,
        'totalQuantity': _totalQuantity,
        'warehouseAllocations': selectedWarehouses.map((e) => {
          'warehouseId': e.key,
          'quantity': e.value,
        }).toList(),
      });

      if (response['code'] == 200) {
        final data = response['data'] as Map<String, dynamic>? ?? {};
        final orders = (data['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        setState(() {
          _selectedProductIds = [];
          for (final k in _warehouseQuantities.keys) {
            _warehouseQuantities[k] = _defaultQty;
          }
        });
        if (mounted) _showInboundNosDialog(orders);
      } else {
        _showSnack(response['msg'] ?? '提交失败，请重试', Colors.red);
      }
    } catch (_) {
      _showSnack('网络错误，请重试', Colors.red);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  void _showInboundNosDialog(List<Map<String, dynamic>> orders) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 26),
            SizedBox(width: 8),
            Text('铺货计划已提交'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('以下入库单号已生成，请发送给对应仓库操作员：',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            ...orders.map((order) {
              final inboundNo = order['inboundNo'] as String? ?? '--';
              final warehouseName = order['warehouseName'] as String? ?? '仓库';
              final itemCount = order['itemCount'] ?? 0;
              final totalQty = order['totalPlanQty'] ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F8E9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFC8E6C9)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(warehouseName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.receipt_long,
                            size: 16, color: Color(0xFF388E3C)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(inboundNo,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF1B5E20),
                                  letterSpacing: 1.0)),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.copy,
                              size: 18, color: Color(0xFF388E3C)),
                          tooltip: '复制单号',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: inboundNo));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('入库单号已复制'),
                                duration: Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    Text('$itemCount 个SKU · 共 $totalQty 件',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                  ],
                ),
              );
            }).toList(),
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
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 商品选择 ──
            _buildSectionHeader('📦 选择铺货商品', '已选 ${_selectedProductIds.length} 个'),
            const SizedBox(height: 10),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: _products.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                          child: Text('暂无商品，请先在"商品"页上架',
                              style: TextStyle(color: Colors.grey))),
                    )
                  : Column(
                      children: _products.map((product) {
                        final id = (product['id'] as num).toInt();
                        final selected = _selectedProductIds.contains(id);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selectedProductIds.add(id);
                            } else {
                              _selectedProductIds.remove(id);
                            }
                          }),
                          title: Text(product['name'] ?? '',
                              style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                            '¥${((product['retailPrice'] ?? product['price'] ?? 0) as num).toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Color(0xFF4CAF50), fontSize: 12),
                          ),
                          activeColor: const Color(0xFF4CAF50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        );
                      }).toList(),
                    ),
            ),

            const SizedBox(height: 20),

            // ── 仓库分配 ──
            _buildSectionHeader(
              '🏪 选择目标仓库',
              _warehouses.isEmpty ? '暂无可用仓库' : '共 ${_warehouses.length} 个仓库',
            ),
            const SizedBox(height: 10),

            if (_warehouses.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_outlined, color: Colors.orange[700]),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '暂无开放中的仓库\n请等待仓主注册并开放仓库',
                        style: TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._warehouses.map((w) {
                final wid = (w['id'] as num).toInt();
                final qty = _warehouseQuantities[wid] ?? 0;
                final typeColor = _warehouseTypeColor(w['type'] as String?);
                final typeLabel = _warehouseTypeLabel(w['type'] as String?);

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: typeColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(typeLabel,
                                  style: TextStyle(
                                      color: typeColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                w['name'] ?? '未命名仓库',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        if ((w['address'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 13, color: Colors.grey),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  w['address'] as String,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (w['areaSqm'] != null) ...[
                          const SizedBox(height: 2),
                          Text(
                              '面积：${w['areaSqm']} ㎡  · 服务费：¥${w['serviceFeeRate'] ?? '--'}/单',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('铺货数量：',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                            const SizedBox(width: 8),
                            _buildQtyButton(Icons.remove, () {
                              if (qty > 0) {
                                setState(() => _warehouseQuantities[wid] =
                                    qty - 10 < 0 ? 0 : qty - 10);
                              }
                            }),
                            Expanded(
                              child: Slider(
                                value: qty.toDouble().clamp(0, 500),
                                min: 0,
                                max: 500,
                                divisions: 50,
                                label: qty == 0 ? '不铺货' : '$qty件',
                                activeColor: qty == 0
                                    ? Colors.grey
                                    : const Color(0xFF4CAF50),
                                onChanged: (v) => setState(
                                    () => _warehouseQuantities[wid] = v.toInt()),
                              ),
                            ),
                            _buildQtyButton(Icons.add, () {
                              if (qty < 500) {
                                setState(() => _warehouseQuantities[wid] = qty + 10);
                              }
                            }),
                            SizedBox(
                              width: 48,
                              child: Text(
                                qty == 0 ? '跳过' : '$qty件',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: qty == 0
                                      ? Colors.grey
                                      : const Color(0xFF4CAF50),
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),

            const SizedBox(height: 20),

            // ── 汇总 ──
            if (_warehouses.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.summarize_outlined, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '铺货摘要',
                            style: TextStyle(
                                color: Colors.green[800],
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '商品 ${_selectedProductIds.length} 种 · '
                            '涉及 ${_warehouseQuantities.values.where((q) => q > 0).length} 个仓库 · '
                            '合计 $_totalQuantity 件',
                            style: TextStyle(
                                color: Colors.green[700], fontSize: 12),
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
                onPressed: _submitting ? null : _submitPlan,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_submitting ? '提交中...' : '提交铺货计划',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        Text(subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildQtyButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: Colors.grey[700]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Tab 2：入库进度列表
// ═══════════════════════════════════════════════
class _InboundProgressTab extends StatefulWidget {
  const _InboundProgressTab();

  @override
  State<_InboundProgressTab> createState() => _InboundProgressTabState();
}

class _InboundProgressTabState extends State<_InboundProgressTab> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ApiService().getReplenishmentList();
      if (resp['code'] == 200) {
        setState(() {
          _orders = (resp['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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

  // 状态对应的颜色和图标
  _StatusStyle _getStatusStyle(String? status) {
    switch (status) {
      case 'PENDING':
        return _StatusStyle('待入库', Colors.orange, Icons.hourglass_empty);
      case 'PROCESSING':
        return _StatusStyle('入库中', const Color(0xFF2196F3), Icons.inventory_outlined);
      case 'COMPLETED':
        return _StatusStyle('已完成', const Color(0xFF4CAF50), Icons.check_circle_outline);
      case 'CANCELLED':
        return _StatusStyle('已取消', Colors.grey, Icons.cancel_outlined);
      default:
        return _StatusStyle(status ?? '未知', Colors.grey, Icons.help_outline);
    }
  }

  String _formatTime(String? t) {
    if (t == null || t.isEmpty) return '--';
    // 裁剪毫秒 / T 格式兼容
    return t.replaceFirst('T', ' ').split('.').first;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
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
              onPressed: _loadOrders,
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
        onRefresh: _loadOrders,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('暂无入库单', style: TextStyle(color: Colors.grey, fontSize: 15)),
                  SizedBox(height: 6),
                  Text('提交铺货计划后，入库单将显示在这里',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        itemBuilder: (ctx, i) => _buildOrderCard(_orders[i]),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final inboundNo = order['inboundNo'] as String? ?? '--';
    final warehouseName = order['warehouseName'] as String? ?? '--';
    final status = order['status'] as String?;
    final style = _getStatusStyle(status);
    final createTime = _formatTime(order['createTime'] as String?);
    final completedAt = _formatTime(order['completedAt'] as String?);
    final itemCount = order['itemCount'] ?? 0;
    final totalPlanQty = order['totalPlanQty'] ?? 0;
    final products = (order['products'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 顶部：入库单号 + 状态徽章 ──
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long,
                          size: 16, color: Color(0xFF4CAF50)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          inboundNo,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              letterSpacing: 0.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 复制按钮
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: inboundNo));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('入库单号已复制'),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.copy,
                              size: 15, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
                // 状态徽章
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: style.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: style.color.withOpacity(0.4), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(style.icon, size: 13, color: style.color),
                      const SizedBox(width: 4),
                      Text(style.label,
                          style: TextStyle(
                              color: style.color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // ── 仓库 + 数量信息 ──
            Row(
              children: [
                const Icon(Icons.warehouse_outlined,
                    size: 15, color: Colors.grey),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(warehouseName,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
                Text('$itemCount 个SKU · 共 $totalPlanQty 件',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),

            const SizedBox(height: 6),

            // ── 时间信息 ──
            Row(
              children: [
                const Icon(Icons.access_time, size: 13, color: Colors.grey),
                const SizedBox(width: 5),
                Text('创建：$createTime',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (status == 'COMPLETED') ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.done_all, size: 13, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 3),
                  Text('完成：$completedAt',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF4CAF50))),
                ],
              ],
            ),

            // ── 商品明细（可展开） ──
            if (products.isNotEmpty) ...[
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text('查看商品明细（${products.length} 种）',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4CAF50),
                        fontWeight: FontWeight.w500)),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: products
                    .map((p) => _buildProductRow(p, status))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProductRow(Map<String, dynamic> p, String? orderStatus) {
    final name = p['productName'] as String? ?? '--';
    final planQty = p['planQty'] ?? 0;
    final actualQty = p['actualQty'];
    final hasActual = actualQty != null && orderStatus == 'COMPLETED';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 6, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          if (hasActual)
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '计划 $planQty',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                  const TextSpan(
                    text: ' → ',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  TextSpan(
                    text: '实入 $actualQty',
                    style: TextStyle(
                      fontSize: 11,
                      color: actualQty == planQty
                          ? const Color(0xFF4CAF50)
                          : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            Text('计划 $planQty 件',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
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

// ═══════════════════════════════════════════════
// Tab 3：出库管理（调拨 + 退货）
// 直接嵌入 OutboundPage 的两个子 Widget
// ═══════════════════════════════════════════════
class _OutboundManagementTab extends StatefulWidget {
  const _OutboundManagementTab();
  @override
  State<_OutboundManagementTab> createState() => _OutboundManagementTabState();
}

class _OutboundManagementTabState extends State<_OutboundManagementTab>
    with SingleTickerProviderStateMixin {
  late TabController _subTab;

  @override
  void initState() {
    super.initState();
    _subTab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _subTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF4CAF50).withOpacity(0.08),
          child: TabBar(
            controller: _subTab,
            indicatorColor: const Color(0xFF4CAF50),
            labelColor: const Color(0xFF2E7D32),
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: '发起出库', icon: Icon(Icons.outbox_outlined, size: 16)),
              Tab(text: '出库记录', icon: Icon(Icons.history_outlined, size: 16)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _subTab,
            children: const [
              _CreateOutboundSubTab(),
              _OutboundHistorySubTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── 出库 Sub-Tab 1：发起出库 ─────────────────────────────────────────
class _CreateOutboundSubTab extends StatefulWidget {
  const _CreateOutboundSubTab();
  @override
  State<_CreateOutboundSubTab> createState() => _CreateOutboundSubTabState();
}

class _CreateOutboundSubTabState extends State<_CreateOutboundSubTab> {
  String _outboundType = 'transfer';
  List<Map<String, dynamic>> _warehouses = [];
  Map<String, dynamic>? _selectedWarehouse;
  List<Map<String, dynamic>> _inventory = [];
  bool _loadingWarehouses = true;
  bool _loadingInventory = false;
  bool _submitting = false;
  Map<int, int> _selectedQty = {};
  final _remarkCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWarehouses() async {
    setState(() => _loadingWarehouses = true);
    try {
      final resp = await ApiService().getBrandWarehouseList();
      if (resp['code'] == 200) {
        final list = (resp['data'] as List? ?? [])
            .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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
    setState(() { _loadingInventory = true; _inventory = []; _selectedQty = {}; });
    try {
      final resp = await ApiService().getBrandOutboundInventory(warehouseId);
      if (resp['code'] == 200) {
        final list = (resp['data'] as List? ?? [])
            .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        setState(() {
          _inventory = list;
          _selectedQty = { for (final i in list) (i['productId'] as num).toInt(): 0 };
        });
      }
    } catch (_) {} finally {
      setState(() => _loadingInventory = false);
    }
  }

  int get _totalQty => _selectedQty.values.fold(0, (s, q) => s + q);

  double get _totalFee {
    double total = 0;
    for (final item in _inventory) {
      final pid = (item['productId'] as num).toInt();
      final qty = _selectedQty[pid] ?? 0;
      if (qty <= 0) continue;
      total += (double.tryParse(item['feePerUnit']?.toString() ?? '0') ?? 0) * qty;
    }
    return total;
  }

  Future<void> _submit() async {
    if (_selectedWarehouse == null) { _snack('请选择出库仓库', Colors.orange); return; }
    final selectedItems = _selectedQty.entries.where((e) => e.value > 0)
        .map((e) => {'productId': e.key, 'quantity': e.value}).toList();
    if (selectedItems.isEmpty) { _snack('请选择至少一件商品', Colors.orange); return; }

    setState(() => _submitting = true);
    try {
      final wid = (_selectedWarehouse!['id'] as num).toInt();
      final body = {
        'warehouseId': wid,
        'items': selectedItems,
        if (_outboundType == 'transfer') 'remark': _remarkCtrl.text.trim().isEmpty ? '品牌方调拨出库' : _remarkCtrl.text.trim(),
        if (_outboundType == 'return') 'reason': _remarkCtrl.text.trim().isEmpty ? '品牌方退货' : _remarkCtrl.text.trim(),
      };
      final resp = _outboundType == 'transfer'
          ? await ApiService().createTransferOrder(body)
          : await ApiService().createReturnOrder(body);

      if (resp['code'] == 200) {
        final data = resp['data'] as Map<String, dynamic>? ?? {};
        _showResult(data);
        setState(() { for (final k in _selectedQty.keys) _selectedQty[k] = 0; _remarkCtrl.clear(); });
      } else {
        _snack(resp['msg'] ?? '提交失败', Colors.red);
      }
    } catch (_) { _snack('网络错误，请重试', Colors.red); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  void _showResult(Map<String, dynamic> data) {
    final no = data['outboundNo'] as String? ?? '--';
    final wName = data['warehouseName'] as String? ?? '';
    final qty = data['totalPlanQty'] ?? 0;
    final fee = double.tryParse(data['totalStorageFee']?.toString() ?? '0') ?? 0;
    final typeText = _outboundType == 'transfer' ? '调拨出库' : '退货出库';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 24),
          const SizedBox(width: 8),
          Text('$typeText单已提交'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row('出库单号', no, bold: true),
          _row('仓库', wName),
          _row('出库数量', '$qty 件'),
          _row('仓储操作费', '¥${fee.toStringAsFixed(2)}', color: fee > 0 ? Colors.red : Colors.green),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!)),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.orange[700], size: 16),
              const SizedBox(width: 6),
              const Expanded(child: Text('等待仓主完成出库后，仓储费将从钱包扣除',
                  style: TextStyle(fontSize: 12, color: Colors.orange))),
            ]),
          ),
        ]),
        actions: [ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          onPressed: () => Navigator.pop(context),
          child: const Text('确认'),
        )],
      ),
    );
  }

  Widget _row(String label, String val, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey))),
      Expanded(child: Text(val, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color))),
    ]),
  );

  void _snack(String msg, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingWarehouses) return const Center(child: CircularProgressIndicator());
    if (_warehouses.isEmpty) return const Center(child: Text('暂无可用仓库', style: TextStyle(color: Colors.grey)));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 出库类型
        const Text('出库类型', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _typeCard(Icons.swap_horiz_outlined, '调拨出库', '将商品从仓库调出', 'transfer', const Color(0xFF2196F3))),
          const SizedBox(width: 10),
          Expanded(child: _typeCard(Icons.keyboard_return_outlined, '退货出库', '将商品退出仓库', 'return', const Color(0xFFFF9800))),
        ]),
        const SizedBox(height: 20),

        // 选择仓库
        const Text('选择仓库', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _warehouses.length,
            itemBuilder: (_, i) {
              final w = _warehouses[i];
              final sel = _selectedWarehouse != null &&
                  (_selectedWarehouse!['id'] as num).toInt() == (w['id'] as num).toInt();
              return GestureDetector(
                onTap: () { setState(() => _selectedWarehouse = w); _loadInventory((w['id'] as num).toInt()); },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFF4CAF50) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? const Color(0xFF4CAF50) : Colors.grey[300]!),
                  ),
                  child: Text(w['name'] as String? ?? '仓库',
                      style: TextStyle(color: sel ? Colors.white : Colors.black87, fontSize: 13,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),

        // 商品列表
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('选择商品', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          if (_totalQty > 0) Text('已选 $_totalQty 件', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        const SizedBox(height: 8),
        if (_loadingInventory)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        else if (_inventory.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!)),
            child: const Center(child: Text('该仓库暂无可出库商品', style: TextStyle(color: Colors.grey))),
          )
        else
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(children: _inventory.map((inv) {
              final pid = (inv['productId'] as num).toInt();
              final available = ((inv['availableQuantity'] ?? 0) as num).toInt();
              final qty = _selectedQty[pid] ?? 0;
              final storageDays = ((inv['storageDays'] ?? 0) as num).toInt();
              final billableDays = ((inv['billableDays'] ?? 0) as num).toInt();
              final feePerUnit = double.tryParse(inv['feePerUnit']?.toString() ?? '0') ?? 0;
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(inv['productName'] as String? ?? '--', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('可用：$available 件  · 在库 $storageDays 天', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      if (billableDays > 0)
                        Text('计费 $billableDays 天 · 单件仓储费 ¥${feePerUnit.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFFE65100)))
                      else
                        const Text('入库不足7天，暂无仓储费', style: TextStyle(fontSize: 12, color: Color(0xFF4CAF50))),
                    ])),
                    Row(children: [
                      _qBtn(Icons.remove, qty > 0 ? () => setState(() => _selectedQty[pid] = qty - 1) : null),
                      Container(width: 42, alignment: Alignment.center,
                          child: Text('$qty', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                              color: qty > 0 ? const Color(0xFF4CAF50) : Colors.grey))),
                      _qBtn(Icons.add, qty < available ? () => setState(() => _selectedQty[pid] = qty + 1) : null),
                    ]),
                  ]),
                  if (qty > 0) ...[
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerRight,
                        child: Text('此商品仓储费：¥${(feePerUnit * qty).toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFFE65100), fontWeight: FontWeight.w500))),
                  ],
                  if (inv != _inventory.last) const Divider(height: 16),
                ]),
              );
            }).toList()),
          ),
        const SizedBox(height: 20),

        // 备注
        Text(_outboundType == 'transfer' ? '调拨备注（选填）' : '退货原因（选填）',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _remarkCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: _outboundType == 'transfer' ? '请描述调拨目的或目标仓库...' : '请描述退货原因...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 20),

        // 费用预估
        if (_totalQty > 0)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _totalFee > 0 ? Colors.orange[50] : Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _totalFee > 0 ? Colors.orange[200]! : Colors.green[200]!),
            ),
            child: Row(children: [
              Icon(_totalFee > 0 ? Icons.account_balance_wallet_outlined : Icons.check_circle_outline,
                  color: _totalFee > 0 ? Colors.orange[700] : Colors.green),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('出库摘要', style: TextStyle(
                    color: _totalFee > 0 ? Colors.orange[800] : Colors.green[800],
                    fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text('共 $_totalQty 件 · 预计仓储操作费：¥${_totalFee.toStringAsFixed(2)}',
                    style: TextStyle(color: _totalFee > 0 ? Colors.orange[700] : Colors.green[700], fontSize: 12)),
                if (_totalFee > 0)
                  Text('费用说明：0.2元/件/天，入库后第7天开始计算',
                      style: TextStyle(color: Colors.orange[600], fontSize: 11)),
              ])),
            ]),
          ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton.icon(
            onPressed: (_submitting || _totalQty == 0) ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(_outboundType == 'transfer' ? Icons.swap_horiz : Icons.keyboard_return),
            label: Text(_submitting ? '提交中...' : (_outboundType == 'transfer' ? '提交调拨单' : '提交退货单'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _outboundType == 'transfer' ? const Color(0xFF2196F3) : const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _typeCard(IconData icon, String label, String sub, String type, Color color) =>
      GestureDetector(
        onTap: () => setState(() => _outboundType = type),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _outboundType == type ? color.withOpacity(0.1) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _outboundType == type ? color : Colors.grey[300]!,
                width: _outboundType == type ? 2 : 1),
          ),
          child: Column(children: [
            Icon(icon, color: _outboundType == type ? color : Colors.grey, size: 26),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: _outboundType == type ? color : Colors.black87,
                fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(color: _outboundType == type ? color.withOpacity(0.8) : Colors.grey,
                fontSize: 10), textAlign: TextAlign.center, maxLines: 2),
          ]),
        ),
      );

  Widget _qBtn(IconData icon, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: onTap != null ? Colors.grey[100] : Colors.grey[50],
          borderRadius: BorderRadius.circular(6)),
      child: Icon(icon, size: 16, color: onTap != null ? Colors.grey[700] : Colors.grey[300]),
    ),
  );
}

// ─── 出库 Sub-Tab 2：出库记录 ─────────────────────────────────────────
class _OutboundHistorySubTab extends StatefulWidget {
  const _OutboundHistorySubTab();
  @override
  State<_OutboundHistorySubTab> createState() => _OutboundHistorySubTabState();
}

class _OutboundHistorySubTabState extends State<_OutboundHistorySubTab> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await ApiService().getBrandOutboundList();
      if (resp['code'] == 200) {
        setState(() { _orders = (resp['data'] as List? ?? []).whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)).toList(); });
      } else { setState(() => _error = resp['msg'] ?? '加载失败'); }
    } catch (_) { setState(() => _error = '网络错误'); }
    finally { setState(() => _loading = false); }
  }

  Future<void> _cancel(int woid) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('取消出库单'),
      content: const Text('确认取消？取消后库存锁定将被释放。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('返回')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('确认取消')),
      ],
    ));
    if (ok != true) return;
    final resp = await ApiService().cancelOutboundOrder(woid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(resp['code'] == 200 ? '已取消' : (resp['msg'] ?? '失败')),
        backgroundColor: resp['code'] == 200 ? Colors.green : Colors.red));
    if (resp['code'] == 200) _load();
  }

  String _ft(String? t) => t == null ? '--' : t.replaceFirst('T', ' ').split('.').first;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: Colors.red),
      const SizedBox(height: 12),
      Text(_error!, style: const TextStyle(color: Colors.red)),
      const SizedBox(height: 16),
      ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('重试'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white)),
    ]));
    if (_orders.isEmpty) return RefreshIndicator(onRefresh: _load, child: ListView(children: const [
      SizedBox(height: 100),
      Center(child: Column(children: [
        Icon(Icons.outbox_outlined, size: 64, color: Colors.grey),
        SizedBox(height: 12),
        Text('暂无出库单', style: TextStyle(color: Colors.grey, fontSize: 15)),
      ])),
    ]));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        itemBuilder: (_, i) => _card(_orders[i]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> o) {
    final no = o['outboundNo'] as String? ?? '--';
    final typeText = o['typeText'] as String? ?? '--';
    final isTransfer = (o['type'] as num?)?.toInt() == 6;
    final typeColor = isTransfer ? const Color(0xFF2196F3) : const Color(0xFFFF9800);
    final status = o['status'] as String?;
    final stStyle = _ss(status);
    final wName = o['warehouseName'] as String? ?? '--';
    final qty = o['totalPlanQty'] ?? 0;
    final fee = double.tryParse(o['totalStorageFee']?.toString() ?? '0') ?? 0;
    final createTime = _ft(o['createTime'] as String?);
    final remark = o['remark'] as String? ?? '';
    final products = (o['products'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final canCancel = status == 'PENDING';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(typeText, style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(no, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: stStyle.color.withOpacity(0.12), borderRadius: BorderRadius.circular(20),
                border: Border.all(color: stStyle.color.withOpacity(0.4))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(stStyle.icon, size: 12, color: stStyle.color),
              const SizedBox(width: 3),
              Text(stStyle.label, style: TextStyle(color: stStyle.color, fontSize: 11, fontWeight: FontWeight.bold)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.warehouse_outlined, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(child: Text(wName, style: const TextStyle(fontSize: 13))),
          Text('$qty 件', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text('仓储操作费：¥${fee.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 12, color: fee > 0 ? Colors.red[700] : Colors.green[600])),
        ]),
        if (remark.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.notes_outlined, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Expanded(child: Text(remark, style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ],
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.access_time, size: 13, color: Colors.grey),
          const SizedBox(width: 4),
          Text('创建：$createTime', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        if (products.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text('查看明细（${products.length} 种）',
                style: const TextStyle(fontSize: 12, color: Color(0xFF4CAF50), fontWeight: FontWeight.w500)),
            children: products.map((p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(children: [
                const Icon(Icons.circle, size: 6, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text(p['productName'] as String? ?? '--',
                    style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                Text('${(p['planQuantity'] ?? 0)} 件  ¥${double.tryParse(p['storageFee']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00'}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            )).toList(),
          ),
        ],
        if (canCancel) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => _cancel(((o['workOrderId'] as num?)?.toInt() ?? 0)),
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('取消', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ),
        ],
      ])),
    );
  }

  _StatusStyle _ss(String? s) {
    switch (s) {
      case 'PENDING': return _StatusStyle('待出库', Colors.orange, Icons.hourglass_empty);
      case 'PROCESSING': return _StatusStyle('出库中', const Color(0xFF2196F3), Icons.outbox_outlined);
      case 'COMPLETED': return _StatusStyle('已完成', const Color(0xFF4CAF50), Icons.check_circle_outline);
      case 'CANCELLED': return _StatusStyle('已取消', Colors.grey, Icons.cancel_outlined);
      default: return _StatusStyle(s ?? '未知', Colors.grey, Icons.help_outline);
    }
  }
}
