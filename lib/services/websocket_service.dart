import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import '../config/constants.dart';
import '../utils/storage.dart';
import '../utils/event_bus.dart';

/// WebSocket 服务（基于 STOMP 协议）
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  StompClient? _client;
  bool _connected = false;

  /// 连接 WebSocket（登录成功后调用）
  void connect() {
    final token = StorageUtil.getToken();
    final role = StorageUtil.getRole();
    if (token == null) return;

    // SockJS 依赖 dart:html，仅 Web 可用；Android/iOS 用原生 WebSocket
    if (kIsWeb) {
      _client = StompClient(
        config: StompConfig.SockJS(
          url: AppConstants.wsUrl.replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://'),
          onConnect: _onConnect,
          onDisconnect: _onDisconnect,
          onStompError: (frame) => print('STOMP 错误: ${frame.body}'),
          onWebSocketError: (error) => print('WebSocket 错误: $error'),
          webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
          connectionTimeout: const Duration(seconds: 10),
        ),
      );
    } else {
      // Android / iOS：原生 WSS 连接
      _client = StompClient(
        config: StompConfig(
          url: AppConstants.wsUrl,
          onConnect: _onConnect,
          onDisconnect: _onDisconnect,
          onStompError: (frame) => print('STOMP 错误: ${frame.body}'),
          onWebSocketError: (error) => print('WebSocket 错误: $error'),
          stompConnectHeaders: {'Authorization': 'Bearer $token'},
          webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
          connectionTimeout: const Duration(seconds: 10),
          reconnectDelay: const Duration(seconds: 5),
        ),
      );
    }

    try {
      _client!.activate();
    } catch (e) {
      print('WebSocket 连接失败: $e');
    }
  }

  /// 断开连接（登出时调用）
  void disconnect() {
    _client?.deactivate();
    _connected = false;
  }

  /// 连接成功回调
  void _onConnect(StompFrame frame) {
    _connected = true;
    print('WebSocket 连接成功');

    final role = StorageUtil.getRole();
    final userId = StorageUtil.getUserId();
    final warehouseId = StorageUtil.getWarehouseId();

    // 根据角色订阅不同频道
    if (role == AppConstants.roleWarehouse && warehouseId != null) {
      // 仓主订阅仓库频道
      _client!.subscribe(
        destination: '/topic/warehouse/$warehouseId',
        callback: _onWarehouseMessage,
      );
      print('订阅仓库频道: /topic/warehouse/$warehouseId');
    }

    if (userId != null) {
      // 所有用户订阅个人频道（用于订单状态更新）
      _client!.subscribe(
        destination: '/topic/user/$userId',
        callback: _onUserMessage,
      );
      print('订阅用户频道: /topic/user/$userId');
    }
  }

  /// 断开连接回调
  void _onDisconnect(StompFrame frame) {
    _connected = false;
    print('WebSocket 已断开');
  }

  /// 处理仓库消息
  void _onWarehouseMessage(StompFrame frame) {
    if (frame.body == null) return;
    try {
      final msg = jsonDecode(frame.body!) as Map<String, dynamic>;
      final type = msg['type'] as String;
      final workOrderId = msg['workOrderId'] as int;

      print('收到仓库消息: type=$type, workOrderId=$workOrderId');

      if (type == 'NEW_PICKING_ORDER') {
        eventBus.fire(NewPickingOrderEvent(workOrderId));
      } else if (type == 'NEW_INBOUND_ORDER') {
        eventBus.fire(NewInboundOrderEvent(workOrderId));
      }
    } catch (e) {
      print('解析仓库消息失败: $e');
    }
  }

  /// 处理用户消息
  void _onUserMessage(StompFrame frame) {
    if (frame.body == null) return;
    try {
      final msg = jsonDecode(frame.body!) as Map<String, dynamic>;
      final type = msg['type'] as String;

      print('收到用户消息: type=$type');

      if (type == 'ORDER_STATUS_UPDATE') {
        final orderId = msg['orderId'] as int;
        final status = msg['status'] as String;
        eventBus.fire(OrderStatusUpdateEvent(orderId, status));
      }
    } catch (e) {
      print('解析用户消息失败: $e');
    }
  }

  bool get isConnected => _connected;
}
