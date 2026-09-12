import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

/// 地图选点页
/// 用法：
///   final result = await Navigator.push<LocationPickResult>(
///     context,
///     MaterialPageRoute(builder: (_) => LocationPickerPage(
///       initialLat: 39.9042, initialLng: 116.4074,
///     )),
///   );
///   if (result != null) { ... result.lat, result.lng, result.address }
///
class LocationPickerPage extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final String title;

  const LocationPickerPage({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.title = '选择位置',
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  late MapController _mapController;
  late LatLng _pickedPoint;

  // 逆地理编码结果
  String _address = '移动地图选择位置';
  String _city    = '';
  String _province = '';
  String _district = '';
  bool _resolving = false;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pickedPoint = LatLng(widget.initialLat, widget.initialLng);
    // 初始化时解析地址
    _resolveAddress(_pickedPoint.latitude, _pickedPoint.longitude);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Nominatim 逆地理编码（OSM，无需 API Key）
  Future<void> _resolveAddress(double lat, double lng) async {
    if (!mounted) return;
    setState(() => _resolving = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2&lat=$lat&lon=$lng&accept-language=zh-CN',
      );
      final resp = await http.get(url, headers: {
        'User-Agent': 'LinghuApp/1.0',
      }).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>? ?? {};

        // 解析省市区
        final province = (addr['state'] as String?) ??
            (addr['province'] as String?) ?? '';
        final city = (addr['city'] as String?) ??
            (addr['county'] as String?) ??
            (addr['town'] as String?) ?? '';
        final district = (addr['district'] as String?) ??
            (addr['suburb'] as String?) ??
            (addr['quarter'] as String?) ?? '';
        final road = (addr['road'] as String?) ??
            (addr['street'] as String?) ?? '';
        final houseNumber = (addr['house_number'] as String?) ?? '';
        final displayName = data['display_name'] as String? ?? '';

        // 组合显示地址（优先精细地址，降级到 display_name 前段）
        String addrText = [road, houseNumber].where((s) => s.isNotEmpty).join('');
        if (addrText.isEmpty) {
          addrText = displayName.split(',').take(3).join(' ').trim();
        }

        if (mounted) {
          setState(() {
            _province = province;
            _city     = city;
            _district = district;
            _address  = addrText.isNotEmpty ? addrText : '$province$city$district';
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _address = '地址解析失败，坐标已记录');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    final center = camera.center;
    setState(() => _pickedPoint = center);

    // 防抖：停止拖动 800ms 后再解析地址，避免频繁请求
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      _resolveAddress(center.latitude, center.longitude);
    });
  }

  void _confirm() {
    Navigator.pop(context, LocationPickResult(
      lat: _pickedPoint.latitude,
      lng: _pickedPoint.longitude,
      address:  _address,
      province: _province,
      city:     _city,
      district: _district,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _resolving ? null : _confirm,
            child: const Text('确认',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 地址显示栏 ──────────────────────────────────────────
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.location_on,
                    color: const Color(0xFFFF6B35), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_resolving)
                            const SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Color(0xFFFF6B35)),
                            )
                          else
                            const Icon(Icons.check_circle,
                                color: Color(0xFF4CAF50), size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _resolving ? '地址解析中...' : _address,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (_province.isNotEmpty || _city.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '$_province$_city$_district',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${_pickedPoint.latitude.toStringAsFixed(5)}\n'
                  '${_pickedPoint.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── 地图区域 ──────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pickedPoint,
                    initialZoom: 15,
                    onPositionChanged: _onMapPositionChanged,
                  ),
                  children: [
                    // 高德中文底图（无需 API Key）
                    TileLayer(
                      urlTemplate:
                          'https://webrd0{s}.is.autonavi.com/appmaptile'
                          '?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                      subdomains: const ['1', '2', '3', '4'],
                      userAgentPackageName: 'com.linghu.app',
                      maxZoom: 18,
                    ),
                  ],
                ),

                // 中心 Pin（固定在屏幕正中，地图在它下面移动）
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const Icon(Icons.location_on,
                            color: Color(0xFFFF6B35), size: 28),
                      ),
                      // 针尖阴影
                      Container(
                        width: 8, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),

                // 右下角：重置到初始位置按钮
                Positioned(
                  right: 12,
                  bottom: 80,
                  child: FloatingActionButton.small(
                    heroTag: 'resetLocation',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFFF6B35),
                    tooltip: '回到初始位置',
                    onPressed: () {
                      _mapController.move(
                        LatLng(widget.initialLat, widget.initialLng), 15);
                    },
                    child: const Icon(Icons.my_location, size: 20),
                  ),
                ),

                // 提示文字
                Positioned(
                  bottom: 16,
                  left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '拖动地图，将 Pin 对准目标位置',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 底部确认按钮 ─────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _resolving ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: _resolving
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            ),
                            SizedBox(width: 8),
                            Text('解析地址中...'),
                          ],
                        )
                      : const Text('确认此位置',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 地图选点结果
class LocationPickResult {
  final double lat;
  final double lng;
  final String address;
  final String province;
  final String city;
  final String district;

  const LocationPickResult({
    required this.lat,
    required this.lng,
    required this.address,
    this.province = '',
    this.city = '',
    this.district = '',
  });
}
