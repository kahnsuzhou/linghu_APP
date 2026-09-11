import 'package:flutter/material.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 仓主槽点列表页
// ─────────────────────────────────────────────────────────────────────────────
class WarehouseComplaintListPage extends StatefulWidget {
  const WarehouseComplaintListPage({super.key});

  @override
  State<WarehouseComplaintListPage> createState() => _WarehouseComplaintListPageState();
}

class _WarehouseComplaintListPageState extends State<WarehouseComplaintListPage> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  int _urgentCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/api/warehouse/complaint/list');
      if (res['code'] == 200) {
        final raw = res['data'];
        if (raw is Map) {
          final records = raw['records'] as List? ?? [];
          setState(() {
            _list = records.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            _urgentCount = (raw['urgentCount'] as num? ?? 0).toInt();
          });
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _list.where((c) => c['status'] == 'PENDING').toList();
    final urgent = pending.where((c) => c['isUrgent'] == true).toList();
    final processing = _list.where((c) => c['status'] == 'PROCESSING' || c['status'] == 'REPLIED').toList();
    final resolved = _list.where((c) => c['status'] == 'RESOLVED').toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('我的槽点', style: TextStyle(fontWeight: FontWeight.bold)),
          if (_urgentCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
              child: Text('$_urgentCount', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ]),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _list.isEmpty
                  ? const Center(child: Text('暂无用户槽点 🎉', style: TextStyle(color: Colors.grey)))
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      if (urgent.isNotEmpty) ...[
                        _sectionHeader('⚠️ 紧急待处理（${urgent.length}）', Colors.red.shade50, Colors.red),
                        ...urgent.map(_buildCard),
                        const SizedBox(height: 12),
                      ],
                      if (processing.isNotEmpty) ...[
                        _sectionHeader('🟡 处理中（${processing.length}）', Colors.orange.shade50, Colors.orange),
                        ...processing.map(_buildCard),
                        const SizedBox(height: 12),
                      ],
                      if (resolved.isNotEmpty) ...[
                        _sectionHeader('✅ 已解决（${resolved.length}）', Colors.green.shade50, Colors.green),
                        ...resolved.map(_buildCard),
                      ],
                    ]),
            ),
    );
  }

  Widget _sectionHeader(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _buildCard(Map<String, dynamic> c) {
    final isUrgent = c['isUrgent'] == true;
    final isOverdue = c['overdue'] == true || c['overdue'] == 1;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(
            builder: (_) => WarehouseComplaintDetailPage(complaint: c)));
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isUrgent
              ? Border.all(color: Colors.red.shade300, width: 1.5)
              : isOverdue
                  ? Border.all(color: Colors.orange.shade300)
                  : null,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (isUrgent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: const Text('⚠️ 紧急', style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            if (isOverdue && !isUrgent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                child: const Text('超时', style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            const Spacer(),
            if (c['relatedId'] != null)
              Text('订单 #${c['relatedId']}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          Text(
            c['content'] as String? ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text(
              c['userName'] as String? ?? '用户',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Text(
              _formatTime(c['createTime']),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ]),
        ]),
      ),
    );
  }

  String _formatTime(dynamic t) {
    if (t == null) return '';
    final s = t.toString();
    return s.length >= 16 ? s.substring(0, 16) : s;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 仓主槽点详情 + 回复页
// ─────────────────────────────────────────────────────────────────────────────
class WarehouseComplaintDetailPage extends StatefulWidget {
  final Map<String, dynamic> complaint;
  const WarehouseComplaintDetailPage({super.key, required this.complaint});

  @override
  State<WarehouseComplaintDetailPage> createState() => _WarehouseComplaintDetailPageState();
}

class _WarehouseComplaintDetailPageState extends State<WarehouseComplaintDetailPage> {
  final _replyController = TextEditingController();
  bool _submitting = false;
  Map<String, dynamic> _complaint = {};

  @override
  void initState() {
    super.initState();
    _complaint = Map<String, dynamic>.from(widget.complaint);
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final res = await ApiService().get('/api/complaint/detail/${_complaint['id']}');
      if (res['code'] == 200 && res['data'] is Map) {
        setState(() => _complaint = Map<String, dynamic>.from(res['data'] as Map));
      }
    } catch (_) {}
  }

  Future<void> _submitReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回复内容不能为空')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiService().post(
          '/api/warehouse/complaint/reply/${_complaint['id']}',
          body: {'content': text});
      if (!mounted) return;
      if (res['code'] == 200) {
        _replyController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('回复成功'), backgroundColor: Colors.green));
        _loadDetail();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['msg'] ?? '回复失败')));
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _updateStatus(String status) async {
    final res = await ApiService().put(
        '/api/warehouse/complaint/status/${_complaint['id']}',
        body: {'status': status});
    if (!mounted) return;
    if (res['code'] == 200) {
      setState(() => _complaint['status'] = status);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('状态已更新'), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = _complaint['isUrgent'] == true;
    final status = _complaint['status'] as String? ?? 'PENDING';
    final replies = (_complaint['replies'] as List? ?? [])
        .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('用户槽点', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            // 紧急提示
            if (isUrgent)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red),
                  SizedBox(width: 8),
                  Text('⚠️ 紧急（用户标记 + AI识别）',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ]),
              ),

            // 用户信息 + 吐槽内容
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.person_outline, color: Colors.grey, size: 16),
                  const SizedBox(width: 6),
                  Text(_complaint['userName'] as String? ?? '匿名用户',
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  const Spacer(),
                  Text(_formatTime(_complaint['createTime']),
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
                if (_complaint['relatedId'] != null) ...[
                  const SizedBox(height: 4),
                  Text('关联订单：#${_complaint['relatedId']}',
                      style: const TextStyle(color: Colors.blue, fontSize: 12)),
                ],
                const Divider(height: 16),
                Text(_complaint['content'] as String? ?? '',
                    style: const TextStyle(fontSize: 15, height: 1.6)),
              ]),
            ),
            const SizedBox(height: 12),

            // 已有回复
            if (replies.isNotEmpty) ...[
              const Text('回复记录', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...replies.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('仓主', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                    const Spacer(),
                    Text(_formatTime(r['createTime']),
                        style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ]),
                  const SizedBox(height: 6),
                  Text(r['content'] as String? ?? '', style: const TextStyle(fontSize: 14)),
                ]),
              )),
              const SizedBox(height: 12),
            ],

            // 状态操作按钮
            Row(children: [
              if (status != 'RESOLVED')
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _updateStatus('PROCESSING'),
                    icon: const Icon(Icons.pending_actions, size: 16),
                    label: const Text('标记处理中'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                  ),
                ),
              if (status != 'RESOLVED') const SizedBox(width: 8),
              if (status != 'RESOLVED')
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _updateStatus('RESOLVED'),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('标记已解决'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                  ),
                ),
            ]),
          ]),
        ),

        // 底部回复输入栏
        if (status != 'RESOLVED')
          Container(
            padding: EdgeInsets.only(
              left: 12, right: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              top: 12,
            ),
            color: Colors.white,
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _replyController,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: '输入回复（500字以内）...',
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _submitting ? null : _submitReply,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _submitting ? Colors.grey : const Color(0xFF2196F3),
                    shape: BoxShape.circle,
                  ),
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  String _formatTime(dynamic t) {
    if (t == null) return '';
    final s = t.toString();
    return s.length >= 16 ? s.substring(0, 16) : s;
  }
}
