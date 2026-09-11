import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../main.dart';
import '../../services/api_service.dart';
import '../../utils/event_bus.dart';
import 'picking_detail.dart';
import 'inbound_detail.dart';
import 'pickup_verification.dart';
import 'complaint_warehouse.dart';
import 'external_picking_list.dart';

/// 仓主工作台
class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key});

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  List<Map<String, dynamic>> _pickingOrders = [];
  List<Map<String, dynamic>> _inboundOrders = [];
  List<Map<String, dynamic>> _outboundOrders = [];
  int _externalPendingCount = 0; // 外单待处理数量
  bool _loading = false;
  late StreamSubscription _pickingSubscription;
  late StreamSubscription _inboundSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();

    // 监听 WebSocket 消息
    _pickingSubscription = eventBus.on<NewPickingOrderEvent>().listen((_) {
      _loadData();
      _showNotification('收到新的拣货任务！');
    });
    _inboundSubscription = eventBus.on<NewInboundOrderEvent>().listen((_) {
      _loadData();
      _showNotification('收到新的入库任务！');
    });
  }

  @override
  void dispose() {
    _pickingSubscription.cancel();
    _inboundSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().getPickingList(),
        ApiService().getInboundList(),
        ApiService().getWarehouseOutboundList(),
      ]);
      setState(() {
        _pickingOrders = (results[0]['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _inboundOrders = (results[1]['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _outboundOrders = (results[2]['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        // 统计外单数量
        _externalPendingCount = _pickingOrders.where((o) => (o['sourceType'] as num?)?.toInt() == 1).length;
      });
    } catch (_) {
      // 使用 mock 数据
      setState(() {
        _pickingOrders = _getMockPickingOrders();
        _inboundOrders = _getMockInboundOrders();
        _outboundOrders = [];
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _getMockPickingOrders() {
    return [
      {'workOrderId': 1, 'orderNo': 'LH20240101001', 'status': 'PENDING', 'totalQuantity': 3, 'scannedQuantity': 0, 'itemCount': 2},
      {'workOrderId': 2, 'orderNo': 'LH20240101002', 'status': 'PROCESSING', 'totalQuantity': 5, 'scannedQuantity': 2, 'itemCount': 3},
    ];
  }

  List<Map<String, dynamic>> _getMockInboundOrders() {
    return [
      {
        'id': 101, 'orderNo': 'RK20240101001', 'status': 'PENDING',
        'items': [
          {'productId': 1, 'productName': '灵狐有机牛奶 250ml', 'planQuantity': 20, 'actualQuantity': 20},
          {'productId': 2, 'productName': '灵狐坚果混合装 200g', 'planQuantity': 10, 'actualQuantity': 10},
        ],
      },
      {
        'id': 102, 'orderNo': 'RK20240101002', 'status': 'PROCESSING',
        'items': [
          {'productId': 3, 'productName': '灵狐绿茶 500ml', 'planQuantity': 15, 'actualQuantity': 15},
        ],
      },
    ];
  }

  void _showNotification(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF2196F3),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = context.watch<AppState>().username ?? '仓主';

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作台'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_outlined),
            tooltip: '按入库单号查询',
            onPressed: _queryByInboundNo,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 欢迎卡片
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2196F3), Color(0xFF64B5F6)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.white30,
                            child: Icon(Icons.warehouse, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('欢迎，$username', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              const Text('今日待办任务', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 待办统计
                    Row(
                      children: [
                        _buildStatCard('待拣货', _pickingOrders.length, Icons.local_shipping, Colors.orange),
                        const SizedBox(width: 8),
                        _buildStatCard('待入库', _inboundOrders.length, Icons.inbox, Colors.green),
                        const SizedBox(width: 8),
                        _buildStatCard('待出库', _outboundOrders.length, Icons.outbox_outlined, Colors.purple),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 外单通快捷入口
                    _buildExternalOrderEntryCard(),
                    const SizedBox(height: 8),
                    // 自提核销快捷入口
                    _buildPickupEntryCard(),
                    const SizedBox(height: 8),
                    // 槽点快捷入口
                    _buildComplaintEntryCard(),
                    const SizedBox(height: 20),
                    // 拣货任务列表
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('拣货任务', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('${_pickingOrders.length}个待处理', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_pickingOrders.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('暂无拣货任务', style: TextStyle(color: Colors.grey))),
                        ),
                      )
                    else
                      ...(_pickingOrders.map((order) => _buildPickingCard(order))),
                    if (_inboundOrders.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('入库任务', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('${_inboundOrders.length}个待处理', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...(_inboundOrders.map((order) => _buildInboundCard(order))),
                    ] else ...[
                      const SizedBox(height: 20),
                      const Text('入库任务', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('暂无入库任务', style: TextStyle(color: Colors.grey))),
                        ),
                      ),
                    ],
                    // 出库任务（调拨 + 退货）
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('出库任务', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('${_outboundOrders.length}个待处理', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_outboundOrders.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('暂无出库任务', style: TextStyle(color: Colors.grey))),
                        ),
                      )
                    else
                      ...(_outboundOrders.map((order) => _buildOutboundCard(order))),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildOutboundCard(Map<String, dynamic> order) {
    final isProcessing = order['status'] == 'PROCESSING';
    final typeText = order['typeText'] as String? ?? '出库';
    final isTransfer = (order['type'] as num?)?.toInt() == 6;
    final typeColor = isTransfer ? const Color(0xFF2196F3) : const Color(0xFFFF9800);
    final outboundNo = order['outboundNo'] as String? ?? '--';
    final brandName = order['brandName'] as String? ?? '';
    final totalQty = ((order['totalPlanQty'] ?? 0) as num).toInt();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: typeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isTransfer ? Icons.swap_horiz : Icons.keyboard_return,
            color: typeColor,
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: typeColor.withOpacity(0.4)),
              ),
              child: Text(typeText,
                  style: TextStyle(
                      fontSize: 11,
                      color: typeColor,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(outboundNo,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (brandName.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.storefront_outlined, size: 12, color: Colors.grey),
                const SizedBox(width: 3),
                Text(brandName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ],
            const SizedBox(height: 2),
            Text('共 $totalQty 件',
                style: TextStyle(fontSize: 12, color: typeColor)),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _handleOutbound(order),
          style: ElevatedButton.styleFrom(
            backgroundColor: isProcessing ? Colors.orange : typeColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(isProcessing ? '继续' : '开始'),
        ),
      ),
    );
  }

  Future<void> _handleOutbound(Map<String, dynamic> order) async {
    final workOrderId = ((order['workOrderId'] ?? order['id']) as num?)?.toInt() ?? 0;
    final isProcessing = order['status'] == 'PROCESSING';
    final typeText = order['typeText'] as String? ?? '出库';

    if (!isProcessing) {
      // 开始出库
      try {
        final resp = await ApiService().startOutbound(workOrderId);
        if (!mounted) return;
        if (resp['code'] != 200) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(resp['msg'] ?? '操作失败'), backgroundColor: Colors.red));
          return;
        }
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('网络错误'), backgroundColor: Colors.red));
        return;
      }
    }

    // 弹出确认完成对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.outbox_outlined, color: Color(0xFF2196F3)),
          const SizedBox(width: 8),
          Text('确认$typeText完成'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('出库单号：${order['outboundNo'] ?? '--'}',
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text('数量：${order['totalPlanQty'] ?? 0} 件',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('完成后将自动扣减库存并结算仓储费',
                    style: TextStyle(fontSize: 12, color: Colors.orange)),
              ),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认完成出库'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      final resp = await ApiService().completeOutbound(workOrderId);
      if (!mounted) return;
      if (resp['code'] == 200) {
        final data = resp['data'] as Map<String, dynamic>? ?? {};
        final fee = data['totalStorageFee']?.toString() ?? '0';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('出库完成！仓储费 ¥$fee 已结算'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ));
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(resp['msg'] ?? '完成失败'), backgroundColor: Colors.red));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络错误'), backgroundColor: Colors.red));
    }
  }

  Widget _buildComplaintEntryCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WarehouseComplaintListPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.chat_bubble_outline, color: Colors.red, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('用户槽点',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text('查看用户反馈 · 及时回复处理',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExternalOrderEntryCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExternalPickingListPage()),
        ).then((_) => _loadData()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link, color: Color(0xFF7B1FA2), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('外单拣货',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      if (_externalPendingCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$_externalPendingCount',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      _externalPendingCount > 0
                          ? '有 $_externalPendingCount 单待拣货，作业费上浮20%'
                          : '淘宝/京东/抖音/拼多多外单配发 · 作业费上浮20%',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickupEntryCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PickupVerificationPage()),
        ).then((_) => _loadData()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepOrange[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.qr_code_scanner, color: Colors.deepOrange, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('自提核销',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text('查看待核销订单 / 输码核销自提',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int count, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickingCard(Map<String, dynamic> order) {
    final isProcessing = order['status'] == 'PROCESSING';
    final progress = order['totalQuantity'] > 0
        ? (order['scannedQuantity'] as num) / (order['totalQuantity'] as num)
        : 0.0;
    final deliveryMode = order['deliveryMode'] as String? ?? 'express';
    final sourceType = (order['sourceType'] as num?)?.toInt() ?? 0;
    final isExternal = sourceType == 1;
    final externalOrderNo = order['externalOrderNo'] as String?;

    // 配送方式标签配置
    final modeConfig = {
      'express': {'label': '快递', 'color': const Color(0xFF2196F3), 'icon': Icons.local_shipping_outlined},
      'delivery': {'label': '外卖', 'color': const Color(0xFFFF6B35), 'icon': Icons.delivery_dining_outlined},
      'pickup': {'label': '自提', 'color': const Color(0xFF4CAF50), 'icon': Icons.store_outlined},
    };
    final mode = modeConfig[deliveryMode] ?? modeConfig['express'] ?? {'label': '快递', 'color': const Color(0xFF2196F3), 'icon': Icons.local_shipping_outlined};
    final modeColor = (mode['color'] as Color?) ?? const Color(0xFF2196F3);
    final modeLabel = (mode['label'] as String?) ?? '快递';
    final modeIcon = (mode['icon'] as IconData?) ?? Icons.local_shipping_outlined;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isExternal
                    ? Colors.purple[50]
                    : isProcessing ? Colors.orange[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isExternal ? Icons.link : Icons.local_shipping,
                color: isExternal
                    ? const Color(0xFF7B1FA2)
                    : isProcessing ? Colors.orange : const Color(0xFF2196F3),
              ),
            ),
            title: Row(
              children: [
                // 外单标签
                if (isExternal) ...
                  [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B1FA2).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF7B1FA2).withOpacity(0.4)),
                      ),
                      child: const Text('外单',
                          style: TextStyle(
                              fontSize: 10, color: Color(0xFF7B1FA2),
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                Expanded(
                  child: Text(
                    isExternal && externalOrderNo != null
                        ? '外单：$externalOrderNo'
                        : '订单: ${order['orderNo'] ?? ''}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                // 配送方式标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: modeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: modeColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(modeIcon, size: 12, color: modeColor),
                      const SizedBox(width: 3),
                      Text(modeLabel, style: TextStyle(fontSize: 11, color: modeColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('共${order['itemCount']}种商品，${order['totalQuantity']}件',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (isProcessing)
                  LinearProgressIndicator(value: progress.toDouble(), backgroundColor: Colors.grey[200], color: Colors.orange),
              ],
            ),
            trailing: ElevatedButton(
                  onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PickingDetailPage(workOrder: order),
                ),
              ).then((_) => _loadData()),
              style: ElevatedButton.styleFrom(
                backgroundColor: isExternal
                    ? const Color(0xFF7B1FA2)
                    : isProcessing ? Colors.orange : const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(isProcessing ? '继续' : '开始'),
            ),
          ),
        ],
      ),
    );
  }

  /// 按入库单号查询并跳转
  Future<void> _queryByInboundNo() async {
    final controller = TextEditingController();
    final inboundNo = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('按入库单号查询'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('输入品牌方提供的入库单号（RK开头）',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'RK20260510xxxxxx',
                prefixIcon: const Icon(Icons.receipt_long),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (v) => Navigator.pop(context, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('查询'),
          ),
        ],
      ),
    );
    if (inboundNo == null || inboundNo.isEmpty) return;
    try {
      final res = await ApiService().queryInboundByNo(inboundNo);
      if (!mounted) return;
      if (res['code'] == 200) {
        final workOrder = res['data'] as Map<String, dynamic>;
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => InboundDetailPage(workOrder: workOrder)),
        ).then((_) => _loadData());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['msg'] ?? '未找到该入库单'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('查询失败，请重试'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Widget _buildInboundCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? 'PENDING';
    final isProcessing = status == 'PROCESSING';
    final orderId = order['id'] ?? order['workOrderId'];
    // 优先显示入库单号，其次显示 orderNo
    final inboundNo = order['inboundNo'] as String?;
    final displayNo = inboundNo ?? order['orderNo'] as String? ?? '#$orderId';
    final brandName = order['brandName'] as String? ?? '';
    final warehouseName = order['warehouseName'] as String? ?? '';
    final itemCount = (order['itemCount'] as num?)?.toInt() ?? 0;
    final totalPlanQty = (order['totalPlanQty'] as num?)?.toInt() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isProcessing ? Colors.orange[50] : Colors.green[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.inbox, color: isProcessing ? Colors.orange : Colors.green),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text('入库单：$displayNo',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isProcessing ? Colors.orange[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isProcessing ? Colors.orange[200]! : Colors.green[200]!,
                ),
              ),
              child: Text(
                isProcessing ? '处理中' : '待入库',
                style: TextStyle(
                  fontSize: 11,
                  color: isProcessing ? Colors.orange[700] : Colors.green[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (brandName.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.storefront_outlined, size: 12, color: Colors.grey),
                const SizedBox(width: 3),
                Text(brandName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ],
            if (warehouseName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.warehouse_outlined, size: 12, color: Colors.grey),
                const SizedBox(width: 3),
                Text(warehouseName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ],
            if (itemCount > 0 || totalPlanQty > 0) ...[
              const SizedBox(height: 2),
              Text(
                '$itemCount 种商品 · 共 $totalPlanQty 件',
                style: const TextStyle(fontSize: 12, color: Color(0xFF4CAF50)),
              ),
            ],
          ],
        ),
        isThreeLine: brandName.isNotEmpty || warehouseName.isNotEmpty,
        trailing: ElevatedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InboundDetailPage(workOrder: order),
            ),
          ).then((_) => _loadData()),
          style: ElevatedButton.styleFrom(
            backgroundColor: isProcessing ? Colors.orange : Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(isProcessing ? '继续入库' : '开始入库'),
        ),
      ),
    );
  }
}
