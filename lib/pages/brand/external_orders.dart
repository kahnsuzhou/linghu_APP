import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import 'external_batch_import.dart';
import 'external_batch_list.dart';

/// 品牌方外单管理页
class BrandExternalOrdersPage extends StatefulWidget {
  const BrandExternalOrdersPage({super.key});

  @override
  State<BrandExternalOrdersPage> createState() => _BrandExternalOrdersPageState();
}

class _BrandExternalOrdersPageState extends State<BrandExternalOrdersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // status: 0=待处理 1=库存锁定 2=拣货中 3=已发货 4=异常 5=已取消
  final List<String> _tabs = ['全部', '库存锁定', '拣货中', '已发货', '异常', '已取消'];
  final List<String?> _statusKeys = [null, '1', '2', '3', '4', '5'];

  final Map<String, List<Map<String, dynamic>>> _dataCache = {};
  final Map<String, bool> _loadingMap = {};

  // 仓库名缓存 warehouseId -> warehouseName
  final Map<int, String> _warehouseNames = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadTab(_statusKeys[_tabController.index]);
      }
    });
    _loadWarehouseNames();
    _loadTab(null); // 全部
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 加载仓库名称列表
  Future<void> _loadWarehouseNames() async {
    try {
      final resp = await ApiService().get('/api/brand/warehouse/list');
      final list = resp['data'] as List? ?? [];
      for (final w in list) {
        if (w is Map) {
          final id = (w['id'] as num?)?.toInt();
          final name = w['name'] as String?;
          if (id != null && name != null) {
            _warehouseNames[id] = name;
          }
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      // 忽略，降级显示ID
    }
  }

  String _tabCacheKey(String? status) => status ?? 'all';

  Future<void> _loadTab(String? status) async {
    final key = _tabCacheKey(status);
    if (_loadingMap[key] == true) return;
    setState(() => _loadingMap[key] = true);
    try {
      final resp = await ApiService().getBrandExternalOrders(
        status: status,
      );
      if (mounted) {
        setState(() {
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
      if (mounted) {
        setState(() => _dataCache[key] = []);
      }
    } finally {
      if (mounted) setState(() => _loadingMap[key] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('外单管理'),
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        actions: [
          // 批次记录
          IconButton(
            icon: const Icon(Icons.history_outlined),
            tooltip: '导入批次记录',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ExternalBatchListPage()),
              );
            },
          ),
          // 批量导入
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: '批量导入外单',
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) => const ExternalBatchImportPage()),
              );
              if (result == true) {
                _loadTab(_statusKeys[_tabController.index]);
              }
            },
          ),
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
    final key = _tabCacheKey(status);
    final loading = _loadingMap[key] == true;
    final list = _dataCache[key];

    if (loading && list == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final orders = list ?? [];

    return RefreshIndicator(
      onRefresh: () => _loadTab(status),
      child: orders.isEmpty
          ? ListView(children: const [
              SizedBox(height: 120),
              Center(
                child: Column(children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('暂无外单', style: TextStyle(color: Colors.grey, fontSize: 15)),
                ]),
              ),
            ])
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _buildOrderCard(orders[i]),
            ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final statusInt = (order['status'] as num?)?.toInt() ?? 0;
    final channel = order['channel'] as String? ?? '';
    final externalNo = order['externalOrderNo'] as String? ?? '--';
    final productName = order['productName'] as String? ?? '--';
    final skuCode = order['skuCode'] as String? ?? '';
    final quantity = (order['quantity'] as num?)?.toInt() ?? 0;
    final receiverName = order['receiverName'] as String? ?? '';
    final receiverAddress = order['receiverAddress'] as String? ?? '';
    final logisticsNo = order['logisticsNo'] as String?;
    final logisticsCompany = order['logisticsCompany'] as String?;
    final exceptionReason = order['exceptionReason'] as String?;
    final createTime = order['createTime'] as String? ?? '';
    final warehouseId = (order['warehouseId'] as num?)?.toInt();
    final warehouseName = warehouseId != null
        ? (_warehouseNames[warehouseId] ?? '仓库#$warehouseId')
        : null;

    final statusConfig = _getStatusConfig(statusInt);
    final channelConfig = _getChannelConfig(channel);
    final canCancel = statusInt == 0 || statusInt == 1; // 待处理(0)或库存锁定(1)可取消

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：渠道 + 状态
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: channelConfig['color'] as Color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${channelConfig['icon']} ${channelConfig['label']}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
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
            // 外单号（可复制）
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: externalNo));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制外单号'), duration: Duration(seconds: 2)),
                );
              },
              child: Row(children: [
                const Icon(Icons.receipt_long_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(externalNo,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey, fontFamily: 'monospace')),
                const SizedBox(width: 4),
                const Icon(Icons.copy_outlined, size: 12, color: Colors.grey),
              ]),
            ),
            const SizedBox(height: 6),
            // 商品
            Row(
              children: [
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
            const SizedBox(height: 4),
            // 收件人 + 时间
            Text('收件人：$receiverName  下单：$createTime',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (receiverAddress.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 12, color: Colors.grey),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(receiverAddress,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ],

            // 仓库信息（库存已锁定后显示）
            if (warehouseName != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B1FA2).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF7B1FA2).withOpacity(0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.warehouse_outlined, size: 14, color: Color(0xFF7B1FA2)),
                  const SizedBox(width: 6),
                  Text('分配仓库：$warehouseName',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7B1FA2),
                          fontWeight: FontWeight.w500)),
                ]),
              ),
            ],

            // 物流信息（已发货）
            if (logisticsNo != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(children: [
                  const Icon(Icons.local_shipping_outlined, size: 14, color: Colors.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('$logisticsCompany  $logisticsNo',
                        style: const TextStyle(fontSize: 12, color: Colors.green)),
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: logisticsNo));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制运单号'), duration: Duration(seconds: 2)),
                      );
                    },
                    child: const Text('复制',
                        style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            ],

            // 异常原因
            if (exceptionReason != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, size: 14, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('异常：$exceptionReason',
                        style: const TextStyle(fontSize: 12, color: Colors.red)),
                  ),
                ]),
              ),
            ],

            // 取消按钮
            if (canCancel) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => _cancelOrder(order),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('取消外单',
                      style: TextStyle(fontSize: 12, color: Colors.red)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.cancel_outlined, color: Colors.red),
          SizedBox(width: 8),
          Text('取消外单'),
        ]),
        content: Text('确认取消外单 ${order['externalOrderNo']}？\n取消后已锁定库存将自动释放。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final resp = await ApiService().cancelExternalOrder(
          (order['id'] as num?)?.toInt() ?? 0);
      if (!mounted) return;
      if (resp['code'] == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('外单已取消，库存已释放'), backgroundColor: Colors.green),
        );
        _loadTab(_statusKeys[_tabController.index]);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp['msg'] ?? '取消失败'), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络错误'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Map<String, dynamic> _getStatusConfig(int status) {
    switch (status) {
      case 0: return {'label': '待处理', 'color': Colors.orange};
      case 1: return {'label': '库存锁定', 'color': const Color(0xFF7B1FA2)};
      case 2: return {'label': '拣货中', 'color': const Color(0xFF2196F3)};
      case 3: return {'label': '已发货', 'color': Colors.green};
      case 4: return {'label': '异常', 'color': Colors.red};
      case 5: return {'label': '已取消', 'color': Colors.grey};
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
