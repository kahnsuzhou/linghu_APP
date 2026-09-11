import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';

/// 外单拣货详情页 - 查看收件人信息、填写物流单号、完成发货
class ExternalPickingDetailPage extends StatefulWidget {
  final Map<String, dynamic> workOrder;
  const ExternalPickingDetailPage({super.key, required this.workOrder});

  @override
  State<ExternalPickingDetailPage> createState() => _ExternalPickingDetailPageState();
}

class _ExternalPickingDetailPageState extends State<ExternalPickingDetailPage> {
  final _logisticsNoCtrl = TextEditingController();
  String _selectedCompany = '顺丰速运';
  bool _submitting = false;

  static const _logisticsCompanies = [
    '顺丰速运', '圆通速递', '中通快递', '韵达速递', '申通快递',
    '邮政EMS', '京东物流', '极兔速递', '菜鸟裹裹', '其他',
  ];

  Map<String, dynamic> get _order => widget.workOrder;
  // 后端返回数字状态: 1=待拣货, 2=拣货中, 3=已发货, 4=异常
  int get _statusInt => (_order['status'] as num?)?.toInt() ?? 1;
  bool get _canShip => _statusInt == 1 || _statusInt == 2;

  @override
  void dispose() {
    _logisticsNoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final externalNo = _order['externalOrderNo'] as String? ?? '--';
    final productName = _order['productName'] as String? ?? _order['skuCode'] ?? '--';
    final quantity = ((_order['quantity'] as num?)?.toInt() ?? 0);
    final channel = _order['channel'] as String? ?? '';
    final receiverName = _order['receiverName'] as String? ?? '';
    final receiverPhone = _order['receiverPhone'] as String? ?? '';
    final receiverAddress = _order['receiverAddress'] as String? ?? '';
    final logisticsNo = _order['logisticsNo'] as String?;
    final logisticsCompany = _order['logisticsCompany'] as String?;
    final shipTime = _order['shipTime'] as String?;
    final createTime = _order['createTime'] as String? ?? '';
    final warehouseId = (_order['warehouseId'] as num?)?.toInt();

    return Scaffold(
      appBar: AppBar(
        title: const Text('外单详情'),
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 状态卡片 ──
            _buildStatusBanner(),
            const SizedBox(height: 16),

            // ── 外单基本信息 ──
            _buildSection(
              icon: Icons.receipt_long_outlined,
              color: const Color(0xFF7B1FA2),
              title: '外单信息',
              child: Column(
                children: [
                  _buildInfoRow('外单号', externalNo, mono: true),
                  _buildInfoRow('来源渠道', _channelLabel(channel)),
                  _buildInfoRow('下单时间', createTime),
                  if (warehouseId != null)
                    _buildInfoRow('分配仓库', '仓库 #$warehouseId',
                        valueColor: const Color(0xFF7B1FA2)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── 商品信息 ──
            _buildSection(
              icon: Icons.inventory_2_outlined,
              color: Colors.orange,
              title: '商品信息',
              child: Column(
                children: [
                  _buildInfoRow('商品名称', productName),
                  _buildInfoRow('SKU编码', _order['skuCode'] as String? ?? '--', mono: true),
                  _buildInfoRow('发货数量', '$quantity 件',
                      valueColor: const Color(0xFF7B1FA2)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── 收件人信息 ──
            _buildSection(
              icon: Icons.person_outline,
              color: const Color(0xFF2196F3),
              title: '收件人信息',
              child: Column(
                children: [
                  _buildInfoRow('收件人', receiverName),
                  _buildInfoRow('联系电话', receiverPhone),
                  _buildInfoRow('收货地址', receiverAddress, multiLine: true),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── 物流信息（已发货时显示）──
            if (_statusInt == 3) ...[
              _buildSection(
                icon: Icons.local_shipping_outlined,
                color: Colors.green,
                title: '物流信息',
                child: Column(
                  children: [
                    _buildInfoRow('快递公司', logisticsCompany ?? '--'),
                    _buildInfoRow('运单号', logisticsNo ?? '--', mono: true,
                        trailing: logisticsNo != null
                            ? GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: logisticsNo));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已复制运单号'), duration: Duration(seconds: 2)),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.green[300]!),
                                  ),
                                  child: const Text('复制',
                                      style: TextStyle(fontSize: 12, color: Colors.green)),
                                ),
                              )
                            : null),
                    _buildInfoRow('发货时间', shipTime ?? '--'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── 填写物流单号（待拣货/拣货中时显示）──
            if (_canShip) ...[
              _buildShipForm(),
              const SizedBox(height: 12),
              // 异常上报入口
              OutlinedButton.icon(
                onPressed: _reportException,
                icon: const Icon(Icons.error_outline, color: Colors.red),
                label: const Text('上报异常（缺货/损坏）',
                    style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ],
        ),
      ),

      // 发货按钮
      bottomNavigationBar: _canShip
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _confirmShip,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.local_shipping),
                    label: Text(_submitting ? '发货中...' : (_statusInt == 1 ? '开始拣货并发货' : '确认发货'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B1FA2),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildStatusBanner() {
    final config = _getStatusConfig(_statusInt);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: (config['color'] as Color).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (config['color'] as Color).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(config['icon'] as IconData, color: config['color'] as Color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(config['label'] as String,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold,
                      color: config['color'] as Color)),
              Text(config['desc'] as String,
                  style: TextStyle(fontSize: 12, color: (config['color'] as Color).withOpacity(0.8))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShipForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_shipping_outlined, color: Color(0xFF7B1FA2), size: 18),
              SizedBox(width: 6),
              Text('填写物流信息',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              SizedBox(width: 6),
              Text('*必填', style: TextStyle(fontSize: 12, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 14),
          // 快递公司选择
          const Text('快递公司', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedCompany,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.business_outlined, size: 18),
            ),
            items: _logisticsCompanies
                .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14))))
                .toList(),
            onChanged: (v) => setState(() => _selectedCompany = v ?? _selectedCompany),
          ),
          const SizedBox(height: 12),
          // 运单号输入
          const Text('运单号', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 6),
          TextField(
            controller: _logisticsNoCtrl,
            decoration: InputDecoration(
              hintText: '请输入快递运单号',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.qr_code_outlined, size: 18),
              suffixIcon: _logisticsNoCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _logisticsNoCtrl.clear()),
                    )
                  : null,
            ),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color color,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          ]),
          const Divider(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value,
      {bool mono = false, bool multiLine = false, Color? valueColor, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: multiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? Colors.black87,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  String _channelLabel(String channel) {
    const map = {
      'taobao': '🛍 淘宝',
      'jd': '🐶 京东',
      'douyin': '🎵 抖音',
      'pdd': '🛒 拼多多',
    };
    return map[channel] ?? '📦 其他';
  }

  Map<String, dynamic> _getStatusConfig(int status) {
    switch (status) {
      case 1:
        return {
          'label': '待拣货', 'desc': '库存已锁定，请拣货后填写物流单号完成发货',
          'color': Colors.orange, 'icon': Icons.pending_outlined,
        };
      case 2:
        return {
          'label': '拣货中', 'desc': '正在作业中，请尽快完成发货',
          'color': const Color(0xFF2196F3), 'icon': Icons.inventory_outlined,
        };
      case 3:
        return {
          'label': '已发货', 'desc': '货物已交付快递，等待品牌方确认',
          'color': Colors.green, 'icon': Icons.check_circle_outline,
        };
      case 4:
        return {
          'label': '异常', 'desc': '请联系平台处理',
          'color': Colors.red, 'icon': Icons.error_outline,
        };
      default:
        return {
          'label': '未知', 'desc': '',
          'color': Colors.grey, 'icon': Icons.help_outline,
        };
    }
  }

  Future<void> _confirmShip() async {
    final logisticsNo = _logisticsNoCtrl.text.trim();
    if (logisticsNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写运单号'), backgroundColor: Colors.red),
      );
      return;
    }

    // 后端接口用 orderId
    final orderId = ((_order['id'] ?? _order['workOrderId']) as num?)?.toInt() ?? 0;

    // 确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.local_shipping, color: Color(0xFF7B1FA2)),
          SizedBox(width: 8),
          Text('确认发货'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _confirmRow('快递公司', _selectedCompany),
            _confirmRow('运单号', logisticsNo),
            _confirmRow('外单号', _order['externalOrderNo'] as String? ?? '--'),
            _confirmRow('商品', _order['productName'] as String? ?? '--'),
            _confirmRow('数量', '${_order['quantity'] ?? 0} 件'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange[700]),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('发货后将自动通知品牌方，作业费即时结算',
                      style: TextStyle(fontSize: 12, color: Colors.orange)),
                ),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7B1FA2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认发货'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _submitting = true);
    try {
      // status=1(待拣货) 时需先调 startPicking 变为 status=2，再调 completePicking
      if (_statusInt == 1) {
        final startResp = await ApiService().startExternalPicking(orderId);
        if (!mounted) return;
        if (startResp['code'] != 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('开始拣货失败：${startResp['msg'] ?? '未知错误'}'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final resp = await ApiService().completeExternalPicking({
        'orderId': orderId,
        'logisticsCompany': _selectedCompany,
        'logisticsNo': logisticsNo,
      });
      if (!mounted) return;
      if (resp['code'] == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('发货成功！品牌方已收到通知'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp['msg'] ?? '发货失败'), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络错误，请重试'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 60,
          child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  Future<void> _reportException() async {
    final reasons = ['库存不足', '商品损坏', '找不到商品', 'SKU不匹配', '其他原因'];
    String selectedReason = reasons[0];
    final noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('上报异常'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('异常原因', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              ...reasons.map((r) => RadioListTile<String>(
                    value: r,
                    groupValue: selectedReason,
                    title: Text(r, style: const TextStyle(fontSize: 14)),
                    dense: true,
                    activeColor: Colors.red,
                    onChanged: (v) => setModalState(() => selectedReason = v ?? r),
                  )),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: '补充说明（选填）',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('提交异常'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    try {
      final orderId = ((_order['id'] ?? _order['workOrderId']) as num?)?.toInt() ?? 0;
      // status=1(待拣货) 时需先 start 变为 status=2，再上报异常
      if (_statusInt == 1) {
        final startResp = await ApiService().startExternalPicking(orderId);
        if (!mounted) return;
        if (startResp['code'] != 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('操作失败：${startResp['msg'] ?? '未知错误'}'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      final resp = await ApiService().reportExternalException({
        'orderId': orderId,
        'reason': selectedReason,
        'note': noteCtrl.text.trim(),
      });
      if (!mounted) return;
      if (resp['code'] == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('异常已上报，平台运营将尽快处理'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp['msg'] ?? '上报失败'), backgroundColor: Colors.red),
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
}
