import 'package:flutter/foundation.dart' show kIsWeb;

/// 应用全局常量配置
class AppConstants {
  // ── 后端服务固定地址（域名指向 124.222.132.208） ─────────────────────────
  /// API 后端根地址
  /// Web 端用空字符串（相对路径，由 serve.js 代理）；Native 用绝对地址
  static String get apiBaseUrl {
    if (kIsWeb) return '';                         // Web: 相对路径 → serve.js 代理
    return 'http://124.222.132.208';               // Android/iOS: IP直连（域名备案中临时方案）
  }

  /// WebSocket 地址（所有平台统一）
  static const String wsUrl = 'ws://124.222.132.208/ws-native';

  // ── 分享链接基础域名 ────────────────────────────────────────────────────
  /// Web 端：动态取浏览器域名（若是 trycloudflare.com 则直用，否则用 Tunnel 备用地址）
  /// Native：用固定前端域名
  static const String _frontendUrl = 'https://aifox.club';
  static const String _tunnelFallbackUrl = 'https://ids-samba-let-committee.trycloudflare.com';

  static String get shareBaseUrl {
    if (!kIsWeb) return _frontendUrl;              // Native: 固定前端域名
    try {
      final base = Uri.base;
      final host = base.host;
      // 域名/IP 访问时，直接用当前访问的 origin（含 IP 直连场景）
      if (host.endsWith('trycloudflare.com') ||
          host.endsWith('aifox.club') ||
          RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) {
        return '${base.scheme}://$host';
      }
      return _tunnelFallbackUrl;                   // Cloud Studio 内部代理时回退
    } catch (_) {
      return _tunnelFallbackUrl;
    }
  }

  // ── JWT Token 存储键 ────────────────────────────────────────────────────
  static const String tokenKey = 'jwt_token';
  static const String userIdKey = 'user_id';
  static const String usernameKey = 'username';
  static const String roleKey = 'user_role';
  static const String warehouseIdKey = 'warehouse_id';
  static const String brandIdKey = 'brand_id';

  // ── 角色常量 ────────────────────────────────────────────────────────────
  static const int roleConsumer = 0;
  static const int roleWarehouse = 1;
  static const int roleBrand = 2;

  // ── 订单状态 ────────────────────────────────────────────────────────────
  static const Map<String, String> orderStatusMap = {
    'PENDING_PAY': '待支付',
    'PENDING_DELIVERY': '待发货',
    'DELIVERING': '待收货',
    'FINISHED': '已完成',
    'CANCELLED': '已取消',
  };

  // ── 作业单状态 ──────────────────────────────────────────────────────────
  static const Map<String, String> workOrderStatusMap = {
    'PENDING': '待处理',
    'PROCESSING': '处理中',
    'COMPLETED': '已完成',
    'CANCELLED': '已取消',
  };

  // ── 主题色（按角色） ────────────────────────────────────────────────────
  static const Map<int, int> themeColors = {
    0: 0xFFFF6B35, // 消费者 - 橙色
    1: 0xFF2196F3, // 仓主 - 蓝色
    2: 0xFF4CAF50, // 品牌方 - 绿色
  };
}
