import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';

class InviteRecordsPage extends StatefulWidget {
  const InviteRecordsPage({super.key});

  @override
  State<InviteRecordsPage> createState() => _InviteRecordsPageState();
}

class _InviteRecordsPageState extends State<InviteRecordsPage> {
  List<dynamic> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().getMyInvites();
      if (res['code'] == 200) {
        setState(() {
          _records = res['data']['records'] as List<dynamic>? ?? [];
        });
      } else {
        _showError(res['message'] ?? '加载失败');
      }
    } catch (e) {
      _showError('网络错误：$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // 状态映射
  String _statusLabel(String status) {
    switch (status) {
      case 'PENDING':
        return '待注册';
      case 'REGISTERED':
        return '已注册';
      case 'ORDERED':
        return '已下单';
      case 'PICKED_UP':
        return '已核销';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PENDING':
        return Colors.grey;
      case 'REGISTERED':
        return const Color(0xFF2196F3);
      case 'ORDERED':
        return const Color(0xFFFF9800);
      case 'PICKED_UP':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  // 手机号脱敏：中间4位替换为***
  String _maskPhone(String phone) {
    if (phone.length < 7) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(7)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          '我的邀请记录',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFFF6B35),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B35)))
          : _records.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: const Color(0xFFFF6B35),
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _records.length,
                    itemBuilder: (context, index) => _buildItem(_records[index]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            '暂无邀请记录',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> record) {
    final status = record['status'] as String? ?? 'PENDING';
    final inviteCode = record['inviteCode'] as String? ?? '';
    final inviteePhone = record['inviteePhone'] as String? ?? '';
    final createTime = record['createTime'] as String? ?? '';
    final pickedUpAt = record['pickedUpAt'] as String?;
    final color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧状态竖条
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
              ),
            ),
            // 内容区
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 第一行：被邀请手机号 + 状态Tag
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _maskPhone(inviteePhone),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF333333),
                          ),
                        ),
                        _buildStatusTag(status, color),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 邀请码（可长按复制）
                    GestureDetector(
                      onLongPress: () async {
                        await Clipboard.setData(ClipboardData(text: inviteCode));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('邀请码已复制'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          Text(
                            '邀请码：$inviteCode',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.copy, size: 12, color: Colors.grey[400]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 邀请时间
                    Text(
                      '邀请时间：$createTime',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    // 核销时间（仅 PICKED_UP 显示）
                    if (status == 'PICKED_UP' && pickedUpAt != null && pickedUpAt.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '核销时间：$pickedUpAt',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTag(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
