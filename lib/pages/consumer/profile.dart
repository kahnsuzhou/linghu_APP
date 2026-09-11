import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../utils/storage.dart';
import '../../services/api_service.dart';
import '../../services/websocket_service.dart';
import '../login.dart';
import '../wallet/wallet_page.dart';
import 'address_page.dart';
import 'invite_records.dart';
import 'pickup_codes.dart';
import 'complaint_page.dart';

class ConsumerProfilePage extends StatefulWidget {
  const ConsumerProfilePage({super.key});

  static Future<void> logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    WebSocketService().disconnect();
    await StorageUtil.clearAll();
    if (context.mounted) {
      context.read<AppState>().clearUser();
    }
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  State<ConsumerProfilePage> createState() => _ConsumerProfilePageState();
}

class _ConsumerProfilePageState extends State<ConsumerProfilePage> {
  bool _loadingVip = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    if (state.userId != null && state.userId != 0 && state.role == 0) {
      _loadVipInfo();
    }
  }

  Future<void> _loadVipInfo() async {
    try {
      final resp = await ApiService().getVipInfo();
      if (resp['code'] == 200 && mounted) {
        final data = resp['data'] as Map<String, dynamic>;
        final level = (data['vipLevel'] as num?)?.toInt() ?? 0;
        final expireStr = data['vipExpireTime'] as String?;
        final expire = expireStr != null ? DateTime.tryParse(expireStr) : null;
        if (mounted) {
          context.read<AppState>().updateVip(level, expire ?? DateTime.now().subtract(const Duration(days: 1)));
        }
      }
    } catch (_) {}
  }

  void _showVipSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VipPurchaseSheet(onPurchased: () {
        _loadVipInfo();
        setState(() {});
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isGuest = state.userId == 0;
    final isVip = state.isVip;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('我的'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 用户信息头部
          Container(
            color: const Color(0xFFFF6B35),
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  child: Text(
                    isGuest ? '👤' : (isVip ? '👑' : '🛒'),
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isGuest ? '游客' : ((state.username ?? '').isNotEmpty ? state.username! : '消费者'),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isGuest
                              ? '游客模式 · 登录后享受完整功能'
                              : isVip ? '会员用户 · 满30免运费' : '消费者',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 游客模式：显示登录引导卡片
                  if (isGuest) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Text('👋', style: TextStyle(fontSize: 40)),
                              const SizedBox(height: 10),
                              const Text('登录后可使用完整功能',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text('下单购物 · 查看订单 · 保存收藏',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton(
                                  onPressed: () {
                                    navigatorKey.currentState?.pushAndRemoveUntil(
                                      MaterialPageRoute(builder: (_) => const LoginPage()),
                                      (_) => false,
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF6B35),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                                  ),
                                  child: const Text('立即登录', style: TextStyle(fontSize: 15, color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),

                    // ===== 会员卡 =====
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: isVip
                          ? _buildActiveVipCard(state)
                          : _buildInactiveVipCard(),
                    ),

                    const SizedBox(height: 8),

                    // ===== 钱包入口 =====
                    _buildItem(Icons.account_balance_wallet_outlined, '我的钱包', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletPage()));
                    }),

                    // ===== 活动功能入口 =====
                    _buildItem(Icons.card_giftcard_outlined, '我的邀请记录', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const InviteRecordsPage()));
                    }),
                    _buildItem(Icons.qr_code_outlined, '我的自提码', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PickupCodesPage()));
                    }),

                    _buildItem(Icons.location_on_outlined, '收货地址', () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressPage()));
                    }),
                    _buildItem(Icons.favorite_border, '我的收藏', () {}),
                    _buildItem(Icons.history, '浏览记录', () {}),
                    _buildItem(Icons.chat_bubble_outline, '我的吐槽', () {
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const MyComplaintListPage()));
                    }),
                    _buildItem(Icons.headset_mic_outlined, '联系客服', () {}),

                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz, color: Colors.orange[700], size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '想切换为仓主或品牌方？退出后在登录页点击角色卡片即可',
                                style: TextStyle(color: Colors.orange[800], fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),

          // 底部按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: isGuest
                  ? OutlinedButton.icon(
                      onPressed: () {
                        navigatorKey.currentState?.pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                          (_) => false,
                        );
                      },
                      icon: const Icon(Icons.login, color: Color(0xFFFF6B35)),
                      label: const Text('去登录 / 注册', style: TextStyle(color: Color(0xFFFF6B35), fontSize: 16)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFF6B35)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => ConsumerProfilePage.logout(context),
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text('退出登录', style: TextStyle(color: Colors.red, fontSize: 16)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 未开通会员：金色渐变召唤卡
  Widget _buildInactiveVipCard() {
    return GestureDetector(
      onTap: _showVipSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.amber.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('开通灵狐会员', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 3),
                  Text('满30元免运费 · 月仅9.9元起', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('立即开通', style: TextStyle(
                color: Color(0xFFFF8F00), fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// 已开通会员：绿色激活卡
  Widget _buildActiveVipCard(AppState state) {
    final expireStr = state.vipExpireTime != null
        ? '${state.vipExpireTime!.year}-${state.vipExpireTime!.month.toString().padLeft(2, '0')}-${state.vipExpireTime!.day.toString().padLeft(2, '0')} 到期'
        : '';
    final levelLabel = _vipLevelLabel(state.vipLevel);

    return GestureDetector(
      onTap: _showVipSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.green.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('灵狐$levelLabel', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('享用中', style: TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text('满30元免运费 · $expireStr',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Text('续费 >', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  String _vipLevelLabel(int level) {
    switch (level) {
      case 1: return '月会员';
      case 2: return '季度会员';
      case 3: return '年度会员';
      default: return '会员';
    }
  }

  Widget _buildItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[600]),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
      tileColor: Colors.white,
    );
  }
}

// ===================== 会员开通弹窗 =====================
class _VipPurchaseSheet extends StatefulWidget {
  final VoidCallback onPurchased;
  const _VipPurchaseSheet({required this.onPurchased});

  @override
  State<_VipPurchaseSheet> createState() => _VipPurchaseSheetState();
}

class _VipPurchaseSheetState extends State<_VipPurchaseSheet> {
  String _selected = 'quarterly';
  bool _purchasing = false;

  static const _plans = [
    {'key': 'monthly', 'label': '月会员', 'price': '9.90', 'months': 1, 'badge': '', 'perMonth': '9.90/月'},
    {'key': 'quarterly', 'label': '季度会员', 'price': '24.90', 'months': 3, 'badge': '省5.8元', 'perMonth': '8.30/月'},
    {'key': 'yearly', 'label': '年度会员', 'price': '88.00', 'months': 12, 'badge': '省30.8元', 'perMonth': '7.33/月'},
  ];

  Future<void> _purchase() async {
    setState(() => _purchasing = true);
    try {
      final resp = await ApiService().purchaseVip(_selected);
      if (resp['code'] == 200 && mounted) {
        final data = resp['data'] as Map<String, dynamic>;
        final level = (data['vipLevel'] as num?)?.toInt() ?? 1;
        final expireStr = data['vipExpireTime'] as String?;
        final expire = expireStr != null ? DateTime.tryParse(expireStr) : null;
        if (expire != null && mounted) {
          context.read<AppState>().updateVip(level, expire);
        }
        widget.onPurchased();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['message'] as String? ?? '会员开通成功！'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(resp['msg'] as String? ?? '开通失败，请重试'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('网络错误，请重试'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlan = _plans.firstWhere((p) => p['key'] == _selected);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽把手
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          // 标题
          Row(children: const [
            Icon(Icons.workspace_premium, color: Color(0xFFFF8F00), size: 26),
            SizedBox(width: 8),
            Text('开通灵狐会员', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          const Text('会员专享权益，快速配送更省钱', style: TextStyle(color: Colors.grey, fontSize: 13)),

          const SizedBox(height: 16),

          // 权益说明
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFCC02)),
            ),
            child: Column(
              children: [
                _buildBenefit(Icons.local_shipping, '快递配送', '满30元免运费（立省¥6）'),
                const SizedBox(height: 8),
                _buildBenefit(Icons.delivery_dining, '外卖配送', '满30元免运费（立省¥10）'),
                const SizedBox(height: 8),
                _buildBenefit(Icons.store, '到仓自提', '始终免运费（非会员也免费）'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 套餐选择
          Row(
            children: _plans.map((plan) {
              final isSelected = _selected == plan['key'];
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selected = plan['key'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFFF3E0) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFFF8F00) : Colors.grey[200]!,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Column(
                          children: [
                            Text(
                              plan['label'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? const Color(0xFFE65100) : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '¥${plan['price']}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? const Color(0xFFE65100) : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              plan['perMonth'] as String,
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        // 徽标
                        if ((plan['badge'] as String).isNotEmpty)
                          Positioned(
                            top: -16, right: -8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                plan['badge'] as String,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        if (plan['key'] == 'quarterly')
                          Positioned(
                            top: -16, left: 0, right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF8F00),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('推荐', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // 开通按钮
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _purchasing ? null : _purchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8F00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _purchasing
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      '¥${selectedPlan['price']} 立即开通${selectedPlan['label']}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            '* 模拟支付，不会扣除真实费用。到期前可续费，期限叠加',
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBenefit(IconData icon, String title, String desc) {
    return Row(children: [
      Icon(icon, size: 18, color: const Color(0xFFFF8F00)),
      const SizedBox(width: 8),
      Expanded(child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          children: [
            TextSpan(text: '$title  ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: desc, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      )),
    ]);
  }
}
