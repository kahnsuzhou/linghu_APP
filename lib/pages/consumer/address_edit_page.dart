import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import '../common/location_picker_page.dart';
import '../../services/api_service.dart';

/// 收货地址 新增/编辑 页
/// [address] 为 null 时为新增，有值时为编辑
class AddressEditPage extends StatefulWidget {
  final Map<String, dynamic>? address;
  const AddressEditPage({super.key, this.address});

  @override
  State<AddressEditPage> createState() => _AddressEditPageState();
}

class _AddressEditPageState extends State<AddressEditPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtr     = TextEditingController();
  final _phoneCtr    = TextEditingController();
  final _provinceCtr = TextEditingController();
  final _cityCtr     = TextEditingController();
  final _districtCtr = TextEditingController();
  final _detailCtr   = TextEditingController();

  double? _latitude;
  double? _longitude;
  bool _locating = false;
  bool _saving   = false;

  bool get _isEdit => widget.address != null;

  @override
  void initState() {
    super.initState();
    final a = widget.address;
    if (a != null) {
      _nameCtr.text     = a['name'] ?? '';
      _phoneCtr.text    = a['phone'] ?? '';
      _provinceCtr.text = a['province'] ?? '';
      _cityCtr.text     = a['city'] ?? '';
      _districtCtr.text = a['district'] ?? '';
      _detailCtr.text   = a['detail'] ?? '';
      _latitude  = (a['latitude']  as num?)?.toDouble();
      _longitude = (a['longitude'] as num?)?.toDouble();
    }
  }

  @override
  void dispose() {
    _nameCtr.dispose(); _phoneCtr.dispose();
    _provinceCtr.dispose(); _cityCtr.dispose();
    _districtCtr.dispose(); _detailCtr.dispose();
    super.dispose();
  }

  // ── GPS 定位 ─────────────────────────────────────────────────

  Future<void> _locateMe() async {
    setState(() => _locating = true);
    try {
      // ── 第一步：IP 定位（无需权限，HTTP/HTTPS 均可）────────────────
      final ipOk = await _locateByIp();
      if (ipOk) {
        // IP 定位成功后静默尝试 GPS 精确升级
        _tryGpsUpgrade();
        return;
      }

      // ── 第二步：IP 失败则尝试 GPS ──────────────────────────────────
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 15));
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _showSnack('自动定位失败，请手动填写省市区', error: true);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      _latitude  = pos.latitude;
      _longitude = pos.longitude;

      // GPS 成功后做逆地理编码
      await _reverseGeocode(pos.latitude, pos.longitude);

    } on TimeoutException {
      _showSnack('定位超时，请手动填写省市区', error: true);
    } catch (e) {
      _showSnack('定位失败，请手动填写省市区', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// IP 定位：ip-api.com，解析城市并填入表单
  Future<bool> _locateByIp() async {
    try {
      final resp = await http.get(
        Uri.parse('http://ip-api.com/json/?lang=zh-CN&fields=status,city,regionName,lat,lon'),
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final lat = (data['lat'] as num?)?.toDouble();
          final lon = (data['lon'] as num?)?.toDouble();
          final city   = (data['city']       as String?) ?? '';
          final region = (data['regionName'] as String?) ?? '';
          if (lat != null && lon != null && mounted) {
            setState(() {
              _latitude  = lat;
              _longitude = lon;
              // 只在字段为空时自动填入，不覆盖用户已填内容
              if (_provinceCtr.text.trim().isEmpty) _provinceCtr.text = region;
              if (_cityCtr.text.trim().isEmpty)     _cityCtr.text     = city;
            });
            _showSnack('已定位到：$region$city（可手动修改）');
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// 后台静默 GPS 精确升级（不弹权限窗）
  void _tryGpsUpgrade() async {
    try {
      final perm = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 3));
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      if (!mounted) return;
      setState(() { _latitude = pos.latitude; _longitude = pos.longitude; });
      await _reverseGeocode(pos.latitude, pos.longitude);
    } catch (_) {}
  }

  /// 逆地理编码：坐标 → 省市区，填入表单
  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 10));
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        setState(() {
          _provinceCtr.text = _bestOf([p.administrativeArea]) ?? _provinceCtr.text;
          _cityCtr.text     = _bestOf([p.subAdministrativeArea, p.locality]) ?? _cityCtr.text;
          _districtCtr.text = _bestOf([p.subLocality, p.locality]) ?? _districtCtr.text;
          final street = _bestOf([p.thoroughfare, p.subThoroughfare, p.street]);
          if (_detailCtr.text.trim().isEmpty && street != null) {
            _detailCtr.text = street;
          }
        });
        _showSnack('GPS精确定位：${_provinceCtr.text}${_cityCtr.text}${_districtCtr.text}');
      }
    } catch (_) {
      // 逆编码失败不影响坐标，只是省市区需手动填
      if (mounted) _showSnack('坐标已获取，请手动确认省市区');
    }
  }

  /// 从候选值里取第一个非空非 null 值
  String? _bestOf(List<String?> candidates) {
    for (final v in candidates) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  // ── 保存 ─────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'name':      _nameCtr.text.trim(),
        'phone':     _phoneCtr.text.trim(),
        'province':  _provinceCtr.text.trim(),
        'city':      _cityCtr.text.trim(),
        'district':  _districtCtr.text.trim(),
        'detail':    _detailCtr.text.trim(),
        if (_latitude  != null) 'latitude':  _latitude,
        if (_longitude != null) 'longitude': _longitude,
      };

      Map<String, dynamic> resp;
      if (_isEdit) {
        resp = await ApiService().updateAddress(widget.address!['id'] as int, body);
      } else {
        resp = await ApiService().addAddress(body);
      }

      if (resp['code'] == 200 && mounted) {
        _showSnack(_isEdit ? '地址已更新' : '地址添加成功');
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.pop(context, true);
      } else if (mounted) {
        _showSnack(resp['msg'] ?? '保存失败', error: true);
      }
    } catch (_) {
      _showSnack('网络错误，请稍后重试', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red[700] : Colors.green[700],
      duration: const Duration(seconds: 3),
    ));
  }

  // ── UI ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_isEdit ? '编辑地址' : '新增地址'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // GPS 定位卡片
              _buildLocateCard(),
              const SizedBox(height: 16),

              // 联系人信息
              _buildSection('联系人信息', [
                _buildField('联系人', _nameCtr,
                    hint: '请输入收货人姓名',
                    prefixIcon: Icons.person_outline,
                    validator: (v) => (v == null || v.trim().isEmpty) ? '联系人不能为空' : null),
                const SizedBox(height: 12),
                _buildField('手机号', _phoneCtr,
                    hint: '请输入手机号',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return '手机号不能为空';
                      if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(v.trim())) return '请输入有效的手机号';
                      return null;
                    }),
              ]),
              const SizedBox(height: 16),

              // 地区信息
              _buildSection('所在地区', [
                Row(children: [
                  Expanded(
                    child: _buildField('省/直辖市', _provinceCtr,
                        hint: '如：广东省',
                        prefixIcon: null),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildField('市', _cityCtr,
                        hint: '如：深圳市',
                        prefixIcon: null),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildField('区/县', _districtCtr,
                        hint: '如：南山区',
                        prefixIcon: null),
                  ),
                ]),
              ]),
              const SizedBox(height: 16),

              // 详细地址
              _buildSection('详细地址', [
                _buildField('详细地址', _detailCtr,
                    hint: '街道、楼栋、门牌号等',
                    prefixIcon: Icons.home_outlined,
                    maxLines: 3,
                    validator: (v) => (v == null || v.trim().isEmpty) ? '详细地址不能为空' : null),
              ]),

              // 坐标提示
              if (_latitude != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(children: [
                    Icon(Icons.gps_fixed, size: 14, color: Colors.green[700]),
                    const SizedBox(width: 6),
                    Text(
                      'GPS坐标：${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                      style: TextStyle(fontSize: 12, color: Colors.green[700]),
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 28),

              // 保存按钮
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_isEdit ? '保存修改' : '添加地址',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// GPS 定位卡片
  Widget _buildLocateCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3EE), Color(0xFFFFE4D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCCB0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.my_location, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('使用真实定位', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  SizedBox(height: 2),
                  Text('自动获取当前位置并填写地区信息', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: _locating ? null : _locateMe,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              icon: _locating
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.gps_fixed, size: 18),
              label: Text(_locating ? '定位中...' : '自动定位',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 10),
          // 地图选点按钮
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: () async {
                final result = await Navigator.push<LocationPickResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LocationPickerPage(
                      initialLat: _latitude  ?? 39.9042,
                      initialLng: _longitude ?? 116.4074,
                      title: '选择收货地址',
                    ),
                  ),
                );
                if (result != null && mounted) {
                  setState(() {
                    _latitude  = result.lat;
                    _longitude = result.lng;
                    if (result.province.isNotEmpty) _provinceCtr.text = result.province;
                    if (result.city.isNotEmpty)     _cityCtr.text     = result.city;
                    if (result.district.isNotEmpty) _districtCtr.text = result.district;
                    if (_detailCtr.text.trim().isEmpty && result.address.isNotEmpty) {
                      _detailCtr.text = result.address;
                    }
                  });
                  _showSnack('已选择：${result.province}${result.city}${result.district}');
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF6B35),
                side: const BorderSide(color: Color(0xFFFF6B35)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(
                _latitude != null ? '地图重新选点' : '地图选点（更精确）',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (_latitude != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 14),
              const SizedBox(width: 4),
              Text(
                '坐标已获取 (${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)})',
                style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50)),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  /// 表单段落容器
  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF333333))),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  /// 通用输入框
  Widget _buildField(
    String label,
    TextEditingController controller, {
    String? hint,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18, color: Colors.grey[500]) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red),
        ),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
    );
  }
}
