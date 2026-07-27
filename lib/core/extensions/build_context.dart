import 'package:flutter/material.dart';

/// GlassAppBar 的默认高度。
const double _appBarHeight = 44;

/// GlassTabBar.bottom 的默认高度。
const double _bottomBarHeight = 64;

/// 宽度达到该值时用侧边栏取代底部标签栏。
const double _sidebarBreakpoint = 600;

/// 宽度达到该值时侧边栏展开显示文字。
const double _expandedSidebarBreakpoint = 900;

/// 低于该高度时收紧纵向留白，典型场景是手机横屏。
const double _compactHeightBreakpoint = 500;

// 方向判断用 GetX 的 `context.isLandscape`：这里再定义一个同名成员会让两个
// 扩展产生歧义，编译期就会报 ambiguous_extension_member_access。
extension BuildContextScreenExtension on BuildContext {
  /// 可用高度偏小，需要收紧纵向留白。
  bool get isCompactHeight =>
      MediaQuery.sizeOf(this).height < _compactHeightBreakpoint;

  /// 是否用侧边栏导航。
  bool get useSidebarNavigation =>
      MediaQuery.sizeOf(this).width >= _sidebarBreakpoint;

  /// 侧边栏是否展开显示文字。
  bool get useExpandedSidebar =>
      MediaQuery.sizeOf(this).width >= _expandedSidebarBreakpoint;

  /// 带 GlassAppBar 的页面的内容留白。
  ///
  /// 顶部按实际安全区加顶栏高度计算，而不是写死一个按竖屏调好的值：横屏时
  /// 状态栏安全区收缩为 0，留白也随之收敛，不会把本就不多的高度吃掉。
  /// 左右会补上横屏刘海一侧的安全区。
  EdgeInsets pageContentPadding({double horizontal = 20, double bottom = 24}) {
    final safeArea = MediaQuery.paddingOf(this);
    return EdgeInsets.fromLTRB(
      horizontal + safeArea.left,
      safeArea.top + _appBarHeight + (isCompactHeight ? 12 : 24),
      horizontal + safeArea.right,
      bottom + safeArea.bottom,
    );
  }

  /// 首页各标签页的内容留白：顶部没有导航栏，底部只在真正显示标签栏时让位。
  EdgeInsets homeContentPadding({double horizontal = 20}) {
    final safeArea = MediaQuery.paddingOf(this);
    return EdgeInsets.fromLTRB(
      horizontal + safeArea.left,
      safeArea.top + (isCompactHeight ? 12 : 28),
      horizontal + safeArea.right,
      safeArea.bottom + (useSidebarNavigation ? 16 : _bottomBarHeight + 12),
    );
  }
}
