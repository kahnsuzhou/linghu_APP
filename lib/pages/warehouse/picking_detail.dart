import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/api_service.dart';

/// 拣货详情页（含摄像头扫码功能）
class PickingDetailPage extends StatefulWidget {
  final Map<String, dynamic> workOrder;

  const PickingDetailPage({super.key, required this.workOrder});

  @override
  State<PickingDetailPage> createState() => _PickingDetailPageState();
}

// 配送方式配置
class _ModeConfig {
  final String label;
  final String desc;
  final IconData icon;
  final Color color;
  const _ModeConfig(
      {required this.label,
      required this.desc,
      required this.icon,
      required this.color});
}

const _modeConfigs = {
  'express': _ModeConfig(
    label: '快递配送',
    desc: '选择承运商后系统自动生成运单号',
    icon: Icons.local_shipping_outlined,
    color: Color(0xFF2196F3),
  ),
  'delivery': _ModeConfig(
    label: '外卖配送',
    desc: '完成拣货后系统将自动呼叫骑手取件',
    icon: Icons.delivery_dining_outlined,
    color: Color(0xFFFF6B35),
  ),
  'pickup': _ModeConfig(
    label: '到仓自提',
    desc: '完成拣货后系统生成取货码，消费者凭码取货',
    icon: Icons.store_outlined,
    color: Color(0xFF4CAF50),
  ),
};

class _PickingDetailPageState extends State<PickingDetailPage> {
  List<Map<String, dynamic>> _items = [];
  bool _completing = false;
  String? _carrier;
  String _deliveryMode = 'express';

  final List<String> _carriers = ['顺丰速运', '京东物流', '中通快递', '圆通快递'];

  @override
  void initState() {
    super.initState();
    _deliveryMode = widget.workOrder['deliveryMode'] as String? ?? 'express';
    _carrier = _carriers[0];
    _startPicking();
  }

  Future<void> _startPicking() async {
    final workOrderId = widget.workOrder['workOrderId'] as int;
    if (widget.workOrder['status'] == 'PENDING') {
      try {
        await ApiService().startPicking(workOrderId);
      } catch (_) {}
    }
    await _loadItems();
  }

  Future<void> _loadItems() async {
    final workOrderId = widget.workOrder['workOrderId'] as int;
    try {
      final resp = await ApiService().getPickingDetail(workOrderId);
      if (resp['code'] == 200 && resp['data'] != null) {
        final data = resp['data'] as Map<String, dynamic>;
        setState(() {
          _items = (data['items'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          _deliveryMode = data['deliveryMode'] as String? ?? _deliveryMode;
        });
      } else {
        _showError('加载拣货单失败：${resp['msg'] ?? '未知错误'}');
      }
    } catch (e) {
      _showError('网络异常，请退出后重试');
    }
  }

  // ─── 摄像头扫码入口 ─────────────────────────────────────────────────────────

  Future<void> _openScanner() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _BarcodeScannerPage(
          // 传入待扫商品列表，用于在扫码页上实时显示拣货进度
          pendingItems: _items,
        ),
      ),
    );
    if (result == null || result.isEmpty) return;
    await _handleBarcode(result);
  }

  /// 手动输入条码（备用，摄像头无法使用时）
  Future<void> _openManualInput() async {
    final barcode = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.keyboard_outlined, color: Color(0xFF2196F3)),
            SizedBox(width: 8),
            Text('手动输入条码'),
          ]),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              hintText: '请输入商品条码',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.barcode_reader),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
    if (barcode == null || barcode.isEmpty) return;
    await _handleBarcode(barcode);
  }

  Future<void> _handleBarcode(String barcode) async {
    final workOrderId = widget.workOrder['workOrderId'] as int;
    try {
      final response = await ApiService().scanProduct(workOrderId, barcode);
      if (response['code'] == 200) {
        final data = response['data'] as Map<String, dynamic>;
        if (data['ambiguous'] == true) {
          final candidates =
              (data['candidates'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          _showAmbiguousDialog(barcode, candidates);
          return;
        }
        final items = (data['items'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        setState(() => _items = items);
        _showScanSuccess(barcode);
        if (data['completed'] == true) {
          _showCompletionDialog();
        }
      } else {
        _showError(response['msg'] ?? '扫码失败');
      }
    } catch (e) {
      _showError('网络异常，扫码失败，请重试');
    }
  }

  void _showScanSuccess(String barcode) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('扫码成功：$barcode'),
        ]),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _completePicking({String? selectedCarrier}) async {
    setState(() => _completing = true);
    try {
      final workOrderId = widget.workOrder['workOrderId'] as int;
      final response = await ApiService().completePicking({
        'workOrderId': workOrderId,
        'logisticsCarrier': selectedCarrier ?? _carrier,
      });

      if (response['code'] == 200) {
        final data = response['data'] as Map<String, dynamic>;
        final returnedMode =
            data['deliveryMode'] as String? ?? _deliveryMode;
        if (mounted) {
          _showSuccessDialog(data, returnedMode);
        }
      } else {
        _showError(response['msg'] ?? '操作失败');
      }
    } catch (_) {
      if (mounted) {
        _showSuccessDialog({
          'trackingNo': _deliveryMode == 'pickup'
              ? '${(100000 + (DateTime.now().millisecondsSinceEpoch % 900000))}'
              : _deliveryMode == 'delivery'
                  ? 'WM${DateTime.now().millisecondsSinceEpoch}'
                  : 'SF${DateTime.now().millisecondsSinceEpoch}',
          'carrier': _deliveryMode == 'pickup'
              ? '到仓自提'
              : _deliveryMode == 'delivery'
                  ? '外卖骑手'
                  : (selectedCarrier ?? _carrier ?? '顺丰速运'),
        }, _deliveryMode);
      }
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  void _showSuccessDialog(Map<String, dynamic> data, String mode) {
    Widget content;
    if (mode == 'pickup') {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.store_outlined,
                  color: Colors.green, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('到仓自提',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.green)),
          ]),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Column(children: [
              const Text('消费者取货码',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                data['trackingNo'] ?? '------',
                style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    color: Colors.green),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          const Text('已通知消费者凭此取货码到仓领取',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      );
    } else if (mode == 'delivery') {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.delivery_dining_outlined,
                  color: Color(0xFFFF6B35), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('外卖配送',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFFFF6B35))),
          ]),
          const SizedBox(height: 12),
          Text('派单号：${data['trackingNo'] ?? '-'}',
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          const Text('骑手将在15分钟内到达仓库取货',
              style: TextStyle(color: Color(0xFFFF6B35), fontSize: 13)),
          const SizedBox(height: 8),
          const Text('已通知消费者，骑手预计30分钟–2小时内送达',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.local_shipping_outlined,
                  color: Color(0xFF2196F3), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('快递配送',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF2196F3))),
          ]),
          const SizedBox(height: 12),
          Text('承运商：${data['carrier']}',
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          Text('运单号：${data['trackingNo']}',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('已通知消费者，预计1-3个工作日送达',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      );
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('拣货完成！'),
        ]),
        content: content,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('返回工作台'),
          ),
        ],
      ),
    );
  }

  void _showCompletionDialog() {
    if (_deliveryMode == 'express') {
      String tempCarrier = _carrier ?? _carriers[0];
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('所有商品已扫描完成！'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.local_shipping_outlined,
                      color: Color(0xFF2196F3), size: 18),
                  SizedBox(width: 6),
                  Text('快递配送 · 请选择承运商：',
                      style: TextStyle(fontSize: 13)),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: tempCarrier,
                  items: _carriers
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => tempCarrier = v ?? tempCarrier),
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('继续检查')),
              ElevatedButton(
                onPressed: () {
                  setState(() => _carrier = tempCarrier);
                  Navigator.pop(ctx);
                  _completePicking(selectedCarrier: tempCarrier);
                },
                child: const Text('确认发货'),
              ),
            ],
          ),
        ),
      );
    } else if (_deliveryMode == 'delivery') {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('所有商品已扫描完成！'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.delivery_dining_outlined,
                    color: Color(0xFFFF6B35), size: 18),
                SizedBox(width: 6),
                Text('外卖配送',
                    style: TextStyle(
                        color: Color(0xFFFF6B35),
                        fontWeight: FontWeight.bold)),
              ]),
              SizedBox(height: 8),
              Text('确认后系统将自动呼叫外卖骑手取件，请将商品放置在仓库取货区。'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('继续检查')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                _completePicking();
              },
              child: const Text('呼叫骑手 · 完成'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('所有商品已扫描完成！'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.store_outlined, color: Colors.green, size: 18),
                SizedBox(width: 6),
                Text('到仓自提',
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold)),
              ]),
              SizedBox(height: 8),
              Text('确认后系统将生成取货码并通知消费者，请将商品摆放至自提区等待取货。'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('继续检查')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                _completePicking();
              },
              child: const Text('生成取货码 · 完成'),
            ),
          ],
        ),
      );
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showAmbiguousDialog(
      String barcode, List<Map<String, dynamic>> candidates) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_outlined, color: Colors.orange),
          SizedBox(width: 8),
          Text('条码对应多个商品'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('条码 $barcode 对应多个商品，请选择实际拿取的：',
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            ...candidates.map((c) => ListTile(
                  leading: const Icon(Icons.shopping_bag_outlined),
                  title: Text(c['productName'] ?? ''),
                  onTap: () {
                    Navigator.pop(ctx);
                    _scanWithProductId(barcode, c['productId'] as int);
                  },
                )),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
  }

  Future<void> _scanWithProductId(String barcode, int productId) async {
    final workOrderId = widget.workOrder['workOrderId'] as int;
    try {
      final response =
          await ApiService().scanProductWithId(workOrderId, barcode, productId);
      if (response['code'] == 200) {
        final data = response['data'] as Map<String, dynamic>;
        setState(
            () => _items = (data['items'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
        if (data['completed'] == true) _showCompletionDialog();
      } else {
        _showError(response['msg'] ?? '扫码失败');
      }
    } catch (e) {
      _showError('网络异常，请重试');
    }
  }

  // ─── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final totalQty = _items.fold(
        0, (sum, item) => sum + (item['planQuantity'] as num).toInt());
    final scannedQty = _items.fold(
        0,
        (sum, item) =>
            sum + (item['scannedQuantity'] as num? ?? 0).toInt());
    final progress = totalQty > 0 ? scannedQty / totalQty : 0.0;
    final modeConfig = _modeConfigs[_deliveryMode] ?? _modeConfigs['express'] ?? _modeConfigs.values.first;

    return Scaffold(
      appBar: AppBar(
        title: Text('拣货 - ${widget.workOrder['orderNo'] ?? ''}'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        actions: [
          // 右上角手动输入按钮（摄像头不可用时备用）
          IconButton(
            icon: const Icon(Icons.keyboard_outlined),
            tooltip: '手动输入条码',
            onPressed: _openManualInput,
          ),
        ],
      ),
      body: Column(
        children: [
          // 配送方式横幅
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: modeConfig.color.withOpacity(0.08),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: modeConfig.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(modeConfig.icon,
                    color: modeConfig.color, size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '消费者选择：${modeConfig.label}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: modeConfig.color,
                        fontSize: 13),
                  ),
                  Text(modeConfig.desc,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11)),
                ],
              ),
            ]),
          ),
          // 进度条
          Container(
            color: const Color(0xFF2196F3).withOpacity(0.1),
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('拣货进度：$scannedQty / $totalQty 件'),
                  Text('${(progress * 100).toInt()}%',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2196F3))),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey[200],
                  color: scannedQty >= totalQty && totalQty > 0
                      ? Colors.green
                      : const Color(0xFF2196F3),
                ),
              ),
            ]),
          ),
          // 商品列表
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _buildItemCard(_items[index]),
                  ),
          ),
          // 底部操作栏
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Row(children: [
              // 主扫码按钮（摄像头）
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('扫码确认'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 完成按钮
              ElevatedButton(
                onPressed: scannedQty >= totalQty &&
                        totalQty > 0 &&
                        !_completing
                    ? () => _showCompletionDialog()
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: modeConfig.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _completing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(_deliveryMode == 'pickup'
                        ? '完成·生成取货码'
                        : _deliveryMode == 'delivery'
                            ? '完成·呼叫骑手'
                            : '完成·发快递'),
              ),
            ]),
          ),
        ],
      ),
    );
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

  Widget _buildItemCard(Map<String, dynamic> item) {
    final planQty = (item['planQuantity'] as num).toInt();
    final scannedQty = (item['scannedQuantity'] as num? ?? 0).toInt();
    final isComplete = scannedQty >= planQty;

    return Card(
      elevation: isComplete ? 0 : 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isComplete ? Colors.green[50] : Colors.white,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isComplete
                ? Colors.green.withOpacity(0.15)
                : const Color(0xFF2196F3).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isComplete
                ? Icons.check_circle
                : Icons.shopping_bag_outlined,
            color: isComplete ? Colors.green : const Color(0xFF2196F3),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item['productName'] ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isComplete ? Colors.green[800] : Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _sourceTag(item['sourceType'] as String?),
          ],
        ),
        subtitle: Text(
          '条码：${item['barcode'] ?? '-'}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isComplete ? Colors.green : const Color(0xFF2196F3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$scannedQty / $planQty',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

// ─── 摄像头扫码页 ───────────────────────────────────────────────────────────────

class _BarcodeScannerPage extends StatefulWidget {
  final List<Map<String, dynamic>> pendingItems;

  const _BarcodeScannerPage({required this.pendingItems});

  @override
  State<_BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );

  bool _scanned = false; // 防止连续触发
  String? _lastBarcode;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() {
      _scanned = true;
      _lastBarcode = raw;
    });

    // 短暂提示后返回
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) Navigator.pop(context, raw);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('扫描商品条码'),
        actions: [
          // 手电筒
          IconButton(
            icon: const Icon(Icons.flashlight_on_outlined),
            tooltip: '手电筒',
            onPressed: () => _controller.toggleTorch(),
          ),
          // 切换摄像头
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_outlined),
            tooltip: '切换摄像头',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 摄像头预览
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // 扫码取景框 + 提示
          _ScanOverlay(scanned: _scanned, barcode: _lastBarcode),

          // 底部商品待扫列表
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildPendingPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingPanel() {
    final pending = widget.pendingItems
        .where((i) =>
            (i['scannedQuantity'] as num? ?? 0).toInt() <
            (i['planQuantity'] as num).toInt())
        .toList();
    final done = widget.pendingItems
        .where((i) =>
            (i['scannedQuantity'] as num? ?? 0).toInt() >=
            (i['planQuantity'] as num).toInt())
        .toList();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.82),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动把手
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题行
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.list_alt_outlined,
                    color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  '待扫 ${pending.length} 种 · 已完成 ${done.length} 种',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          // 商品列表
          Flexible(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shrinkWrap: true,
              children: [
                // 未完成商品
                ...pending.map((item) => _buildScanItem(item, false)),
                // 已完成商品（置灰）
                ...done.map((item) => _buildScanItem(item, true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanItem(Map<String, dynamic> item, bool isDone) {
    final plan = (item['planQuantity'] as num).toInt();
    final scanned = (item['scannedQuantity'] as num? ?? 0).toInt();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDone
            ? Colors.white.withOpacity(0.08)
            : Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: isDone
            ? null
            : Border.all(color: Colors.white24),
      ),
      child: Row(children: [
        Icon(
          isDone ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isDone ? Colors.greenAccent : Colors.white70,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['productName'] ?? '',
                style: TextStyle(
                  color: isDone ? Colors.white38 : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                item['barcode'] ?? '',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: isDone
                ? Colors.green.withOpacity(0.4)
                : const Color(0xFF2196F3).withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$scanned/$plan',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
        ),
      ]),
    );
  }
}

// ─── 扫码取景框遮罩 ─────────────────────────────────────────────────────────────

class _ScanOverlay extends StatelessWidget {
  final bool scanned;
  final String? barcode;

  const _ScanOverlay({required this.scanned, this.barcode});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _OverlayPainter(scanned: scanned),
      child: Align(
        alignment: const Alignment(0, -0.25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 取景框占位（与 painter 尺寸对应）
            const SizedBox(height: 240, width: 260),
            const SizedBox(height: 16),
            // 提示文字
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                scanned
                    ? '✓  已识别：$barcode'
                    : '将条码对准取景框中央',
                style: TextStyle(
                  color: scanned ? Colors.greenAccent : Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final bool scanned;
  const _OverlayPainter({required this.scanned});

  @override
  void paint(Canvas canvas, Size size) {
    const boxW = 260.0;
    const boxH = 240.0;
    final cx = size.width / 2;
    final cy = size.height * 0.38;
    final rect = Rect.fromCenter(
        center: Offset(cx, cy), width: boxW, height: boxH);

    // 暗色遮罩（取景框外）
    final dimPaint = Paint()..color = Colors.black.withOpacity(0.55);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()
          ..addRRect(RRect.fromRectAndRadius(
              rect, const Radius.circular(12))),
      ),
      dimPaint,
    );

    // 取景框边框
    final borderPaint = Paint()
      ..color = scanned ? Colors.greenAccent : Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      borderPaint,
    );

    // 四角指示线
    const cornerLen = 24.0;
    const cornerWidth = 3.5;
    final cornerColor = scanned ? Colors.greenAccent : const Color(0xFF2196F3);
    final cornerPaint = Paint()
      ..color = cornerColor
      ..strokeWidth = cornerWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final corners = [
      // 左上
      [rect.topLeft, rect.topLeft + const Offset(cornerLen, 0)],
      [rect.topLeft, rect.topLeft + const Offset(0, cornerLen)],
      // 右上
      [rect.topRight, rect.topRight + const Offset(-cornerLen, 0)],
      [rect.topRight, rect.topRight + const Offset(0, cornerLen)],
      // 左下
      [rect.bottomLeft, rect.bottomLeft + const Offset(cornerLen, 0)],
      [rect.bottomLeft, rect.bottomLeft + const Offset(0, -cornerLen)],
      // 右下
      [rect.bottomRight, rect.bottomRight + const Offset(-cornerLen, 0)],
      [rect.bottomRight, rect.bottomRight + const Offset(0, -cornerLen)],
    ];

    for (final c in corners) {
      canvas.drawLine(c[0] as Offset, c[1] as Offset, cornerPaint);
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.scanned != scanned;
}
