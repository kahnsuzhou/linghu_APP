import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../config/constants.dart';

/// 拉新活动邀请页
/// 展示带商品图片的邀请卡片，支持复制邀请码 / 复制分享链接
class ActivityInvitePage extends StatefulWidget {
  final int activityId;
  final String activityName;

  const ActivityInvitePage({
    super.key,
    required this.activityId,
    required this.activityName,
  });

  @override
  State<ActivityInvitePage> createState() => _ActivityInvitePageState();
}

class _ActivityInvitePageState extends State<ActivityInvitePage> {
  static const _orange = Color(0xFFFF6B35);
  static const _deepOrange = Color(0xFFFF9A00);

  // 活动详情（先加载，不依赖邀请码）
  bool _detailLoading = true;
  String? _productName;
  String? _productImageUrl;
  num _activityPrice = 0.1;
  num _originalPrice = 0;
  String? _description;
  String? _activityName;

  // 邀请码（后加载）
  bool _inviteLoading = false;
  String? _inviteCode;
  String? _inviteError;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  /// 第一步：加载活动详情（商品图片、价格、说明）
  Future<void> _loadDetail() async {
    setState(() => _detailLoading = true);
    try {
      final res = await ApiService().getActivityDetail(widget.activityId);
      if (res['code'] == 200) {
        final data = res['data'] as Map<String, dynamic>;
        setState(() {
          _activityName  = data['name'] as String? ?? widget.activityName;
          _productName   = data['productName'] as String?;
          _productImageUrl = _parseImageUrl(data['productImage']);
          _activityPrice = data['activityPrice'] as num? ?? 0.1;
          _originalPrice = data['originalPrice'] as num? ?? 0;
          _description   = data['description'] as String?;
        });
        // 详情加载完立即生成邀请码
        _generateInvite();
      } else {
        setState(() => _inviteError = res['msg'] as String? ?? '活动加载失败');
      }
    } catch (e) {
      setState(() => _inviteError = '网络错误：$e');
    } finally {
      setState(() => _detailLoading = false);
    }
  }

  /// 第二步：生成邀请码（独立于详情，失败不影响商品展示）
  Future<void> _generateInvite() async {
    setState(() {
      _inviteLoading = true;
      _inviteError = null;
      _inviteCode = null;
    });
    try {
      final res = await ApiService().createInvite(widget.activityId);
      if (res['code'] == 200) {
        final data = res['data'] as Map<String, dynamic>;
        setState(() {
          _inviteCode = data['inviteCode'] as String? ?? '';
          // 如果详情里没拿到商品信息，从这里补
          _productName     ??= data['productName'] as String?;
          _productImageUrl ??= _parseImageUrl(data['productImage']);
          if (_activityPrice == 0.1 && data['activityPrice'] != null) {
            _activityPrice = data['activityPrice'] as num;
          }
          if (_originalPrice == 0 && data['originalPrice'] != null) {
            _originalPrice = data['originalPrice'] as num;
          }
          _description ??= data['description'] as String?;
        });
      } else {
        setState(() => _inviteError = res['msg'] as String? ?? '生成邀请码失败');
      }
    } catch (e) {
      setState(() => _inviteError = '网络错误：$e');
    } finally {
      setState(() => _inviteLoading = false);
    }
  }

  /// 解析商品图片 JSON 数组，取第一张并补全为绝对 URL
  String? _parseImageUrl(dynamic raw) {
    if (raw == null) return null;
    try {
      String url = '';
      if (raw is String && raw.isNotEmpty) {
        if (raw.startsWith('[')) {
          final list = jsonDecode(raw) as List?;
          if (list != null && list.isNotEmpty) url = list.first.toString();
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

  /// 分享链接：落地页 URL，带邀请码参数
  String get _shareLink {
    final base = AppConstants.shareBaseUrl;
    return '$base/#/?inviteCode=$_inviteCode';
  }

  void _copyCode() {
    if (_inviteCode == null || _inviteCode!.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _inviteCode!));
    _showSnack('✓ 邀请码已复制');
  }

  void _copyLink() {
    if (_inviteCode == null || _inviteCode!.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _shareLink));
    _showSnack('✓ 分享链接已复制，发给好友吧！');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
      backgroundColor: _orange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ─── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('邀请好友·0.1元购',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _orange,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _detailLoading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : _buildContent(),
    );
  }

  // ─── 主内容（详情加载完就显示，不等邀请码）──────────────────────────────────

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        children: [
          // ① 邀请卡片（含商品图片、价格、说明、邀请码）
          _buildInviteCard(),
          const SizedBox(height: 20),
          // ② 分享链接行（邀请码生成后才显示）
          if (_inviteCode != null && _inviteCode!.isNotEmpty) ...[
            _buildShareLinkRow(),
            const SizedBox(height: 24),
            _buildActionButtons(),
            const SizedBox(height: 24),
          ],
          // ③ 活动说明
          _buildRules(),
        ],
      ),
    );
  }

  // ─── ① 邀请卡片 ──────────────────────────────────────────────────────────

  Widget _buildInviteCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B35), Color(0xFFFF9A00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _orange.withOpacity(0.4),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // 顶部：商品图片区
          _buildProductImageArea(),
          // 分隔虚线
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _DashedDivider(),
          ),
          // 底部：活动信息 + 邀请码
          _buildCardBottom(),
        ],
      ),
    );
  }

  Widget _buildProductImageArea() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Stack(
        children: [
          // 商品图片（或占位）
          SizedBox(
            width: double.infinity,
            height: 200,
            child: _productImageUrl != null
                ? Image.network(
                    _productImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _productPlaceholder(),
                  )
                : _productPlaceholder(),
          ),
          // 渐变蒙层
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.55),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
          ),
          // 活动价格 badge（左上角）
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('¥',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  Text(
                    _activityPrice.toStringAsFixed(2),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.0),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '原价¥${_originalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        decoration: TextDecoration.lineThrough),
                  ),
                ],
              ),
            ),
          ),
          // 商品名（左下角）
          if (_productName != null)
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Text(
                _productName!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.black54, blurRadius: 4),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _productPlaceholder() {
    return Container(
      width: double.infinity,
      height: 200,
      color: _deepOrange.withOpacity(0.25),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.card_giftcard, size: 64, color: Colors.white54),
          SizedBox(height: 8),
          Text('限时特惠商品',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildCardBottom() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Column(
        children: [
          // 活动名称
          Text(
            _activityName ?? widget.activityName,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
          // 活动说明
          if (_description != null && _description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                _description!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // 邀请码区域
          _buildInviteCodeArea(),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.arrow_downward_rounded,
                  color: Colors.white54, size: 14),
              SizedBox(width: 4),
              Text('把链接发给好友，ta 注册后双方都能 0.1 元购',
                  style: TextStyle(fontSize: 12, color: Colors.white60)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInviteCodeArea() {
    // 邀请码生成中
    if (_inviteLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2)),
            SizedBox(width: 10),
            Text('生成邀请码中…', style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      );
    }
    // 邀请码生成失败
    if (_inviteError != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            const Icon(Icons.info_outline, color: Colors.white70, size: 20),
            const SizedBox(height: 6),
            Text(_inviteError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _generateInvite,
              child: const Text('重新生成',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
    // 邀请码展示
    if (_inviteCode != null && _inviteCode!.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white30, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Column(
              children: [
                const Text('我的邀请码',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        letterSpacing: 2)),
                const SizedBox(height: 4),
                Text(
                  _inviteCode!,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 6,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _copyCode,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.copy_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // ─── ② 分享链接行 ─────────────────────────────────────────────────────────

  Widget _buildShareLinkRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, color: _orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _shareLink,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF444444),
                  fontFamily: 'monospace'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _copyLink,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _orange,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('复制',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── ③ 操作按钮 ──────────────────────────────────────────────────────────

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _copyCode,
            icon: const Icon(Icons.confirmation_number_outlined, size: 18),
            label: const Text('复制邀请码'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _orange,
              side: const BorderSide(color: _orange, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _copyLink,
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('复制分享链接'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 4,
              shadowColor: _orange.withOpacity(0.45),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  // ─── ④ 活动规则 ──────────────────────────────────────────────────────────

  Widget _buildRules() {
    final rules = [
      {'title': '新用户专属', 'desc': '每位新用户限参与1次，仅限首次注册用户'},
      {'title': '到仓自提',   'desc': '下单后需到就近仓库凭取货码自提'},
      {'title': '双方受益',   'desc': '好友注册并下单后，邀请人也获得0.1元购资格'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
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
}

// ─── 虚线分隔组件 ─────────────────────────────────────────────────────────────

class _DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashPainter(),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 1;
    const dashWidth = 6.0;
    const gapWidth = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
