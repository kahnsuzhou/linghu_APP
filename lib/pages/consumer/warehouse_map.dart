import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/api_service.dart';

/// 消费者端 — 仓库地图页
class WarehouseMapPage extends StatefulWidget {
  final double userLat;
  final double userLng;

  const WarehouseMapPage({
    super.key,
    this.userLat = 39.9042,
    this.userLng = 116.4074,
  });

  @override
  State<WarehouseMapPage> createState() => _WarehouseMapPageState();
}

class _WarehouseMapPageState extends State<WarehouseMapPage> {
  List<Map<String, dynamic>> _warehouses = [];
  bool _loading = true;
  int? _selectedId;
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().getWarehouseMap(widget.userLat, widget.userLng);
      if (res['code'] == 200) {
        setState(() {
          _warehouses = (res['data'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
        });
      }
    } catch (_) {
      // Mock 数据兜底
      setState(() {
        _warehouses = [
          {
            'warehouseId': 1, 'name': '平高冷链物流园Mini仓',
            'address': '上海市浦东新区航塘公路', 'lat': 30.981632, 'lng': 121.59734,
            'type': 'MINI', 'productCount': 5, 'totalStock': 240, 'distance': '1.2km'
          },
          {
            'warehouseId': 2, 'name': '海淀区中关村Mini仓',
            'address': '北京市海淀区中关村南大街27号', 'lat': 39.978, 'lng': 116.312,
            'type': 'MINI', 'productCount': 3, 'totalStock': 120, 'distance': '3.5km'
          },
        ];
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  LatLng get _center {
    if (_warehouses.isEmpty) return LatLng(widget.userLat, widget.userLng);
    // 以第一个仓库（最近）为默认中心
    final first = _warehouses.first;
    return LatLng((first['lat'] as num).toDouble(), (first['lng'] as num).toDouble());
  }

  // 仓库类型颜色
  Color _typeColor(String? type) {
    switch (type) {
      case 'LARGE': return const Color(0xFF9C27B0);
      case 'STANDARD': return const Color(0xFF2196F3);
      default: return const Color(0xFFFF6B35); // MINI
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('附近仓库'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadWarehouses),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B35)))
          : Column(
              children: [
                // 地图区域
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _center,
                          initialZoom: 12,
                          onTap: (_, __) => setState(() => _selectedId = null),
                        ),
                        children: [
                          // 高德地图中文底图（支持 CORS，无需 API Key）
                          TileLayer(
                            urlTemplate:
                                'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                            subdomains: const ['1', '2', '3', '4'],
                            userAgentPackageName: 'com.linghu.app',
                            maxZoom: 18,
                          ),
                          // 用户位置圆圈
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: LatLng(widget.userLat, widget.userLng),
                                radius: 8,
                                color: const Color(0xFFFF6B35).withOpacity(0.8),
                                borderStrokeWidth: 2,
                                borderColor: Colors.white,
                              ),
                              CircleMarker(
                                point: LatLng(widget.userLat, widget.userLng),
                                radius: 30,
                                color: const Color(0xFFFF6B35).withOpacity(0.12),
                                borderStrokeWidth: 0,
                                borderColor: Colors.transparent,
                              ),
                            ],
                          ),
                          // 仓库标记
                          MarkerLayer(
                            markers: _warehouses.map((w) {
                              final id = w['warehouseId'] as int;
                              final isSelected = _selectedId == id;
                              final color = _typeColor(w['type'] as String?);
                              return Marker(
                                point: LatLng(
                                  (w['lat'] as num).toDouble(),
                                  (w['lng'] as num).toDouble(),
                                ),
                                width: isSelected ? 56 : 44,
                                height: isSelected ? 64 : 52,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() => _selectedId = id);
                                    _mapController.move(
                                      LatLng((w['lat'] as num).toDouble(),
                                          (w['lng'] as num).toDouble()),
                                      14,
                                    );
                                  },
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: isSelected ? color : color.withOpacity(0.85),
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: color.withOpacity(0.4),
                                              blurRadius: isSelected ? 12 : 4,
                                              spreadRadius: isSelected ? 2 : 0,
                                            ),
                                          ],
                                          border: isSelected
                                              ? Border.all(color: Colors.white, width: 2)
                                              : null,
                                        ),
                                        child: Icon(
                                          Icons.warehouse,
                                          color: Colors.white,
                                          size: isSelected ? 22 : 18,
                                        ),
                                      ),
                                      // 小三角尖
                                      CustomPaint(
                                        painter: _TrianglePainter(color: isSelected ? color : color.withOpacity(0.85)),
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
                      // 图例
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLegend(const Color(0xFFFF6B35), 'MINI 仓'),
                              const SizedBox(height: 4),
                              _buildLegend(const Color(0xFF2196F3), 'STANDARD 仓'),
                              const SizedBox(height: 4),
                              _buildLegend(const Color(0xFF9C27B0), 'LARGE 仓'),
                              const SizedBox(height: 4),
                              Row(children: [
                                Container(
                                  width: 10, height: 10,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6B35),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text('我的位置', style: TextStyle(fontSize: 10)),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 仓库列表
                Expanded(
                  flex: 2,
                  child: Container(
                    color: Colors.grey[50],
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            children: [
                              const Icon(Icons.warehouse, size: 16, color: Color(0xFFFF6B35)),
                              const SizedBox(width: 6),
                              Text('共 ${_warehouses.length} 个仓库',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            itemCount: _warehouses.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, i) => _buildWarehouseCard(_warehouses[i]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _buildWarehouseCard(Map<String, dynamic> warehouse) {
    final id = warehouse['warehouseId'] as int;
    final isSelected = _selectedId == id;
    final color = _typeColor(warehouse['type'] as String?);
    final stock = (warehouse['totalStock'] as num? ?? 0).toInt();
    final products = (warehouse['productCount'] as num? ?? 0).toInt();

    return GestureDetector(
      onTap: () {
        setState(() => _selectedId = id);
        _mapController.move(
          LatLng((warehouse['lat'] as num).toDouble(), (warehouse['lng'] as num).toDouble()),
          14,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[200]!,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withOpacity(0.15), blurRadius: 8)]
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.warehouse, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(warehouse['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(warehouse['address'] ?? '',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      _buildChip(Icons.inventory_2_outlined, '$products 种商品', color),
                      const SizedBox(width: 6),
                      _buildChip(Icons.layers_outlined, '$stock 件库存', Colors.grey),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                Text(warehouse['distance'] ?? '',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(warehouse['type'] ?? 'MINI',
                      style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}

// 绘制标记底部小三角
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
