import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../utils/storage.dart';
import 'login.dart';
import 'main_wrapper.dart';
import 'consumer/activity_landing.dart';

/// 启动页 - 检查登录状态并跳转
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginAndNavigate();
  }

  /// 从当前页面 URL 提取 inviteCode 参数（Flutter Web 专用，原生平台直接返回 null）
  String? _getInviteCodeFromUrl() {
    // Uri.base 仅在 Web 平台可用，Native 直接返回 null 避免崩溃
    if (!kIsWeb) return null;
    try {
      final uri = Uri.base;
      // 支持两种格式：
      //   /?inviteCode=xxx         (query 参数)
      //   /#/?inviteCode=xxx       (hash 内的 query)
      final directCode = uri.queryParameters['inviteCode'];
      if (directCode != null && directCode.isNotEmpty) return directCode;

      // 解析 fragment（hash）里的 query
      final fragment = uri.fragment; // 例如 "/?inviteCode=ABC123"
      if (fragment.isNotEmpty) {
        final hashUri = Uri.tryParse('http://dummy$fragment');
        if (hashUri != null) {
          final code = hashUri.queryParameters['inviteCode'];
          if (code != null && code.isNotEmpty) return code;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _checkLoginAndNavigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    // ── 深链检测：优先处理邀请链接 ──────────────────────────────
    final inviteCode = _getInviteCodeFromUrl();
    final token = StorageUtil.getToken();

    if (token == null) {
      // 未登录
      if (inviteCode != null) {
        // 有邀请码 → 直接打开落地页
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ActivityLandingPage(inviteCode: inviteCode),
          ),
        );
      } else {
        _navigateToLogin();
      }
      return;
    }

    // 有 token → 验证有效性
    try {
      final response = await ApiService().getCurrentUser();
      if (response['code'] == 200) {
        final data = response['data'] as Map<String, dynamic>;
        final role = data['role'] as int;
        final userId = (data['userId'] as num).toInt();
        final username = data['username'] as String;

        if (mounted) {
          context.read<AppState>().setUser(
            role: role,
            userId: userId,
            username: username,
            warehouseId: data['warehouseId'] != null
                ? (data['warehouseId'] as num).toInt()
                : null,
            brandId: data['brandId'] != null
                ? (data['brandId'] as num).toInt()
                : null,
          );

          if (inviteCode != null) {
            // 已登录 + 有邀请码 → 进主界面后再叠加落地页
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainWrapper()),
            );
            await Future.delayed(const Duration(milliseconds: 300));
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ActivityLandingPage(inviteCode: inviteCode),
                ),
              );
            }
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainWrapper()),
            );
          }
        }
      } else {
        await StorageUtil.clearAll();
        if (inviteCode != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ActivityLandingPage(inviteCode: inviteCode),
            ),
          );
        } else {
          _navigateToLogin();
        }
      }
    } catch (e) {
      // 网络错误：若有邀请码先展示落地页，否则去登录
      if (inviteCode != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ActivityLandingPage(inviteCode: inviteCode),
          ),
        );
      } else {
        _navigateToLogin();
      }
    }
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFF6B35),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Center(
                child: Text('🦊', style: TextStyle(fontSize: 56)),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '灵狐·优库近选',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '优选好货，近在咫尺',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
