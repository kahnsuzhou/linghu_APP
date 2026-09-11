import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui' as ui;
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../services/api_service.dart';
import '../../config/constants.dart';
import '../../utils/event_bus.dart';
import 'complaint_page.dart';

/// 消费者订单列表页
class OrdersPage extends StatefulWidget {
  /// initialTabIndex: 0=全部, 1=待支付, 2=待发货...
  final int initialTabIndex;
  const OrdersPage({super.key, this.initialTabIndex = 0});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String?> _statuses = [
    null,
    'PENDING_PAY',
    'PENDING_DELIVERY',
    'DELIVERING',
    'FINISHED',
    'CANCELLED'
  ];
  final List<String> _tabs = ['全部', '待支付', '待发货', '待收货', '已完成', '已取消'];

  // 每个 tab 对应一个 GlobalKey，用于父级主动触发子 tab 刷新
  late final List<GlobalKey<_OrderListTabState>> _tabKeys;
  StreamSubscription? _orderStatusSub;

  @override
  void initState() {
    super.initState();
    _tabKeys = List.generate(_statuses.length, (_) => GlobalKey<_OrderListTabState>());
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabs.length - 1),
    );
    // 切换 tab 时刷新目标 tab 数据（保证从未访问过的 tab 也能拿到最新数据）
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _tabKeys[_tabController.index].currentState?._loadOrders();
      }
    });
    // 统一在父级监听订单状态变更，驱动对应 tab 刷新
    _orderStatusSub = eventBus.on<OrderStatusUpdateEvent>().listen((event) {
      // 全部 tab 始终刷新
      _tabKeys[0].currentState?._loadOrders();
      // 找到新状态对应的 tab index，刷新该 tab
      final newStatusIdx = _statuses.indexOf(event.status);
      if (newStatusIdx > 0) {
        _tabKeys[newStatusIdx].currentState?._loadOrders();
      }
      // 找到旧订单所在的 tab，将该订单从列表移除
      for (int i = 1; i < _tabKeys.length; i++) {
        final tabState = _tabKeys[i].currentState;
        if (tabState == null) continue;
        final idx = tabState._orders.indexWhere(
            (o) => (o['orderId'] as num?)?.toInt() == event.orderId);
        if (idx >= 0 && _statuses[i] != event.status) {
          // 该订单状态已变化，从当前 tab 移除
          tabState.setState(() => tabState._orders.removeAt(idx));
        }
      }
    });
  }

  @override
  void dispose() {
    _orderStatusSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的订单'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: List.generate(
          _statuses.length,
          (i) => _OrderListTab(key: _tabKeys[i], status: _statuses[i]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  订单列表 Tab
// ─────────────────────────────────────────────────────────
class _OrderListTab extends StatefulWidget {
  final String? status;
  const _OrderListTab({super.key, this.status});

  @override
  State<_OrderListTab> createState() => _OrderListTabState();
}

class _OrderListTabState extends State<_OrderListTab> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() => _loading = true);
    try {
      final response = await ApiService().getOrderList(status: widget.status);
      if (response['code'] == 200) {
        setState(() {
          _orders = (response['data'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
        });
      }
    } catch (_) {
      setState(() => _orders = []);
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── 钱包支付 ──
  Future<void> _walletPay(Map<String, dynamic> order) async {
    final orderId = (order['orderId'] as num).toInt();
    final amount = (order['totalAmount'] as num).toDouble();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('钱包支付'),
        content: Text('确认使用钱包支付 ¥${amount.toStringAsFixed(2)}？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认支付'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final res = await ApiService().walletPay(orderId);
      if (!mounted) return;
      if (res['code'] == 200) {
        final balanceAfter = (res['data']?['balanceAfter'] as num?)?.toDouble();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('支付成功！剩余余额：¥${balanceAfter?.toStringAsFixed(2) ?? '--'}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ));
        _loadOrders();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res['msg'] ?? '支付失败'),
            backgroundColor: Colors.red));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('网络错误，请重试'), backgroundColor: Colors.red));
      }
    }
  }

  // ── 申请售后退款 ──
  Future<void> _applyRefund(Map<String, dynamic> order) async {
    final orderId = (order['orderId'] as num).toInt();
    final amount = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;

    // 已有进行中的申请 → 弹详情弹窗
    final existingRefundStatus = order['refundStatus'] as String?;
    if (existingRefundStatus != null && existingRefundStatus != 'REJECTED') {
      _showRefundStatusDialog(order);
      return;
    }

    String selectedType = 'REFUND_ONLY';
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('申请售后退款'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline, color: Color(0xFFE65100), size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('退款金额：¥${amount.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 13, color: Color(0xFFE65100))),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                const Text('退款类型', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setS(() => selectedType = 'REFUND_ONLY'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selectedType == 'REFUND_ONLY'
                              ? const Color(0xFFFF6B35).withOpacity(0.1)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selectedType == 'REFUND_ONLY'
                                ? const Color(0xFFFF6B35)
                                : Colors.grey[300]!,
                          ),
                        ),
                        child: Column(children: [
                          Icon(Icons.money_off,
                              color: selectedType == 'REFUND_ONLY'
                                  ? const Color(0xFFFF6B35) : Colors.grey),
                          const SizedBox(height: 4),
                          Text('仅退款',
                              style: TextStyle(fontSize: 12,
                                  color: selectedType == 'REFUND_ONLY'
                                      ? const Color(0xFFFF6B35) : Colors.grey)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setS(() => selectedType = 'RETURN'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selectedType == 'RETURN'
                              ? const Color(0xFF2196F3).withOpacity(0.1)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selectedType == 'RETURN'
                                ? const Color(0xFF2196F3)
                                : Colors.grey[300]!,
                          ),
                        ),
                        child: Column(children: [
                          Icon(Icons.keyboard_return,
                              color: selectedType == 'RETURN'
                                  ? const Color(0xFF2196F3) : Colors.grey),
                          const SizedBox(height: 4),
                          Text('退货退款',
                              style: TextStyle(fontSize: 12,
                                  color: selectedType == 'RETURN'
                                      ? const Color(0xFF2196F3) : Colors.grey)),
                        ]),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                const Text('退款原因', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  maxLength: 100,
                  decoration: InputDecoration(
                    hintText: '请描述退款原因（必填）',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(10),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('提交申请'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写退款原因'), backgroundColor: Colors.orange));
      return;
    }

    try {
      final res = await ApiService().applyRefund(orderId, selectedType, reason);
      if (!mounted) return;
      if (res['code'] == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('售后申请已提交，等待运营处理'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ));
        _loadOrders();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res['msg'] ?? '申请失败'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('申请失败：$e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── 查看退款申请状态 ──
  void _showRefundStatusDialog(Map<String, dynamic> order) {
    final refundStatus = order['refundStatus'] as String? ?? '';
    final refundReason = order['refundReason'] as String? ?? '';
    final refundRemark = order['refundRemark'] as String? ?? '';
    final refundType = order['refundType'] as String? ?? 'REFUND_ONLY';

    final Map<String, Map<String, dynamic>> statusConfig = {
      'REQUESTED': {'label': '审核中', 'color': Colors.orange, 'icon': Icons.hourglass_top},
      'APPROVED':  {'label': '已批准', 'color': Colors.green,  'icon': Icons.check_circle},
      'REJECTED':  {'label': '已拒绝', 'color': Colors.red,    'icon': Icons.cancel},
      'REFUNDED':  {'label': '已退款', 'color': Colors.blue,   'icon': Icons.account_balance_wallet},
    };
    final cfg = statusConfig[refundStatus] ??
        {'label': refundStatus, 'color': Colors.grey, 'icon': Icons.help};

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退款申请详情'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(cfg['icon'] as IconData, color: cfg['color'] as Color, size: 20),
              const SizedBox(width: 8),
              Text(cfg['label'] as String,
                  style: TextStyle(
                      color: cfg['color'] as Color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ]),
            const SizedBox(height: 12),
            _infoRow('退款类型', refundType == 'RETURN' ? '退货退款' : '仅退款'),
            _infoRow('退款原因', refundReason),
            if (refundRemark.isNotEmpty)
              _infoRow('运营备注', refundRemark, valueColor: Colors.red),
            if (refundStatus == 'REFUNDED')
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 6),
                  Text('款项已退回您的钱包',
                      style: TextStyle(color: Colors.green, fontSize: 13)),
                ]),
              ),
          ],
        ),
        actions: [
          if (refundStatus == 'REQUESTED')
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _cancelRefund(order);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('撤销申请'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 13, color: valueColor ?? Colors.black87)),
        ),
      ]),
    );
  }

  // ── 撤销退款申请 ──
  Future<void> _cancelRefund(Map<String, dynamic> order) async {
    final orderId = (order['orderId'] as num).toInt();
    try {
      final res = await ApiService().cancelRefund(orderId);
      if (!mounted) return;
      if (res['code'] == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已撤销退款申请'), backgroundColor: Colors.grey));
        _loadOrders();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res['msg'] ?? '撤销失败'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('撤销失败：$e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── 确认收货 ──
  Future<void> _confirmReceipt(Map<String, dynamic> order) async {
    final orderId = (order['orderId'] as num).toInt();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认收货'),
        content: const Text('确认已收到商品？确认后订单将完成，不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('再想想')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认收货'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await ApiService().confirmReceipt(orderId);
      if (!mounted) return;
      if (res['code'] == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('收货确认成功！'), backgroundColor: Colors.green));
        _loadOrders();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res['msg'] ?? '操作失败'),
            backgroundColor: Colors.red));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('网络错误，请重试'), backgroundColor: Colors.red));
    }
  }

  // ── 取消订单 ──
  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final orderId = (order['orderId'] as num).toInt();
    final status = order['status'] as String? ?? '';
    final isPaid = status == 'PENDING_DELIVERY';
    final amount = isPaid ? (order['totalAmount'] as num?)?.toDouble() : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('取消订单'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要取消此订单吗？'),
            if (isPaid && amount != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        color: Color(0xFF4CAF50), size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '已支付 ¥${amount.toStringAsFixed(2)} 将自动退回钱包',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF2E7D32)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('不取消')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await ApiService().cancelOrder(orderId);
      if (!mounted) return;
      if (res['code'] == 200) {
        final data = res['data'] as Map<String, dynamic>? ?? {};
        final refunded = data['refunded'] == true;
        final refundAmount = (data['refundAmount'] as num?)?.toDouble();
        final balanceAfter = (data['balanceAfter'] as num?)?.toDouble();
        if (refunded && refundAmount != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              '订单已取消，¥${refundAmount.toStringAsFixed(2)} 已退回钱包'
              '${balanceAfter != null ? "（余额：¥${balanceAfter.toStringAsFixed(2)}）" : ""}',
            ),
            backgroundColor: const Color(0xFF4CAF50),
            duration: const Duration(seconds: 4),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('订单已取消'), backgroundColor: Colors.grey));
        }
        _loadOrders();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res['msg'] ?? '取消失败'),
            backgroundColor: Colors.red));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('网络错误，请重试'), backgroundColor: Colors.red));
    }
  }

  // ── 自提导航弹窗 ──
  void _showPickupNavigation(
      BuildContext context, List<Map<String, dynamic>> warehouses) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickupNavigationSheet(warehouses: warehouses),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_orders.isEmpty) return const Center(child: Text('暂无订单'));
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
      ),
    );
  }

  // ── 辅助方法 ──
  String _deliveryLabel(String? mode) {
    switch (mode) {
      case 'delivery': return '外卖配送';
      case 'pickup':   return '到仓自提';
      default:         return '快递配送';
    }
  }

  /// 商品来源标签：品牌=蓝色，自产=绿色
  Widget _sourceTag(String? sourceType) {
    final isSelf = sourceType == 'self';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: (isSelf ? Colors.green : Colors.blue).withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: (isSelf ? Colors.green : Colors.blue).withOpacity(0.4),
        ),
      ),
      child: Text(
        isSelf ? '自产' : '品牌',
        style: TextStyle(
          fontSize: 10,
          color: isSelf ? Colors.green[700] : Colors.blue[700],
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  IconData _deliveryIcon(String? mode) {
    switch (mode) {
      case 'delivery': return Icons.delivery_dining_outlined;
      case 'pickup':   return Icons.store_outlined;
      default:         return Icons.local_shipping_outlined;
    }
  }

  Color _deliveryColor(String? mode) {
    switch (mode) {
      case 'delivery': return const Color(0xFFFF6B35);
      case 'pickup':   return const Color(0xFF4CAF50);
      default:         return const Color(0xFF2196F3);
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'DELIVERING': return const Color(0xFF2196F3);
      case 'FINISHED':   return const Color(0xFF4CAF50);
      case 'CANCELLED':  return Colors.grey;
      case 'PENDING_PAY': return Colors.red;
      default:           return const Color(0xFFFF6B35);
    }
  }

  // ── 订单卡片 ──
  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status       = order['status'] as String? ?? '';
    final statusText   = AppConstants.orderStatusMap[status] ?? status;
    final items        = order['items'] as List? ?? [];
    final deliveryMode = order['deliveryMode'] as String?;
    final logisticsNo  = order['logisticsNo'] as String?;
    final carrier      = order['carrier'] as String?;
    final isSplit      = order['isSplit'] == true;
    final warehouseCount = order['warehouseCount'] as num?;
    final isPickup     = deliveryMode == 'pickup';

    // 自提仓库列表
    final pickupWarehouses = isPickup
        ? (order['pickupWarehouses'] as List? ?? []).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final hasPickupLocation = pickupWarehouses.isNotEmpty &&
        pickupWarehouses.any((w) => w['lat'] != null && w['lng'] != null);

    final canConfirm = status == 'DELIVERING';
    final canCancel  = status == 'PENDING_PAY' || status == 'PENDING_DELIVERY';
    final canPay     = status == 'PENDING_PAY';
    // 可申请售后：待收货或已完成，且无进行中的申请（或已被拒绝可重新申请）
    final refundStatus = order['refundStatus'] as String?;
    final canRefund = (status == 'DELIVERING' || status == 'FINISHED')
        && (refundStatus == null || refundStatus == 'REJECTED');
    // 已有退款申请，显示查看入口
    final hasActiveRefund = refundStatus != null && refundStatus != 'REJECTED';
    // 自提订单只要不是已取消/已完成，就显示导航
    final canNavigate = isPickup &&
        hasPickupLocation &&
        status != 'CANCELLED' &&
        status != 'FINISHED';
    // 已发货/已完成/已收货可发起吐槽
    final canComplaint = status == 'DELIVERING' || status == 'FINISHED';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 订单号 + 状态 ──
            Row(
              children: [
                Expanded(
                  child: Text('订单: ${order['orderSn'] ?? ''}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(statusText,
                      style: TextStyle(
                          color: _statusColor(status),
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),

            // ── 拆单 banner ──
            if (isSplit) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: Row(children: [
                  const Icon(Icons.call_split_outlined,
                      size: 14, color: Color(0xFFFF8F00)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '已自动拆单：由 $warehouseCount 个仓库分批发货',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE65100),
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
            ],

            // ── 自提导航 banner ──
            if (canNavigate) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showPickupNavigation(context, pickupWarehouses),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.navigation,
                        size: 16, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('自提仓库位置',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1B5E20))),
                          Text(
                            pickupWarehouses.length == 1
                                ? (pickupWarehouses.first['address'] ?? '点击查看地图')
                                : '${pickupWarehouses.length} 个仓库 · 点击查看地图',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF388E3C)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: Color(0xFF4CAF50), size: 18),
                  ]),
                ),
              ),
            ],

            const Divider(height: 16),

            // ── 商品列表 ──
            ...items.take(2).map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Icon(Icons.shopping_bag_outlined,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(item['productName'] ?? '',
                            style: const TextStyle(fontSize: 13))),
                    _sourceTag(item['sourceType'] as String?),
                    const SizedBox(width: 6),
                    Text('x${item['quantity']}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                  ]),
                )),
            if (items.length > 2)
              Text('...等${items.length}件商品',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),

            const Divider(height: 16),

            // ── 收货地址行 ──
            if (order['deliveryAddress'] != null && (order['deliveryAddress'] as String).isNotEmpty) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${order['deliveryName'] ?? ''}  ${order['deliveryPhone'] ?? ''}\n${order['deliveryAddress']}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              const SizedBox(height: 6),
            ],

            // ── 配送方式行 ──
            Row(children: [
              Icon(_deliveryIcon(deliveryMode),
                  size: 14, color: _deliveryColor(deliveryMode)),
              const SizedBox(width: 4),
              Text(_deliveryLabel(deliveryMode),
                  style: TextStyle(
                      fontSize: 12, color: _deliveryColor(deliveryMode))),
              if (logisticsNo != null && logisticsNo.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${carrier ?? ''} $logisticsNo',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ]),
            const SizedBox(height: 8),

            // ── 底部：金额 + 操作按钮 ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('共${items.length}件商品',
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(
                    '合计：¥${(order['totalAmount'] as num).toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ]),
                Row(children: [
                  if (canCancel)
                    OutlinedButton(
                      onPressed: () => _cancelOrder(order),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: const BorderSide(color: Colors.grey),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('取消订单',
                          style: TextStyle(fontSize: 12)),
                    ),
                  if (canCancel) const SizedBox(width: 8),
                  if (canPay)
                    ElevatedButton(
                      onPressed: () => _walletPay(order),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text('钱包支付',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  if (canPay) const SizedBox(width: 8),
                  if (canConfirm)
                    ElevatedButton(
                      onPressed: () => _confirmReceipt(order),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text('确认收货',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  // 自提已完成时也显示"再次导航"（方便下次）
                  if (isPickup && hasPickupLocation && status == 'FINISHED')
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showPickupNavigation(context, pickupWarehouses),
                      icon: const Icon(Icons.map_outlined, size: 14),
                      label: const Text('查看仓库',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4CAF50),
                        side:
                            const BorderSide(color: Color(0xFF4CAF50)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  // 申请售后退款按钮
                  if (canRefund) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _applyRefund(order),
                      icon: const Icon(Icons.assignment_return_outlined, size: 14),
                      label: const Text('申请退款', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                  // 查看退款进度（有进行中/已完结的申请）
                  if (hasActiveRefund) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _showRefundStatusDialog(order),
                      icon: Icon(
                        refundStatus == 'REFUNDED'
                            ? Icons.check_circle_outline
                            : Icons.hourglass_top_outlined,
                        size: 14,
                        color: refundStatus == 'REFUNDED' ? Colors.blue : Colors.orange,
                      ),
                      label: Text(
                        refundStatus == 'REFUNDED' ? '已退款' : '退款中',
                        style: TextStyle(
                            fontSize: 12,
                            color: refundStatus == 'REFUNDED' ? Colors.blue : Colors.orange),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: refundStatus == 'REFUNDED' ? Colors.blue : Colors.orange,
                        side: BorderSide(
                            color: refundStatus == 'REFUNDED' ? Colors.blue : Colors.orange),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                  // 吐槽按钮（已发货/已完成）
                  if (canComplaint) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        // 提取第一个仓库ID和商品名用于展示
                        final itemList = order['items'] as List? ?? [];
                        final firstItem = itemList.isNotEmpty
                            ? itemList[0] as Map<String, dynamic>
                            : <String, dynamic>{};
                        final warehouseId = firstItem['warehouseId'];
                        final productNames = itemList
                            .whereType<Map>()
                            .map((i) => i['productName'] ?? '')
                            .where((n) => n.toString().isNotEmpty)
                            .take(2)
                            .join('、');
                        final orderSn = order['orderSn'] as String? ?? '';
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ComplaintPage(
                              relatedType: 'ORDER',
                              relatedId: order['orderId'],
                              orderSn: orderSn,
                              warehouseId: warehouseId,
                              relatedLabel: '订单 $orderSn${productNames.isNotEmpty ? " · $productNames" : ""}',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 14),
                      label: const Text('吐槽', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF6B35),
                        side: const BorderSide(color: Color(0xFFFF6B35)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  自提仓库导航底部弹窗
// ─────────────────────────────────────────────────────────
class _PickupNavigationSheet extends StatefulWidget {
  final List<Map<String, dynamic>> warehouses;
  const _PickupNavigationSheet({required this.warehouses});

  @override
  State<_PickupNavigationSheet> createState() =>
      _PickupNavigationSheetState();
}

class _PickupNavigationSheetState extends State<_PickupNavigationSheet> {
  late MapController _mapCtrl;
  int _selectedIdx = 0;

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
  }

  Map<String, dynamic> get _selected => widget.warehouses[_selectedIdx];

  LatLng get _selectedLatLng => LatLng(
        (_selected['lat'] as num).toDouble(),
        (_selected['lng'] as num).toDouble(),
      );

  // 打开高德导航（Web 用 URL Scheme）
  void _openNavigation(Map<String, dynamic> w) {
    final lat = (w['lat'] as num).toDouble();
    final lng = (w['lng'] as num).toDouble();
    final name = Uri.encodeComponent(w['name'] ?? '自提仓库');

    // 高德地图导航链接（Web 可直接跳转）
    final url =
        'https://uri.amap.com/navigation?to=$lng,$lat,$name&mode=walking&callnative=1';

    // 在 Web 端用 url_launcher 或直接 window.open
    // 因已有 flutter/services，用 platform channel 打开
    _launchUrl(url);
  }

  void _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.warehouses.length > 1;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // 把手
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          ),

          // 标题行
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              const Icon(Icons.store, color: Color(0xFF4CAF50), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasMultiple
                      ? '自提仓库（共 ${widget.warehouses.length} 个）'
                      : '自提仓库位置',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ]),
          ),

          // 多仓库 Tab 选择
          if (hasMultiple)
            SizedBox(
              height: 36,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: widget.warehouses.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final selected = i == _selectedIdx;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedIdx = i);
                      _mapCtrl.move(_selectedLatLng, 15);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF4CAF50)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        '仓库${i + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? Colors.white : Colors.grey[700],
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

          if (hasMultiple) const SizedBox(height: 10),

          // 地图
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: _selectedLatLng,
                    initialZoom: 15,
                  ),
                  children: [
                    // 高德中文底图
                    TileLayer(
                      urlTemplate:
                          'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                      subdomains: const ['1', '2', '3', '4'],
                      userAgentPackageName: 'com.linghu.app',
                      maxZoom: 18,
                    ),
                    // 所有仓库标记
                    MarkerLayer(
                      markers: widget.warehouses.asMap().entries.map((e) {
                        final i = e.key;
                        final w = e.value;
                        if (w['lat'] == null || w['lng'] == null) {
                          return Marker(
                              point: const LatLng(0, 0),
                              child: const SizedBox.shrink());
                        }
                        final isSelected = i == _selectedIdx;
                        return Marker(
                          point: LatLng(
                            (w['lat'] as num).toDouble(),
                            (w['lng'] as num).toDouble(),
                          ),
                          width: isSelected ? 52 : 40,
                          height: isSelected ? 60 : 48,
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _selectedIdx = i);
                              _mapCtrl.move(
                                LatLng((w['lat'] as num).toDouble(),
                                    (w['lng'] as num).toDouble()),
                                15,
                              );
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF2E7D32)
                                        : const Color(0xFF4CAF50),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF4CAF50)
                                            .withOpacity(
                                                isSelected ? 0.6 : 0.3),
                                        blurRadius: isSelected ? 10 : 4,
                                        spreadRadius: isSelected ? 2 : 0,
                                      )
                                    ],
                                    border: isSelected
                                        ? Border.all(
                                            color: Colors.white, width: 2)
                                        : null,
                                  ),
                                  child: Icon(Icons.store,
                                      color: Colors.white,
                                      size: isSelected ? 20 : 16),
                                ),
                                CustomPaint(
                                  painter: _TrianglePainter(
                                    color: isSelected
                                        ? const Color(0xFF2E7D32)
                                        : const Color(0xFF4CAF50),
                                  ),
                                  size: const Size(10, 6),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 仓库信息卡 + 导航按钮
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F8E9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFA5D6A7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.warehouse,
                      size: 16, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _selected['name'] ?? '自提仓库',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20)),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.location_on_outlined,
                      size: 13, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _selected['address'] ?? '地址未知',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF388E3C)),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.info_outline,
                      size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'GPS: ${(_selected['lat'] as num?)?.toStringAsFixed(5) ?? '-'}, '
                    '${(_selected['lng'] as num?)?.toStringAsFixed(5) ?? '-'}',
                    style:
                        const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ]),
              ],
            ),
          ),

          // 导航按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => _openNavigation(_selected),
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('高德地图导航',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25)),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── 标记三角尖 ──
class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}
