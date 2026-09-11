import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';
import '../../config/constants.dart';
import '../common/location_picker_page.dart';
import 'cart.dart';
import 'warehouse_map.dart';
import 'search_page.dart';
import 'activity_invite.dart';

/// 消费者首页 - 附近商品瀑布流
class ConsumerHomePage extends StatefulWidget {
  const ConsumerHomePage({super.key});

  @override
  State<ConsumerHomePage> createState() => _ConsumerHomePageState();
}

class _ConsumerHomePageState extends State<ConsumerHomePage> {
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  double _lat = 39.9042;
  double _lng = 116.4074;

  // 定位状态：'locating' | 'located' | 'failed' | 'manual'
  String _locateStatus = 'locating';
  String _locationLabel = '定位中...';

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    if (!mounted) return;
    setState(() {
      _locateStatus = 'locating';
      _locationLabel = '定位中...';
    });

    // ── 第一步：IP 定位（快速兜底，无需权限）────────────────────────
    final ipLocated = await _locateByIp();

    if (ipLocated) {
      // IP 定位成功：立刻加载商品，让用户看到正确城市的商品
      await _loadProducts();
      // 再静默尝试 GPS 精确定位（后台，不阻塞页面）
      _tryGpsUpgrade();
    } else {
      // IP 定位也失败（网络断了等极端情况）：尝试 GPS
      final gpsLocated = await _locateByGps(showRequest: true);
      if (!gpsLocated && mounted) {
        // 两种都失败，降级到默认北京坐标，提示用户手动选
        setState(() {
          _locateStatus = 'failed';
          _locationLabel = '定位失败';
        });
      }
      await _loadProducts();
    }
  }

  /// IP 定位：调用 ip-api.com，解析城市名 + 坐标
  /// 返回是否成功
  Future<bool> _locateByIp() async {
    try {
      final resp = await http.get(
        Uri.parse('http://ip-api.com/json/?lang=zh-CN&fields=status,city,lat,lon,regionName'),
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final city = (data['city'] as String?) ?? '';
          final region = (data['regionName'] as String?) ?? '';
          final lat = (data['lat'] as num?)?.toDouble();
          final lon = (data['lon'] as num?)?.toDouble();
          if (lat != null && lon != null && mounted) {
            setState(() {
              _lat = lat;
              _lng = lon;
              _locateStatus = 'located';
              // 优先显示城市名，退而显示省/地区名
              _locationLabel = city.isNotEmpty ? city : (region.isNotEmpty ? region : '已定位');
            });
            return true;
          }
        }
      }
    } catch (_) {
      // 网络超时或解析失败，静默
    }
    return false;
  }

  /// 尝试 GPS 精确定位，成功则替换 IP 坐标并显示精确标记
  /// [showRequest] 为 true 时会触发权限弹窗（主动重试时用）
  Future<bool> _locateByGps({bool showRequest = false}) async {
    try {
      bool serviceEnabled = false;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled()
            .timeout(const Duration(seconds: 3));
      } catch (_) {}

      if (!serviceEnabled) return false;

      LocationPermission perm;
      try {
        perm = await Geolocator.checkPermission()
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        return false;
      }

      if (perm == LocationPermission.denied && showRequest) {
        try {
          perm = await Geolocator.requestPermission()
              .timeout(const Duration(seconds: 15));
        } catch (_) {
          return false;
        }
      }

      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return false;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 12));

      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _locateStatus = 'located';
          _locationLabel = '精确定位';
        });
        // GPS 成功后刷新一次商品（比 IP 更精准）
        _loadProducts();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 后台静默尝试 GPS（不弹权限窗），仅当已有权限时升级
  void _tryGpsUpgrade() {
    _locateByGps(showRequest: false);
  }

  void _setLocationFailed(String reason) {
    if (!mounted) return;
    setState(() {
      _locateStatus = 'failed';
      _locationLabel = reason;
    });
  }

  /// 手动设置位置对话框
  Future<void> _showManualLocationDialog() async {
    // 预设城市
    final cities = [
      {'name': '北京', 'lat': 39.9042, 'lng': 116.4074},
      {'name': '上海', 'lat': 31.2304, 'lng': 121.4737},
      {'name': '广州', 'lat': 23.1291, 'lng': 113.2644},
      {'name': '深圳', 'lat': 22.5431, 'lng': 114.0579},
      {'name': '杭州', 'lat': 30.2741, 'lng': 120.1551},
      {'name': '成都', 'lat': 30.5728, 'lng': 104.0668},
      {'name': '武汉', 'lat': 30.5928, 'lng': 114.3055},
      {'name': '西安', 'lat': 34.3416, 'lng': 108.9398},
    ];

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFFFF6B35)),
                const SizedBox(width: 8),
                const Text('选择位置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                // GPS 精确定位按钮
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    if (!mounted) return;
                    setState(() {
                      _locateStatus = 'locating';
                      _locationLabel = 'GPS定位中...';
                    });
                    final ok = await _locateByGps(showRequest: true);
                    if (!ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('GPS定位失败，请确认已授权位置权限'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                      // GPS 失败则恢复到之前的 IP 定位状态或失败状态
                      if (_locateStatus == 'locating') {
                        await _locateByIp();
                        if (_locateStatus == 'locating') {
                          _setLocationFailed('定位失败');
                        }
                      }
                    }
                  },
                  icon: const Icon(Icons.gps_fixed, size: 16),
                  label: const Text('GPS定位'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B35)),
                ),
                // 地图选点按钮
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    if (!mounted) return;
                    final result = await Navigator.push<LocationPickResult>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LocationPickerPage(
                          initialLat: _lat,
                          initialLng: _lng,
                          title: '选择我的位置',
                        ),
                      ),
                    );
                    if (result != null && mounted) {
                      setState(() {
                        _lat = result.lat;
                        _lng = result.lng;
                        _locateStatus = 'manual';
                        // 优先显示区 > 城市 > 省
                        _locationLabel = result.district.isNotEmpty
                            ? result.district
                            : result.city.isNotEmpty
                                ? result.city
                                : result.province.isNotEmpty
                                    ? result.province
                                    : '已选点';
                      });
                      _loadProducts();
                    }
                  },
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('地图选点'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B35)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 当前定位状态说明
            Text(
              _locateStatus == 'failed'
                  ? '⚠️ 自动定位失败，请手动选择城市'
                  : _locateStatus == 'located' && _locationLabel == '精确定位'
                      ? '✅ GPS精确定位 (${_lat.toStringAsFixed(3)}, ${_lng.toStringAsFixed(3)})'
                      : '📍 当前：$_locationLabel · 点击切换城市',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            // 城市网格
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: cities.map((city) {
                final isSelected = ((_lat - (city['lat'] as double)).abs() < 0.5 &&
                    (_lng - (city['lng'] as double)).abs() < 0.5);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _lat = city['lat'] as double;
                      _lng = city['lng'] as double;
                      _locateStatus = 'manual';
                      _locationLabel = city['name'] as String;
                    });
                    Navigator.pop(context);
                    _loadProducts();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFF6B35)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFF6B35)
                            : Colors.grey[300]!,
                      ),
                    ),
                    child: Text(
                      city['name'] as String,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            // IP 重新定位按钮
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadLocation();
                },
                child: const Text('重新自动定位',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    try {
      final response = await ApiService().getNearbyProducts(_lat, _lng);
      if (response['code'] == 200) {
        final raw = response['data'];
        final List rawList = raw is List ? raw : [];
        // 过滤 null 和非 Map 元素，避免 Null check operator 崩溃
        final data = rawList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() {
          _products = data.isNotEmpty ? data : _getMockProducts();
        });
      } else {
        setState(() => _products = _getMockProducts());
      }
    } catch (e) {
      setState(() => _products = _getMockProducts());
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _getMockProducts() {
    return [
      {'productId': 1, 'name': '灵狐有机牛奶250ml', 'price': 5.90, 'distance': '1.2km', 'stock': 100, 'warehouseId': 1, 'barcode': '6901234567890', 'images': '["https://picsum.photos/seed/milk/400/400"]'},
      {'productId': 2, 'name': '灵狐坚果混合装200g', 'price': 29.90, 'distance': '1.5km', 'stock': 50, 'warehouseId': 1, 'barcode': '6902345678901', 'images': '["https://picsum.photos/seed/nuts/400/400"]'},
      {'productId': 3, 'name': '灵狐矿泉水500ml', 'price': 2.50, 'distance': '0.8km', 'stock': 200, 'warehouseId': 2, 'barcode': '6903456789012', 'images': '["https://picsum.photos/seed/water/400/400"]'},
      {'productId': 4, 'name': '灵狐绿茶饮料330ml', 'price': 4.50, 'distance': '2.1km', 'stock': 80, 'warehouseId': 1, 'barcode': '6904567890123', 'images': '["https://picsum.photos/seed/tea/400/400"]'},
      {'productId': 5, 'name': '灵狐全麦饼干100g', 'price': 8.80, 'distance': '1.8km', 'stock': 60, 'warehouseId': 2, 'barcode': '6905678901234', 'images': '["https://picsum.photos/seed/cookies/400/400"]'},
    ];
  }

  void _addToCart(Map<String, dynamic> product) {
    final item = Map<String, dynamic>.from(product);
    item['price'] = (product['price'] ?? product['retailPrice'] ?? 0.0);
    CartPage.addItem(item, 1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已加入购物车: ${product['name']}'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFFFF6B35),
      ),
    );
  }

  /// 点击商品卡片弹出详情底部弹窗
  void _showProductDetail(Map<String, dynamic> product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductDetailSheet(
        product: product,
        onAddToCart: () {
          Navigator.pop(context);
          _addToCart(product);
        },
      ),
    );
  }

  /// 定位图标颜色
  Color get _locationIconColor {
    switch (_locateStatus) {
      case 'located':
        return _locationLabel == '精确定位' ? Colors.greenAccent : Colors.white;
      case 'failed':  return Colors.yellow[300]!;
      case 'manual':  return Colors.white70;
      default:        return Colors.white60; // locating
    }
  }

  /// 定位图标
  IconData get _locationIcon {
    switch (_locateStatus) {
      case 'located':
        return _locationLabel == '精确定位' ? Icons.gps_fixed : Icons.location_on;
      case 'failed':  return Icons.gps_off;
      case 'manual':  return Icons.location_city;
      default:        return Icons.gps_not_fixed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // 定位按钮 - 点击可切换城市或重试定位
            GestureDetector(
              onTap: _showManualLocationDialog,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 旋转动画（定位中）
                  if (_locateStatus == 'locating')
                    const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white70, strokeWidth: 2),
                    )
                  else
                    Icon(_locationIcon, size: 16, color: _locationIconColor),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      _locateStatus == 'locating' ? '定位中...' : _locationLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _locateStatus == 'failed'
                            ? Colors.yellow[300]
                            : Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down,
                      size: 16,
                      color: Colors.white.withOpacity(0.8)),
                ],
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SearchPage(userLat: _lat, userLng: _lng),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: '仓库地图',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WarehouseMapPage(userLat: _lat, userLng: _lng),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadProducts,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _products.isEmpty
                ? const Center(child: Text('附近暂无商品'))
                : CustomScrollView(
                    slivers: [
                      // 定位失败提示条
                      if (_locateStatus == 'failed')
                        SliverToBoxAdapter(
                          child: GestureDetector(
                            onTap: _showManualLocationDialog,
                            child: Container(
                              color: Colors.orange[50],
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_outlined,
                                      size: 16, color: Colors.orange[700]),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '自动定位失败，当前显示默认位置（北京）的商品。点击切换城市',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange[800]),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      size: 16, color: Colors.orange[700]),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // ===== 0.1元活动入口 Banner =====
                      SliverToBoxAdapter(
                        child: _ActivityBanner(),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.all(12),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.68,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildProductCard(_products[index]),
                            childCount: _products.length,
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  /// 从 images 字段（JSON 数组字符串）中取第一张图片完整 URL
  /// 支持相对路径（/uploads/xxx）和绝对 URL 两种存储格式
  String _getFirstImage(Map<String, dynamic> product) {
    final raw = product['images'] as String? ?? '';
    if (raw.isEmpty) return '';
    final trimmed = raw.trim();
    String url = trimmed;
    if (trimmed.startsWith('[')) {
      // JSON 数组格式：["url1","url2"]
      try {
        final inner = trimmed.substring(1, trimmed.length - 1).trim();
        if (inner.isEmpty) return '';
        url = inner.split('","').first.replaceAll('"', '').trim();
      } catch (_) {
        return '';
      }
    }
    // 相对路径自动补全为当前 API 域名
    if (url.startsWith('/')) {
      return AppConstants.apiBaseUrl + url;
    }
    return url;
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

  Widget _buildProductCard(Map<String, dynamic> product) {    final barcode = product['barcode'] as String? ?? '';
    final hasBarcode = barcode.isNotEmpty;
    final imageUrl = _getFirstImage(product);

    return GestureDetector(
      onTap: () => _showProductDetail(product),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 商品图片
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 130,
                        color: Colors.grey[200],
                        child: const Icon(Icons.image_outlined, size: 50, color: Colors.grey),
                      ),
                    )
                  : Container(
                      height: 130,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image_outlined, size: 50, color: Colors.grey),
                    ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 商品名 + 来源标签
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product['name'] ?? '',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _sourceTag(product['sourceType'] as String?),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // 条形码行（仅在有条码时显示）
                  if (hasBarcode)
                    Row(
                      children: [
                        const Icon(Icons.barcode_reader, size: 11, color: Color(0xFF9E9E9E)),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            barcode,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF9E9E9E),
                              fontFamily: 'monospace',
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 4),
                  // 距离
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 11, color: Colors.grey),
                      Text(
                        product['distance'] ?? '',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // 价格 + 加购按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '¥${((product['price'] ?? product['retailPrice'] ?? 0) as num).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6B35),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _addToCart(product),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6B35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 商品详情弹窗（优化版）====================

class _ProductDetailSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback onAddToCart;

  const _ProductDetailSheet({
    required this.product,
    required this.onAddToCart,
  });

  @override
  State<_ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<_ProductDetailSheet>
    with SingleTickerProviderStateMixin {
  // ── 图片轮播 ──────────────────────────────────────────
  final PageController _imgCtrl = PageController();
  int _imgIndex = 0;

  // ── 加购动效 ──────────────────────────────────────────
  late final AnimationController _cartAnimCtrl;
  late final Animation<double> _cartScale;
  bool _cartAdded = false;

  // ── 收藏状态 ──────────────────────────────────────────
  bool _isFav = false;

  // ── 模拟评价数据（实际可接后端） ─────────────────────
  final List<Map<String, dynamic>> _reviews = const [
    {
      'avatar': '🧑',
      'name': '张**',
      'star': 5,
      'tag': '有图',
      'content': '新鲜！早上7点下单，8点不到就到了，牛奶温度刚好，下次还买。',
      'time': '3天前',
      'hasImg': true,
    },
    {
      'avatar': '👩',
      'name': '王**',
      'star': 5,
      'tag': '仓主推荐',
      'content': '仓主说这批是今天早上刚到的，喝起来确实比超市的新鲜，会复购。',
      'time': '5天前',
      'hasImg': false,
    },
    {
      'avatar': '🧒',
      'name': '李**',
      'star': 4,
      'tag': '追评',
      'content': '买了三次了，口感稳定，追评一下，包装也不错没漏液。',
      'time': '1周前',
      'hasImg': false,
    },
  ];

  @override
  void initState() {
    super.initState();
    _cartAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _cartScale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _cartAnimCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _imgCtrl.dispose();
    _cartAnimCtrl.dispose();
    super.dispose();
  }

  // ── 解析全部图片列表 ─────────────────────────────────
  List<String> _getImages() {
    final raw = widget.product['images'] as String? ?? '';
    if (raw.isEmpty) return [];
    final trimmed = raw.trim();
    List<String> urls = [];
    if (trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) urls = decoded.map((e) => e.toString()).toList();
      } catch (_) {
        urls = [trimmed.replaceAll(RegExp(r'[\[\]"]'), '').trim()];
      }
    } else {
      urls = trimmed.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return urls.map((u) => u.startsWith('/') ? AppConstants.apiBaseUrl + u : u).toList();
  }

  void _onAddToCart() async {
    setState(() => _cartAdded = true);
    await _cartAnimCtrl.forward();
    await _cartAnimCtrl.reverse();
    widget.onAddToCart();
  }

  void _onShare() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎁 分享成功可获 0.5 元购物券，好友首单你得 2 元！'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final price = ((p['price'] ?? p['retailPrice'] ?? 0) as num).toDouble();
    final originalPrice = ((p['originalPrice'] ?? p['marketPrice'] ?? price * 1.25) as num).toDouble();
    final stock = (p['stock'] ?? p['totalStock'] ?? 0) as num;
    final warehouseName = p['warehouseName'] as String? ?? '';
    final distance = p['distance'] as String? ?? '';
    final barcode = p['barcode'] as String? ?? '';
    final soldCount = (p['soldCount'] ?? p['sales'] ?? 892) as num;
    final images = _getImages();
    final stockLow = stock > 0 && stock <= 5;
    final sourceType = p['sourceType'] as String? ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ── 拖拽把手 ──────────────────────────────────
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── 顶部操作栏 ────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Row(
                    children: [
                      // 收藏按钮
                      GestureDetector(
                        onTap: () => setState(() => _isFav = !_isFav),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            _isFav ? Icons.favorite : Icons.favorite_border,
                            key: ValueKey(_isFav),
                            color: _isFav ? Colors.red : Colors.grey[600],
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 分享按钮 + 气泡提示
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GestureDetector(
                            onTap: _onShare,
                            child: Icon(Icons.share_outlined, color: Colors.grey[600], size: 24),
                          ),
                          Positioned(
                            top: -18, right: -8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B35),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('得券', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── 滚动主内容 ────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.zero,
                children: [

                  // ═══ 图片轮播区 ═══════════════════════════
                  _buildImageCarousel(images),

                  // ═══ 价格与促销区（首屏核心）═══════════════
                  _buildPriceZone(price, originalPrice, soldCount, stock, stockLow),

                  // ═══ 服务标签行 ═══════════════════════════
                  _buildServiceTags(distance, warehouseName, stock, stockLow),

                  // ═══ 品类标签 ═════════════════════════════
                  if (sourceType.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(children: [
                        _tag(sourceType == 'self' ? '🌱 农户自产' : '🏢 品牌商品',
                            sourceType == 'self' ? Colors.green : Colors.blue),
                        const SizedBox(width: 8),
                        _tag('✅ 质检合格', Colors.teal),
                      ]),
                    ),
                  ],

                  // ═══ 商品名称 ════════════════════════════
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Text(
                      p['name'] ?? '',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.4),
                    ),
                  ),

                  // ═══ 服务承诺 ════════════════════════════
                  _buildServicePromise(),

                  // ═══ 关联推荐（买了还买了）════════════════
                  _buildRelatedProducts(),

                  // ═══ 用户评价 ════════════════════════════
                  _buildReviews(),

                  // ═══ 条形码区 ════════════════════════════
                  if (barcode.isNotEmpty) _buildBarcode(barcode),

                  // ═══ 品牌资质（折叠）════════════════════
                  _buildQualification(),

                  const SizedBox(height: 100), // 底部按钮留空
                ],
              ),
            ),

            // ═══ 底部固定：加购按钮 ═══════════════════════
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 图片轮播
  // ─────────────────────────────────────────────────────
  Widget _buildImageCarousel(List<String> images) {
    if (images.isEmpty) {
      return Container(
        height: 260,
        color: Colors.grey[100],
        child: const Icon(Icons.image_outlined, size: 80, color: Colors.grey),
      );
    }
    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          PageView.builder(
            controller: _imgCtrl,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _imgIndex = i),
            itemBuilder: (_, i) => Image.network(
              images[i],
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey[100],
                child: const Icon(Icons.image_outlined, size: 80, color: Colors.grey),
              ),
            ),
          ),
          // 页码指示器
          if (images.length > 1)
            Positioned(
              bottom: 10, right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_imgIndex + 1}/${images.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          // 滑动提示（仅首次）
          if (images.length > 1 && _imgIndex == 0)
            Positioned(
              bottom: 10, left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swipe, color: Colors.white, size: 12),
                    SizedBox(width: 3),
                    Text('左右滑动', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 价格与促销区
  // ─────────────────────────────────────────────────────
  Widget _buildPriceZone(double price, double originalPrice, num soldCount, num stock, bool stockLow) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFFFF3EE), const Color(0xFFFFF8F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD5C0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 价格行
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '¥',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFFF6B35)),
              ),
              Text(
                price.toStringAsFixed(2),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Color(0xFFFF6B35)),
              ),
              const SizedBox(width: 8),
              if (originalPrice > price)
                Text(
                  '¥${originalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14, color: Colors.grey,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              const Spacer(),
              // 限时标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '🏷️ 限时特惠',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 销量 + 好评率行
          Row(
            children: [
              _infoChip('📦 已售 ${soldCount}件', const Color(0xFF888888)),
              const SizedBox(width: 8),
              _infoChip('👍 好评 98%', const Color(0xFF4CAF50)),
              const SizedBox(width: 8),
              if (stockLow)
                _infoChip('🔥 仅剩 ${stock}件', const Color(0xFFFF6B35)),
            ],
          ),
          const SizedBox(height: 8),
          // 自提返现提示（高亮）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
            ),
            child: Row(
              children: const [
                Icon(Icons.directions_walk, size: 14, color: Color(0xFFFF6B35)),
                SizedBox(width: 4),
                Text('到仓自提立减 1.5 元', style: TextStyle(fontSize: 12, color: Color(0xFFFF6B35), fontWeight: FontWeight.w600)),
                SizedBox(width: 8),
                Text('·', style: TextStyle(color: Colors.grey)),
                SizedBox(width: 8),
                Icon(Icons.access_time, size: 14, color: Color(0xFF2196F3)),
                SizedBox(width: 4),
                Text('30分钟达', style: TextStyle(fontSize: 12, color: Color(0xFF2196F3), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 服务标签行（距离/仓库/库存预警）
  // ─────────────────────────────────────────────────────
  Widget _buildServiceTags(String distance, String warehouseName, num stock, bool stockLow) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (warehouseName.isNotEmpty)
            _chip(
              icon: Icons.warehouse_outlined,
              label: warehouseName,
              color: const Color(0xFF9C27B0),
            ),
          if (distance.isNotEmpty)
            _chip(
              icon: Icons.location_on_outlined,
              label: distance,
              color: const Color(0xFF2196F3),
            ),
          if (stock > 0 && !stockLow)
            _chip(icon: Icons.check_circle_outline, label: '有货', color: const Color(0xFF4CAF50)),
          if (stockLow)
            _chip(icon: Icons.warning_amber_outlined, label: '即将售罄', color: const Color(0xFFFF6B35)),
          _chip(icon: Icons.flash_on_outlined, label: '30分钟达', color: const Color(0xFF2196F3)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 服务承诺
  // ─────────────────────────────────────────────────────
  Widget _buildServicePromise() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FFF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.25)),
      ),
      child: Column(
        children: [
          _promiseRow(Icons.replay, '7天无理由退货（生鲜除外）'),
          const SizedBox(height: 6),
          _promiseRow(Icons.camera_alt_outlined, '破损包赔：拍照上传24小时内处理'),
          const SizedBox(height: 6),
          _promiseRow(Icons.bolt, '闪电退款：仓主确认后2小时到账'),
        ],
      ),
    );
  }

  Widget _promiseRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF4CAF50)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32))),
      ],
    );
  }

  // ─────────────────────────────────────────────────────
  // 关联推荐
  // ─────────────────────────────────────────────────────
  Widget _buildRelatedProducts() {
    final related = [
      {'name': '鲜牛奶 200ml', 'price': '¥3.5', 'emoji': '🥛'},
      {'name': '全麦吐司', 'price': '¥8.9', 'emoji': '🍞'},
      {'name': '水煮鸡蛋 6枚', 'price': '¥12.9', 'emoji': '🥚'},
      {'name': '酸奶 100g', 'price': '¥4.9', 'emoji': '🫙'},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              Text('🛒 买了还买了', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              SizedBox(width: 6),
              Text('AI 推荐', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: related.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final item = related[i];
              return GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已加入购物车：${item['name']}'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: Container(
                  width: 80,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(item['emoji']!, style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 4),
                      Text(
                        item['name']!,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF333333)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        item['price']!,
                        style: const TextStyle(fontSize: 11, color: Color(0xFFFF6B35), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // 场景套餐提示
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFCC02).withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Text('☀️', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('早餐套餐搭配', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF7B5800))),
                      Text('面包+牛奶+鸡蛋，套餐价再省3元', style: TextStyle(fontSize: 11, color: Color(0xFF9E7000))),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('组合购', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────
  // 用户评价
  // ─────────────────────────────────────────────────────
  Widget _buildReviews() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('⭐ 用户评价', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              Text('好评 98%', style: TextStyle(fontSize: 12, color: Colors.orange[700])),
            ],
          ),
        ),
        ..._reviews.map((r) => _buildReviewItem(r)),
      ],
    );
  }

  Widget _buildReviewItem(Map<String, dynamic> r) {
    final star = (r['star'] as int? ?? 5);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(r['avatar'] as String, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['name'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Row(
                      children: List.generate(5, (i) => Icon(
                        i < star ? Icons.star : Icons.star_border,
                        size: 12,
                        color: Colors.orange,
                      )),
                    ),
                  ],
                ),
              ),
              // 评价标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: r['tag'] == '有图'
                      ? Colors.blue.withOpacity(0.12)
                      : r['tag'] == '仓主推荐'
                          ? Colors.purple.withOpacity(0.12)
                          : Colors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  r['tag'] as String,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: r['tag'] == '有图'
                        ? Colors.blue
                        : r['tag'] == '仓主推荐'
                            ? Colors.purple
                            : Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(r['time'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          Text(r['content'] as String, style: const TextStyle(fontSize: 13, color: Color(0xFF444444), height: 1.5)),
          if (r['hasImg'] == true) ...[
            const SizedBox(height: 8),
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.image_outlined, color: Colors.grey, size: 28),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 条形码
  // ─────────────────────────────────────────────────────
  Widget _buildBarcode(String barcode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.barcode_reader, size: 15, color: Color(0xFF616161)),
              SizedBox(width: 6),
              Text('商品条形码', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF616161))),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Column(
                children: [
                  BarcodeWidget(barcode: Barcode.code128(), data: barcode, width: 220, height: 70, drawText: false, color: Colors.black87),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: barcode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('条码已复制'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating),
                      );
                    },
                    child: Text(barcode, style: const TextStyle(fontSize: 15, fontFamily: 'monospace', letterSpacing: 2.0, color: Color(0xFF212121), fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 2),
                  const Text('长按条码数字可复制', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 品牌资质（折叠）
  // ─────────────────────────────────────────────────────
  Widget _buildQualification() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Row(
          children: [
            Icon(Icons.verified_outlined, size: 16, color: Color(0xFF4CAF50)),
            SizedBox(width: 6),
            Text('资质公示', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _qualRow('食品经营许可证：已核验 ✅'),
                _qualRow('检测报告：近期合格 ✅'),
                _qualRow('品牌授权书：已上传 ✅'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qualRow(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF4CAF50))),
  );

  // ─────────────────────────────────────────────────────
  // 底部固定加购栏
  // ─────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          // 客服按钮
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('联系仓主功能即将上线'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 1)),
              );
            },
            child: Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.headset_mic_outlined, color: Colors.grey, size: 22),
            ),
          ),
          const SizedBox(width: 10),
          // 加购按钮（带动效）
          Expanded(
            child: ScaleTransition(
              scale: _cartScale,
              child: GestureDetector(
                onTap: _onAddToCart,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _cartAdded
                          ? [const Color(0xFF4CAF50), const Color(0xFF43A047)]
                          : [const Color(0xFFFF8C42), const Color(0xFFFF6B35)],
                    ),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6B35).withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          _cartAdded ? Icons.check : Icons.shopping_cart_outlined,
                          key: ValueKey(_cartAdded),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _cartAdded ? '已加入购物车 ✓' : '⚡ 30分钟达 · 加入购物车',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 通用组件
  // ─────────────────────────────────────────────────────
  Widget _chip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
  );

  Widget _infoChip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );
}

/// 首页活动入口 Banner
class _ActivityBanner extends StatefulWidget {
  @override
  State<_ActivityBanner> createState() => _ActivityBannerState();
}

class _ActivityBannerState extends State<_ActivityBanner> {
  List<Map<String, dynamic>> _activities = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getActivityList();
      if (res['code'] == 200) {
        // data 可能是 List（直接数组）或 Map（含 records 字段）
        final raw = res['data'];
        final List records;
        if (raw is List) {
          records = raw;
        } else if (raw is Map) {
          records = (raw['records'] as List?) ?? [];
        } else {
          records = [];
        }
        if (mounted) {
          setState(() => _activities = records
              .whereType<Map>()  // 过滤掉 null 或非 Map 元素
              .map((e) => Map<String, dynamic>.from(e))
              .toList());
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_activities.isEmpty) return const SizedBox.shrink();
    final activity = _activities.first;
    // null 安全：id 可能是 int 或 num，统一转换
    final activityId = activity['id'];
    if (activityId == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActivityInvitePage(
            activityId: (activityId as num).toInt(),
            activityName: activity['name'] as String? ?? '限时特惠',
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B35), Color(0xFFFF9A00)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: const Color(0xFFFF6B35).withOpacity(0.3),
                blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            const Text('🎁', style: TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('邀请好友·0.1元购',
                      style: TextStyle(color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(activity['name'] ?? '限时特惠活动',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('去邀请',
                  style: TextStyle(color: Color(0xFFFF6B35),
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
