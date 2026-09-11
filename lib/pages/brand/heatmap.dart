import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/api_service.dart';

/// 品牌方热力图页（库存 + 订单热力）
class BrandHeatmapPage extends StatefulWidget {
  const BrandHeatmapPage({super.key});

  @override
  State<BrandHeatmapPage> createState() => _BrandHeatmapPageState();
}

enum _HeatmapMode { inventory, orders }

class _BrandHeatmapPageState extends State<BrandHeatmapPage> {
  List<Map<String, dynamic>> _data = [];
  bool _loading = true;
  _HeatmapMode _mode = _HeatmapMode.inventory;
  int? _selectedId;
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().getBrandHeatmap();
      if (res['code'] == 200) {
        setState(() {
          _data = (res['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {
      setState(() {
        _data = [
          {
            'warehouseId': 1, 'name': '平高冷链物流园Mini仓',
            'address': '上海市浦东新区航塘公路',
            'lat': 30.981632, 'lng': 121.59734,
            'type': 'MINI', 'totalInventory': 240, 'productCount': 5, 'orderCount': 5,
          },
          {
            'warehouseId': 2, 'name': '海淀区中关村Mini仓',
            'address': '北京市海淀区中关村南大街27号',
            'lat': 39.978, 'lng': 116.312,
            'type': 'MINI', 'totalInventory': 120, 'productCount': 3, 'orderCount': 1,
          },
        ];
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 当前模式下每个点的"强度"值（0.0 - 1.0）
  double _intensity(Map<String, dynamic> w) {
    final values = _data.map((d) {
      return _mode == _HeatmapMode.inventory
          ? (d['totalInventory'] as num? ?? 0).toDouble()
          : (d['orderCount'] as num? ?? 0).toDouble();
    }).toList();
    final maxVal = values.isEmpty ? 1.0 : values.reduce(max);
    if (maxVal == 0) return 0.0;
    final val = _mode == _HeatmapMode.inventory
        ? (w['totalInventory'] as num? ?? 0).toDouble()
        : (w['orderCount'] as num? ?? 0).toDouble();
    return (val / maxVal).clamp(0.1, 1.0);
  }

  Color _heatColor(double intensity) {
    if (_mode == _HeatmapMode.inventory) {
      // 绿→黄→橙 渐变
      if (intensity < 0.5) {
        return Color.lerp(const Color(0xFF4CAF50), const Color(0xFFFFEB3B), intensity * 2)!;
      } else {
        return Color.lerp(const Color(0xFFFFEB3B), const Color(0xFFFF6B35), (intensity - 0.5) * 2)!;
      }
    } else {
      // 蓝→紫→红 渐变（订单热力）
      if (intensity < 0.5) {
        return Color.lerp(const Color(0xFF2196F3), const Color(0xFF9C27B0), intensity * 2)!;
      } else {
        return Color.lerp(const Color(0xFF9C27B0), const Color(0xFFF44336), (intensity - 0.5) * 2)!;
      }
    }
  }

  LatLng get _center {
    if (_data.isEmpty) return const LatLng(35.0, 116.0);
    // 计算所有仓库的中心点
    double sumLat = 0, sumLng = 0;
    for (final w in _data) {
      sumLat += (w['lat'] as num).toDouble();
      sumLng += (w['lng'] as num).toDouble();
    }
    return LatLng(sumLat / _data.length, sumLng / _data.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('仓库热力图'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
          : Column(
              children: [
                // 模式切换
                Container(
                  color: const Color(0xFF4CAF50).withOpacity(0.08),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildModeBtn(
                          _HeatmapMode.inventory,
                          Icons.inventory_2_outlined,
                          '库存热力',
                          const Color(0xFF4CAF50),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildModeBtn(
                          _HeatmapMode.orders,
                          Icons.receipt_long_outlined,
                          '订单热力',
                          const Color(0xFF2196F3),
                        ),
                      ),
                    ],
                  ),
                ),
                // 地图
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _center,
                          initialZoom: _data.length <= 1 ? 10 : 5,
                          onTap: (_, __) => setState(() => _selectedId = null),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                            subdomains: const ['1', '2', '3', '4'],
                            userAgentPackageName: 'com.linghu.app',
                            maxZoom: 18,
                          ),
                          // 热力圆（大圆渐变 + 实心圆）
                          CircleLayer(
                            circles: [
                              for (final w in _data) ...[
                                // 外层热力光晕（大半径低透明度）
                                CircleMarker(
                                  point: LatLng(
                                    (w['lat'] as num).toDouble(),
                                    (w['lng'] as num).toDouble(),
                                  ),
                                  radius: 20 + _intensity(w) * 35,
                                  useRadiusInMeter: false,
                                  color: _heatColor(_intensity(w)).withOpacity(0.13 + _intensity(w) * 0.17),
                                  borderStrokeWidth: 0,
                                  borderColor: Colors.transparent,
                                ),
                                // 中层光晕
                                CircleMarker(
                                  point: LatLng(
                                    (w['lat'] as num).toDouble(),
                                    (w['lng'] as num).toDouble(),
                                  ),
                                  radius: 10 + _intensity(w) * 20,
                                  useRadiusInMeter: false,
                                  color: _heatColor(_intensity(w)).withOpacity(0.25 + _intensity(w) * 0.2),
                                  borderStrokeWidth: 0,
                                  borderColor: Colors.transparent,
                                ),
                              ],
                            ],
                          ),
                          // 仓库标记点
                          MarkerLayer(
                            markers: _data.map((w) {
                              final id = w['warehouseId'] as int;
                              final isSelected = _selectedId == id;
                              final color = _heatColor(_intensity(w));
                              return Marker(
                                point: LatLng(
                                  (w['lat'] as num).toDouble(),
                                  (w['lng'] as num).toDouble(),
                                ),
                                width: 48,
                                height: 56,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() => _selectedId = id);
                                    _mapController.move(
                                      LatLng((w['lat'] as num).toDouble(),
                                          (w['lng'] as num).toDouble()),
                                      12,
                                    );
                                  },
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: color.withOpacity(0.5),
                                              blurRadius: isSelected ? 16 : 6,
                                              spreadRadius: isSelected ? 3 : 0,
                                            ),
                                          ],
                                          border: isSelected
                                              ? Border.all(color: Colors.white, width: 2)
                                              : null,
                                        ),
                                        child: Icon(
                                          _mode == _HeatmapMode.inventory
                                              ? Icons.inventory_2
                                              : Icons.receipt_long,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                      CustomPaint(
                                        painter: _TrianglePainter(color: color),
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
                      // 渐变色阶图例
                      Positioned(
                        bottom: 16,
                        left: 16,
                        child: _buildColorScale(),
                      ),
                    ],
                  ),
                ),
                // 数据列表
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
                              Icon(
                                _mode == _HeatmapMode.inventory
                                    ? Icons.inventory_2_outlined
                                    : Icons.receipt_long_outlined,
                                size: 16,
                                color: const Color(0xFF4CAF50),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _mode == _HeatmapMode.inventory ? '库存分布' : '订单分布',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            itemCount: _data.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, i) => _buildDataCard(_data[i]),
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

  Widget _buildModeBtn(_HeatmapMode mode, IconData icon, String label, Color color) {
    final isActive = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _mode = mode;
        _selectedId = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? color : Colors.grey[300]!),
          boxShadow: isActive
              ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 6)]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.white : color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.white : color,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildColorScale() {
    final colors = _mode == _HeatmapMode.inventory
        ? [const Color(0xFF4CAF50), const Color(0xFFFFEB3B), const Color(0xFFFF6B35)]
        : [const Color(0xFF2196F3), const Color(0xFF9C27B0), const Color(0xFFF44336)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _mode == _HeatmapMode.inventory ? '库存量' : '订单量',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('低', style: TextStyle(fontSize: 9, color: Colors.grey)),
              const SizedBox(width: 4),
              Container(
                width: 80,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(colors: colors),
                ),
              ),
              const SizedBox(width: 4),
              const Text('高', style: TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataCard(Map<String, dynamic> w) {
    final id = w['warehouseId'] as int;
    final isSelected = _selectedId == id;
    final color = _heatColor(_intensity(w));
    final intensity = _intensity(w);

    final metricVal = _mode == _HeatmapMode.inventory
        ? (w['totalInventory'] as num? ?? 0).toInt()
        : (w['orderCount'] as num? ?? 0).toInt();
    final metricLabel = _mode == _HeatmapMode.inventory ? '件库存' : '笔订单';

    return GestureDetector(
      onTap: () {
        setState(() => _selectedId = id);
        _mapController.move(
          LatLng((w['lat'] as num).toDouble(), (w['lng'] as num).toDouble()),
          12,
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
                  Text(w['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: intensity,
                      minHeight: 5,
                      backgroundColor: Colors.grey[200],
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$metricVal',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    )),
                Text(metricLabel,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
