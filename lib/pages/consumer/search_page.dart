import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../config/constants.dart';
import 'cart.dart';

/// 消费者搜索页
/// 支持：商品名称 / 条码 / 仓店名称 三路模糊搜索
class SearchPage extends StatefulWidget {
  final double userLat;
  final double userLng;
  const SearchPage({super.key, this.userLat = 39.9042, this.userLng = 116.4074});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _focusNode  = FocusNode();

  List<Map<String, dynamic>> _productResults   = [];
  List<Map<String, dynamic>> _warehouseResults = [];
  List<String> _history = [];

  bool _loading  = false;
  bool _searched = false;
  String _lastKeyword = '';

  Timer? _debounce;
  late TabController _tabController;

  static const _historyKey = 'search_history';
  static const _maxHistory = 10;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── 搜索历史 ────────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _history = prefs.getStringList(_historyKey) ?? []);
  }

  Future<void> _saveToHistory(String kw) async {
    if (kw.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList(_historyKey) ?? [];
    list.remove(kw);
    list.insert(0, kw);
    if (list.length > _maxHistory) list = list.sublist(0, _maxHistory);
    await prefs.setStringList(_historyKey, list);
    setState(() => _history = list);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    setState(() => _history = []);
  }

  Future<void> _removeHistoryItem(String kw) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList(_historyKey) ?? [];
    list.remove(kw);
    await prefs.setStringList(_historyKey, list);
    setState(() => _history = list);
  }

  // ── 搜索逻辑 ────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() { _productResults = []; _warehouseResults = []; _searched = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _doSearch(value.trim()));
  }

  Future<void> _doSearch(String keyword) async {
    if (keyword == _lastKeyword && _searched) return;
    _lastKeyword = keyword;
    setState(() => _loading = true);
    try {
      final resp = await ApiService().searchProducts(
        keyword, lat: widget.userLat, lng: widget.userLng,
      );
      if (resp['code'] == 200 && mounted) {
        final data = resp['data'];
        List<Map<String, dynamic>> products = [];
        List<Map<String, dynamic>> warehouses = [];

        if (data is Map) {
          // 新接口：{ products: [...], warehouses: [...] }
          products = (data['products'] as List? ?? [])
              .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          warehouses = (data['warehouses'] as List? ?? [])
              .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        } else if (data is List) {
          // 兼容旧接口（纯商品列表）
          products = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }

        setState(() {
          _productResults   = products;
          _warehouseResults = warehouses;
          _searched = true;
        });
        await _saveToHistory(keyword);

        // 自动跳到有结果的 tab
        if (products.isEmpty && warehouses.isNotEmpty) {
          _tabController.animateTo(1);
        } else {
          _tabController.animateTo(0);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('搜索失败，请检查网络'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _tapHistory(String keyword) {
    _searchCtrl.text = keyword;
    _searchCtrl.selection = TextSelection.fromPosition(TextPosition(offset: keyword.length));
    _doSearch(keyword);
  }

  void _addToCart(Map<String, dynamic> product) {
    final item = Map<String, dynamic>.from(product);
    item['price'] = (product['price'] ?? product['retailPrice'] ?? 0.0);
    CartPage.addItem(item, 1);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已加入购物车：${product['name']}'),
      duration: const Duration(seconds: 1),
      backgroundColor: const Color(0xFFFF6B35),
    ));
  }

  // ── 图片解析 ────────────────────────────────────────────────────

  String _getFirstImage(Map<String, dynamic> product) {
    final raw = product['images'] as String? ?? '';
    if (raw.isEmpty) return '';
    final trimmed = raw.trim();
    String url = trimmed;
    if (trimmed.startsWith('[')) {
      try {
        final inner = trimmed.substring(1, trimmed.length - 1).trim();
        if (inner.isEmpty) return '';
        url = inner.split('","').first.replaceAll('"', '').trim();
      } catch (_) { return ''; }
    }
    if (url.startsWith('/')) return AppConstants.apiBaseUrl + url;
    return url;
  }

  // ── UI ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Container(
          height: 38,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _focusNode,
            onChanged: _onQueryChanged,
            onSubmitted: (v) { if (v.trim().isNotEmpty) _doSearch(v.trim()); },
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: InputDecoration(
              hintText: '搜索商品名称或仓店名称',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
              prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFFF6B35)),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() {
                          _productResults = []; _warehouseResults = [];
                          _searched = false; _lastKeyword = '';
                        });
                      },
                      child: const Icon(Icons.clear, size: 16, color: Colors.grey),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
          ),
        ),
        // 搜索后显示 Tab 栏
        bottom: _searched
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFFFF6B35),
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: const Color(0xFFFF6B35),
                    indicatorWeight: 2,
                    labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    tabs: [
                      Tab(text: '商品 (${_productResults.length})'),
                      Tab(text: '仓店 (${_warehouseResults.length})'),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B35)))
          : _searched
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProductResults(),
                    _buildWarehouseResults(),
                  ],
                )
              : _buildInitialState(),
    );
  }

  // ── 未搜索：搜索历史 ────────────────────────────────────────────

  Widget _buildInitialState() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('搜索附近商品或仓店', style: TextStyle(fontSize: 16, color: Colors.grey[400])),
            const SizedBox(height: 6),
            Text('试试商品名称、仓店名称或条码', style: TextStyle(fontSize: 13, color: Colors.grey[350])),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('搜索历史', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            GestureDetector(
              onTap: _clearHistory,
              child: Text('清空', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _history.map((kw) => _buildHistoryChip(kw)).toList(),
        ),
      ],
    );
  }

  Widget _buildHistoryChip(String keyword) {
    return GestureDetector(
      onTap: () => _tapHistory(keyword),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(keyword, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _removeHistoryItem(keyword),
              child: const Icon(Icons.close, size: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 1：商品结果 ─────────────────────────────────────────────

  Widget _buildProductResults() {
    if (_productResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('没有找到相关商品', style: TextStyle(fontSize: 16, color: Colors.grey[400])),
            const SizedBox(height: 6),
            Text('换个关键词，或者试试搜索仓店名称', style: TextStyle(fontSize: 13, color: Colors.grey[350])),
          ],
        ),
      );
    }
    return Column(
      children: [
        Container(
          width: double.infinity, color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('找到 ${_productResults.length} 件商品',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _productResults.length,
            itemBuilder: (ctx, i) => _buildProductCard(_productResults[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final imageUrl = _getFirstImage(product);
    final price = (product['price'] ?? product['retailPrice'] ?? 0.0) as num;
    final distance = product['distance'] as String? ?? '';
    final stock = (product['stock'] as num?)?.toInt() ?? 0;
    final warehouseName = product['warehouseName'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showProductDetail(product),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl.isNotEmpty
                    ? Image.network(imageUrl, width: 80, height: 80, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imagePlaceholder())
                    : _imagePlaceholder(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product['name'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.store_outlined, size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(warehouseName,
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (distance.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.near_me_outlined, size: 11, color: Colors.grey[400]),
                        Text(' $distance', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                      ],
                    ]),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('¥${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Color(0xFFFF6B35), fontWeight: FontWeight.bold, fontSize: 17)),
                        Row(children: [
                          Text('库存$stock件  ', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                          _buildAddBtn(product),
                        ]),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 2：仓店结果 ─────────────────────────────────────────────

  Widget _buildWarehouseResults() {
    if (_warehouseResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_mall_directory_outlined, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('没有找到相关仓店', style: TextStyle(fontSize: 16, color: Colors.grey[400])),
            const SizedBox(height: 6),
            Text('换个关键词试试吧', style: TextStyle(fontSize: 13, color: Colors.grey[350])),
          ],
        ),
      );
    }
    return Column(
      children: [
        Container(
          width: double.infinity, color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('找到 ${_warehouseResults.length} 家仓店',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _warehouseResults.length,
            itemBuilder: (ctx, i) => _buildWarehouseCard(_warehouseResults[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildWarehouseCard(Map<String, dynamic> wh) {
    final name     = wh['warehouseName'] as String? ?? '';
    final address  = wh['address']       as String? ?? '';
    final distance = wh['distance']      as String? ?? '';
    final count    = (wh['productCount'] as num?)?.toInt() ?? 0;
    final deliveries = wh['supportedDeliveries'] as String? ?? '';
    final hasSelfPickup = deliveries.contains('pickup');
    final hasDelivery   = deliveries.contains('delivery');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // 仓店图标
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.store, color: Color(0xFFFF6B35), size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if (address.isNotEmpty)
                    Row(children: [
                      Icon(Icons.location_on_outlined, size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(address,
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    _tag('在售$count件', Colors.blue),
                    const SizedBox(width: 6),
                    if (hasDelivery) _tag('配送', Colors.green),
                    if (hasSelfPickup) ...[const SizedBox(width: 6), _tag('自提', Colors.orange)],
                  ]),
                ],
              ),
            ),
            // 距离
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(distance, style: const TextStyle(
                    color: Color(0xFFFF6B35), fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Widget _imagePlaceholder() => Container(
      width: 80, height: 80, color: Colors.grey[100],
      child: const Icon(Icons.image_outlined, color: Colors.grey));

  Widget _buildAddBtn(Map<String, dynamic> product) {
    return GestureDetector(
      onTap: () => _addToCart(product),
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
            color: const Color(0xFFFF6B35), borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.add, color: Colors.white, size: 18),
      ),
    );
  }

  void _showProductDetail(Map<String, dynamic> product) {
    final imageUrl = _getFirstImage(product);
    final price = (product['price'] ?? product['retailPrice'] ?? 0.0) as num;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(imageUrl, height: 180, width: double.infinity, fit: BoxFit.cover),
              ),
            const SizedBox(height: 14),
            Text(product['name'] ?? '',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('¥${price.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 22, color: Color(0xFFFF6B35), fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.store_outlined, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(product['warehouseName'] ?? '', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(width: 12),
              Icon(Icons.near_me_outlined, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(product['distance'] ?? '', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton.icon(
                onPressed: () { Navigator.pop(context); _addToCart(product); },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35), foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('加入购物车', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
