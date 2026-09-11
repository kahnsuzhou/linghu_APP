import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'address_edit_page.dart';

/// 收货地址列表页
class AddressPage extends StatefulWidget {
  /// 若为选择模式（从下单页调用），选中后回传地址数据
  final bool selectMode;
  const AddressPage({super.key, this.selectMode = false});

  @override
  State<AddressPage> createState() => _AddressPageState();
}

class _AddressPageState extends State<AddressPage> {
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiService().getAddressList();
      if (resp['code'] == 200 && mounted) {
        setState(() {
          _addresses = (resp['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {
      if (mounted) _showSnack('加载失败，请检查网络', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setDefault(int id) async {
    try {
      final resp = await ApiService().setDefaultAddress(id);
      if (resp['code'] == 200) {
        _loadAddresses();
        _showSnack('已设为默认地址');
      } else {
        _showSnack(resp['msg'] ?? '操作失败', error: true);
      }
    } catch (_) {
      _showSnack('网络错误', error: true);
    }
  }

  Future<void> _delete(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个收货地址吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final resp = await ApiService().deleteAddress(id);
      if (resp['code'] == 200) {
        _loadAddresses();
        _showSnack('已删除');
      } else {
        _showSnack(resp['msg'] ?? '删除失败', error: true);
      }
    } catch (_) {
      _showSnack('网络错误', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  void _toEdit({Map<String, dynamic>? address}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddressEditPage(address: address),
      ),
    );
    if (changed == true) _loadAddresses();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(widget.selectMode ? '选择收货地址' : '收货地址'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _toEdit(),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('新增地址'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _addresses.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadAddresses,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: _addresses.length,
                    itemBuilder: (ctx, i) => _buildCard(_addresses[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('还没有收货地址', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
          const SizedBox(height: 8),
          Text('点击右下角按钮添加', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> addr) {
    final isDefault = (addr['isDefault'] ?? 0) == 1;
    final id = addr['id'] as int;

    return GestureDetector(
      onTap: widget.selectMode
          ? () => Navigator.pop(context, addr)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isDefault
              ? Border.all(color: const Color(0xFFFF6B35), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 联系人 + 电话 + 默认标签 + 菜单
              Row(
                children: [
                  if (isDefault) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('默认', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    addr['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    addr['phone'] ?? '',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const Spacer(),
                  // 操作菜单
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                    onSelected: (action) {
                      if (action == 'edit') _toEdit(address: addr);
                      if (action == 'default') _setDefault(id);
                      if (action == 'delete') _delete(id);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('编辑')])),
                      if (!isDefault)
                        const PopupMenuItem(value: 'default', child: Row(children: [Icon(Icons.star_outline, size: 16), SizedBox(width: 8), Text('设为默认')])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.red), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))])),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 完整地址
              Text(
                addr['fullAddress'] ?? '',
                style: TextStyle(color: Colors.grey[700], fontSize: 14, height: 1.4),
              ),
              // 如果有GPS坐标，显示小标记
              if (addr['latitude'] != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.gps_fixed, size: 12, color: Colors.green[600]),
                  const SizedBox(width: 4),
                  Text('已定位', style: TextStyle(fontSize: 11, color: Colors.green[600])),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
