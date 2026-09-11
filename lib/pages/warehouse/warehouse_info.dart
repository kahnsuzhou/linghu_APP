import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';
import '../common/location_picker_page.dart';

// ========== 仓库列表管理页 ==========
class WarehouseInfoPage extends StatefulWidget {
  const WarehouseInfoPage({super.key});

  @override
  State<WarehouseInfoPage> createState() => _WarehouseInfoPageState();
}

class _WarehouseInfoPageState extends State<WarehouseInfoPage> {
  List<Map<String, dynamic>> _warehouses = [];
  int _quota = 2;
  int _vipLevel = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiService().getWarehouseList();
      if (resp['code'] == 200 && resp['data'] != null) {
        final rawData = resp['data'];
        final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
        setState(() {
          _warehouses = (data['warehouses'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          _quota = (data['quota'] as num? ?? 2).toInt();
          _vipLevel = (data['vipLevel'] as num? ?? 0).toInt();
        });
      }
    } catch (_) {
      // 兜底：尝试旧接口
      try {
        final resp = await ApiService().getWarehouseInfo();
        if (resp['code'] == 200 && resp['data'] != null) {
          setState(() {
            final rawInfo = resp['data'];
            _warehouses = rawInfo is Map ? [Map<String, dynamic>.from(rawInfo)] : [];
            _quota = 2;
          });
        }
      } catch (_) {}
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteWarehouse(Map<String, dynamic> warehouse) async {
    final name = warehouse['name'] ?? '该仓库';
    final auditStatus = warehouse['auditStatus'] as String? ?? 'APPROVED';

    // 被拒仓库直接确认删除，不需要提醒进行中任务
    final tipText = auditStatus == 'REJECTED'
        ? '确定删除审核被拒的「$name」？删除后可重新申请入驻。'
        : '确定要删除「$name」吗？删除后不可恢复，进行中的任务会阻止删除。';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除仓库'),
        content: Text(tipText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final id = (warehouse['id'] as num).toInt();
      final res = await ApiService().deleteWarehouse(id);
      if (res['code'] == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('仓库已删除'), backgroundColor: Colors.grey));
          _load();
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['msg'] ?? '删除失败'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$e'), backgroundColor: Colors.red));
    }
  }

  String _typeEmoji(String? type) {
    switch (type) {
      case 'LARGE': return '🏭';
      case 'STANDARD': return '🏢';
      default: return '🏠';
    }
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'LARGE': return const Color(0xFF9C27B0);
      case 'STANDARD': return const Color(0xFF2196F3);
      default: return const Color(0xFFFF6B35);
    }
  }

  @override
  Widget build(BuildContext context) {
    // REJECTED仓库不占配额，仓主可以删掉重新申请
    final activeCount = _warehouses.where((w) {
      final a = w['auditStatus'] as String? ?? 'APPROVED';
      return a != 'REJECTED';
    }).length;
    final canCreate = activeCount < _quota;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('我的仓库'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 配额说明横幅
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _vipLevel >= 1
                          ? [const Color(0xFFFFD700), const Color(0xFFFFA000)]
                          : [const Color(0xFF2196F3), const Color(0xFF64B5F6)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _vipLevel >= 1 ? '⭐ VIP仓主' : '🏠 普通仓主',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '已创建 $activeCount / $_quota 个仓库',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const Spacer(),
                      if (_vipLevel < 1)
                        GestureDetector(
                          onTap: () => _showVipDialog(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white60),
                            ),
                            child: const Text('升级VIP', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                ),
                // 仓库卡片列表
                Expanded(
                  child: _warehouses.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('🏠', style: TextStyle(fontSize: 64)),
                              const SizedBox(height: 12),
                              const Text('还没有仓库', style: TextStyle(color: Colors.grey, fontSize: 16)),
                              const SizedBox(height: 6),
                              const Text('点击右下角按钮创建第一个仓库', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _warehouses.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) => _buildWarehouseCard(_warehouses[i]),
                        ),
                ),
              ],
            ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: canCreate
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WarehouseEditPage()),
                      ).then((_) => _load())
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_vipLevel >= 1
                              ? 'VIP仓主最多创建 $_quota 个仓库，已达上限'
                              : '普通仓主最多创建 $_quota 个仓库，升级VIP可增至5个'),
                          backgroundColor: Colors.orange,
                        ),
                      ),
              backgroundColor: canCreate ? const Color(0xFF2196F3) : Colors.grey,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(canCreate ? '新建仓库' : '已达上限'),
            ),
    );
  }

  Widget _buildWarehouseCard(Map<String, dynamic> w) {
    final type = w['type'] as String? ?? 'MINI';
    final color = _typeColor(type);
    final status = (w['status'] as num? ?? 1).toInt();
    final auditStatus = w['auditStatus'] as String? ?? 'APPROVED';

    // 审核状态展示配置
    final auditConfig = {
      'PENDING':  {'label': '审核中', 'color': const Color(0xFFFF9800), 'bg': const Color(0xFFFFF3E0), 'icon': Icons.hourglass_top},
      'APPROVED': {'label': '已通过', 'color': const Color(0xFF4CAF50), 'bg': const Color(0xFFE8F5E9), 'icon': Icons.check_circle_outline},
      'REJECTED': {'label': '已拒绝', 'color': const Color(0xFFF44336), 'bg': const Color(0xFFFFEBEE), 'icon': Icons.cancel_outlined},
    };
    final audit = auditConfig[auditStatus] ?? auditConfig['PENDING']!;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                Text(_typeEmoji(type), style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w['name'] ?? '未命名仓库',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(type,
                                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          // 审核状态 tag（优先展示）
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (audit['bg'] as Color),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(audit['icon'] as IconData,
                                    size: 11, color: audit['color'] as Color),
                                const SizedBox(width: 3),
                                Text(
                                  audit['label'] as String,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: audit['color'] as Color,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 仅 APPROVED 时展示开放/关闭状态
                          if (auditStatus == 'APPROVED') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: status == 1 ? Colors.green[50] : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status == 1 ? '开放中' : '已关闭',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: status == 1 ? Colors.green : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // 拒绝原因提示条
            if (auditStatus == 'REJECTED' && w['auditRemark'] != null && (w['auditRemark'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF9A9A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 13, color: Color(0xFFF44336)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '拒绝原因：${w['auditRemark']}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFC62828)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // 待审核提示条
            if (auditStatus == 'PENDING') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.schedule, size: 13, color: Color(0xFFFF8F00)),
                    SizedBox(width: 6),
                    Text(
                      '仓库信息已提交，等待运营审核通过后将自动上线',
                      style: TextStyle(fontSize: 12, color: Color(0xFFE65100)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            // 地址
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(w['address'] ?? '--',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 面积 + 费率 + 发货方式
            Row(
              children: [
                _buildInfoChip(Icons.square_foot, '${w['areaSqm'] ?? '--'} ㎡'),
                const SizedBox(width: 10),
                _buildInfoChip(Icons.attach_money, '¥${w['serviceFeeRate'] ?? '--'}/单'),
                if (w['lat'] != null) ...[
                  const SizedBox(width: 10),
                  _buildInfoChip(Icons.my_location, '已定位'),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // 发货方式标签
            _buildDeliveryTags(w['supportedDeliveries'] as String?),
            const SizedBox(height: 12),
            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _deleteWarehouse(w),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => WarehouseEditPage(warehouse: w)),
                  ).then((_) => _load()),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('编辑', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildDeliveryTags(String? rawJson) {
    const labels = {
      'express': '快递',
      'delivery': '外卖配送',
      'pickup': '自提',
    };
    const colors = {
      'express': Color(0xFF2196F3),
      'delivery': Color(0xFFFF6B35),
      'pickup': Color(0xFF4CAF50),
    };
    Set<String> modes = {'express', 'delivery', 'pickup'};
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final parsed = rawJson.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '')
            .split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
        if (parsed.isNotEmpty) modes = parsed;
      } catch (_) {}
    }
    return Wrap(
      spacing: 6,
      children: modes.map((m) {
        final label = labels[m] ?? m;
        final color = colors[m] ?? Colors.grey;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        );
      }).toList(),
    );
  }

  void _showVipDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Text('⭐', style: TextStyle(fontSize: 24)),
            SizedBox(width: 8),
            Text('升级VIP仓主'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VIP仓主权益：', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('• 最多创建 5 个仓库（普通仓主限 2 个）'),
            Text('• 优先展示在消费者附近仓库列表'),
            Text('• 专属客服支持'),
            SizedBox(height: 12),
            Text('请联系平台运营团队升级', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }
}

// ========== 仓库编辑/创建子页 ==========
class WarehouseEditPage extends StatefulWidget {
  /// null = 创建模式；非 null = 编辑模式
  final Map<String, dynamic>? warehouse;

  const WarehouseEditPage({super.key, this.warehouse});

  @override
  State<WarehouseEditPage> createState() => _WarehouseEditPageState();
}

class _WarehouseEditPageState extends State<WarehouseEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _feeRateCtrl = TextEditingController();
  String _selectedType = 'MINI';
  double? _lat;
  double? _lng;
  bool _locating = false;
  // HTTP 环境下浏览器禁止定位，切换为手动输入
  bool get _isHttpEnv => kIsWeb && Uri.base.scheme == 'http';
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lngCtrl = TextEditingController();
  bool _saving = false;

  // 支持的发货方式（至少选一个）
  Set<String> _supportedDeliveries = {'express', 'delivery', 'pickup'};

  static const _deliveryModeOptions = [
    {'value': 'express',  'label': '快递配送', 'desc': '顺丰/京东/中通等，1-3天'},
    {'value': 'delivery', 'label': '外卖配送', 'desc': '骑手即时配送，30min-2h'},
    {'value': 'pickup',   'label': '到仓自提', 'desc': '消费者自行来仓取货，免运费'},
  ];

  bool get _isCreate => widget.warehouse == null;

  static const _typeOptions = [
    {'value': 'MINI', 'label': 'Mini仓', 'desc': '50㎡以下，适合居家闲置空间', 'icon': '🏠'},
    {'value': 'STANDARD', 'label': '标准仓', 'desc': '50–200㎡，专业仓储空间', 'icon': '🏢'},
    {'value': 'LARGE', 'label': '大型仓', 'desc': '200㎡以上，高容量仓储', 'icon': '🏭'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.warehouse != null) {
      final w = widget.warehouse!;
      _nameCtrl.text = w['name'] ?? '';
      _addressCtrl.text = w['address'] ?? '';
      _areaCtrl.text = (w['areaSqm'] ?? '').toString();
      _feeRateCtrl.text = (w['serviceFeeRate'] ?? '2.00').toString();
      _selectedType = w['type'] ?? 'MINI';
      _lat = w['lat'] != null ? double.tryParse(w['lat'].toString()) : null;
      _lng = w['lng'] != null ? double.tryParse(w['lng'].toString()) : null;
      // 解析已保存的发货方式
      final rawDelivery = w['supportedDeliveries'] as String? ?? '';
      if (rawDelivery.isNotEmpty) {
        try {
          final list = (rawDelivery.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '').split(','))
              .map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
          if (list.isNotEmpty) _supportedDeliveries = list;
        } catch (_) {}
      }
    } else {
      _feeRateCtrl.text = '2.00';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _areaCtrl.dispose();
    _feeRateCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() => _locating = true);
    try {
      // ── 第一步：IP 定位（无需权限，HTTP/HTTPS 均可）──────────────
      final ipOk = await _locateByIp();
      if (ipOk) {
        // IP 定位成功后，静默尝试 GPS 升级（不弹窗）
        _tryGpsUpgrade();
        return;
      }
      // ── 第二步：IP 失败则尝试 GPS ────────────────────────────────
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 15));
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('自动定位失败，请手动填写经纬度或输入地址', Colors.orange);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));
      if (mounted) {
        setState(() { _lat = pos.latitude; _lng = pos.longitude; });
        _snack('GPS定位成功：${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}', Colors.green);
      }
    } catch (_) {
      if (mounted) _snack('自动定位失败，请手动填写经纬度', Colors.orange);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// IP 定位：调用 ip-api.com，城市级精度，无需权限
  Future<bool> _locateByIp() async {
    try {
      final resp = await http.get(
        Uri.parse('http://ip-api.com/json/?lang=zh-CN&fields=status,city,lat,lon'),
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final lat = (data['lat'] as num?)?.toDouble();
          final lon = (data['lon'] as num?)?.toDouble();
          final city = (data['city'] as String?) ?? '';
          if (lat != null && lon != null && mounted) {
            setState(() { _lat = lat; _lng = lon; });
            _snack('已定位到：$city（${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}）', Colors.green);
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// 后台静默尝试 GPS 升级（仅当已有权限时）
  void _tryGpsUpgrade() async {
    try {
      final perm = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 3));
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));
      if (mounted) {
        setState(() { _lat = pos.latitude; _lng = pos.longitude; });
        _snack('GPS精确定位：${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}', Colors.green);
      }
    } catch (_) {}
  }

  /// HTTP 环境下手动输入经纬度并确认
  void _confirmManualLatLng() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) {
      _snack('请输入有效的经纬度数值', Colors.red);
      return;
    }
    if (lat < 3 || lat > 55 || lng < 70 || lng > 140) {
      _snack('经纬度超出中国范围，请确认是否填反', Colors.orange);
    }
    setState(() { _lat = lat; _lng = lng; });
    _snack('位置已设置：${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}', Colors.green);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lat == null || _lng == null) {
      _snack('请先获取仓库真实位置', Colors.orange);
      return;
    }
    setState(() => _saving = true);
    try {
      if (_supportedDeliveries.isEmpty) {
        _snack('请至少选择一种发货方式', Colors.orange);
        return;
      }
      // 构建 JSON 数组字符串
      final deliveriesJson = '[' +
          _supportedDeliveries.map((e) => '"$e"').join(',') + ']';
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'lat': _lat,
        'lng': _lng,
        'areaSqm': double.tryParse(_areaCtrl.text.trim()) ?? 0,
        'type': _selectedType,
        'serviceFeeRate': double.tryParse(_feeRateCtrl.text.trim()) ?? 2.0,
        'supportedDeliveries': deliveriesJson,
      };

      Map<String, dynamic> resp;
      if (_isCreate) {
        resp = await ApiService().createWarehouse(data);
      } else {
        data['id'] = widget.warehouse!['id'];
        resp = await ApiService().updateWarehouse(data);
      }

      if (resp['code'] == 200) {
        _snack(_isCreate ? '仓库创建成功！' : '仓库信息已更新', Colors.green);
        if (mounted) Navigator.pop(context);
      } else {
        _snack(resp['msg'] ?? '保存失败', Colors.red);
      }
    } catch (_) {
      _snack('网络错误，请重试', Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_isCreate ? '新建仓库' : '编辑仓库'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 提示
              if (_isCreate)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('填写仓库信息后即可接收品牌方铺货任务',
                            style: TextStyle(color: Colors.blue[800], fontSize: 13)),
                      ),
                    ],
                  ),
                ),

              // 仓库类型
              const Text('仓库类型 *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              ..._typeOptions.map((t) => _buildTypeOption(
                t['value']!, t['icon']!, t['label']!, t['desc']!)),
              const SizedBox(height: 20),

              // 基本信息
              const Text('基本信息', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nameCtrl,
                decoration: _deco('仓库名称', '例：朝阳区望京Mini仓', Icons.warehouse_outlined),
                validator: (v) => v == null || v.trim().isEmpty ? '请输入仓库名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: _deco('详细地址', '例：北京市朝阳区望京街道5号', Icons.location_on_outlined),
                validator: (v) => v == null || v.trim().isEmpty ? '请输入仓库地址' : null,
              ),
              const SizedBox(height: 16),

              // 定位
              const Text('真实地理位置 *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (false && _isHttpEnv) ...[
                // 保留旧的手动输入分支（已禁用）
              ] else ...[
                // 定位 + 地图选点
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _lat != null ? Colors.green[50] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _lat != null ? Colors.green[300]! : Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_lat != null ? Icons.my_location : Icons.location_off,
                              color: _lat != null ? Colors.green : Colors.grey),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _lat != null
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('定位成功',
                                          style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 13)),
                                      Text(
                                          '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                                          style: const TextStyle(
                                              color: Colors.grey, fontSize: 12)),
                                    ],
                                  )
                                : const Text('点击按钮自动获取或地图选点',
                                    style:
                                        TextStyle(color: Colors.grey, fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // 自动定位按钮
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _locating ? null : _getLocation,
                              icon: _locating
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF2196F3)))
                                  : const Icon(Icons.gps_fixed, size: 16),
                              label: Text(_locating
                                  ? '定位中...'
                                  : (_lat != null ? '重新定位' : '自动定位')),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2196F3),
                                side: const BorderSide(color: Color(0xFF2196F3)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // 地图选点按钮
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final result =
                                    await Navigator.push<LocationPickResult>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LocationPickerPage(
                                      initialLat: _lat ?? 39.9042,
                                      initialLng: _lng ?? 116.4074,
                                      title: '选择仓库位置',
                                    ),
                                  ),
                                );
                                if (result != null && mounted) {
                                  setState(() {
                                    _lat = result.lat;
                                    _lng = result.lng;
                                    // 如果地址字段为空，自动填入
                                    if (_addressCtrl.text.trim().isEmpty &&
                                        result.address.isNotEmpty) {
                                      _addressCtrl.text = result.address;
                                    }
                                  });
                                  _snack(
                                      '已选择：${result.province}${result.city}${result.district}',
                                      Colors.green);
                                }
                              },
                              icon: const Icon(Icons.map_outlined, size: 16),
                              label: const Text('地图选点'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6B35),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // 发货方式
              const Text('支持的发货方式 *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('至少选择一种，消费者结账时仅可选择您支持的方式',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 10),
              ..._deliveryModeOptions.map((opt) {
                final val = opt['value'] as String;
                final label = opt['label'] as String;
                final desc = opt['desc'] as String;
                final selected = _supportedDeliveries.contains(val);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (selected) {
                        if (_supportedDeliveries.length > 1) {
                          _supportedDeliveries.remove(val);
                        } else {
                          _snack('至少保留一种发货方式', Colors.orange);
                        }
                      } else {
                        _supportedDeliveries.add(val);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? Colors.blue[50] : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? const Color(0xFF2196F3) : Colors.grey[300]!,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          val == 'express'
                              ? Icons.local_shipping_outlined
                              : val == 'delivery'
                                  ? Icons.delivery_dining_outlined
                                  : Icons.store_outlined,
                          color: selected ? const Color(0xFF2196F3) : Colors.grey,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? const Color(0xFF2196F3) : Colors.black87,
                                  )),
                              const SizedBox(height: 2),
                              Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Checkbox(
                          value: selected,
                          activeColor: const Color(0xFF2196F3),
                          onChanged: (_) {
                            setState(() {
                              if (selected) {
                                if (_supportedDeliveries.length > 1) {
                                  _supportedDeliveries.remove(val);
                                } else {
                                  _snack('至少保留一种发货方式', Colors.orange);
                                }
                              } else {
                                _supportedDeliveries.add(val);
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 10),

              // 规格
              const Text('仓储规格', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _areaCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _deco('面积（㎡）', '例：50', Icons.square_foot),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return '请输入面积';
                        if (double.tryParse(v.trim()) == null) return '请输入有效数字';
                        if (double.parse(v.trim()) <= 0) return '面积须大于0';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _feeRateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _deco('服务费率（元/单）', '例：2.00', Icons.attach_money),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return '请输入费率';
                        if (double.tryParse(v.trim()) == null) return '请输入有效数字';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : Text(_isCreate ? '创建仓库' : '保存修改',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeOption(String value, String emoji, String label, String desc) {
    final selected = _selectedType == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? Colors.blue[50] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF2196F3) : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold,
                    color: selected ? const Color(0xFF2196F3) : Colors.black87,
                  )),
                  const SizedBox(height: 2),
                  Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: Color(0xFF2196F3)),
          ],
        ),
      ),
    );
  }

  InputDecoration _deco(String label, String hint, IconData icon) => InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon, size: 20),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}
