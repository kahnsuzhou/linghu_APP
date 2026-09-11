import 'package:flutter/material.dart';
import '../../services/api_service.dart';

/// 支付账号绑定管理页（三端通用）
/// 功能：查看已绑定的支付宝/微信账号、绑定新账号、解绑、设为默认
class PaymentAccountPage extends StatefulWidget {
  const PaymentAccountPage({super.key});

  @override
  State<PaymentAccountPage> createState() => _PaymentAccountPageState();
}

class _PaymentAccountPageState extends State<PaymentAccountPage> {
  List<Map<String, dynamic>> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiService().getPaymentAccounts();
      if (resp['code'] == 200 && mounted) {
        setState(() {
          _accounts = (resp['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 渠道图标和颜色
  Widget _channelIcon(String channel, {double size = 28}) {
    if (channel == 'ALIPAY') {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1677FF),
          borderRadius: BorderRadius.circular(size / 4),
        ),
        child: Center(
          child: Text('支', style: TextStyle(color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.bold)),
        ),
      );
    } else {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF07C160),
          borderRadius: BorderRadius.circular(size / 4),
        ),
        child: Center(
          child: Text('微', style: TextStyle(color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.bold)),
        ),
      );
    }
  }

  // 已绑定两个渠道则不显示添加按钮
  bool get _canAddMore {
    final channels = _accounts.map((a) => a['channel'] as String).toSet();
    return !channels.contains('ALIPAY') || !channels.contains('WECHAT');
  }

  void _showBindDialog({String? presetChannel}) {
    String selectedChannel = presetChannel ?? 'ALIPAY';
    final accountCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setLocal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(ctx2).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖拽指示条
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('绑定支付账号',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // 渠道选择
              const Text('选择渠道',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                children: ['ALIPAY', 'WECHAT'].map((ch) {
                  final alreadyBound = _accounts.any((a) =>
                      a['channel'] == ch);
                  final isSelected = selectedChannel == ch;
                  return Expanded(
                    child: GestureDetector(
                      onTap: alreadyBound
                          ? null
                          : () => setLocal(() => selectedChannel = ch),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: EdgeInsets.only(right: ch == 'ALIPAY' ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (ch == 'ALIPAY'
                                  ? const Color(0xFF1677FF).withOpacity(0.1)
                                  : const Color(0xFF07C160).withOpacity(0.1))
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? (ch == 'ALIPAY'
                                    ? const Color(0xFF1677FF)
                                    : const Color(0xFF07C160))
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            _channelIcon(ch, size: 32),
                            const SizedBox(height: 6),
                            Text(
                              ch == 'ALIPAY' ? '支付宝' : '微信',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: alreadyBound
                                    ? Colors.grey
                                    : Colors.black87,
                              ),
                            ),
                            if (alreadyBound)
                              const Text('已绑定',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // 账号输入
              Text(
                selectedChannel == 'ALIPAY'
                    ? '支付宝账号（手机号/邮箱）'
                    : '微信账号（手机号/OpenID）',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: accountCtrl,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  hintText: selectedChannel == 'ALIPAY'
                      ? '请输入支付宝绑定手机号或邮箱'
                      : '请输入微信绑定手机号',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: _channelIcon(selectedChannel, size: 22),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 真实姓名
              const Text('真实姓名（提现时需与账号一致）',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  hintText: '请输入账号持有人真实姓名',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  prefixIcon: const Icon(Icons.person_outline,
                      color: Colors.grey),
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedChannel == 'ALIPAY'
                        ? const Color(0xFF1677FF)
                        : const Color(0xFF07C160),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final account = accountCtrl.text.trim();
                    final name = nameCtrl.text.trim();
                    if (account.isEmpty) {
                      _showSnack('请输入账号');
                      return;
                    }
                    Navigator.pop(ctx2);
                    await _doBind(selectedChannel, account, name);
                  },
                  child: const Text('确认绑定',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doBind(String channel, String accountNo, String realName) async {
    try {
      final resp = await ApiService().bindPaymentAccount(channel, accountNo, realName);
      if (resp['code'] == 200 && mounted) {
        _showSnack('绑定成功', Colors.green);
        _loadAccounts();
      } else if (mounted) {
        _showSnack(resp['msg'] ?? '绑定失败', Colors.red);
      }
    } catch (_) {
      if (mounted) _showSnack('网络错误，请重试', Colors.red);
    }
  }

  Future<void> _doUnbind(int id, String channelName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认解绑'),
        content: Text('确定要解绑该$channelName账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final resp = await ApiService().unbindPaymentAccount(id);
      if (resp['code'] == 200 && mounted) {
        _showSnack('解绑成功', Colors.green);
        _loadAccounts();
      } else if (mounted) {
        _showSnack(resp['msg'] ?? '解绑失败', Colors.red);
      }
    } catch (_) {
      if (mounted) _showSnack('网络错误，请重试', Colors.red);
    }
  }

  Future<void> _doSetDefault(int id) async {
    try {
      final resp = await ApiService().setDefaultPaymentAccount(id);
      if (resp['code'] == 200 && mounted) {
        _showSnack('已设为默认收款账号', Colors.green);
        _loadAccounts();
      }
    } catch (_) {}
  }

  void _showSnack(String msg, [Color color = Colors.orange]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color,
          behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('绑定支付账号'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAccounts,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAccounts,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 说明卡片
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[100]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.blue[700], size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '绑定支付宝或微信账号后，可用于充值和提现。提现时款项将打入绑定的账号。',
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 已绑定账号列表
                  if (_accounts.isNotEmpty) ...[
                    const Text('已绑定账号',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black54)),
                    const SizedBox(height: 10),
                    ..._accounts.map((a) => _buildAccountCard(a)),
                    const SizedBox(height: 20),
                  ],

                  // 可添加渠道列表
                  if (_canAddMore) ...[
                    const Text('添加账号',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black54)),
                    const SizedBox(height: 10),
                    // 支付宝
                    if (!_accounts.any((a) => a['channel'] == 'ALIPAY'))
                      _buildAddCard('ALIPAY', '支付宝',
                          const Color(0xFF1677FF)),
                    const SizedBox(height: 10),
                    // 微信
                    if (!_accounts.any((a) => a['channel'] == 'WECHAT'))
                      _buildAddCard(
                          'WECHAT', '微信', const Color(0xFF07C160)),
                  ],

                  if (_accounts.isEmpty && !_canAddMore)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: Text('暂无绑定账号',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 14)),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildAccountCard(Map<String, dynamic> account) {
    final channel = account['channel'] as String;
    final channelName = account['channelName'] as String? ?? channel;
    final accountNo = account['accountNo'] as String? ?? '--';
    final realName = account['realName'] as String?;
    final isDefault = (account['isDefault'] as int?) == 1;
    final id = (account['id'] as num).toInt();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _channelIcon(channel, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(channelName,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      if (isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.orange[300]!),
                          ),
                          child: Text('默认',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(accountNo,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black54)),
                  if (realName != null && realName.isNotEmpty)
                    Text(realName,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            // 操作菜单
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              onSelected: (action) {
                if (action == 'default') _doSetDefault(id);
                if (action == 'unbind') _doUnbind(id, channelName);
              },
              itemBuilder: (_) => [
                if (!isDefault)
                  const PopupMenuItem(
                    value: 'default',
                    child: Row(children: [
                      Icon(Icons.star_outline, size: 18),
                      SizedBox(width: 8),
                      Text('设为默认'),
                    ]),
                  ),
                PopupMenuItem(
                  value: 'unbind',
                  child: Row(
                    children: [
                      Icon(Icons.link_off, size: 18, color: Colors.red[400]),
                      const SizedBox(width: 8),
                      Text('解绑',
                          style: TextStyle(color: Colors.red[400])),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddCard(String channel, String name, Color color) {
    return GestureDetector(
      onTap: () => _showBindDialog(presetChannel: channel),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            _channelIcon(channel, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  Text('点击绑定$name账号，用于充值和提现',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Icon(Icons.add_circle_outline, color: color, size: 24),
          ],
        ),
      ),
    );
  }
}
