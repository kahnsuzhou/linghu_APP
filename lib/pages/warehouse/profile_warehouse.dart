import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../utils/storage.dart';
import '../../services/websocket_service.dart';
import '../login.dart';
import '../consumer/profile.dart' show ConsumerProfilePage;
import '../wallet/wallet_page.dart';
import 'warehouse_info.dart';

class WarehouseProfilePage extends StatelessWidget {
  const WarehouseProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('我的'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            color: const Color(0xFF2196F3),
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  child: const Text('📦', style: TextStyle(fontSize: 28)),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (state.username ?? '').isNotEmpty ? state.username! : '仓主',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('仓主', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildItem(Icons.warehouse_outlined, '仓库信息', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const WarehouseInfoPage()));
          }),
          _buildItem(Icons.account_balance_wallet_outlined, '我的钱包', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletPage()));
          }),
          _buildItem(Icons.settings_outlined, '服务费率设置', () {}),
          _buildItem(Icons.notifications_outlined, '消息通知', () {}),
          _buildItem(Icons.headset_mic_outlined, '联系平台', () {}),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '退出后在登录页可快速切换为消费者或品牌方',
                      style: TextStyle(color: Colors.blue[800], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
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
