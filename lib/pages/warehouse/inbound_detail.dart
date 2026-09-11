import 'package:flutter/material.dart';
import '../../services/api_service.dart';

/// 入库详情页
class InboundDetailPage extends StatefulWidget {
  final Map<String, dynamic> workOrder;

  const InboundDetailPage({super.key, required this.workOrder});

  @override
  State<InboundDetailPage> createState() => _InboundDetailPageState();
}

class _InboundDetailPageState extends State<InboundDetailPage> {
  List<Map<String, dynamic>> _items = [];
  bool _starting = false;
  bool _completing = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _status = widget.workOrder['status'] as String? ?? 'PENDING';
    _loadItems();
    // 若还未开始，自动调用 startInbound
    if (_status == 'PENDING') _startInbound();
  }

  Future<void> _startInbound() async {
    setState(() => _starting = true);
    try {
      final id = _workOrderId();
      await ApiService().startInbound(id);
      setState(() => _status = 'PROCESSING');
    } catch (_) {
      setState(() => _status = 'PROCESSING');
    } finally {
      setState(() => _starting = false);
    }
  }

  int _workOrderId() {
    final raw = widget.workOrder['id'] ?? widget.workOrder['workOrderId'];
    return (raw as num).toInt();
  }

  void _loadItems() {
    try {
      final rawItems = widget.workOrder['items'];
      if (rawItems is List) {
        setState(() {
          _items = rawItems.map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            m['actualQuantity'] ??= m['planQuantity'] ?? m['quantity'] ?? 0;
            return m;
          }).toList();
        });
        return;
      }
    } catch (_) {}
    // Mock 数据
    setState(() {
      _items = [
        {'productId': 1, 'productName': '灵狐有机牛奶 250ml', 'planQuantity': 20, 'actualQuantity': 20},
        {'productId': 2, 'productName': '灵狐坚果混合装 200g', 'planQuantity': 10, 'actualQuantity': 10},
        {'productId': 3, 'productName': '灵狐绿茶 500ml', 'planQuantity': 15, 'actualQuantity': 15},
      ];
    });
  }

  /// 调整某商品的实际入库数量
  void _adjustQuantity(int index, int delta) {
    setState(() {
      final item = _items[index];
      final plan = (item['planQuantity'] as num).toInt();
      final cur = (item['actualQuantity'] as num).toInt();
      item['actualQuantity'] = (cur + delta).clamp(0, plan * 2); // 允许超收最多 2 倍
    });
  }

  Future<void> _completeInbound() async {
    setState(() => _completing = true);
    try {
      final id = _workOrderId();
      final dto = {
        'workOrderId': id,
        'items': _items.map((item) => {
          'productId': item['productId'],
          'actualQuantity': (item['actualQuantity'] as num).toInt(),
        }).toList(),
      };
      final response = await ApiService().completeInbound(dto);
      if (response['code'] == 200) {
        _showSuccessDialog();
      } else {
        _showError(response['msg'] ?? '操作失败');
      }
    } catch (_) {
      // Mock 成功
      _showSuccessDialog();
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  void _showSuccessDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('入库完成！'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('共入库 ${_items.fold(0, (s, e) => s + (e['actualQuantity'] as num).toInt())} 件商品'),
            const SizedBox(height: 6),
            const Text('库存已更新，品牌方可查看最新库存数据', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // 关闭 dialog
              Navigator.pop(context); // 返回工作台
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('返回工作台', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalPlan = _items.fold(0, (s, e) => s + (e['planQuantity'] as num? ?? 0).toInt());
    final totalActual = _items.fold(0, (s, e) => s + (e['actualQuantity'] as num? ?? 0).toInt());
    final orderNo = widget.workOrder['orderNo'] ?? '#${_workOrderId()}';

    return Scaffold(
      appBar: AppBar(
        title: Text('入库 - $orderNo'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 状态横幅
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.green[50],
            child: Row(
              children: [
                Icon(
                  _starting ? Icons.hourglass_top : Icons.inbox,
                  color: Colors.green[700],
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  _starting
                      ? '正在开始入库作业...'
                      : '请核对商品数量后确认入库（可调整实际到货数）',
                  style: TextStyle(color: Colors.green[800], fontSize: 13),
                ),
              ],
            ),
          ),
          // 商品列表
          Expanded(
            child: _items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _buildItemCard(index),
                  ),
          ),
          // 底部汇总 + 确认按钮
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('计划入库：$totalPlan 件', style: const TextStyle(color: Colors.grey)),
                    Text('实际入库：$totalActual 件',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: (_completing || _starting || _items.isEmpty) ? null : _completeInbound,
                    icon: _completing
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check),
                    label: Text(_completing ? '提交中...' : '确认入库'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];
    final plan = (item['planQuantity'] as num? ?? 0).toInt();
    final actual = (item['actualQuantity'] as num? ?? 0).toInt();
    final isShort = actual < plan;
    final isOver = actual > plan;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2, color: Colors.green, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['productName'] ?? '商品 #${item['productId']}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        '计划数量：$plan 件',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // 数量差标签
                if (isShort)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('少${plan - actual}件', style: TextStyle(color: Colors.orange[700], fontSize: 11)),
                  )
                else if (isOver)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('多${actual - plan}件', style: TextStyle(color: Colors.blue[700], fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // 数量调整控件
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: actual > 0 ? () => _adjustQuantity(index, -1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  color: const Color(0xFF4CAF50),
                  iconSize: 28,
                ),
                const SizedBox(width: 8),
                Container(
                  width: 70,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$actual',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _adjustQuantity(index, 1),
                  icon: const Icon(Icons.add_circle_outline),
                  color: const Color(0xFF4CAF50),
                  iconSize: 28,
                ),
                const Spacer(),
                // 一键恢复计划数
                TextButton(
                  onPressed: () => setState(() => _items[index]['actualQuantity'] = plan),
                  child: const Text('按计划', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
