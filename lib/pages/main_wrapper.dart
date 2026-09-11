import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../config/constants.dart';
import 'consumer/home.dart';
import 'consumer/cart.dart';
import 'consumer/orders.dart';
import 'consumer/profile.dart';
import 'warehouse/workbench.dart';
import 'warehouse/inventory.dart' show WarehouseInventoryPage, EarningsPage;
import 'warehouse/profile_warehouse.dart';
import 'brand/products.dart';
import 'brand/replenishment.dart';
import 'brand/brand_orders.dart';
import 'brand/dashboard.dart';
import 'brand/complaint_brand.dart';
import 'brand/external_orders.dart';

/// 主容器页面（核心：根据 role 动态切换 TabBar 和页面）
class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;

  // ==================== 消费者 TabBar ====================
  static const _consumerTabs = [
    BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: '首页'),
    BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), activeIcon: Icon(Icons.shopping_cart), label: '购物车'),
    BottomNavigationBarItem(icon: Icon(Icons.receipt_outlined), activeIcon: Icon(Icons.receipt), label: '订单'),
    BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: '我的'),
  ];

  static final _consumerPages = [
    const ConsumerHomePage(),
    const CartPage(),
    const OrdersPage(),
    const ConsumerProfilePage(),
  ];

  // ==================== 仓主 TabBar ====================
  static const _warehouseTabs = [
    BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: '工作台'),
    BottomNavigationBarItem(icon: Icon(Icons.inventory_outlined), activeIcon: Icon(Icons.inventory), label: '库存'),
    BottomNavigationBarItem(icon: Icon(Icons.attach_money_outlined), activeIcon: Icon(Icons.attach_money), label: '收益'),
    BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: '我的'),
  ];

  static final _warehousePages = [
    const WorkbenchPage(),
    const WarehouseInventoryPage(),
    const EarningsPage(),
    const WarehouseProfilePage(),
  ];

  // ==================== 品牌方 TabBar ====================
  static const _brandTabs = [
    BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), activeIcon: Icon(Icons.inventory_2), label: '商品'),
    BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined), activeIcon: Icon(Icons.local_shipping), label: '铺货'),
    BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: '订单'),
    BottomNavigationBarItem(icon: Icon(Icons.link_outlined), activeIcon: Icon(Icons.link), label: '外单'),
    BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: '数据'),
  ];

  static final _brandPages = [
    const BrandProductsPage(),
    const ReplenishmentPage(),
    const BrandOrdersPage(),
    const BrandExternalOrdersPage(),
    const DashboardPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AppState>().role;
    final themeColor = Color(AppConstants.themeColors[role] ?? 0xFFFF6B35);

    List<BottomNavigationBarItem> tabs;
    List<Widget> pages;

    switch (role) {
      case AppConstants.roleWarehouse:
        tabs = _warehouseTabs;
        pages = _warehousePages;
        break;
      case AppConstants.roleBrand:
        tabs = _brandTabs;
        pages = _brandPages;
        break;
      default: // 消费者
        tabs = _consumerTabs;
        pages = _consumerPages;
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex.clamp(0, pages.length - 1),
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex.clamp(0, tabs.length - 1),
        onTap: (index) => setState(() => _currentIndex = index),
        items: tabs,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: themeColor,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        elevation: 12,
      ),
    );
  }
}
