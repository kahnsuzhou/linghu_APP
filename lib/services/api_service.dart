import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../utils/storage.dart';

/// API 响应封装
class ApiResponse<T> {
  final int code;
  final String msg;
  final T? data;
  final bool success;

  ApiResponse({
    required this.code,
    required this.msg,
    this.data,
  }) : success = code == 200;

  factory ApiResponse.fromJson(Map<String, dynamic> json, T? Function(dynamic)? fromData) {
    return ApiResponse<T>(
      code: json['code'] ?? 500,
      msg: json['msg'] ?? '未知错误',
      data: fromData != null ? fromData(json['data']) : json['data'] as T?,
    );
  }
}

/// HTTP API 服务
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // 动态 getter 保证 Web/Native 都能取到正确值
  String get _baseUrl => AppConstants.apiBaseUrl;

  /// 构建请求头
  Map<String, String> _buildHeaders({bool withAuth = true}) {
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      'bypass-tunnel-reminder': 'true', // localtunnel/cloudflare 穿透跳过确认页
      'cf-access-client-id': '', // cloudflare tunnel 兼容头
    };
    if (withAuth) {
      final token = StorageUtil.getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  /// GET 请求
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParams}) async {
    var uri = Uri.parse('$_baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }
    final response = await http.get(uri, headers: _buildHeaders());
    return _handleResponse(response);
  }

  /// POST 请求
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body, bool withAuth = true}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http.post(
      uri,
      headers: _buildHeaders(withAuth: withAuth),
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  /// PUT 请求
  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http.put(
      uri,
      headers: _buildHeaders(),
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  /// DELETE 请求
  Future<Map<String, dynamic>> delete(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http.delete(uri, headers: _buildHeaders());
    return _handleResponse(response);
  }

  /// 处理响应
  Map<String, dynamic> _handleResponse(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(body) as Map<String, dynamic>;
    } else {
      try {
        final errorBody = jsonDecode(body) as Map<String, dynamic>;
        return errorBody;
      } catch (_) {
        return {'code': response.statusCode, 'msg': 'HTTP错误: ${response.statusCode}', 'data': null};
      }
    }
  }

  // ===== 认证接口 =====

  Future<Map<String, dynamic>> login(String username, String password) async {
    return await post('/api/auth/login', body: {'username': username, 'password': password}, withAuth: false);
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    return await post('/api/auth/register', body: data, withAuth: false);
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    return await get('/api/auth/current-user');
  }

  Future<Map<String, dynamic>> getHomeConfig() async {
    return await get('/api/home/config');
  }

  // ===== 消费者接口 =====

  Future<Map<String, dynamic>> getNearbyProducts(double lat, double lng) async {
    return await get('/api/consumer/products/nearby',
        queryParams: {'lat': lat.toString(), 'lng': lng.toString()});
  }

  Future<Map<String, dynamic>> getWarehouseMap(double lat, double lng) async {
    return await get('/api/consumer/warehouses/map',
        queryParams: {'lat': lat.toString(), 'lng': lng.toString()});
  }

  Future<Map<String, dynamic>> getProductDetail(int productId) async {
    return await get('/api/consumer/product/detail/$productId');
  }

  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> orderData) async {
    return await post('/api/consumer/order/create', body: orderData);
  }

  Future<Map<String, dynamic>> payOrder(int orderId) async {
    return await post('/api/consumer/order/pay-callback?orderId=$orderId');
  }

  Future<Map<String, dynamic>> getOrderList({String? status}) async {
    return await get('/api/consumer/order/list',
        queryParams: status != null ? {'status': status} : null);
  }

  Future<Map<String, dynamic>> getOrderDetail(int orderId) async {
    return await get('/api/consumer/order/detail/$orderId');
  }

  Future<Map<String, dynamic>> cancelOrder(int orderId) async {
    return await post('/api/consumer/order/cancel/$orderId');
  }

  Future<Map<String, dynamic>> confirmReceipt(int orderId) async {
    return await post('/api/consumer/order/confirm/$orderId');
  }

  /// 申请售后退款
  Future<Map<String, dynamic>> applyRefund(int orderId, String refundType, String refundReason) async {
    return await post('/api/consumer/order/refund/$orderId', body: {
      'refundType': refundType,
      'refundReason': refundReason,
    });
  }

  /// 撤销退款申请
  Future<Map<String, dynamic>> cancelRefund(int orderId) async {
    return await post('/api/consumer/order/refund/$orderId/cancel');
  }

  // ===== 仓主接口 =====

  Future<Map<String, dynamic>> getInboundList() async {
    return await get('/api/warehouse/work/inbound/list');
  }

  Future<Map<String, dynamic>> queryInboundByNo(String inboundNo) async {
    return await get('/api/warehouse/work/inbound/query?inboundNo=$inboundNo');
  }

  Future<Map<String, dynamic>> startInbound(int workOrderId) async {
    return await post('/api/warehouse/work/inbound/start/$workOrderId');
  }

  Future<Map<String, dynamic>> completeInbound(Map<String, dynamic> data) async {
    return await post('/api/warehouse/work/inbound/complete', body: data);
  }

  Future<Map<String, dynamic>> getPickingList() async {
    return await get('/api/warehouse/work/picking/list');
  }

  Future<Map<String, dynamic>> getPickingDetail(int workOrderId) async {
    return await get('/api/warehouse/work/picking/detail/$workOrderId');
  }

  Future<Map<String, dynamic>> startPicking(int workOrderId) async {
    return await post('/api/warehouse/work/picking/start/$workOrderId');
  }

  Future<Map<String, dynamic>> scanProduct(int workOrderId, String barcode) async {
    return await post('/api/warehouse/work/picking/scan',
        body: {'workOrderId': workOrderId, 'barcode': barcode});
  }

  Future<Map<String, dynamic>> scanProductWithId(int workOrderId, String barcode, int productId) async {
    return await post('/api/warehouse/work/picking/scan',
        body: {'workOrderId': workOrderId, 'barcode': barcode, 'productId': productId});
  }

  Future<Map<String, dynamic>> completePicking(Map<String, dynamic> data) async {
    return await post('/api/warehouse/work/picking/complete', body: data);
  }

  Future<Map<String, dynamic>> getWarehouseInventory() async {
    return await get('/api/warehouse/inventory/list');
  }

  Future<Map<String, dynamic>> getWarehouseEarnings({String period = 'month'}) async {
    return await get('/api/warehouse/earnings', queryParams: {'period': period});
  }

  Future<Map<String, dynamic>> getWarehouseInfo() async {
    return await get('/api/warehouse/info');
  }

  Future<Map<String, dynamic>> getWarehouseList() async {
    return await get('/api/warehouse/info/list');
  }

  Future<Map<String, dynamic>> createWarehouse(Map<String, dynamic> data) async {
    return await post('/api/warehouse/info/create', body: data);
  }

  Future<Map<String, dynamic>> updateWarehouse(Map<String, dynamic> data) async {
    return await put('/api/warehouse/info/update', body: data);
  }

  Future<Map<String, dynamic>> deleteWarehouse(int warehouseId) async {
    return await delete('/api/warehouse/info/delete/$warehouseId');
  }

  // ===== 品牌方接口 =====

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> data) async {
    return await post('/api/brand/product/create', body: data);
  }

  Future<Map<String, dynamic>> updateProduct(int productId, Map<String, dynamic> data) async {
    return await put('/api/brand/product/update/$productId', body: data);
  }

  Future<Map<String, dynamic>> getBrandProducts() async {
    return await get('/api/brand/product/list');
  }

  Future<Map<String, dynamic>> createReplenishmentPlan(Map<String, dynamic> data) async {
    return await post('/api/brand/replenishment/plan', body: data);
  }

  Future<Map<String, dynamic>> getReplenishmentList() async {
    return await get('/api/brand/replenishment/list');
  }

  Future<Map<String, dynamic>> getBrandInventoryOverview() async {
    return await get('/api/brand/inventory/overview');
  }

  Future<Map<String, dynamic>> getBrandOrders() async {
    return await get('/api/brand/order/list');
  }

  Future<Map<String, dynamic>> getReplenishmentSuggestion({int? warehouseId, int? skuId}) async {
    final params = <String, String>{};
    if (warehouseId != null) params['warehouseId'] = warehouseId.toString();
    if (skuId != null) params['skuId'] = skuId.toString();
    return await get('/api/brand/ai/predict-replenishment', queryParams: params);
  }

  Future<Map<String, dynamic>> getBrandWarehouseList() async {
    return await get('/api/brand/warehouse/list');
  }

  Future<Map<String, dynamic>> getBrandHeatmap() async {
    return await get('/api/brand/heatmap');
  }

  // ===== 钱包接口（三端通用）=====

  Future<Map<String, dynamic>> getWalletInfo() async {
    return await get('/api/wallet/info');
  }

  Future<Map<String, dynamic>> getWalletTransactions({int page = 1, int size = 20}) async {
    return await get('/api/wallet/transactions',
        queryParams: {'page': page.toString(), 'size': size.toString()});
  }

  /// 充值（仅消费者）
  Future<Map<String, dynamic>> rechargeWallet(double amount) async {
    return await post('/api/wallet/recharge', body: {'amount': amount});
  }

  /// 钱包支付订单（仅消费者）
  Future<Map<String, dynamic>> walletPay(int orderId) async {
    return await post('/api/wallet/pay', body: {'orderId': orderId});
  }

  /// 提现（三端通用）
  Future<Map<String, dynamic>> withdrawWallet(double amount) async {
    return await post('/api/wallet/withdraw', body: {'amount': amount});
  }

  // ===== 支付账号绑定接口 =====

  /// 查询已绑定的支付宝/微信账号列表
  Future<Map<String, dynamic>> getPaymentAccounts() async {
    return await get('/api/payment/account/list');
  }

  /// 绑定支付账号
  /// channel: 'ALIPAY' | 'WECHAT'
  Future<Map<String, dynamic>> bindPaymentAccount(String channel, String accountNo, String realName) async {
    return await post('/api/payment/account/bind', body: {
      'channel': channel,
      'accountNo': accountNo,
      'realName': realName,
    });
  }

  /// 解绑支付账号
  Future<Map<String, dynamic>> unbindPaymentAccount(int id) async {
    return await delete('/api/payment/account/$id');
  }

  /// 设为默认收款账号
  Future<Map<String, dynamic>> setDefaultPaymentAccount(int id) async {
    return await post('/api/payment/account/set-default/$id');
  }

  /// 发起充值（返回 payUrl 或直接成功）
  /// channel: 'ALIPAY' | 'WECHAT'
  Future<Map<String, dynamic>> createRechargeOrder(double amount, String channel) async {
    return await post('/api/payment/recharge', body: {'amount': amount, 'channel': channel});
  }

  /// 发起提现（指定收款账号 ID）
  Future<Map<String, dynamic>> createWithdrawOrder(double amount, {int? accountId}) async {
    final body = <String, dynamic>{'amount': amount};
    if (accountId != null) body['accountId'] = accountId;
    return await post('/api/payment/withdraw', body: body);
  }

  /// 查询支付单状态
  Future<Map<String, dynamic>> queryPaymentOrder(String orderNo) async {
    return await get('/api/payment/order/$orderNo');
  }

  /// 关键词搜索附近商品（商品名/条码模糊匹配，按最近仓库排序）
  Future<Map<String, dynamic>> searchProducts(String keyword, {double lat = 39.9042, double lng = 116.4074}) async {
    return await get('/api/consumer/products/search', queryParams: {
      'keyword': keyword,
      'lat': lat.toString(),
      'lng': lng.toString(),
    });
  }

  // ===== 收货地址接口 =====

  /// 查询收货地址列表
  Future<Map<String, dynamic>> getAddressList() async {
    return await get('/api/address/list');
  }

  /// 新增收货地址
  Future<Map<String, dynamic>> addAddress(Map<String, dynamic> body) async {
    return await post('/api/address/add', body: body);
  }

  /// 更新收货地址
  Future<Map<String, dynamic>> updateAddress(int id, Map<String, dynamic> body) async {
    return await put('/api/address/update/$id', body: body);
  }

  /// 设为默认收货地址
  Future<Map<String, dynamic>> setDefaultAddress(int id) async {
    return await post('/api/address/set-default/$id');
  }

  /// 删除收货地址
  Future<Map<String, dynamic>> deleteAddress(int id) async {
    return await delete('/api/address/$id');
  }

  /// 上传商品图片（multipart/form-data）
  /// [bytes] 图片字节数据，[filename] 文件名（含扩展名）
  Future<Map<String, dynamic>> uploadProductImage(Uint8List bytes, String filename) async {
    final uri = Uri.parse('$_baseUrl/api/brand/product/upload-image');
    final request = http.MultipartRequest('POST', uri);
    // 添加认证头
    final token = StorageUtil.getToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['bypass-tunnel-reminder'] = 'true';
    }
    // 推断 MIME 类型
    final ext = filename.split('.').last.toLowerCase();
    final mimeType = ext == 'png' ? 'image/png'
        : ext == 'gif' ? 'image/gif'
        : ext == 'webp' ? 'image/webp'
        : 'image/jpeg';
    request.files.add(http.MultipartFile.fromBytes('file', bytes,
        filename: filename, contentType: _parseMediaType(mimeType)));
    final streamedResponse = await request.send();
    final responseBody = await streamedResponse.stream.bytesToString();
    if (streamedResponse.statusCode == 200 || streamedResponse.statusCode == 201) {
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } else {
      try {
        return jsonDecode(responseBody) as Map<String, dynamic>;
      } catch (_) {
        return {'code': streamedResponse.statusCode, 'msg': '上传失败', 'data': null};
      }
    }
  }

  /// 辅助：将 MIME 字符串解析为 MediaType（避免引入额外依赖）
  http.MediaType _parseMediaType(String mimeType) {
    final parts = mimeType.split('/');
    return http.MediaType(parts[0], parts.length > 1 ? parts[1] : '*');
  }

  // ===== 消费者会员接口 =====

  Future<Map<String, dynamic>> getVipInfo() async {
    return await get('/api/consumer/vip/info');
  }

  Future<Map<String, dynamic>> purchaseVip(String plan) async {
    return await post('/api/consumer/vip/purchase?plan=$plan', body: {});
  }

  // ===== 0.1元拼团拉新活动接口 =====

  /// 获取活动列表
  Future<Map<String, dynamic>> getActivityList() async {
    return await get('/api/consumer/activity/list');
  }

  /// 获取活动详情（可带邀请码）
  Future<Map<String, dynamic>> getActivityDetail(int activityId, {String? inviteCode}) async {
    final params = <String, String>{};
    if (inviteCode != null && inviteCode.isNotEmpty) params['inviteCode'] = inviteCode;
    return await get('/api/consumer/activity/$activityId/detail', queryParams: params.isEmpty ? null : params);
  }

  /// 创建邀请（邀请人调用），返回 inviteCode
  Future<Map<String, dynamic>> createInvite(int activityId) async {
    return await post('/api/consumer/activity/$activityId/invite', body: {});
  }

  /// 绑定邀请码（新用户注册后调用）
  Future<Map<String, dynamic>> bindInvite(String inviteCode) async {
    return await post('/api/consumer/activity/bind-invite', body: {'inviteCode': inviteCode});
  }

  /// 下单0.1元（inviteCode为空时代表邀请人下单，否则为被邀请人下单）
  Future<Map<String, dynamic>> placeActivityOrder(int activityId, int warehouseId, {String? inviteCode}) async {
    final body = <String, dynamic>{'warehouseId': warehouseId};
    if (inviteCode != null && inviteCode.isNotEmpty) body['inviteCode'] = inviteCode;
    return await post('/api/consumer/activity/$activityId/order', body: body);
  }

  /// 我的邀请记录
  Future<Map<String, dynamic>> getMyInvites() async {
    return await get('/api/consumer/activity/my-invites');
  }

  /// 我的自提码列表（活动订单）
  Future<Map<String, dynamic>> getMyPickupCodes() async {
    return await get('/api/consumer/activity/my-pickup-codes');
  }

  /// 我的自提码列表（普通订单）
  Future<Map<String, dynamic>> getMyOrderPickupCodes() async {
    return await get('/api/consumer/order/pickup-codes');
  }

  // ─── 仓主端：自提核销 ───────────────────────────────────────────────

  /// 待核销自提订单列表
  Future<Map<String, dynamic>> getPickupList({String? keyword}) async {
    final params = keyword != null && keyword.isNotEmpty
        ? '?keyword=${Uri.encodeComponent(keyword)}'
        : '';
    return await get('/api/warehouse/pickup/list$params');
  }

  /// 核销自提码
  /// [pickUpCode] 6位数字码，[inviteId] 记录ID（二选一：传二维码字符串 [pickUpQr]）
  Future<Map<String, dynamic>> verifyPickup({
    String? pickUpQr,
    String? pickUpCode,
    int? inviteId,
  }) async {
    final body = <String, dynamic>{};
    if (pickUpQr != null) body['pickUpQr'] = pickUpQr;
    if (pickUpCode != null) body['pickUpCode'] = pickUpCode;
    if (inviteId != null) body['inviteId'] = inviteId;
    return await post('/api/warehouse/pickup/verify', body: body);
  }

  // ===== 品牌方出库接口（调拨单 + 退货单）=====

  /// 查询某仓库品牌方库存（含仓储费预估）
  Future<Map<String, dynamic>> getBrandOutboundInventory(int warehouseId) async {
    return await get('/api/brand/outbound/inventory', queryParams: {'warehouseId': warehouseId.toString()});
  }

  /// 发起调拨出库单
  Future<Map<String, dynamic>> createTransferOrder(Map<String, dynamic> data) async {
    return await post('/api/brand/outbound/transfer', body: data);
  }

  /// 发起退货出库单
  Future<Map<String, dynamic>> createReturnOrder(Map<String, dynamic> data) async {
    return await post('/api/brand/outbound/return', body: data);
  }

  /// 品牌方出库单列表
  Future<Map<String, dynamic>> getBrandOutboundList() async {
    return await get('/api/brand/outbound/list');
  }

  /// 取消出库单
  Future<Map<String, dynamic>> cancelOutboundOrder(int workOrderId) async {
    return await post('/api/brand/outbound/cancel/$workOrderId');
  }

  // ===== 仓主出库作业接口 =====

  /// 仓主出库作业单列表（调拨+退货）
  Future<Map<String, dynamic>> getWarehouseOutboundList() async {
    return await get('/api/warehouse/work/outbound/list');
  }

  /// 开始出库作业
  Future<Map<String, dynamic>> startOutbound(int workOrderId) async {
    return await post('/api/warehouse/work/outbound/start/$workOrderId');
  }

  /// 完成出库作业
  Future<Map<String, dynamic>> completeOutbound(int workOrderId) async {
    return await post('/api/warehouse/work/outbound/complete/$workOrderId');
  }

  // ===== 外单通 - 仓端接口 =====

  /// 外单拣货列表（支持状态筛选：null=全部, 1=待拣货, 2=拣货中, 3=已发货, 4=异常）
  Future<Map<String, dynamic>> getExternalPickingList({String? status}) async {
    final params = <String, String>{};
    if (status != null && status != 'all') params['status'] = status;
    return await get('/api/warehouse/external/picking/list', queryParams: params.isEmpty ? null : params);
  }

  /// 开始拣货（status 1→2）
  Future<Map<String, dynamic>> startExternalPicking(int orderId) async {
    return await post('/api/warehouse/external/picking/start', body: {'orderId': orderId});
  }

  /// 外单拣货详情
  Future<Map<String, dynamic>> getExternalPickingDetail(int workOrderId) async {
    return await get('/api/warehouse/external/picking/detail/$workOrderId');
  }

  /// 完成外单发货（填写物流单号），body: {orderId, logisticsCompany, logisticsNo}
  Future<Map<String, dynamic>> completeExternalPicking(Map<String, dynamic> data) async {
    return await post('/api/warehouse/external/picking/complete', body: data);
  }

  /// 外单异常上报，body: {orderId, reason, note}
  Future<Map<String, dynamic>> reportExternalException(Map<String, dynamic> data) async {
    return await post('/api/warehouse/external/picking/exception', body: data);
  }

  /// 外单统计数据
  Future<Map<String, dynamic>> getExternalStatistics({String period = 'month'}) async {
    return await get('/api/warehouse/external/statistics', queryParams: {'period': period});
  }

  /// 外单接单设置（是否开启接外单）
  Future<Map<String, dynamic>> updateExternalSettings(Map<String, dynamic> data) async {
    return await put('/api/warehouse/external/settings', body: data);
  }

  // ===== 外单通 - 品牌端接口 =====

  /// 品牌方外单列表
  Future<Map<String, dynamic>> getBrandExternalOrders({String? status, int page = 1, int size = 20}) async {
    final params = <String, String>{'page': page.toString(), 'size': size.toString()};
    if (status != null && status != 'all') params['status'] = status;
    return await get('/api/brand/external/order/list', queryParams: params);
  }

  /// 取消外单
  Future<Map<String, dynamic>> cancelExternalOrder(int externalOrderId) async {
    return await post('/api/brand/external/order/cancel', body: {'orderId': externalOrderId});
  }

  /// 获取导入批次列表
  Future<Map<String, dynamic>> getExternalBatchList({int page = 1}) async {
    return await get('/api/brand/external/batch/list', queryParams: {'page': page.toString()});
  }

  /// 查询批次处理状态
  Future<Map<String, dynamic>> getExternalBatchStatus(String batchNo) async {
    return await get('/api/brand/external/batch/status', queryParams: {'batchNo': batchNo});
  }

  /// 获取品牌方 API Key
  Future<Map<String, dynamic>> getBrandExternalApiKey() async {
    return await get('/api/brand/external/api-key');
  }

  /// 批量导入外单（提交解析好的订单列表）
  Future<Map<String, dynamic>> importExternalOrders(
      List<Map<String, dynamic>> orders) async {
    return await post('/api/brand/external/batch/import',
        body: {'orders': orders});
  }
}
