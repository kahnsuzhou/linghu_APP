import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';

/// 仓主端 — 自提核销页面
class PickupVerificationPage extends StatefulWidget {
  const PickupVerificationPage({super.key});

  @override
  State<PickupVerificationPage> createState() => _PickupVerificationPageState();
}

class _PickupVerificationPageState extends State<PickupVerificationPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ─── 列表 Tab ───────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loadingList = false;
  String _listError = '';

  // ─── 核销 Tab ───────────────────────────────────────────
  final _codeCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  bool _verifying = false;
  String _verifyResult = '';
  bool _verifySuccess = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _codeCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  // ─── 加载列表 ───────────────────────────────────────────
  Future<void> _loadList({String? keyword}) async {
    setState(() {
      _loadingList = true;
      _listError = '';
    });
    try {
      final res = await ApiService().getPickupList(keyword: keyword);
      if (res['code'] == 200) {
        final data = (res['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        setState(() {
          _allItems = data;
          _filtered = data;
        });
      } else {
        setState(() => _listError = res['msg'] ?? '加载失败');
      }
    } catch (e) {
      setState(() => _listError = '网络错误，请重试');
    } finally {
      setState(() => _loadingList = false);
    }
  }

  void _onSearch(String val) {
    final kw = val.trim().toLowerCase();
    setState(() {
      _filtered = kw.isEmpty
          ? List.from(_allItems)
          : _allItems.where((item) {
              final code = (item['pickUpCode'] ?? '').toString().toLowerCase();
              final phone = (item['consumerPhone'] ?? '').toString();
              final name = (item['consumerName'] ?? '').toString().toLowerCase();
              return code.contains(kw) || phone.contains(kw) || name.contains(kw);
            }).toList();
    });
  }

  // ─── 核销操作 ───────────────────────────────────────────
  Future<void> _doVerify() async {
    final code = _codeCtrl.text.trim();
    final idStr = _idCtrl.text.trim();
    if (code.isEmpty) {
      _showSnack('请输入6位自提码', isError: true);
      return;
    }
    if (code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) {
      _showSnack('自提码应为6位数字', isError: true);
      return;
    }
    if (idStr.isEmpty) {
      _showSnack('请输入记录ID（可从列表中获取）', isError: true);
      return;
    }
    final inviteId = int.tryParse(idStr);
    if (inviteId == null) {
      _showSnack('记录ID格式不正确', isError: true);
      return;
    }

    setState(() {
      _verifying = true;
      _verifyResult = '';
      _verifySuccess = false;
    });

    try {
      final res = await ApiService().verifyPickup(
        pickUpCode: code,
        inviteId: inviteId,
      );
      if (res['code'] == 200) {
        setState(() {
          _verifySuccess = true;
          _verifyResult = '✅ 核销成功！\n商品：${res['data']?['productName'] ?? '—'}\n金额：¥${res['data']?['activityPrice'] ?? '—'}';
        });
        _codeCtrl.clear();
        _idCtrl.clear();
        // 刷新列表
        _loadList();
      } else {
        setState(() {
          _verifySuccess = false;
          _verifyResult = '❌ ${res['msg'] ?? '核销失败'}';
        });
      }
    } catch (e) {
      setState(() {
        _verifySuccess = false;
        _verifyResult = '❌ 网络错误，请重试';
      });
    } finally {
      setState(() => _verifying = false);
    }
  }

  /// 从列表项快速填入核销 Tab
  void _prefillVerify(Map<String, dynamic> item) {
    _tabController.animateTo(1);
    _codeCtrl.text = item['pickUpCode']?.toString() ?? '';
    _idCtrl.text = item['inviteId']?.toString() ?? '';
    setState(() {
      _verifyResult = '';
      _verifySuccess = false;
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  // ─── Build ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自提核销'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadList(keyword: _searchCtrl.text.trim()),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: '待核销列表'),
            Tab(icon: Icon(Icons.check_circle_outline), text: '输码核销'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildListTab(),
          _buildVerifyTab(),
        ],
      ),
    );
  }

  // ─── 列表 Tab ───────────────────────────────────────────
  Widget _buildListTab() {
    return Column(
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索自提码 / 手机号 / 用户名',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearch('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            onChanged: _onSearch,
            onSubmitted: (v) => _loadList(keyword: v.trim()),
          ),
        ),
        // 计数
        if (!_loadingList && _listError.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildChip('全部', _allItems.length, Colors.blue),
                const SizedBox(width: 8),
                _buildChip(
                  '待核销',
                  _allItems.where((i) => i['status'] == 'ORDERED').length,
                  Colors.orange,
                ),
                const SizedBox(width: 8),
                _buildChip(
                  '已核销',
                  _allItems.where((i) => i['status'] == 'PICKED_UP').length,
                  Colors.green,
                ),
              ],
            ),
          ),
        Expanded(
          child: _loadingList
              ? const Center(child: CircularProgressIndicator())
              : _listError.isNotEmpty
                  ? _buildError(_listError, () => _loadList())
                  : _filtered.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: () => _loadList(keyword: _searchCtrl.text.trim()),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _buildPickupCard(_filtered[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildPickupCard(Map<String, dynamic> item) {
    final isPending = item['status'] == 'ORDERED';
    final code = item['pickUpCode']?.toString() ?? '——';
    final formattedCode = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    final statusColor = isPending ? Colors.orange : Colors.green;
    final statusText = item['statusText'] ?? (isPending ? '待核销' : '已核销');
    final phone = (item['consumerPhone'] ?? '') as String;
    final maskedPhone = phone.length == 11
        ? '${phone.substring(0, 3)}****${phone.substring(7)}'
        : phone;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 大码显示
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_2, color: statusColor, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        formattedCode,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: isPending ? Colors.black87 : Colors.grey,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                // 状态标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 商品 & 活动
            if (item['productName'] != null)
              _infoRow(Icons.inventory_2_outlined, item['productName'].toString()),
            if (item['activityName'] != null)
              _infoRow(Icons.local_activity_outlined, item['activityName'].toString(),
                  sub: item['activityPrice'] != null ? '¥${item['activityPrice']}' : null),
            if (maskedPhone.isNotEmpty)
              _infoRow(Icons.person_outline, '${item['consumerName'] ?? '消费者'}  $maskedPhone'),
            if (item['pickedUpAt'] != null)
              _infoRow(Icons.check_circle_outline, '核销时间: ${_formatTime(item['pickedUpAt'])}',
                  color: Colors.green),
            // 操作按钮（仅待核销）
            if (isPending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  // 复制 ID
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                        text: 'ID:${item['inviteId']}  Code:$code',
                      ));
                      _showSnack('已复制');
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('复制', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 去核销
                  ElevatedButton.icon(
                    onPressed: () => _prefillVerify(item),
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('去核销', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {String? sub, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color ?? Colors.grey),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color ?? Colors.grey[700]),
            ),
          ),
          if (sub != null)
            Text(sub, style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatTime(dynamic t) {
    if (t == null) return '';
    final s = t.toString();
    if (s.length >= 16) return s.substring(0, 16).replaceAll('T', ' ');
    return s;
  }

  Widget _buildError(String msg, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Text(msg, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
          SizedBox(height: 10),
          Text('暂无自提订单', style: TextStyle(color: Colors.grey, fontSize: 15)),
          SizedBox(height: 4),
          Text('消费者下单后将在此处显示', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  // ─── 输码核销 Tab ─────────────────────────────────────────
  Widget _buildVerifyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 说明卡片
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2196F3), Color(0xFF64B5F6)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('核销说明', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ]),
                SizedBox(height: 8),
                Text(
                  '消费者出示6位自提码时，在下方输入自提码即可完成核销。\n也可在"待核销列表"点击"去核销"自动填入。',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 输入区域
          const Text('自提码', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '输入6位数字自提码',
              prefixIcon: const Icon(Icons.pin_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              counterText: '',
              filled: true,
              fillColor: Colors.grey[50],
            ),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 6),
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() => _verifyResult = ''),
          ),
          const SizedBox(height: 24),

          // 核销按钮
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _verifying ? null : _doVerify,
              icon: _verifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_verifying ? '核销中...' : '确认核销'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // 结果提示
          if (_verifyResult.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _verifySuccess ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _verifySuccess ? Colors.green[200]! : Colors.red[200]!,
                ),
              ),
              child: Text(
                _verifyResult,
                style: TextStyle(
                  fontSize: 15,
                  color: _verifySuccess ? Colors.green[800] : Colors.red[800],
                  height: 1.6,
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),
          // 快捷跳转
          OutlinedButton.icon(
            onPressed: () => _tabController.animateTo(0),
            icon: const Icon(Icons.list_alt),
            label: const Text('查看待核销列表'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2196F3),
              side: const BorderSide(color: Color(0xFF2196F3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}
