import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../config/constants.dart';

/// 品牌方商品管理页
class BrandProductsPage extends StatefulWidget {
  const BrandProductsPage({super.key});

  @override
  State<BrandProductsPage> createState() => _BrandProductsPageState();
}

class _BrandProductsPageState extends State<BrandProductsPage> {
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await ApiService().getBrandProducts();
      if (response['code'] == 200) {
        setState(() =>
            _products = (response['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
      }
    } catch (_) {
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 从 images JSON 字符串取第一张图片完整 URL（支持相对路径和绝对 URL）
  String? _getFirstImage(dynamic images) {
    if (images == null) return null;
    try {
      String url = '';
      if (images is String && images.isNotEmpty) {
        if (images.startsWith('[')) {
          final inner = images.trim()
              .replaceFirst('[', '')
              .replaceFirst(RegExp(r']$'), '');
          if (inner.isEmpty) return null;
          final parts = inner.split(',')
              .map((e) => e.trim().replaceAll('"', ''))
              .where((e) => e.isNotEmpty)
              .toList();
          url = parts.isNotEmpty ? parts.first : '';
        } else {
          url = images;
        }
      } else if (images is List && images.isNotEmpty) {
        url = images.first.toString();
      }
      if (url.isEmpty) return null;
      // 相对路径自动补全为当前 API 域名
      if (url.startsWith('/')) {
        return AppConstants.apiBaseUrl + url;
      }
      return url;
    } catch (_) {}
    return null;
  }

  void _openAddPage() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const _ProductEditPage()),
    );
    if (result == true) _load();
  }

  void _openEditPage(Map<String, dynamic> product) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _ProductEditPage(product: product)),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('商品管理'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddPage,
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _products.isEmpty
                  ? const Center(child: Text('暂无商品，点击右下角添加'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _products.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final product = _products[index];
                        final isActive = product['status'] == 1;
                        final imageUrl = _getFirstImage(product['images']);
                        return Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openEditPage(product),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // 商品图片
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: imageUrl != null
                                        ? Image.network(
                                            imageUrl,
                                            width: 64,
                                            height: 64,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _placeholderIcon(),
                                          )
                                        : _placeholderIcon(),
                                  ),
                                  const SizedBox(width: 12),
                                  // 商品信息
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product['name'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${product['skuCode'] ?? ''} | ¥${(product['retailPrice'] as num?)?.toStringAsFixed(2) ?? '--'}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600]),
                                        ),
                                        if (product['barcode'] != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            '条码: ${product['barcode']}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[500]),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  // 状态标签
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? Colors.green[50]
                                          : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isActive ? '已上架' : '已下架',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isActive
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _placeholderIcon() {
    return Container(
      width: 64,
      height: 64,
      color: Colors.grey[100],
      child: const Icon(Icons.inventory_2, color: Colors.grey, size: 32),
    );
  }
}

// ============================================================
// 商品新增/编辑页面
// ============================================================

class _ProductEditPage extends StatefulWidget {
  final Map<String, dynamic>? product; // null 表示新增，非 null 表示编辑

  const _ProductEditPage({this.product});

  @override
  State<_ProductEditPage> createState() => _ProductEditPageState();
}

class _ProductEditPageState extends State<_ProductEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  // 商品类型：'brand'=品牌商品（外部采购/授权），'self'=自产商品
  String _sourceType = 'brand';
  bool _isActive = true;
  bool _saving = false;

  /// 已上传/已有的图片 URL 列表
  List<String> _imageUrls = [];

  /// 本地选中但尚未上传的图片（bytes + 文件名）
  final List<_LocalImage> _pendingImages = [];

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = widget.product!;
      _nameCtrl.text = p['name'] ?? '';
      _skuCtrl.text = p['skuCode'] ?? '';
      _priceCtrl.text =
          (p['retailPrice'] as num?)?.toStringAsFixed(2) ?? '';
      _barcodeCtrl.text = p['barcode'] ?? '';
      _weightCtrl.text = p['weightG']?.toString() ?? '';
      _isActive = p['status'] == 1;
      _sourceType = p['sourceType'] as String? ?? 'brand';
      // 解析已有图片（相对路径自动补全为完整 URL，用于 Image.network 展示）
      final images = p['images'];
      if (images != null && images is String && images.isNotEmpty) {
        try {
          final rawList = images.startsWith('[') ? _parseJsonArray(images) : [images];
          // 相对路径补全，保证 _ImageThumb 能正常显示
          _imageUrls = rawList.map((u) {
            if (u.startsWith('/')) return AppConstants.apiBaseUrl + u;
            return u;
          }).toList();
        } catch (_) {
          _imageUrls = [images];
        }
      }
    }
  }

  List<String> _parseJsonArray(String s) {
    // 简单解析 ["a","b"] 格式
    final inner = s.trim().replaceFirst('[', '').replaceFirst(RegExp(r']$'), '');
    if (inner.isEmpty) return [];
    return inner
        .split(',')
        .map((e) => e.trim().replaceAll('"', ''))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _priceCtrl.dispose();
    _barcodeCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  // ── 选择图片 ──────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    setState(() {
      _pendingImages.add(_LocalImage(bytes: bytes, filename: xfile.name));
    });
  }

  void _removePendingImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }

  void _removeUploadedImage(int index) {
    setState(() => _imageUrls.removeAt(index));
  }

  /// 上传所有待上传图片，返回 URL 列表
  Future<List<String>> _uploadPendingImages() async {
    final uploaded = <String>[];
    for (final img in _pendingImages) {
      final res = await ApiService()
          .uploadProductImage(img.bytes, img.filename);
      if (res['code'] == 200) {
        final url = res['data']?['url'] as String?;
        if (url != null) uploaded.add(url);
      } else {
        throw Exception(res['msg'] ?? '图片上传失败');
      }
    }
    return uploaded;
  }

  // ── 保存 ──────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // 1. 上传待上传图片
      final newUrls = await _uploadPendingImages();
      final allUrls = [..._imageUrls, ...newUrls];

      // 2. 构建商品数据
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'skuCode': _skuCtrl.text.trim(),
        'retailPrice': double.parse(_priceCtrl.text.trim()),
        'barcode': _barcodeCtrl.text.trim(),
        'status': _isActive ? 1 : 0,
      };
      if (_weightCtrl.text.trim().isNotEmpty) {
        data['weightG'] = int.tryParse(_weightCtrl.text.trim());
      }
      if (allUrls.isNotEmpty) {
        // 存储时去掉域名前缀，只保存相对路径（避免绑定到特定隧道域名）
        final relativeUrls = allUrls.map((u) {
          if (u.startsWith(AppConstants.apiBaseUrl)) {
            return u.substring(AppConstants.apiBaseUrl.length);
          }
          return u;
        }).toList();
        data['images'] = '[${relativeUrls.map((u) => '"$u"').join(',')}]';
      }

      // 商品类型
      data['sourceType'] = _sourceType;

      // 3. 调用接口
      Map<String, dynamic> response;
      if (_isEdit) {
        response = await ApiService().updateProduct(
            widget.product!['id'] as int, data);
      } else {
        response = await ApiService().createProduct(data);
      }

      if (!mounted) return;
      if (response['code'] == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEdit ? '商品信息已更新' : '商品已上架'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context, true);
      } else {
        _showError(response['msg'] ?? '操作失败');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ── UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑商品' : '上架新商品'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        actions: [
          if (_saving)
            const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
          else
            TextButton(
              onPressed: _save,
              child: const Text('保存',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 商品图片 ──
            _SectionTitle(title: '商品图片'),
            const SizedBox(height: 8),
            _buildImageSection(),
            const SizedBox(height: 24),

            // ── 商品类型 ──
            _SectionTitle(title: '商品类型'),
            const SizedBox(height: 12),
            _buildSourceTypeSelector(),
            const SizedBox(height: 24),

            // ── 基本信息 ──
            _SectionTitle(title: '基本信息'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: '商品名称 *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline)),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入商品名称' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _skuCtrl,
              decoration: const InputDecoration(
                  labelText: 'SKU编码 *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code)),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入SKU编码' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: '零售价（元）*',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money)),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '请输入零售价';
                if (double.tryParse(v.trim()) == null) return '请输入有效的价格';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _barcodeCtrl,
              decoration: const InputDecoration(
                  labelText: '商品条码',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.barcode_reader),
                  hintText: '例：6901234567890'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _weightCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: '重量（克）',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.scale)),
            ),
            const SizedBox(height: 16),

            // ── 上架状态 ──
            Card(
              child: SwitchListTile(
                title: const Text('上架状态'),
                subtitle:
                    Text(_isActive ? '商品可被消费者购买' : '商品已下架，不可购买'),
                value: _isActive,
                activeColor: const Color(0xFF4CAF50),
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ── 商品类型选择器 ───────────────────────────────────────────
  Widget _buildSourceTypeSelector() {
    const options = [
      {
        'value': 'brand',
        'label': '品牌商品',
        'desc': '外部采购 / 授权品牌，商品来自合作方',
        'icon': Icons.business_center_outlined,
        'color': Color(0xFF4CAF50),
      },
      {
        'value': 'self',
        'label': '自产商品',
        'desc': '自主生产制造，商品来自本品牌',
        'icon': Icons.factory_outlined,
        'color': Color(0xFF2196F3),
      },
    ];

    return Column(
      children: options.map((opt) {
        final isSelected = _sourceType == opt['value'];
        final color = opt['color'] as Color;
        return GestureDetector(
          onTap: () => setState(() => _sourceType = opt['value'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.06) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // 自定义单选圆圈
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? color : Colors.grey.shade400,
                      width: isSelected ? 6 : 2,
                    ),
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(opt['icon'] as IconData,
                    size: 22,
                    color: isSelected ? color : Colors.grey.shade500),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        opt['label'] as String,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isSelected ? color : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        opt['desc'] as String,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildImageSection() {
    final allImages = <Widget>[
      // 已上传的图片
      ..._imageUrls.asMap().entries.map((entry) => _ImageThumb(
            url: entry.value,
            onRemove: () => _removeUploadedImage(entry.key),
          )),
      // 待上传的本地图片
      ..._pendingImages.asMap().entries.map((entry) => _LocalImageThumb(
            bytes: entry.value.bytes,
            onRemove: () => _removePendingImage(entry.key),
          )),
      // 添加按钮
      if (_imageUrls.length + _pendingImages.length < 5)
        _AddImageButton(onTap: _pickImage),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: allImages,
    );
  }
}

// ── 小组件 ───────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 4, height: 18, color: const Color(0xFF4CAF50)),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
    ]);
  }
}

class _ImageThumb extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;
  const _ImageThumb({required this.url, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(url,
              width: 90,
              height: 90,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                    width: 90,
                    height: 90,
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  )),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalImageThumb extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback onRemove;
  const _LocalImageThumb({required this.bytes, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, width: 90, height: 90, fit: BoxFit.cover),
        ),
        // 上传中标识
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 22,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8)),
            ),
            child: const Center(
              child: Text('待上传',
                  style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddImageButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddImageButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!, width: 1.5),
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[50],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined,
                size: 30, color: Colors.grey[500]),
            const SizedBox(height: 4),
            Text('添加图片',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}

/// 本地待上传图片数据结构
class _LocalImage {
  final Uint8List bytes;
  final String filename;
  const _LocalImage({required this.bytes, required this.filename});
}
