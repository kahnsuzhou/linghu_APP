import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../config/constants.dart';
import '../register.dart';

/// 拉新活动落地页
/// 好友打开分享链接后看到此页，展示商品图片 + 活动价格 + 注册入口
class ActivityLandingPage extends StatefulWidget {
  final String inviteCode;

  const ActivityLandingPage({super.key, required this.inviteCode});

  @override
  State<ActivityLandingPage> createState() => _ActivityLandingPageState();
}

class _ActivityLandingPageState extends State<ActivityLandingPage> {
  static const _orange = Color(0xFFFF6B35);

  Map<String, dynamic>? _activity;
  bool _loading = true;
  bool _isLoggedIn = false;
  bool _bindingInvite = false; // 正在绑定邀请关系

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    try {
      // 优先通过邀请码反查活动详情（最精确）
      final res = await ApiService().get(
        '/api/consumer/activity/by-invite-code',
        queryParams: {'inviteCode': widget.inviteCode},
      );
      if (res['code'] == 200 && res['data'] != null) {
        setState(() {
          _activity = (res['data'] as Map?)?.cast<String, dynamic>() ?? {};
          _loading = false;
        });
        _checkLoginState();
        return;
      }
    } catch (_) {}

    // 降级：从活动列表取第一个活动的详情
    try {
      final listRes = await ApiService().getActivityList();
      if (listRes['code'] == 200) {
        final raw = listRes['data'];
        final List records = raw is List
            ? raw
            : raw is Map
                ? (raw['records'] as List? ?? [])
                : [];
        if (records.isNotEmpty) {
          final first = records.first as Map;
          final activityId = first['id'] ?? first['activityId'];
          if (activityId != null) {
            final detailRes = await ApiService().getActivityDetail(
              activityId as int,
              inviteCode: widget.inviteCode,
            );
            if (detailRes['code'] == 200 && detailRes['data'] != null) {
              setState(() {
                _activity = (detailRes['data'] as Map?)?.cast<String, dynamic>() ?? {};
                _loading = false;
              });
              _checkLoginState();
              return;
            }
          }
        }
      }
    } catch (_) {}

    setState(() => _loading = false);
    _checkLoginState();
  }

  Future<void> _checkLoginState() async {
    try {
      final profileRes = await ApiService().get('/api/consumer/profile');
      if (profileRes['code'] == 200 && mounted) {
        setState(() => _isLoggedIn = true);
      }
    } catch (_) {}
  }

  /// 解析商品图片 JSON 数组，取第一张并补全为绝对 URL
  String? _parseImageUrl(dynamic raw) {
    if (raw == null) return null;
    try {
      String url = '';
      if (raw is String && raw.isNotEmpty) {
        if (raw.startsWith('[')) {
          final list = (jsonDecode(raw) as List?)?.cast<String>() ?? [];
          url = list.isNotEmpty ? list.first : '';
        } else {
          url = raw;
        }
      } else if (raw is List && raw.isNotEmpty) {
        url = raw.first.toString();
      }
      if (url.isEmpty) return null;
      if (url.startsWith('/')) return AppConstants.shareBaseUrl + url;
      return url;
    } catch (_) {
      return null;
    }
  }

  // ─── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHero()),
                SliverToBoxAdapter(child: _buildPriceCard()),
                SliverToBoxAdapter(child: _buildInviteCodeBadge()),
                SliverToBoxAdapter(child: _buildRules()),
                SliverToBoxAdapter(child: _buildBottomButton(context)),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
    );
  }

  // ─── Hero：商品大图 + 渐变 + 标题 ────────────────────────────────────────

  Widget _buildHero() {
    final productImageUrl = _parseImageUrl(_activity?['productImage']);
    final activityName = _activity?['activityName'] as String? ??
        _activity?['name'] as String? ??
        '新用户专属0.1元购活动';
    final inviterName =
        _activity?['inviterName'] as String? ?? '好友';

    return SizedBox(
      height: 280,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 商品图片背景
          if (productImageUrl != null)
            Image.network(productImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _imageFallback())
          else
            _imageFallback(),

          // 渐变蒙层
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.15),
                  Colors.black.withOpacity(0.70),
                ],
              ),
            ),
          ),

          // 顶部返回按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 22),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // 底部文字层
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "xxx 邀请你来" 标签
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _orange.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '🎁  $inviterName 邀请你参与',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  activityName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageFallback() {
    return Container(
      color: const Color(0xFFFF8C55),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🎁', style: TextStyle(fontSize: 72)),
          SizedBox(height: 8),
          Text('限时特惠好物',
              style: TextStyle(color: Colors.white70, fontSize: 15)),
        ],
      ),
    );
  }

  // ─── 价格卡片 ─────────────────────────────────────────────────────────────

  Widget _buildPriceCard() {
    final price = _activity?['activityPrice'] as num? ?? 0.1;
    final originalPrice = _activity?['originalPrice'] as num? ?? 0;
    final productName = _activity?['productName'] as String?;
    final description = _activity?['description'] as String? ??
        _activity?['activityDesc'] as String? ??
        '新用户专属福利，限时0.1元即可带走精选好物，需到就近仓库自提。';

    return Transform.translate(
      offset: const Offset(0, -20),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (productName != null) ...[
              Text(productName,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
            ],
            // 价格行
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('¥',
                    style: TextStyle(
                        color: Color(0xFFE53935),
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text(
                  price.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Color(0xFFE53935),
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 10),
                if (originalPrice > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '原价 ¥${originalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBE5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('新人专享',
                      style: TextStyle(
                          color: _orange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(description,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }

  // ─── 邀请码 badge ──────────────────────────────────────────────────────────

  Widget _buildInviteCodeBadge() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3EE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.confirmation_number_outlined,
                color: _orange, size: 18),
            const SizedBox(width: 10),
            const Text('邀请码：',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            Text(
              widget.inviteCode,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: _orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 活动规则 ─────────────────────────────────────────────────────────────

  Widget _buildRules() {
    final rules = [
      {'title': '新用户专属', 'desc': '每人限购1次，仅限首次注册用户'},
      {'title': '到仓自提',   'desc': '需到就近仓库凭取货码领取商品'},
      {'title': '双方受益',   'desc': '邀请人在好友注册后同样享受0.1元购'},
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                    color: _orange,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            const Text('活动规则',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          ...rules.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(top: 1, right: 10),
                      decoration: const BoxDecoration(
                          color: _orange, shape: BoxShape.circle),
                      child: const Icon(Icons.check,
                          color: Colors.white, size: 13),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r['title'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          Text(r['desc'] ?? '',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _bindInviteAndGoHome(BuildContext context) async {
    setState(() => _bindingInvite = true);
    try {
      final res = await ApiService().post(
        '/api/consumer/activity/bind-invite',
        body: {'inviteCode': widget.inviteCode},
      );
      if (!mounted) return;
      if (res['code'] == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 邀请关系已绑定，快去下单吧！'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // 已参与过、邀请码无效等提示用户
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['msg'] ?? '绑定失败'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络异常，请重试'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _bindingInvite = false);
        Navigator.of(context).pop();
      }
    }
  }

  // ─── 底部按钮 ─────────────────────────────────────────────────────────────

  Widget _buildBottomButton(BuildContext context) {
    if (_isLoggedIn) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _bindingInvite
                  ? null
                  : () => _bindInviteAndGoHome(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28)),
                elevation: 4,
                shadowColor: _orange.withOpacity(0.4),
              ),
              child: _bindingInvite
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('已有账号，绑定邀请关系',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            const Text('绑定后即可享受邀请人的0.1元购优惠',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    RegisterPage(inviteCode: widget.inviteCode),
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
              elevation: 4,
              shadowColor: _orange.withOpacity(0.4),
            ),
            child: const Text('立即注册 · 享0.1元购',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 10),
          const Text('注册后即可以 0.1 元购买活动商品',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}
