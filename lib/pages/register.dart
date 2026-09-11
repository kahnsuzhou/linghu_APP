import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// 注册页面
/// [inviteCode] 可选，由邀请落地页传入，注册成功后自动绑定邀请关系
class RegisterPage extends StatefulWidget {
  final String? inviteCode;

  const RegisterPage({super.key, this.inviteCode});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  int _selectedRole = 0;
  bool _loading = false;

  final List<Map<String, dynamic>> _roles = [
    {'value': 0, 'label': '消费者', 'icon': '🛒', 'desc': '购物下单，享受即时配送'},
    {'value': 1, 'label': '仓主', 'icon': '📦', 'desc': '管理Mini仓，提供履约服务'},
    {'value': 2, 'label': '品牌方', 'icon': '🏢', 'desc': '上架商品，铺货至各仓'},
  ];

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final response = await ApiService().register({
        'username': _usernameCtrl.text.trim(),
        'password': _passwordCtrl.text,
        'phone': _phoneCtrl.text.trim(),
        'role': _selectedRole,
      });

      if (response['code'] == 200) {
        // 注册成功后，若有邀请码则自动登录并绑定
        if (widget.inviteCode != null && widget.inviteCode!.isNotEmpty) {
          await _autoLoginAndBind();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('注册成功，请登录'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context);
          }
        }
      } else {
        _showError(response['msg'] ?? '注册失败');
      }
    } catch (e) {
      _showError('网络错误，请检查连接');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 注册成功后自动登录，然后绑定邀请码，最后返回落地页
  Future<void> _autoLoginAndBind() async {
    try {
      // 自动登录获取 token
      final loginRes = await ApiService().login(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
      );
      if (loginRes['code'] == 200) {
        // 绑定邀请码（静默，失败不影响体验）
        try {
          await ApiService().bindInvite(widget.inviteCode!);
        } catch (_) {
          // 绑定失败不报错，继续流程
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('注册成功，邀请关系已绑定 🎉'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          // 返回两层：回到落地页，让用户可以去下单
          Navigator.pop(context); // 关闭注册页
          Navigator.pop(context); // 关闭落地页（可选：根据产品需求决定是否保留落地页）
        }
      } else {
        // 登录失败（不影响注册结果），降级提示手动登录
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('注册成功，请手动登录后参与活动'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('注册成功，请手动登录后参与活动'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('注册账号'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 邀请码提示横幅
              if (widget.inviteCode != null && widget.inviteCode!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B35), Color(0xFFFF9A62)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Text('🎉', style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '好友邀请你来了！',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '注册即可享0.1元特惠购',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const Text('选择账号类型',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ..._roles.map((role) => _buildRoleCard(role)),
              const SizedBox(height: 24),
              TextFormField(
                controller: _usernameCtrl,
                decoration: InputDecoration(
                  labelText: '用户名',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) =>
                    v == null || v.length < 3 ? '用户名至少3位' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '密码',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) =>
                    v == null || v.length < 6 ? '密码至少6位' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: '手机号',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          widget.inviteCode != null
                              ? '注册并参与活动'
                              : '注 册',
                          style: const TextStyle(
                              fontSize: 16, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(Map<String, dynamic> role) {
    final selected = _selectedRole == role['value'];
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role['value']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFF6B35).withOpacity(0.1)
              : Colors.grey[50],
          border: Border.all(
            color: selected ? const Color(0xFFFF6B35) : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(role['icon'], style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role['label'],
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(role['desc'],
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: Color(0xFFFF6B35)),
          ],
        ),
      ),
    );
  }
}
