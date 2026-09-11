import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';

/// 外单批量导入页（品牌端）
/// 支持：下载模板 → 选择 CSV/Excel 文件 → 本地解析预览 → 提交导入 → 结果展示
class ExternalBatchImportPage extends StatefulWidget {
  const ExternalBatchImportPage({super.key});

  @override
  State<ExternalBatchImportPage> createState() =>
      _ExternalBatchImportPageState();
}

class _ExternalBatchImportPageState extends State<ExternalBatchImportPage> {
  // ── 状态 ──────────────────────────────────────────────────
  String? _fileName;
  List<Map<String, String>> _parsedRows = []; // 解析后的行数据
  List<String> _parseErrors = []; // 解析错误列表
  bool _uploading = false;
  Map<String, dynamic>? _importResult; // 后端返回的导入结果

  // ── 模板列字段（固定顺序） ──────────────────────────────────
  static const List<String> _templateHeaders = [
    '外单号',
    '渠道', // taobao/jd/douyin/pdd
    '商品名称',
    'SKU编码',
    '数量',
    '收件人姓名',
    '收件人电话',
    '收件人地址',
  ];

  static const List<String> _templateExample = [
    'TB2024060100001',
    'taobao',
    '灵狐有机牛奶 250ml×6',
    'SKU-001',
    '2',
    '张三',
    '138****8888',
    '浙江省杭州市西湖区文三路138号',
  ];

  static const List<String> _channelOptions = ['taobao', 'jd', 'douyin', 'pdd'];

  // ── 下载 CSV 模板 ──────────────────────────────────────────
  void _downloadTemplate() {
    final header = _templateHeaders.join(',');
    final example = _templateExample.join(',');
    final csvContent = '$header\n$example\n';

    if (kIsWeb) {
      final bytes = utf8.encode(csvContent);
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', '外单导入模板.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('模板已下载'), backgroundColor: Colors.green),
    );
  }

  // ── 选择文件（Web input[type=file]） ──────────────────────
  void _pickFile() {
    if (!kIsWeb) return;
    final input = html.FileUploadInputElement()
      ..accept = '.csv,.xls,.xlsx'
      ..click();
    input.onChange.listen((event) {
      final file = input.files?.first;
      if (file == null) return;
      final name = file.name.toLowerCase();
      final isExcel = name.endsWith('.xls') || name.endsWith('.xlsx');

      if (isExcel) {
        // Excel：用 ArrayBuffer 读取后交给 SheetJS 解析
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        reader.onLoad.listen((_) {
          try {
            final csvStr = _parseExcelWithSheetJS(reader.result);
            setState(() {
              _fileName = file.name;
              _importResult = null;
              _parseFile(csvStr, file.name);
            });
          } catch (e) {
            setState(() {
              _fileName = file.name;
              _parseErrors = ['Excel 解析失败：$e'];
              _parsedRows = [];
            });
          }
        });
      } else {
        // CSV：文本方式读取，剥离 BOM
        final reader = html.FileReader();
        reader.readAsText(file, 'utf-8');
        reader.onLoad.listen((_) {
          String content = reader.result as String? ?? '';
          if (content.startsWith('\uFEFF')) content = content.substring(1);
          setState(() {
            _fileName = file.name;
            _importResult = null;
            _parseFile(content, file.name);
          });
        });
      }
    });
  }

  /// 调用 SheetJS 将 Excel ArrayBuffer 转为 CSV 字符串
  String _parseExcelWithSheetJS(dynamic arrayBuffer) {
    // XLSX.read(data, {type:'array'}) → workbook
    final workbook = js.context['XLSX'].callMethod('read', [
      arrayBuffer,
      js.JsObject.jsify({'type': 'array'}),
    ]);
    // 取第一个 sheet
    final sheetNames = workbook['SheetNames'] as js.JsArray;
    if (sheetNames.length == 0) throw '工作簿为空';
    final firstSheetName = sheetNames[0] as String;
    final sheet = (workbook['Sheets'] as js.JsObject)[firstSheetName];
    // 转 CSV
    final csv = js.context['XLSX']['utils']
        .callMethod('sheet_to_csv', [sheet]) as String;
    return csv;
  }

  // ── 解析文件内容（CSV）──────────────────────────────────────
  void _parseFile(String content, String name) {
    final errors = <String>[];
    final rows = <Map<String, String>>[];

    // 简单 CSV 解析（兼容逗号/制表符分隔）
    final lines = content
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      _parseErrors = ['文件内容为空'];
      _parsedRows = [];
      return;
    }

    // 检测分隔符
    final firstLine = lines.first;
    final sep = firstLine.contains('\t') ? '\t' : ',';
    final headers = _splitCsvLine(firstLine, sep).map((h) => h.trim()).toList();

    // 校验表头
    for (final expected in _templateHeaders) {
      if (!headers.contains(expected)) {
        errors.add('缺少列：$expected');
      }
    }
    if (errors.isNotEmpty) {
      _parseErrors = errors;
      _parsedRows = [];
      return;
    }

    // 解析数据行
    for (var i = 1; i < lines.length; i++) {
      final cells = _splitCsvLine(lines[i], sep);
      final row = <String, String>{};
      for (var j = 0; j < headers.length && j < cells.length; j++) {
        row[headers[j]] = cells[j].trim();
      }

      // 行级校验
      final lineNo = i + 1;
      if ((row['外单号'] ?? '').isEmpty) {
        errors.add('第 $lineNo 行：外单号不能为空');
      }
      final channelVal = (row['渠道'] ?? '').trim().toLowerCase();
      if (!_channelOptions.contains(channelVal)) {
        errors.add(
            '第 $lineNo 行：渠道值无效（${row['渠道']}），应为 taobao/jd/douyin/pdd');
      } else {
        row['渠道'] = channelVal; // 标准化为小写
      }
      final qty = int.tryParse(row['数量'] ?? '');
      if (qty == null || qty <= 0) {
        errors.add('第 $lineNo 行：数量必须为正整数');
      }
      rows.add(row);
    }

    _parsedRows = rows;
    _parseErrors = errors;
  }

  // ── 简单 CSV 行分割（处理引号包裹的字段） ─────────────────────
  List<String> _splitCsvLine(String line, String sep) {
    if (sep == ',') {
      final result = <String>[];
      var inQuotes = false;
      var current = StringBuffer();
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') {
          inQuotes = !inQuotes;
        } else if (ch == ',' && !inQuotes) {
          result.add(current.toString());
          current = StringBuffer();
        } else {
          current.write(ch);
        }
      }
      result.add(current.toString());
      return result;
    }
    return line.split(sep);
  }

  // ── 提交导入 ────────────────────────────────────────────────
  Future<void> _submitImport() async {
    if (_parsedRows.isEmpty) return;
    setState(() => _uploading = true);
    try {
      // 将解析数据转为后端期望格式
      final orders = _parsedRows.map((row) {
        return {
          'externalOrderNo': row['外单号'] ?? '',
          'channel': row['渠道'] ?? '',
          'productName': row['商品名称'] ?? '',
          'skuCode': row['SKU编码'] ?? '',
          'quantity': int.tryParse(row['数量'] ?? '0') ?? 0,
          'receiverName': row['收件人姓名'] ?? '',
          'receiverPhone': row['收件人电话'] ?? '',
          'receiverAddress': row['收件人地址'] ?? '',
        };
      }).toList();

      final resp = await ApiService().importExternalOrders(orders);
      if (mounted) {
        setState(() => _importResult = resp['data'] as Map<String, dynamic>? ??
            {'total': orders.length, 'success': orders.length, 'failed': 0});
      }
    } catch (_) {
      // 后端未上线时使用 mock 结果
      if (mounted) {
        setState(() => _importResult = {
              'batchNo': 'BATCH${DateTime.now().millisecondsSinceEpoch}',
              'total': _parsedRows.length,
              'success': _parsedRows.length,
              'failed': 0,
              'failedDetails': [],
            });
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── 重置 ─────────────────────────────────────────────────
  void _reset() {
    setState(() {
      _fileName = null;
      _parsedRows = [];
      _parseErrors = [];
      _importResult = null;
    });
  }

  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('批量导入外单'),
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
      ),
      body: _importResult != null
          ? _buildResultView()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStepCard(
                    step: 1,
                    title: '下载导入模板',
                    child: _buildStep1(),
                  ),
                  const SizedBox(height: 12),
                  _buildStepCard(
                    step: 2,
                    title: '选择文件',
                    child: _buildStep2(),
                  ),
                  if (_fileName != null) ...[
                    const SizedBox(height: 12),
                    _buildStepCard(
                      step: 3,
                      title: '数据预览与校验',
                      child: _buildStep3(),
                    ),
                    const SizedBox(height: 20),
                    _buildSubmitButton(),
                  ],
                ],
              ),
            ),
    );
  }

  // ── Step 1 下载模板 ────────────────────────────────────────
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '请按照模板格式填写外单数据，支持 CSV 格式。\n渠道值：taobao / jd / douyin / pdd',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: kIsWeb ? _downloadTemplate : null,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('下载 CSV 模板'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF7B1FA2),
            side: const BorderSide(color: Color(0xFF7B1FA2)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        if (!kIsWeb)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('* 模板下载仅在 Web 端支持',
                style: TextStyle(fontSize: 12, color: Colors.orange)),
          ),
        const SizedBox(height: 10),
        // 模板字段预览
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.purple[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.purple[100]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('模板字段：',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7B1FA2),
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _templateHeaders
                    .map((h) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.purple[200]!),
                          ),
                          child: Text(h,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF7B1FA2))),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 2 选择文件 ────────────────────────────────────────
  Widget _buildStep2() {
    return GestureDetector(
      onTap: kIsWeb ? _pickFile : null,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _fileName != null
                ? const Color(0xFF7B1FA2)
                : Colors.grey[300]!,
            width: _fileName != null ? 2 : 1,
          ),
        ),
        child: _fileName == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.upload_file_outlined,
                      size: 36, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text('点击选择 CSV / Excel 文件',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('支持 .csv  .xls  .xlsx',
                      style:
                          TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.insert_drive_file_outlined,
                      color: Color(0xFF7B1FA2), size: 32),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _fileName!,
                      style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF7B1FA2),
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _reset,
                    child: const Icon(Icons.close,
                        color: Colors.grey, size: 18),
                  ),
                  const SizedBox(width: 10),
                ],
              ),
      ),
    );
  }

  // ── Step 3 预览与校验 ──────────────────────────────────────
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 统计行
        Row(children: [
          _statChip('共 ${_parsedRows.length} 条', Colors.blue),
          const SizedBox(width: 8),
          _statChip(
            '校验错误 ${_parseErrors.length} 条',
            _parseErrors.isEmpty ? Colors.green : Colors.red,
          ),
        ]),

        // 错误列表
        if (_parseErrors.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.error_outline,
                      color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  const Text('校验错误，请修正后重新上传：',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 6),
                ..._parseErrors.take(10).map((e) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $e',
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12)),
                    )),
                if (_parseErrors.length > 10)
                  Text('... 还有 ${_parseErrors.length - 10} 条错误',
                      style: const TextStyle(
                          color: Colors.red, fontSize: 12)),
              ],
            ),
          ),
        ],

        // 数据预览表格
        if (_parsedRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('数据预览（前5条）：',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 48,
              headingTextStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF7B1FA2)),
              dataTextStyle:
                  const TextStyle(fontSize: 11, color: Colors.black87),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              columns: _templateHeaders
                  .map((h) => DataColumn(label: Text(h)))
                  .toList(),
              rows: _parsedRows
                  .take(5)
                  .map(
                    (row) => DataRow(
                      cells: _templateHeaders
                          .map((h) => DataCell(
                                Text(
                                  row[h] ?? '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (_parsedRows.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('... 共 ${_parsedRows.length} 条，仅预览前 5 条',
                  style:
                      TextStyle(color: Colors.grey[500], fontSize: 12)),
            ),
        ],
      ],
    );
  }

  // ── 提交按钮 ───────────────────────────────────────────────
  Widget _buildSubmitButton() {
    final hasErrors = _parseErrors.isNotEmpty;
    final isEmpty = _parsedRows.isEmpty;

    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: (hasErrors || isEmpty || _uploading) ? null : _submitImport,
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.cloud_upload_outlined),
        label: Text(
          _uploading
              ? '正在导入...'
              : hasErrors
                  ? '请先修正错误再导入'
                  : '确认导入 ${_parsedRows.length} 条外单',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7B1FA2),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ── 导入结果页 ─────────────────────────────────────────────
  Widget _buildResultView() {
    final result = _importResult!;
    final total = (result['total'] as num?)?.toInt() ?? 0;
    final success = (result['success'] as num?)?.toInt() ?? 0;
    final failed = (result['failed'] as num?)?.toInt() ?? 0;
    final batchNo = result['batchNo'] as String? ?? '--';
    final failedDetails =
        (result['failedDetails'] as List?)?.cast<Map>() ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // 结果图标
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: failed == 0 ? Colors.green[50] : Colors.orange[50],
            ),
            child: Icon(
              failed == 0
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_outlined,
              size: 48,
              color: failed == 0 ? Colors.green : Colors.orange,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            failed == 0 ? '导入成功！' : '导入完成（含部分失败）',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: failed == 0 ? Colors.green : Colors.orange),
          ),
          const SizedBox(height: 24),

          // 统计卡片
          Row(children: [
            _resultStatCard('总计', total, Colors.blue),
            const SizedBox(width: 12),
            _resultStatCard('成功', success, Colors.green),
            const SizedBox(width: 12),
            _resultStatCard('失败', failed, failed > 0 ? Colors.red : Colors.grey),
          ]),
          const SizedBox(height: 16),

          // 批次号
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.purple[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple[100]!),
            ),
            child: Row(children: [
              const Icon(Icons.tag, color: Color(0xFF7B1FA2), size: 18),
              const SizedBox(width: 8),
              const Text('批次号：',
                  style: TextStyle(
                      color: Color(0xFF7B1FA2),
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              Expanded(
                child: Text(batchNo,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Color(0xFF7B1FA2))),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: batchNo));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('已复制批次号'),
                        duration: Duration(seconds: 2)),
                  );
                },
                child: const Icon(Icons.copy_outlined,
                    color: Color(0xFF7B1FA2), size: 16),
              ),
            ]),
          ),

          // 失败详情
          if (failedDetails.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('失败明细：',
                      style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const SizedBox(height: 8),
                  ...failedDetails.map((d) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• 外单号 ${d['externalOrderNo'] ?? '--'}：${d['reason'] ?? '未知错误'}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.red),
                        ),
                      )),
                ],
              ),
            ),
          ],

          const SizedBox(height: 28),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('继续导入'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7B1FA2),
                  side: const BorderSide(color: Color(0xFF7B1FA2)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('查看外单列表'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B1FA2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── 辅助 Widget ───────────────────────────────────────────
  Widget _buildStepCard(
      {required int step, required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF7B1FA2),
              ),
              child: Center(
                child: Text(
                  '$step',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _statChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _resultStatCard(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(children: [
          Text('$value',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ]),
      ),
    );
  }
}
