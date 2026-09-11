import 'package:flutter/material.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 品牌方吐槽列表页
// ─────────────────────────────────────────────────────────────────────────────
class BrandComplaintListPage extends StatefulWidget {
  const BrandComplaintListPage({super.key});

  @override
  State<BrandComplaintListPage> createState() => _BrandComplaintListPageState();
}

class _BrandComplaintListPageState extends State<BrandComplaintListPage> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/api/brand/complaint/list');
      if (res['code'] == 200) {
        final raw = res['data'];
        if (raw is Map) {
          final records = raw['records'] as List? ?? [];
          setState(() {
            _list = records.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)).toList();
          });
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('商品吐槽', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _list.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('暂无商品吐槽 🎉', style: TextStyle(color: Colors.grey, fontSize: 15)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _list.length,
                      itemBuilder: (ctx, i) => _buildCard(_list[i]),
                    ),
            ),
    );
  }

  Widget _buildCard(Map<String, dynamic> c) {
    final isUrgent = c['isUrgent'] == true;
    final status = c['status'] as String? ?? 'PENDING';
    final statusLabel = const {
      'PENDING': '待处理', 'PROCESSING': '处理中',
      'REPLIED': '已回复', 'RESOLVED': '已解决',
    }[status] ?? status;
    final statusColor = const {
      'PENDING': Color(0xFF9E9E9E), 'PROCESSING': Color(0xFFFF9800),
      'REPLIED': Color(0xFF2196F3), 'RESOLVED': Color(0xFF4CAF50),
    }[status] ?? const Color(0xFF9E9E9E);

    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(
            builder: (_) => BrandComplaintDetailPage(complaint: c)));
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isUrgent ? Border.all(color: Colors.red.shade300, width: 1.5) : null,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (isUrgent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: const Text('⚠️ 紧急', style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const Spacer(),
            if (c['orderSn'] != null)
              Text('订单 ${(c['orderSn'] as String).substring((c['orderSn'] as String).length > 8 ? (c['orderSn'] as String).length - 8 : 0)}',
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
            Text(c['userName'] as String? ?? '用户',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(width: 8),
            Text(_fmtTime(c['createTime']),
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (c['aiCategory'] != null) ...[
              const Spacer(),
              Text('#${c['aiCategory']}',
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 11)),
            ],
          ]),
        ]),
      ),
    );
  }

  String _fmtTime(dynamic t) {
    if (t == null) return '';
    final s = t.toString();
    return s.length >= 16 ? s.substring(0, 16) : s;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 品牌方吐槽详情 + 回复页
// ─────────────────────────────────────────────────────────────────────────────
class BrandComplaintDetailPage extends StatefulWidget {
  final Map<String, dynamic> complaint;
  const BrandComplaintDetailPage({super.key, required this.complaint});

  @override
  State<BrandComplaintDetailPage> createState() => _BrandComplaintDetailPageState();
}

class _BrandComplaintDetailPageState extends State<BrandComplaintDetailPage> {
  final _replyCtrl = TextEditingController();
  bool _submitting = false;
  Map<String, dynamic> _complaint = {};

  @override
  void initState() {
    super.initState();
    _complaint = Map<String, dynamic>.from(widget.complaint);
    _loadDetail();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
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
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回复内容不能为空')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiService().post(
          '/api/brand/complaint/reply/${_complaint['id']}',
          body: {'content': text});
      if (!mounted) return;
      if (res['code'] == 200) {
        _replyCtrl.clear();
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

  @override
  Widget build(BuildContext context) {
    final isUrgent = _complaint['isUrgent'] == true;
    final replies = (_complaint['replies'] as List? ?? [])
        .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final status = _complaint['status'] as String? ?? 'PENDING';
    final canReply = status != 'RESOLVED';

    return Scaffold(
      appBar: AppBar(
        title: const Text('吐槽详情', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  Text('⚠️ 紧急投诉，请尽快处理',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ]),
              ),

            // 吐槽内容
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
                  Text(_fmtTime(_complaint['createTime']),
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
                if (_complaint['orderSn'] != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.receipt_outlined, color: Colors.orange, size: 14),
                    const SizedBox(width: 4),
                    Text('订单：${_complaint['orderSn']}',
                        style: const TextStyle(color: Colors.orange, fontSize: 12)),
                  ]),
                ],
                const SizedBox(height: 10),
                Text(_complaint['content'] as String? ?? '',
                    style: const TextStyle(fontSize: 15, height: 1.5)),
                if (_complaint['aiCategory'] != null) ...[
                  const SizedBox(height: 8),
                  Chip(
                    label: Text('AI分类：${_complaint['aiCategory']}',
                        style: const TextStyle(fontSize: 11)),
                    backgroundColor: Colors.blue.shade50,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),

            // 回复列表
            if (replies.isNotEmpty) ...[
              const Text('回复记录', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              ...replies.map((r) => _buildReplyBubble(r)),
              const SizedBox(height: 12),
            ],
          ]),
        ),

        // 回复输入栏
        if (canReply)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: SafeArea(
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    decoration: InputDecoration(
                      hintText: '以品牌方身份回复...',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _submitting ? null : _submitReply,
                  child: Container(
                    padding: const EdgeInsets.all(10),
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
          ),
      ]),
    );
  }

  Widget _buildReplyBubble(Map<String, dynamic> r) {
    final roleLabels = {0: '用户', 1: '仓主', 2: '品牌方', 9: '客服'};
    final role = (r['replierRole'] as num?)?.toInt() ?? 9;
    final isOwn = role == 2;
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isOwn ? const Color(0xFF2196F3) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(roleLabels[role] ?? '系统',
              style: TextStyle(
                  fontSize: 11,
                  color: isOwn ? Colors.white70 : Colors.grey,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(r['content'] as String? ?? '',
              style: TextStyle(
                  fontSize: 14,
                  color: isOwn ? Colors.white : Colors.black87)),
        ]),
      ),
    );
  }

  String _fmtTime(dynamic t) {
    if (t == null) return '';
    final s = t.toString();
    return s.length >= 16 ? s.substring(0, 16) : s;
  }
}
