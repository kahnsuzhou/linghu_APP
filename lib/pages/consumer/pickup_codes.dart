import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/api_service.dart';

class PickupCodesPage extends StatefulWidget {
  const PickupCodesPage({super.key});

  @override
  State<PickupCodesPage> createState() => _PickupCodesPageState();
}

class _PickupCodesPageState extends State<PickupCodesPage> {
  List<Map<String, dynamic>> _records = [];
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
      // 并发拉取：普通订单自提码 + 活动订单自提码
      final results = await Future.wait([
        ApiService().getMyOrderPickupCodes(),   // 普通订单
        ApiService().getMyPickupCodes(),         // 活动订单
      ]);

      final List<Map<String, dynamic>> all = [];

      // 普通订单
      final orderRes = results[0];
      if (orderRes['code'] == 200) {
        final data = orderRes['data'];
        final rawList = data is List ? data : (data is Map ? (data['records'] as List? ?? []) : []);
        for (final e in rawList) {
          final item = Map<String, dynamic>.from(e as Map);
          item['_type'] = 'order';
          all.add(item);
        }
      }

      // 活动订单
      final actRes = results[1];
      if (actRes['code'] == 200) {
        final data = actRes['data'];
        final rawList = data is List ? data : (data is Map ? (data['records'] as List? ?? []) : []);
        for (final e in rawList) {
          final item = Map<String, dynamic>.from(e as Map);
          item['_type'] = 'activity';
          all.add(item);
        }
      }

      // 待核销的排最前面
      all.sort((a, b) {
        final aDone = _isDone(a);
        final bDone = _isDone(b);
        if (aDone != bDone) return aDone ? 1 : -1;
        return 0;
      });

      setState(() {
        _records = all;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '网络错误：$e';
        _loading = false;
      });
    }
  }

  bool _isDone(Map<String, dynamic> r) {
    final status = r['status'] as String? ?? '';
    return status == 'PICKED_UP' || status == 'FINISHED';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的自提码'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _records.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Column(
                                children: [
                                  Icon(Icons.qr_code_2, size: 64, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text('暂无自提码', style: TextStyle(color: Colors.grey, fontSize: 16)),
                                  SizedBox(height: 8),
                                  Text('选择自提方式下单后，自提码将显示在这里',
                                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _records.length,
                          itemBuilder: (context, index) {
                            return _PickupCodeCard(record: _records[index]);
                          },
                        ),
                ),
    );
  }
}

class _PickupCodeCard extends StatelessWidget {
  final Map<String, dynamic> record;

  const _PickupCodeCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final type = record['_type'] as String? ?? 'order';
    final status = record['status'] as String? ?? '';
    final pickUpCode = record['pickUpCode'] as String? ?? '';
    final warehouseName = record['warehouseName'] as String? ?? '';

    // 标题：活动订单用活动名，普通订单用商品名
    final title = type == 'activity'
        ? (record['activityName'] as String? ?? '活动订单')
        : (record['productName'] as String? ?? '自提订单');

    // 是否已完成
    final isDone = status == 'PICKED_UP' || status == 'FINISHED';

    // 状态文字和颜色
    String statusLabel;
    Color statusColor;
    if (status == 'PICKED_UP' || status == 'FINISHED') {
      // 活动订单核销后为 PICKED_UP，普通自提订单完成后为 FINISHED
      statusLabel = '已核销';
      statusColor = Colors.grey;
    } else if (status == 'CANCELLED') {
      statusLabel = '已取消';
      statusColor = Colors.red;
    } else {
      // PENDING_DELIVERY / DELIVERING 等待中状态均显示"待核销"
      statusLabel = '待核销';
      statusColor = Colors.green;
    }

    // 标签（活动 / 普通）
    final typeLabel = type == 'activity' ? '活动' : '普通';
    final typeColor = type == 'activity' ? const Color(0xFFFF6B35) : const Color(0xFF4A90D9);

    Widget card = Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：类型标签 + 标题 + 状态
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: typeColor, width: 0.8),
                  ),
                  child: Text(typeLabel,
                      style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    border: Border.all(color: statusColor),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // 中间：大字自提码
            Center(
              child: GestureDetector(
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: pickUpCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('自提码已复制'), duration: Duration(seconds: 1)),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3EE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatCode(pickUpCode),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 12,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text('长按复制自提码', style: TextStyle(color: Colors.grey, fontSize: 11)),
            ),
            const SizedBox(height: 20),

            // 二维码
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFF6B35), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B35).withOpacity(0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: pickUpCode,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFFFF6B35),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '出示二维码给仓主扫码核销',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 底部：仓库名
            if (warehouseName.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.warehouse_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      warehouseName,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );

    if (isDone) {
      return Stack(
        children: [
          Opacity(opacity: 0.55, child: card),
          Positioned.fill(
            child: Center(
              child: Transform.rotate(
                angle: -0.4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return card;
  }

  String _formatCode(String code) {
    if (code.length == 6) return '${code.substring(0, 3)} ${code.substring(3)}';
    return code;
  }
}
