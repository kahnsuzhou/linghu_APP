import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'external_picking_detail.dart';

/// 外单拣货列表页（仓端）
class ExternalPickingListPage extends StatefulWidget {
  const ExternalPickingListPage({super.key});

  @override
  State<ExternalPickingListPage> createState() => _ExternalPickingListPageState();
}

class _ExternalPickingListPageState extends State<ExternalPickingListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // 后端 status: 1=库存锁定(待拣货), 2=拣货中, 3=已发货, 4=异常
  final List<String> _tabs = ['全部', '待拣货', '拣货中', '已发货', '异常'];
  final List<String?> _statusKeys = [null, '1', '2', '3', '4'];

  final Map<String, List<Map<String, dynamic>>> _dataCache = {};
  final Map<String, bool> _loadingMap = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadTab(_statusKeys[_tabController.index]);
      }
    });
    _loadTab(null);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _cacheKey(String? status) => status ?? 'all';

  Future<void> _loadTab(String? status) async {
    final key = _cacheKey(status);
    if (_loadingMap[key] == true) return;
    setState(() => _loadingMap[key] = true);
    try {
      final resp = await ApiService().getExternalPickingList(status: status);
      if (mounted) {
        setState(() {
          // 后端返回分页结构 {total, list} 或直接数组
          final data = resp['data'];
          final rawList = data is Map
              ? (data['list'] as List? ?? [])
              : (data as List? ?? []);
          _dataCache[key] = rawList
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _dataCache[key] = []);
    } finally {
      if (mounted) setState(() => _loadingMap[key] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('外单拣货'),
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadTab(_statusKeys[_tabController.index]),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: List.generate(_tabs.length, (i) {
          return _buildTabContent(_statusKeys[i]);
        }),
      ),
    );
  }

  Widget _buildTabContent(String? status) {
    final key = _cacheKey(status);
    final loading = _loadingMap[key] == true;
    final list = _dataCache[key];

    if (loading && list == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final orders = list ?? [];

    return RefreshIndicator(
      onRefresh: () => _loadTab(status),
      child: orders.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('暂无外单', style: TextStyle(color: Colors.grey, fontSize: 15)),
                    ],
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _buildOrderCard(orders[i]),
            ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    // 后端返回数字状态
    final statusInt = (order['status'] as num?)?.toInt() ?? 1;
    final channel = order['channel'] as String? ?? '';
    final externalNo = order['externalOrderNo'] as String? ?? '--';
    final productName = order['productName'] as String? ?? order['skuCode'] ?? '--';
    final skuCode = order['skuCode'] as String? ?? '';
    final quantity = (order['quantity'] as num?)?.toInt() ?? 0;
    final receiverName = order['receiverName'] as String? ?? '';
    final receiverPhone = order['receiverPhone'] as String? ?? '';
    final receiverAddress = order['receiverAddress'] as String? ?? '';
    final exceptionReason = order['exceptionReason'] as String?;
    final createTime = order['createTime'] as String? ?? '';

    final statusConfig = _getStatusConfig(statusInt);
    final channelConfig = _getChannelConfig(channel);
    // 待拣货(1)和拣货中(2)可操作
    final canAct = statusInt == 1 || statusInt == 2;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExternalPickingDetailPage(workOrder: order),
          ),
        ).then((_) => _loadTab(_statusKeys[_tabController.index])),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：渠道标签 + 外单号 + 状态
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: channelConfig['color'] as Color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(channelConfig['icon'] as String,
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 3),
                        Text(channelConfig['label'] as String,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B1FA2).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF7B1FA2).withOpacity(0.4)),
                    ),
                    child: const Text('外单',
                        style: TextStyle(
                            fontSize: 10, color: Color(0xFF7B1FA2), fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (statusConfig['color'] as Color).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: (statusConfig['color'] as Color).withOpacity(0.4)),
                    ),
                    child: Text(statusConfig['label'] as String,
                        style: TextStyle(
                            fontSize: 11,
                            color: statusConfig['color'] as Color,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 外单号
              Row(children: [
                const Icon(Icons.receipt_long_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('外单号：$externalNo',
                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'monospace'),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 6),
              // 商品信息
              Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 14, color: Color(0xFF7B1FA2)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(productName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (skuCode.isNotEmpty)
                          Text(skuCode,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                  Text('× $quantity',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF7B1FA2), fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              // 收件人 + 地址
              Row(children: [
                const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text('$receiverName  $receiverPhone',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
              if (receiverAddress.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(receiverAddress,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ],
              const SizedBox(height: 3),
              Text('下单：$createTime',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),

              // 异常原因
              if (exceptionReason != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(exceptionReason,
                          style: const TextStyle(fontSize: 12, color: Colors.red)),
                    ),
                  ]),
                ),
              ],

              // 底部操作按钮
              if (canAct) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExternalPickingDetailPage(workOrder: order),
                        ),
                      ).then((_) => _loadTab(_statusKeys[_tabController.index])),
                      icon: Icon(
                        statusInt == 2 ? Icons.local_shipping_outlined : Icons.inventory_outlined,
                        size: 16,
                      ),
                      label: Text(statusInt == 2 ? '继续发货' : '开始拣货',
                          style: const TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: statusInt == 2 ? Colors.orange : const Color(0xFF7B1FA2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getStatusConfig(int status) {
    switch (status) {
      case 1: return {'label': '待拣货', 'color': Colors.orange};
      case 2: return {'label': '拣货中', 'color': const Color(0xFF2196F3)};
      case 3: return {'label': '已发货', 'color': Colors.green};
      case 4: return {'label': '异常', 'color': Colors.red};
      default: return {'label': '未知', 'color': Colors.grey};
    }
  }

  Map<String, dynamic> _getChannelConfig(String channel) {
    switch (channel) {
      case 'taobao': return {'label': '淘宝', 'icon': '🛍', 'color': const Color(0xFFFF6900)};
      case 'jd':     return {'label': '京东', 'icon': '🐶', 'color': const Color(0xFFE01831)};
      case 'douyin': return {'label': '抖音', 'icon': '🎵', 'color': const Color(0xFF161823)};
      case 'pdd':    return {'label': '拼多多', 'icon': '🛒', 'color': const Color(0xFFE02020)};
      default:       return {'label': '其他', 'icon': '📦', 'color': Colors.grey};
    }
  }
}
