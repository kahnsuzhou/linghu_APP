import 'package:flutter/material.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 吐槽入口页
// ─────────────────────────────────────────────────────────────────────────────
class ComplaintPage extends StatefulWidget {
  final String? relatedType; // ORDER / PRODUCT / WAREHOUSE / NONE
  final dynamic relatedId;
  final String? relatedLabel; // 关联对象描述，如订单号
  final String? orderSn;     // 冗余订单号
  final dynamic warehouseId; // 关联仓库ID

  const ComplaintPage({
    super.key,
    this.relatedType,
    this.relatedId,
    this.relatedLabel,
    this.orderSn,
    this.warehouseId,
  });

  @override
  State<ComplaintPage> createState() => _ComplaintPageState();
}

class _ComplaintPageState extends State<ComplaintPage> {
  static const _orange = Color(0xFFFF6B35);
  final _controller = TextEditingController();
  bool _isUrgent = false;
  bool _isAnonymous = false;
  bool _submitting = false;
  String? _selectedRelatedType;

  @override
  void initState() {
    super.initState();
    _selectedRelatedType = widget.relatedType ?? 'NONE';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.length < 10) {
      _showSnack('内容不能少于10字（当前${text.length}字）', Colors.red);
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiService().post('/api/complaint/create', body: {
        'content': text,
        'related_type': _selectedRelatedType,
        if (widget.relatedId != null) 'related_id': widget.relatedId,
        if (widget.orderSn != null) 'order_sn': widget.orderSn,
        if (widget.warehouseId != null) 'warehouse_id': widget.warehouseId,
        'is_urgent': _isUrgent,
        'is_anonymous': _isAnonymous,
      });
      if (!mounted) return;
      if (res['code'] == 200) {
        _showSnack('吐槽已提交 🎉 我们会尽快处理', Colors.green);
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        _showSnack(res['msg'] ?? '提交失败', Colors.red);
      }
    } catch (_) {
      _showSnack('网络异常，请重试', Colors.red);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('灵狐吐槽', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 标语
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFFF9A5C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('有什么想对我们说的吗？',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('好的、坏的、建议，我们都想听 👂',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 16),

          // 输入框
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
            ),
            child: TextField(
              controller: _controller,
              maxLines: 6,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: '输入你的吐槽...\n支持文字（10-500字）',
                hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 关联对象
          if (widget.relatedLabel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                Icon(Icons.link, color: _orange, size: 16),
                const SizedBox(width: 8),
                Text('关联：${widget.relatedLabel}',
                    style: TextStyle(color: _orange, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // 紧急 + 匿名开关
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              CheckboxListTile(
                value: _isUrgent,
                onChanged: (v) => setState(() => _isUrgent = v ?? false),
                title: const Text('⚡ 有急事，需要马上处理',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: const Text('标记后将进入优先处理队列',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                activeColor: Colors.red,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const Divider(height: 1, indent: 16),
              CheckboxListTile(
                value: _isAnonymous,
                onChanged: (v) => setState(() => _isAnonymous = v ?? false),
                title: const Text('🎭 匿名提交',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: const Text('公开页面不显示你的昵称',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                activeColor: _orange,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // 提交按钮
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                elevation: 4,
                shadowColor: _orange.withOpacity(0.4),
              ),
              child: _submitting
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('提交吐槽', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),

          // 提示
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text('紧急问题可直接联系客服，我们7×12小时在线',
                    style: TextStyle(color: Colors.blue, fontSize: 12)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 我的吐槽列表页
// ─────────────────────────────────────────────────────────────────────────────
class MyComplaintListPage extends StatefulWidget {
  const MyComplaintListPage({super.key});

  @override
  State<MyComplaintListPage> createState() => _MyComplaintListPageState();
}

class _MyComplaintListPageState extends State<MyComplaintListPage> {
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
      final res = await ApiService().get('/api/complaint/my-list');
      if (res['code'] == 200) {
        final raw = res['data'];
        final records = raw is Map ? (raw['records'] as List? ?? []) : (raw as List? ?? []);
        setState(() {
          _list = records.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的吐槽', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () async {
              final result = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ComplaintPage()));
              if (result == true) _load();
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildCard(_list[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('还没有吐槽记录', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              final result = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ComplaintPage()));
              if (result == true) _load();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B35)),
            child: const Text('去吐槽', style: TextStyle(color: Colors.white)),
          ),
        ]),
      );

  Widget _buildCard(Map<String, dynamic> c) {
    final status = c['status'] as String? ?? 'PENDING';
    final isUrgent = c['isUrgent'] == true;
    final statusConfig = _statusConfig(status);

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ComplaintDetailPage(id: c['id'] as int))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isUrgent ? Border.all(color: Colors.red.shade300) : null,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (isUrgent) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: const Text('紧急', style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                c['content'] as String? ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.schedule, size: 13, color: Colors.grey.shade400),
            const SizedBox(width: 4),
            Text(_formatTime(c['createTime']),
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusConfig['color'] as Color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(statusConfig['label'] as String,
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ]),
          if (c['satisfaction'] != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.star, size: 14, color: Colors.amber),
              const SizedBox(width: 4),
              Text(_satLabel(c['satisfaction'] as int),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ],
        ]),
      ),
    );
  }

  Map<String, dynamic> _statusConfig(String status) {
    switch (status) {
      case 'PENDING':     return {'label': '待处理', 'color': Colors.grey};
      case 'PROCESSING':  return {'label': '处理中', 'color': Colors.orange};
      case 'REPLIED':     return {'label': '已回复', 'color': const Color(0xFF2196F3)};
      case 'RESOLVED':    return {'label': '已解决', 'color': Colors.green};
      default:            return {'label': status, 'color': Colors.grey};
    }
  }

  String _satLabel(int sat) {
    switch (sat) {
      case 1: return '满意 👍';
      case 2: return '一般 😐';
      case 3: return '不满意 👎';
      default: return '';
    }
  }

  String _formatTime(dynamic t) {
    if (t == null) return '';
    final s = t.toString();
    return s.length >= 16 ? s.substring(0, 16) : s;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 吐槽详情页（含回复列表 + 满意度评价）
// ─────────────────────────────────────────────────────────────────────────────
class ComplaintDetailPage extends StatefulWidget {
  final int id;
  const ComplaintDetailPage({super.key, required this.id});

  @override
  State<ComplaintDetailPage> createState() => _ComplaintDetailPageState();
}

class _ComplaintDetailPageState extends State<ComplaintDetailPage> {
  Map<String, dynamic>? _complaint;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/api/complaint/detail/${widget.id}');
      if (res['code'] == 200) {
        final raw = res['data'];
        setState(() => _complaint = raw is Map ? Map<String, dynamic>.from(raw) : null);
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitSatisfaction(int rating) async {
    final res = await ApiService().post('/api/complaint/satisfaction', body: {
      'complaint_id': widget.id,
      'rating': rating,
    });
    if (!mounted) return;
    if (res['code'] == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('感谢您的评价！'), backgroundColor: Colors.green));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('吐槽详情', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _complaint == null
              ? const Center(child: Text('加载失败'))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final c = _complaint!;
    final replies = (c['replies'] as List? ?? [])
        .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final isUrgent = c['isUrgent'] == true;
    final status = c['status'] as String? ?? 'PENDING';
    final canRate = status == 'REPLIED' && c['satisfaction'] == null;

    return ListView(padding: const EdgeInsets.all(16), children: [
      // 紧急提示
      if (isUrgent)
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
            SizedBox(width: 8),
            Text('已标记为紧急，优先处理中', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
          ]),
        ),

      // 吐槽内容卡片
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.chat_bubble_outline, color: Color(0xFFFF6B35), size: 18),
            const SizedBox(width: 8),
            const Text('我的吐槽', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            _statusBadge(status),
          ]),
          const Divider(height: 16),
          Text(c['content'] as String? ?? '',
              style: const TextStyle(fontSize: 14, height: 1.6)),
          if (c['aiCategory'] != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('AI分类：${c['aiCategory']}',
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 12)),
            ),
          ],
          const SizedBox(height: 8),
          Text(_formatTime(c['createTime']),
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 12),

      // 回复列表
      if (replies.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('回复', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
        ...replies.map((r) => _buildReplyCard(r)),
        const SizedBox(height: 12),
      ],

      // 满意度评价
      if (canRate)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            const Text('问题解决了吗？', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _satButton('满意 👍', 1, Colors.green),
              _satButton('一般 😐', 2, Colors.orange),
              _satButton('不满意 👎', 3, Colors.red),
            ]),
          ]),
        ),

      if (c['satisfaction'] != null)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Text('您已评价：${_satLabel(c['satisfaction'] as int)}',
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
          ]),
        ),
    ]);
  }

  Widget _buildReplyCard(Map<String, dynamic> r) {
    final role = r['replierRole'] as int? ?? 9;
    final roleLabel = role == 1 ? '仓主' : role == 2 ? '品牌方' : '灵狐客服';
    final roleColor = role == 1 ? Colors.blue : role == 2 ? Colors.purple : const Color(0xFFFF6B35);
    final isAuto = r['isAuto'] == true || r['isAuto'] == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: roleColor, borderRadius: BorderRadius.circular(6)),
            child: Text(roleLabel, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          if (isAuto) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('AI自动回复', style: TextStyle(color: Colors.grey, fontSize: 11)),
            ),
          ],
          const Spacer(),
          Text(_formatTime(r['createTime']),
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        Text(r['content'] as String? ?? '',
            style: const TextStyle(fontSize: 14, height: 1.5)),
      ]),
    );
  }

  Widget _satButton(String label, int value, Color color) {
    return ElevatedButton(
      onPressed: () => _submitSatisfaction(value),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(label),
    );
  }

  Widget _statusBadge(String status) {
    final cfg = {
      'PENDING':    {'label': '待处理', 'color': Colors.grey},
      'PROCESSING': {'label': '处理中', 'color': Colors.orange},
      'REPLIED':    {'label': '已回复', 'color': const Color(0xFF2196F3)},
      'RESOLVED':   {'label': '已解决', 'color': Colors.green},
    }[status] ?? {'label': status, 'color': Colors.grey};

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cfg['color'] as Color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(cfg['label'] as String,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  String _satLabel(int sat) {
    switch (sat) {
      case 1: return '满意 👍';
      case 2: return '一般 😐';
      case 3: return '不满意 👎';
      default: return '';
    }
  }

  String _formatTime(dynamic t) {
    if (t == null) return '';
    final s = t.toString();
    return s.length >= 16 ? s.substring(0, 16) : s;
  }
}
