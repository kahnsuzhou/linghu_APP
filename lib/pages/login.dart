import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../config/constants.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../utils/storage.dart';
import 'main_wrapper.dart';
import 'register.dart';

/// 统一登录页（三端共用）
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _guestLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// 游客身份：跳过登录，直接以 role=0（消费者）进入主页面
  Future<void> _enterAsGuest() async {
    setState(() => _guestLoading = true);
    // 设置游客全局状态（无 token，无 userId）
    if (mounted) {
      context.read<AppState>().setUser(
        role: AppConstants.roleConsumer,
        userId: 0,
        username: '游客',
        warehouseId: null,
        brandId: null,
      );
    }
    // 游客不存 token，不连 WebSocket
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainWrapper()),
      );
    }
    if (mounted) setState(() => _guestLoading = false);
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final response = await ApiService().login(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
      );

      if (response['code'] == 200) {
        final data = response['data'] as Map<String, dynamic>;
        final token = data['token'] as String;
        final role = data['role'] as int;
        final userId = (data['userId'] as num).toInt();
        final username = data['username'] as String? ?? _usernameCtrl.text;

        // 保存 token 和用户信息
        await StorageUtil.saveToken(token);
        await StorageUtil.saveUserInfo(
          userId: userId,
          username: username,
          role: role,
          warehouseId: data['warehouseId'] != null ? (data['warehouseId'] as num).toInt() : null,
          brandId: data['brandId'] != null ? (data['brandId'] as num).toInt() : null,
        );

        // 更新全局状态
        if (mounted) {
          context.read<AppState>().setUser(
            role: role,
            userId: userId,
            username: username,
            warehouseId: data['warehouseId'] != null ? (data['warehouseId'] as num).toInt() : null,
            brandId: data['brandId'] != null ? (data['brandId'] as num).toInt() : null,
          );
        }

        // 建立 WebSocket 连接
        WebSocketService().connect();

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainWrapper()),
          );
        }
      } else {
        _showError(response['msg'] ?? '登录失败');
      }
    } catch (e) {
      _showError('网络错误，请检查连接');
    } finally {
      if (mounted) setState(() => _loading = false);
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
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              // Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text('🦊', style: TextStyle(fontSize: 44)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '灵狐·优库近选',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                '消费者 / 仓主 / 品牌方 统一入口',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 48),
              // 登录表单
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _usernameCtrl,
                      decoration: InputDecoration(
                        labelText: '用户名',
                        hintText: '请输入用户名',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (v) => v == null || v.isEmpty ? '请输入用户名' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: '密码',
                        hintText: '请输入密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (v) => v == null || v.isEmpty ? '请输入密码' : null,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B35),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _loading
                            ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                            : const Text('登 录', style: TextStyle(fontSize: 16, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 游客入口按钮
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: (_loading || _guestLoading) ? null : _enterAsGuest,
                        icon: _guestLoading
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B35)),
                              )
                            : const Text('👀', style: TextStyle(fontSize: 18)),
                        label: const Text(
                          '游客浏览（无需登录）',
                          style: TextStyle(fontSize: 15, color: Color(0xFFFF6B35)),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFF6B35), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('还没有账号？', style: TextStyle(color: Colors.grey)),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RegisterPage()),
                          ),
                          child: const Text('立即注册', style: TextStyle(color: Color(0xFFFF6B35))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // 快速切换角色卡片
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flash_on, size: 15, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('快速切换角色',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickLoginCard(
                          emoji: '🛒',
                          label: '消费者',
                          username: 'consumer',
                          color: const Color(0xFFFF6B35),
                          bgColor: const Color(0xFFFFF3EE),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildQuickLoginCard(
                          emoji: '📦',
                          label: '仓主',
                          username: 'warehouse',
                          color: const Color(0xFF2196F3),
                          bgColor: const Color(0xFFE8F4FD),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildQuickLoginCard(
                          emoji: '🏢',
                          label: '品牌方',
                          username: 'brand',
                          color: const Color(0xFF4CAF50),
                          bgColor: const Color(0xFFEDF7EE),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  /// 一键登录卡片：点击 → 自动填入账号密码 → 立即发起登录
  Widget _buildQuickLoginCard({
    required String emoji,
    required String label,
    required String username,
    required Color color,
    required Color bgColor,
  }) {
    return GestureDetector(
      onTap: _loading
          ? null
          : () async {
              _usernameCtrl.text = username;
              _passwordCtrl.text = '123456';
              await _login();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '点击登录',
              style: TextStyle(color: color.withOpacity(0.6), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
