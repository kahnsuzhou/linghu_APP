import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pages/splash_screen.dart';
import 'pages/login.dart';
import 'utils/storage.dart';
import 'config/constants.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
String? _startupError;

void main() async {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _startupError ??= '[FlutterError]\n${details.exceptionAsString()}\n\n${details.stack}';
  };

  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await StorageUtil.init();
    } catch (e, st) {
      _startupError = '[StorageUtil.init failed]\n$e\n\n$st';
    }
    runApp(const LinghuApp());
  }, (error, stack) {
    _startupError ??= '[Zone Error]\n$error\n\n$stack';
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => _ErrorDialog(title: 'Unhandled Error', message: '$error\n\n$stack'),
      );
    }
  });
}

class _ErrorDialog extends StatelessWidget {
  final String title;
  final String message;
  const _ErrorDialog({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('❌ $title', style: const TextStyle(color: Colors.red, fontSize: 15)),
      content: SingleChildScrollView(
        child: SelectableText(message, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  final String error;
  const _StartupErrorPage({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.error_outline, color: Colors.red, size: 32),
                SizedBox(width: 8),
                Text('APP启动错误', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
              ]),
              const SizedBox(height: 8),
              const Text('请截图发给开发者', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                  child: SingleChildScrollView(
                    child: SelectableText(error, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LinghuApp extends StatelessWidget {
  const LinghuApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (_startupError != null) {
      return MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        home: _StartupErrorPage(error: _startupError!),
      );
    }

    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: Consumer<AppState>(
        builder: (context, appState, child) {
          final themeColor = Color(AppConstants.themeColors[appState.role] ?? 0xFFFF6B35);
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: '灵狐·优库近选',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: themeColor),
              useMaterial3: true,
              // 不指定 fontFamily，使用系统字体（Android: Noto Sans，iOS: PingFang）
              // 避免下载 4 个 Roboto ttf 文件（共 2MB）导致移动端加载慢
              textTheme: const TextTheme(
                displayLarge:   TextStyle(fontWeight: FontWeight.w700),
                displayMedium:  TextStyle(fontWeight: FontWeight.w700),
                displaySmall:   TextStyle(fontWeight: FontWeight.w700),
                headlineLarge:  TextStyle(fontWeight: FontWeight.w700),
                headlineMedium: TextStyle(fontWeight: FontWeight.w700),
                headlineSmall:  TextStyle(fontWeight: FontWeight.w600),
                titleLarge:     TextStyle(fontWeight: FontWeight.w600),
                titleMedium:    TextStyle(fontWeight: FontWeight.w500),
                titleSmall:     TextStyle(fontWeight: FontWeight.w500),
                bodyLarge:      TextStyle(fontWeight: FontWeight.w400),
                bodyMedium:     TextStyle(fontWeight: FontWeight.w400),
                bodySmall:      TextStyle(fontWeight: FontWeight.w400),
                labelLarge:     TextStyle(fontWeight: FontWeight.w500),
                labelMedium:    TextStyle(fontWeight: FontWeight.w500),
                labelSmall:     TextStyle(fontWeight: FontWeight.w400),
              ),
              appBarTheme: AppBarTheme(backgroundColor: themeColor, foregroundColor: Colors.white, elevation: 0),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white),
              ),
            ),
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

class AppState extends ChangeNotifier {
  int _role = 0;
  int? _userId;
  String? _username;
  int? _warehouseId;
  int? _brandId;
  int _vipLevel = 0;
  DateTime? _vipExpireTime;

  int get role => _role;
  int? get userId => _userId;
  String? get username => _username;
  int? get warehouseId => _warehouseId;
  int? get brandId => _brandId;
  int get vipLevel => _vipLevel;
  DateTime? get vipExpireTime => _vipExpireTime;

  bool get isVip =>
      _role == 0 && _vipLevel > 0 && _vipExpireTime != null && _vipExpireTime!.isAfter(DateTime.now());

  void setUser({
    required int role, required int userId, required String username,
    int? warehouseId, int? brandId, int vipLevel = 0, DateTime? vipExpireTime,
  }) {
    _role = role; _userId = userId; _username = username;
    _warehouseId = warehouseId; _brandId = brandId;
    _vipLevel = vipLevel; _vipExpireTime = vipExpireTime;
    notifyListeners();
  }

  void updateVip(int level, DateTime expireTime) {
    _vipLevel = level; _vipExpireTime = expireTime;
    notifyListeners();
  }

  void clearUser() {
    _role = 0; _userId = null; _username = null;
    _warehouseId = null; _brandId = null;
    _vipLevel = 0; _vipExpireTime = null;
    notifyListeners();
  }
}
