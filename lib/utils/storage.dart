import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

/// 本地存储工具类
class StorageUtil {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get prefs {
    if (_prefs == null) throw Exception('StorageUtil 未初始化');
    return _prefs!;
  }

  static bool get isInitialized => _prefs != null;

  // ===== Token 管理 =====

  static Future<void> saveToken(String token) async {
    await prefs.setString(AppConstants.tokenKey, token);
  }

  static String? getToken() {
    if (!isInitialized) return null;
    return _prefs!.getString(AppConstants.tokenKey);
  }

  static Future<void> removeToken() async {
    await prefs.remove(AppConstants.tokenKey);
  }

  // ===== 用户信息 =====

  static Future<void> saveUserInfo({
    required int userId,
    required String username,
    required int role,
    int? warehouseId,
    int? brandId,
  }) async {
    await prefs.setInt(AppConstants.userIdKey, userId);
    await prefs.setString(AppConstants.usernameKey, username);
    await prefs.setInt(AppConstants.roleKey, role);
    if (warehouseId != null) {
      await prefs.setInt(AppConstants.warehouseIdKey, warehouseId);
    }
    if (brandId != null) {
      await prefs.setInt(AppConstants.brandIdKey, brandId);
    }
  }

  static int? getUserId() => prefs.getInt(AppConstants.userIdKey);
  static String? getUsername() => prefs.getString(AppConstants.usernameKey);
  static int? getRole() => prefs.getInt(AppConstants.roleKey);
  static int? getWarehouseId() => prefs.getInt(AppConstants.warehouseIdKey);
  static int? getBrandId() => prefs.getInt(AppConstants.brandIdKey);

  /// 清除所有用户数据（登出时调用）
  static Future<void> clearAll() async {
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userIdKey);
    await prefs.remove(AppConstants.usernameKey);
    await prefs.remove(AppConstants.roleKey);
    await prefs.remove(AppConstants.warehouseIdKey);
    await prefs.remove(AppConstants.brandIdKey);
    // 强制刷新实例，确保 Web 环境下内存缓存同步
    _prefs = await SharedPreferences.getInstance();
  }

  static bool isLoggedIn() {
    return getToken() != null && getRole() != null;
  }
}
