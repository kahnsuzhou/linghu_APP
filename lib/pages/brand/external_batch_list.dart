import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import 'external_batch_import.dart';

/// 外单导入批次记录页（品牌端）
class ExternalBatchListPage extends StatefulWidget {
  const ExternalBatchListPage({super.key});

  @override
  State<ExternalBatchListPage> createState() => _ExternalBatchListPageState();
}

class _ExternalBatchListPageState extends State<ExternalBatchListPage> {
  List<Map<String, dynamic>> _batches = [];
  bool _loading = true;
  int _page = 1;
  bool _hasMore = true;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadBatches();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >=
              _scrollCtrl.position.maxScrollExtent - 80 &&
          _hasMore &&
          !_loading) {
        _loadBatches(loadMore: true);
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBatches({bool loadMore = false}) async {
    if (loadMore) {
      _page++;
    } else {
      _page = 1;
      setState(() => _loading = true);
    }

    try {
      final resp = await ApiService().getExternalBatchList(page: _page);
      final list = (resp['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        if (loadMore) {
          _batches.addAll(list);
        } else {
          _batches = list;
        }
        _hasMore = list.length >= 10;
      });
    } catch (_) {
      // mock 数据降级
      if (!loadMore) {
        setState(() => _batches = _mockBatches());
      }
      setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _mockBatches() {
    return [
      {
        'batchNo': 'BATCH20240528001',
        'fileName': '外单导入_5月28日.csv',
        'totalCount': 50,
        'successCount': 48,
        'failedCount': 2,
        'status': 'completed',
        'createTime': '2024-05-28 14:30:00',
        'operatorName': '品牌管理员',
      },
      {
        'batchNo': 'BATCH20240527002',
        'fileName': '淘宝订单_0527.csv',
        'totalCount': 120,
        'successCount': 120,
        'failedCount': 0,
        'status': 'completed',
        'createTime': '2024-05-27 10:15:00',
        'operatorName': '品牌管理员',
      },
      {
        'batchNo': 'BATCH20240526003',
        'fileName': '多平台订单合并.csv',
        'totalCount': 30,
        'successCount': 25,
        'failedCount': 5,
        'status': 'partial',
        'createTime': '2024-05-26 16:45:00',
        'operatorName': '品牌管理员',
      },
      {
        'batchNo': 'BATCH20240525004',
        'fileName': '京东抖音订单.csv',
        'totalCount': 88,
        'successCount': 0,
        'failedCount': 88,
        'status': 'failed',
        'createTime': '2024-05-25 09:00:00',
        'operatorName': '品牌管理员',
        'failReason': '文件格式错误',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('导入批次记录'),
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '新建导入',
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) => const ExternalBatchImportPage()),
              );
              if (result == true) _loadBatches();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _loadBatches(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _batches.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: () => _loadBatches(),
                  child: ListView.separated(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: _batches.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      if (i >= _batches.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      return _buildBatchCard(_batches[i]);
                    },
                  ),
                ),
      // 底部「新建导入」FAB
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => const ExternalBatchImportPage()),
          );
          if (result == true) _loadBatches();
        },
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('新建导入'),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(children: [
      const SizedBox(height: 120),
      const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
      const SizedBox(height: 12),
      const Center(
          child: Text('暂无导入记录',
              style: TextStyle(color: Colors.grey, fontSize: 15))),
      const SizedBox(height: 20),
      Center(
        child: ElevatedButton.icon(
          onPressed: () async {
            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                  builder: (_) => const ExternalBatchImportPage()),
            );
            if (result == true) _loadBatches();
          },
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('立即导入'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7B1FA2),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ),
    ]);
  }

  Widget _buildBatchCard(Map<String, dynamic> batch) {
    final batchNo = batch['batchNo'] as String? ?? '--';
    final fileName = batch['fileName'] as String? ?? '--';
    final total = (batch['totalCount'] as num?)?.toInt() ?? 0;
    final success = (batch['successCount'] as num?)?.toInt() ?? 0;
    final failed = (batch['failedCount'] as num?)?.toInt() ?? 0;
    final status = batch['status'] as String? ?? 'completed';
    final createTime = batch['createTime'] as String? ?? '';
    final operator0 = batch['operatorName'] as String? ?? '--';
    final failReason = batch['failReason'] as String?;

    final statusConf = _statusConfig(status, failed);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showBatchDetail(batch),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：文件名 + 状态
              Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined,
                      size: 18, color: Color(0xFF7B1FA2)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          (statusConf['color'] as Color).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: (statusConf['color'] as Color)
                              .withOpacity(0.4)),
                    ),
                    child: Text(
                      statusConf['label'] as String,
                      style: TextStyle(
                          fontSize: 11,
                          color: statusConf['color'] as Color,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 批次号（可复制）
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: batchNo));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('已复制批次号'),
                        duration: Duration(seconds: 2)),
                  );
                },
                child: Row(children: [
                  const Icon(Icons.tag,
                      size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(batchNo,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  const Icon(Icons.copy_outlined,
                      size: 12, color: Colors.grey),
                ]),
              ),
              const SizedBox(height: 10),

              // 统计数据行
              Row(children: [
                _miniStat('总计', total, Colors.blue),
                const SizedBox(width: 8),
                _miniStat('成功', success, Colors.green),
                const SizedBox(width: 8),
                _miniStat('失败', failed,
                    failed > 0 ? Colors.red : Colors.grey),
                const Spacer(),
                // 进度条
                if (total > 0)
                  SizedBox(
                    width: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${(success / total * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 12,
                              color: success == total
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: success / total,
                            backgroundColor: Colors.grey[200],
                            color: success == total
                                ? Colors.green
                                : Colors.orange,
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),

              const SizedBox(height: 8),
              Divider(height: 1, color: Colors.grey[100]),
              const SizedBox(height: 8),

              // 底部信息
              Row(children: [
                const Icon(Icons.access_time_outlined,
                    size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(createTime,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
                const SizedBox(width: 12),
                const Icon(Icons.person_outline,
                    size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(operator0,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
                const Spacer(),
                const Text('查看详情',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF7B1FA2))),
                const Icon(Icons.chevron_right,
                    size: 16, color: Color(0xFF7B1FA2)),
              ]),

              // 失败原因
              if (failReason != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        size: 13, color: Colors.red),
                    const SizedBox(width: 6),
                    Text('失败原因：$failReason',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.red)),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── 批次详情弹窗 ──────────────────────────────────────────
  void _showBatchDetail(Map<String, dynamic> batch) {
    final batchNo = batch['batchNo'] as String? ?? '--';
    final total = (batch['totalCount'] as num?)?.toInt() ?? 0;
    final success = (batch['successCount'] as num?)?.toInt() ?? 0;
    final failed = (batch['failedCount'] as num?)?.toInt() ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('批次详情',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _detailRow('批次号', batchNo, mono: true),
            _detailRow('文件名', batch['fileName'] as String? ?? '--'),
            _detailRow('导入时间', batch['createTime'] as String? ?? '--'),
            _detailRow('操作人', batch['operatorName'] as String? ?? '--'),
            const Divider(height: 20),
            Row(children: [
              Expanded(child: _detailStatCard('总计', total, Colors.blue)),
              const SizedBox(width: 10),
              Expanded(child: _detailStatCard('成功', success, Colors.green)),
              const SizedBox(width: 10),
              Expanded(
                  child: _detailStatCard(
                      '失败', failed, failed > 0 ? Colors.red : Colors.grey)),
            ]),
            if ((batch['failReason'] as String?) != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '失败原因：${batch['failReason']}',
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B1FA2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    fontFamily: mono ? 'monospace' : null)),
          ),
        ],
      ),
    );
  }

  Widget _detailStatCard(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Text('$value',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ]),
    );
  }

  Widget _miniStat(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text('$label $value',
          style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold)),
    );
  }

  Map<String, dynamic> _statusConfig(String status, int failed) {
    if (status == 'failed') {
      return {'label': '全部失败', 'color': Colors.red};
    }
    if (status == 'partial' || failed > 0) {
      return {'label': '部分成功', 'color': Colors.orange};
    }
    if (status == 'processing') {
      return {'label': '处理中', 'color': Colors.blue};
    }
    return {'label': '全部成功', 'color': Colors.green};
  }
}
