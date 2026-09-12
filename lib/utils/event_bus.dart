import 'package:event_bus/event_bus.dart';

/// 全局事件总线（用于组件间通信）
final EventBus eventBus = EventBus();

/// 订单状态更新事件
class OrderStatusUpdateEvent {
  final int orderId;
  final String status;

  OrderStatusUpdateEvent(this.orderId, this.status);
}

/// 仓主新订单事件（通过WebSocket接收）
class NewPickingOrderEvent {
  final int workOrderId;

  NewPickingOrderEvent(this.workOrderId);
}

/// 仓主新入库事件
class NewInboundOrderEvent {
  final int workOrderId;

  NewInboundOrderEvent(this.workOrderId);
}

/// 购物车更新事件
class CartUpdateEvent {
  final int totalCount;

  CartUpdateEvent(this.totalCount);
}

/// 登出事件
class LogoutEvent {}
