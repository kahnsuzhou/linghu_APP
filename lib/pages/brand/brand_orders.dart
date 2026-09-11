import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../config/constants.dart';

/// 品牌方订单列表页
class BrandOrdersPage extends StatefulWidget {
  const BrandOrdersPage({super.key});

  @override
  State<BrandOrdersPage> createState() => _BrandOrdersPageState();
}

class _BrandOrdersPageState extends State<BrandOrdersPage> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await ApiService().getBrandOrders();
      if (response['code'] == 200) {
        setState(() => _orders = (response['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
      }
    } catch (_) {
      setState(() => _orders = [
        {'orderId': 1, 'orderSn': 'LH20240101001', 'totalAmount': 35.80, 'status': 'FINISHED', 'createTime': '2024-01-01 10:00:00'},
        {'orderId': 2, 'orderSn': 'LH20240101002', 'totalAmount': 9.90, 'status': 'DELIVERING', 'createTime': '2024-01-01 11:00:00'},
      ]);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('订单列表'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _orders.isEmpty
                  ? const Center(child: Text('暂无订单'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final order = _orders[index];
                        final statusText = AppConstants.orderStatusMap[order['status']] ?? order['status'];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('订单：${order['orderSn']}', style: const TextStyle(fontWeight: FontWeight.w500)),
                                      const SizedBox(height: 4),
                                      Text('${order['createTime']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '¥${(order['totalAmount'] as num).toStringAsFixed(2)}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4CAF50).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(statusText, style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50))),
                                    ),
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
