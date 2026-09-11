import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../services/api_service.dart';
import '../../config/constants.dart';
import 'orders.dart';
import 'address_page.dart';

/// 购物车页面（本地存储）
class CartPage extends StatefulWidget {
  const CartPage({super.key});

  // 全局购物车数据 + 通知器（静态，跨页面共享）
  static final List<Map<String, dynamic>> cartItems = [];
  static final cartNotifier = ValueNotifier<int>(0);

  static void addItem(Map<String, dynamic> product, int quantity) {
    final existing = cartItems.indexWhere((item) =>
        item['productId'] == product['productId'] &&
        item['warehouseId'] == product['warehouseId']);
    if (existing >= 0) {
      cartItems[existing]['quantity'] += quantity;
    } else {
      cartItems.add({...product, 'quantity': quantity});
    }
    cartNotifier.value = cartItems.fold(0, (sum, item) => sum + (item['quantity'] as int));
  }

  @override
  State<CartPage> createState() => _CartPageState();
}

// ===================== 配送方式配置 =====================
class _DeliveryOption {
  final String value;
  final String label;
  final String desc;
  final IconData icon;
  final Color color;
  const _DeliveryOption({
    required this.value,
    required this.label,
    required this.desc,
    required this.icon,
    required this.color,
  });
}

const _deliveryOptions = [
  _DeliveryOption(
    value: 'express',
    label: '快递配送',
    desc: '顺丰 / 京东 / 中通等，预计1-3天送达 · 运费¥6（会员满30免）',
    icon: Icons.local_shipping_outlined,
    color: Color(0xFF2196F3),
  ),
  _DeliveryOption(
    value: 'delivery',
    label: '外卖配送',
    desc: '仓库骑手即时配送，30分钟–2小时内 · 运费¥10（会员满30免）',
    icon: Icons.delivery_dining_outlined,
    color: Color(0xFFFF6B35),
  ),
  _DeliveryOption(
    value: 'pickup',
    label: '到仓自提',
    desc: '前往仓库自行取货，免运费',
    icon: Icons.store_outlined,
    color: Color(0xFF4CAF50),
  ),
];

// ===================== 购物车 State =====================
class _CartPageState extends State<CartPage> {
  List<Map<String, dynamic>> get _cartItems => CartPage.cartItems;
  bool _checkingOut = false;
  String _selectedDelivery = 'express'; // 当前选中的配送方式
  Map<String, dynamic>? _selectedAddress; // 当前选中的收货地址

  double get _totalAmount => _cartItems.fold(0, (sum, item) =>
      sum + ((item['price'] ?? 0) as num).toDouble() * ((item['quantity'] ?? 1) as int));

  /// 根据配送方式 + 会员状态计算运费
  double _calcShippingFee(String mode, double goodsAmount, bool isVip) {
    if (mode == 'pickup') return 0;
    if (isVip && goodsAmount >= 30) return 0;
    return mode == 'delivery' ? 10.0 : 6.0;
  }

  /// 计算购物车中所有仓库共同支持的发货方式（取交集）
  /// 若某件商品没有 supportedDeliveries 则视为全部支持
  List<_DeliveryOption> get _availableDeliveryOptions {
    // 收集每个购物车项的仓库支持方式
    Set<String> commonModes = {'express', 'delivery', 'pickup'};
    for (final item in _cartItems) {
      final raw = item['supportedDeliveries'] as String? ?? '';
      if (raw.isEmpty) continue;
      try {
        final modes = raw
            .replaceAll('[', '').replaceAll(']', '').replaceAll('"', '')
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet();
        if (modes.isNotEmpty) commonModes = commonModes.intersection(modes);
      } catch (_) {}
    }
    // 如果交集为空（仓库设置冲突），降级为全部显示
    if (commonModes.isEmpty) commonModes = {'express', 'delivery', 'pickup'};
    return _deliveryOptions.where((o) => commonModes.contains(o.value)).toList();
  }

  /// 从 images 字段（JSON 数组字符串）取第一张图片完整 URL(支持相对路径和绝对 URL)
  String _getFirstImage(Map<String, dynamic> item) {
    final raw = item['images'] as String? ?? '';
    if (raw.isEmpty) return '';
    final trimmed = raw.trim();
    String url = trimmed;
    if (trimmed.startsWith('[')) {
      final inner = trimmed.substring(1, trimmed.length - 1).trim();
      if (inner.isEmpty) return '';
      url = inner.split('","').first.replaceAll('"', '').trim();
    }
    // 相对路径自动补全
    if (url.startsWith('/')) {
      return AppConstants.apiBaseUrl + url;
    }
    return url;
  }

  /// 构建商品图片 Widget（优先用真实图，失败则显示灰色占位）
  Widget _buildProductImage(Map<String, dynamic> item, double size) {
    final url = _getFirstImage(item);
    if (url.isNotEmpty) {
      return Image.network(
        url,
        width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderImage(size),
      );
    }
    return _placeholderImage(size);
  }

  Widget _placeholderImage(double size) => Container(
    width: size, height: size, color: Colors.grey[200],
    child: const Icon(Icons.image_outlined, color: Colors.grey),
  );

  void _notifyChange() {
    CartPage.cartNotifier.value =
        _cartItems.fold(0, (sum, item) => sum + (item['quantity'] as int));
    setState(() {});
  }

  /// 点击结算：弹出独立的结算面板（状态完全在 _CheckoutSheet 内部管理）
  Future<void> _showDeliverySheet() async {
    if (_cartItems.isEmpty) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CheckoutSheet(
        availableOpts: _availableDeliveryOptions,
        allOpts: _deliveryOptions,
        initialMode: _selectedDelivery,
        initialAddress: _selectedAddress,
        totalAmount: _totalAmount,
        calcShipping: _calcShippingFee,
      ),
    );

    if (result != null) {
      final mode = result['mode'] as String;
      final addr = result['address'] as Map<String, dynamic>?;
      final pickupTime = result['pickupTime'] as String?;
      setState(() {
        _selectedDelivery = mode;
        _selectedAddress = addr;
      });
      await _checkout(mode, addr, pickupTime: pickupTime);
    }
  }

  Future<void> _checkout(String deliveryMode, Map<String, dynamic>? address, {String? pickupTime}) async {
    setState(() => _checkingOut = true);
    try {
      final orderItems = _cartItems.map((item) => {
        'productId': item['productId'],
        'warehouseId': item['warehouseId'],
        'quantity': item['quantity'],
      }).toList();

      final Map<String, dynamic> orderBody = {
        'items': orderItems,
        'deliveryMode': deliveryMode,
      };
      if (address != null && address['id'] != null) {
        orderBody['addressId'] = address['id'];
      }
      if (pickupTime != null && pickupTime.isNotEmpty) {
        orderBody['pickupTime'] = pickupTime;
      }

      final response = await ApiService().createOrder(orderBody);

      if (response['code'] == 200) {
        final data = response['data'] as Map<String, dynamic>;
        _cartItems.clear();
        _notifyChange();

        if (mounted) {
          final modeLabel = _deliveryOptions
              .firstWhere((o) => o.value == deliveryMode,
                  orElse: () => _deliveryOptions.first)
              .label;

          final isSplit = data['isSplit'] == true;
          final splitMsg = data['splitMessage'] as String?;
          final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;

          // 显示下单成功弹窗，引导用户去支付
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.green, size: 26),
                  SizedBox(width: 8),
                  Text('下单成功'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSplit && splitMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFCC02)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.call_split_outlined, color: Color(0xFFFF8F00), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(splitMsg,
                                style: const TextStyle(fontSize: 13, color: Color(0xFFE65100))),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Text('配送方式：$modeLabel',
                      style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined,
                            color: Color(0xFFFF6B35), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '待支付金额 ¥${totalAmount.toStringAsFixed(2)}，请前往"我的订单"完成支付',
                            style: const TextStyle(fontSize: 13, color: Color(0xFFE65100)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('稍后支付', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    // 跳转到订单页（待支付 tab）
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OrdersPage(initialTabIndex: 1)),
                    );
                  },
                  child: const Text('去支付'),
                ),
              ],
            ),
          );
        }
      } else {
        _showError(response['msg'] ?? '下单失败');
      }
    } catch (_) {
      _showError('网络错误，请重试');
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CartPage.cartNotifier,
      builder: (context, _, __) {
        return Scaffold(
          appBar: AppBar(
            title: Text('购物车${_cartItems.isNotEmpty ? "（${_cartItems.length}）" : ""}'),
            backgroundColor: const Color(0xFFFF6B35),
            foregroundColor: Colors.white,
            actions: [
              if (_cartItems.isNotEmpty)
                TextButton(
                  onPressed: () {
                    _cartItems.clear();
                    _notifyChange();
                  },
                  child: const Text('清空', style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
          body: _cartItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('购物车空空如也', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      SizedBox(height: 12),
                      Text('去首页挑选商品吧~', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 商品列表
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _cartItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _cartItems[index];
                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: _buildProductImage(item, 70),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item['name'] ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.w500),
                                            maxLines: 2, overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 4),
                                        Text(
                                          '¥${((item['price'] ?? 0) as num).toStringAsFixed(2)}',
                                          style: const TextStyle(color: Color(0xFFFF6B35), fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, size: 22),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          if (item['quantity'] > 1) {
                                            item['quantity']--;
                                          } else {
                                            _cartItems.removeAt(index);
                                          }
                                          _notifyChange();
                                        },
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        child: Text('${item['quantity']}',
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, size: 22),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          item['quantity']++;
                                          _notifyChange();
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // 底部结算栏
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
                      ),
                      child: Column(
                        children: [
                          // 当前配送方式展示
                          Builder(builder: (_) {
                            final opt = _deliveryOptions.firstWhere(
                              (o) => o.value == _selectedDelivery,
                              orElse: () => _deliveryOptions.first,
                            );
                            return GestureDetector(
                              onTap: _checkingOut ? null : _showDeliverySheet,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: opt.color.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: opt.color.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(opt.icon, color: opt.color, size: 18),
                                    const SizedBox(width: 8),
                                    Text(opt.label, style: TextStyle(color: opt.color, fontWeight: FontWeight.w500, fontSize: 13)),
                                    const Spacer(),
                                    Text('点击更换', style: TextStyle(color: opt.color.withOpacity(0.7), fontSize: 12)),
                                    Icon(Icons.chevron_right, color: opt.color, size: 16),
                                  ],
                                ),
                              ),
                            );
                          }),
                          // 合计 + 结算按钮
                          Builder(builder: (ctx) {
                            final isVip = ctx.watch<AppState>().isVip;
                            final shipping = _calcShippingFee(_selectedDelivery, _totalAmount, isVip);
                            final total = _totalAmount + shipping;
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text(
                                          '合计：¥${total.toStringAsFixed(2)}',
                                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                        ),
                                      ]),
                                      const SizedBox(height: 2),
                                      if (_selectedDelivery != 'pickup')
                                        Row(children: [
                                          Text(
                                            shipping == 0
                                                ? '运费：¥0.00'
                                                : '运费：¥${shipping.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: shipping == 0 ? Colors.green : Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          if (isVip && _totalAmount >= 30 && _selectedDelivery != 'pickup')
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.green[50],
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.green[300]!),
                                              ),
                                              child: const Text('会员免运费', style: TextStyle(fontSize: 10, color: Colors.green)),
                                            )
                                          else if (!isVip && _selectedDelivery != 'pickup')
                                            GestureDetector(
                                              onTap: () {},
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber[50],
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.amber[300]!),
                                                ),
                                                child: const Text('开会员免运费', style: TextStyle(fontSize: 10, color: Colors.orange)),
                                              ),
                                            ),
                                        ])
                                      else
                                        const Text('运费：免费', style: TextStyle(fontSize: 12, color: Colors.green)),
                                      Text(
                                        '共${_cartItems.fold(0, (s, e) => s + (e['quantity'] as int))}件商品',
                                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 110,
                                  height: 46,
                                  child: ElevatedButton(
                                    onPressed: _checkingOut ? null : _showDeliverySheet,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF6B35),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                                    ),
                                    child: _checkingOut
                                        ? const SizedBox(
                                            width: 20, height: 20,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                          )
                                        : const Text('去结算', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 结算底部弹窗（独立 StatefulWidget，彻底避免闭包状态捕获问题）
// ─────────────────────────────────────────────────────────────────────────────
class _CheckoutSheet extends StatefulWidget {
  final List<_DeliveryOption> availableOpts;
  final List<_DeliveryOption> allOpts;
  final String initialMode;
  final Map<String, dynamic>? initialAddress;
  final double totalAmount;
  final double Function(String mode, double amount, bool isVip) calcShipping;

  const _CheckoutSheet({
    required this.availableOpts,
    required this.allOpts,
    required this.initialMode,
    required this.initialAddress,
    required this.totalAmount,
    required this.calcShipping,
  });

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

// 预约提货时间段配置
class _TimeSlot {
  final String label;  // 显示文本
  final String value;  // 传给后端的值
  const _TimeSlot(this.label, this.value);
}

const _timeSlots = [
  _TimeSlot('09:00 - 12:00', '09:00-12:00'),
  _TimeSlot('12:00 - 14:00', '12:00-14:00'),
  _TimeSlot('14:00 - 17:00', '14:00-17:00'),
  _TimeSlot('17:00 - 20:00', '17:00-20:00'),
];

class _CheckoutSheetState extends State<_CheckoutSheet> {
  late String _mode;
  Map<String, dynamic>? _address;
  bool _loadingAddr = false;

  // 预约自提时间
  int _pickupDateOffset = 0;   // 0=今天 1=明天 2=后天
  int _pickupSlotIndex = -1;   // -1=未选

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _address = widget.initialAddress;
    // 如果没有初始地址，异步加载默认地址
    if (_address == null) {
      _loadDefaultAddress();
    }
  }

  /// 把日期偏移 + 时间段组合成字符串，如「今天 14:00-17:00」
  String? get _pickupTimeString {
    if (_pickupSlotIndex < 0) return null;
    final dateLabels = ['今天', '明天', '后天'];
    final slot = _timeSlots[_pickupSlotIndex];
    return '${dateLabels[_pickupDateOffset]} ${slot.value}';
  }

  Future<void> _loadDefaultAddress() async {
    setState(() => _loadingAddr = true);
    try {
      final resp = await ApiService().getAddressList();
      if (resp['code'] == 200 && mounted) {
        final list = (resp['data'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (list.isNotEmpty) {
          final def = list.firstWhere(
            (a) => (a['isDefault'] ?? 0) == 1,
            orElse: () => list.first,
          );
          setState(() => _address = def);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingAddr = false);
    }
  }

  Future<void> _pickAddress() async {
    final addr = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const AddressPage(selectMode: true)),
    );
    if (addr != null && mounted) {
      setState(() => _address = addr);
    }
  }

  /// 构建预约提货时间选择区域
  List<Widget> _buildPickupTimeSection() {
    final dateOptions = [
      {'label': '今天', 'offset': 0},
      {'label': '明天', 'offset': 1},
      {'label': '后天', 'offset': 2},
    ];
    return [
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _pickupSlotIndex < 0 ? Colors.red.shade50 : Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _pickupSlotIndex < 0 ? Colors.red.shade200 : Colors.green.shade300,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 18,
                  color: _pickupSlotIndex < 0 ? Colors.red : Colors.green[700],
                ),
                const SizedBox(width: 6),
                Text(
                  '预约提货时间',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _pickupSlotIndex < 0 ? Colors.red : Colors.green[700],
                  ),
                ),
                const Spacer(),
                if (_pickupSlotIndex >= 0)
                  Text(
                    _pickupTimeString ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[700],
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else
                  const Text('必填', style: TextStyle(fontSize: 12, color: Colors.red)),
              ],
            ),
            const SizedBox(height: 12),
            // 日期选择（今天/明天/后天）
            Row(
              children: dateOptions.map((d) {
                final offset = d['offset'] as int;
                final selected = _pickupDateOffset == offset;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _pickupDateOffset = offset;
                      _pickupSlotIndex = -1; // 切换日期重置时间段
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: EdgeInsets.only(right: offset < 2 ? 6.0 : 0.0),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF4CAF50) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? const Color(0xFF4CAF50) : Colors.grey[300]!,
                        ),
                      ),
                      child: Text(
                        d['label'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: selected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            // 时间段选择
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 3.2,
              children: List.generate(_timeSlots.length, (i) {
                final slot = _timeSlots[i];
                final selected = _pickupSlotIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _pickupSlotIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF4CAF50) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? const Color(0xFF4CAF50) : Colors.grey[300]!,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        slot.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          color: selected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isVip = context.watch<AppState>().isVip;
    final shipping = widget.calcShipping(_mode, widget.totalAmount, isVip);
    final total = widget.totalAmount + shipping;
    final addrData = _address; // 捕获为局部不可变变量，避免 null check 问题

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽把手
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('确认订单', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // ──── 收货地址选择区（自提模式隐藏） ────
            if (_mode != 'pickup')
              GestureDetector(
                onTap: _pickAddress,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8F0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: addrData == null
                          ? Colors.red.shade300
                          : const Color(0xFFFF6B35).withOpacity(0.4),
                    ),
                  ),
                  child: Row(children: [
                    _loadingAddr
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B35)))
                        : Icon(
                            Icons.location_on_outlined,
                            color: addrData == null ? Colors.red : const Color(0xFFFF6B35),
                            size: 22,
                          ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: addrData == null
                          ? Text(
                              _loadingAddr ? '正在加载地址...' : '请选择收货地址',
                              style: TextStyle(
                                color: _loadingAddr ? Colors.grey : Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text(
                                    addrData['name'] as String? ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    addrData['phone'] as String? ?? '',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                  ),
                                ]),
                                const SizedBox(height: 3),
                                Text(
                                  addrData['fullAddress'] as String? ?? '',
                                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                  ]),
                ),
              ),
            if (_mode != 'pickup') const SizedBox(height: 16),

            // ──── 配送方式 ────
            const Text('配送方式', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (widget.availableOpts.length < widget.allOpts.length)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '仓库不支持全部配送方式，仅显示可用选项',
                      style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                    ),
                  ),
                ]),
              ),

            // 价格汇总
            Text('商品金额：¥${widget.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            Row(children: [
              Text('运费：¥${shipping.toStringAsFixed(2)}',
                  style: TextStyle(color: shipping == 0 ? Colors.green : Colors.grey, fontSize: 13)),
              if (isVip && widget.totalAmount >= 30 && _mode != 'pickup') ...[
                const SizedBox(width: 4),
                const Text('会员免运费', style: TextStyle(color: Colors.green, fontSize: 11)),
              ],
            ]),
            Text('合计：¥${total.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),

            // 配送方式列表
            ...widget.availableOpts.map((opt) => GestureDetector(
              onTap: () => setState(() {
                _mode = opt.value;
                // 切换配送方式时重置自提时间
                if (opt.value != 'pickup') {
                  _pickupDateOffset = 0;
                  _pickupSlotIndex = -1;
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _mode == opt.value ? opt.color.withOpacity(0.06) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _mode == opt.value ? opt.color : Colors.grey[200]!,
                    width: _mode == opt.value ? 2 : 1,
                  ),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: opt.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(opt.icon, color: opt.color, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(opt.label, style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _mode == opt.value ? opt.color : Colors.black87,
                        )),
                        const SizedBox(height: 3),
                        Text(opt.desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  if (_mode == opt.value)
                    Icon(Icons.check_circle, color: opt.color, size: 22),
                ]),
              ),
            )),
            // ──── 自提预约时间（仅 pickup 模式显示） ────
            if (_mode == 'pickup') ..._buildPickupTimeSection(),

            const SizedBox(height: 8),

            // 确认按钮
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  if (_mode != 'pickup' && _address == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请先选择收货地址'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  if (_mode == 'pickup' && _pickupSlotIndex < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请选择预约提货时间段'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  Navigator.pop(context, {
                    'mode': _mode,
                    'address': _address,
                    'pickupTime': _pickupTimeString,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('确认结算', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
