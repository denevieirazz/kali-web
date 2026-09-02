import 'dart:async';

import 'package:flutter/material.dart';

import '../models/window_model.dart';
import 'app_registry.dart';
import 'session_service.dart';
import 'window_geometry.dart';
import 'window_mru.dart';

enum SnapRegion {
  none,
  top,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// CloudOS WindowManager V23.
///
/// Render z-order and task-switch MRU are deliberately separate. Geometry is
/// delegated to WindowGeometryEngine and persistence is debounced while the
/// SessionService serializes all durable writes.
class WindowManager extends ChangeNotifier {
  WindowManager({
    WindowGeometryEngine geometryEngine = const WindowGeometryEngine(),
    Duration persistenceDebounce = const Duration(milliseconds: 180),
    SessionService? sessionService,
  })  : _geometryEngine = geometryEngine,
        _persistenceDebounce = persistenceDebounce,
        _sessionService = sessionService ?? SessionService.instance;

  final List<CloudWindow> _windows = <CloudWindow>[];
  final WindowMruTracker _mru = WindowMruTracker();
  final WindowGeometryEngine _geometryEngine;
  final Duration _persistenceDebounce;
  final SessionService _sessionService;

  int _nextWindowSeq = 1;
  SnapRegion _activeSnapPreview = SnapRegion.none;
  int _activeWorkspace = 1;
  Timer? _persistenceTimer;
  bool _disposed = false;
  bool _showDesktopActive = false;
  final Set<String> _showDesktopMinimized = <String>{};

  List<CloudWindow> get windows => List<CloudWindow>.unmodifiable(_windows);
  SnapRegion get activeSnapPreview => _activeSnapPreview;
  int get activeWorkspace => _activeWorkspace;
  bool get showDesktopActive => _showDesktopActive;
  List<String> get mruWindowIds => _mru.ids;

  List<CloudWindow> get currentWorkspaceWindows => _windows
      .where((window) => window.workspaceIndex == _activeWorkspace)
      .toList(growable: false);

  /// Includes minimized windows and orders them by actual focus recency.
  List<CloudWindow> get altTabWindows =>
      _mru.orderedForWorkspace(_windows, _activeWorkspace);

  CloudWindow? get focusedWindow {
    final current = currentWorkspaceWindows;
    for (var index = current.length - 1; index >= 0; index--) {
      final window = current[index];
      if (!window.minimized && window.focused) return window;
    }
    return null;
  }

  bool isAppOpen(String appId) =>
      _windows.any((window) => window.appId == appId);

  bool isAppFocused(String appId) {
    final focused = focusedWindow;
    return focused != null && focused.appId == appId;
  }

  bool isAppMinimized(String appId) {
    final matching = _windows.where((window) => window.appId == appId).toList();
    return matching.isNotEmpty && matching.every((window) => window.minimized);
  }

  CloudWindow? getWindowById(String id) {
    for (final window in _windows) {
      if (window.id == id) return window;
    }
    return null;
  }

  void setWorkspace(int index) {
    if (_disposed || index < 1 || index > 4 || index == _activeWorkspace) {
      return;
    }
    _activeWorkspace = index;
    _showDesktopActive = false;
    _showDesktopMinimized.clear();
    _focusBestWindowInActiveWorkspace(touchMru: false);
    _schedulePersistence(immediate: true);
    notifyListeners();
  }

  void moveWindowToWorkspace(String id, int targetWorkspace) {
    final window = getWindowById(id);
    if (window == null || targetWorkspace < 1 || targetWorkspace > 4) return;
    final wasCurrent = window.workspaceIndex == _activeWorkspace;
    window.workspaceIndex = targetWorkspace;
    window.focused = false;
    if (wasCurrent) _focusBestWindowInActiveWorkspace(touchMru: false);
    _schedulePersistence(immediate: true);
    notifyListeners();
  }

  void openWindow(
    String appId, {
    String? title,
    IconData? icon,
    double? width,
    double? height,
    Map<String, dynamic>? params,
  }) {
    if (_disposed) return;
    final definition = AppRegistry.findById(appId);
    if (definition == null || !definition.isInternal) return;

    if (definition.isSingleton) {
      final existingIndex = _windows.indexWhere(
        (window) => window.appId == definition.id,
      );
      if (existingIndex != -1) {
        final existing = _windows[existingIndex];
        if (params != null && params.isNotEmpty) {
          final merged = <String, dynamic>{
            ...existing.customParams,
            ...params,
          };
          _windows[existingIndex] = existing.copyWith(
            customParams: Map<String, dynamic>.unmodifiable(merged),
          );
        }
        final refreshed = _windows[existingIndex];
        if (refreshed.workspaceIndex != _activeWorkspace) {
          refreshed.workspaceIndex = _activeWorkspace;
        }
        refreshed.minimized = false;
        focusWindow(refreshed.id);
        return;
      }
    }

    final winTitle = title ?? definition.name;
    final winIcon = icon ?? definition.icon;
    final winWidth = width ?? definition.defaultWidth;
    final winHeight = height ?? definition.defaultHeight;
    final current = currentWorkspaceWindows;
    final cascadeIndex = current.length % 7;
    final startX = 72.0 + (cascadeIndex * 34.0);
    final startY = 34.0 + (cascadeIndex * 28.0);
    final id = 'win_${_nextWindowSeq++}_${definition.id}';

    for (final window in current) {
      window.focused = false;
    }

    final created = CloudWindow(
      id: id,
      appId: definition.id,
      title: winTitle,
      icon: winIcon,
      x: startX,
      y: startY,
      width: winWidth,
      height: winHeight,
      focused: true,
      minimized: false,
      maximized: false,
      workspaceIndex: _activeWorkspace,
      customParams: Map<String, dynamic>.unmodifiable(
        params ?? const <String, dynamic>{},
      ),
      previousX: startX,
      previousY: startY,
      previousWidth: winWidth,
      previousHeight: winHeight,
    );
    _windows.add(created);
    _mru.touch(id);
    _showDesktopActive = false;
    _schedulePersistence(immediate: true);
    notifyListeners();
  }

  void closeWindow(String id) {
    final index = _windows.indexWhere((window) => window.id == id);
    if (index == -1) return;
    _windows.removeAt(index);
    _mru.remove(id);
    _showDesktopMinimized.remove(id);
    _focusBestWindowInActiveWorkspace(touchMru: false);
    _schedulePersistence(immediate: true);
    notifyListeners();
  }

  void focusWindow(String id) {
    final index = _windows.indexWhere((window) => window.id == id);
    if (index == -1) return;

    final target = _windows.removeAt(index);
    if (target.workspaceIndex != _activeWorkspace) {
      _activeWorkspace = target.workspaceIndex.clamp(1, 4).toInt();
    }
    for (final window in _windows) {
      if (window.workspaceIndex == _activeWorkspace) window.focused = false;
    }
    target.focused = true;
    target.minimized = false;
    _windows.add(target);
    _mru.touch(target.id);
    _showDesktopActive = false;
    _showDesktopMinimized.remove(target.id);
    _schedulePersistence();
    notifyListeners();
  }

  void minimizeWindow(String id) {
    final window = getWindowById(id);
    if (window == null) return;
    window.minimized = true;
    window.focused = false;
    _focusBestWindowInActiveWorkspace(touchMru: false);
    _schedulePersistence();
    notifyListeners();
  }

  void restoreWindow(String id) {
    final window = getWindowById(id);
    if (window == null) return;
    window.minimized = false;
    focusWindow(id);
  }

  void toggleMaximizeWindow(String id, Size viewportSize) {
    final window = getWindowById(id);
    if (window == null) return;
    if (window.maximized) {
      window.maximized = false;
      window.x = window.previousX;
      window.y = window.previousY;
      window.width = window.previousWidth;
      window.height = window.previousHeight;
    } else {
      _rememberRestoreBounds(window);
      _applyGeometry(
        window,
        _geometryEngine.geometryForSnap(
          target: WindowSnapTarget.maximize,
          viewport: viewportSize,
        ),
      );
      window.maximized = true;
    }
    focusWindow(id);
  }

  void snapWindowLeft(String id, Size viewportSize) =>
      _snapWindow(id, WindowSnapTarget.left, viewportSize);

  void snapWindowRight(String id, Size viewportSize) =>
      _snapWindow(id, WindowSnapTarget.right, viewportSize);

  void snapWindowTopLeft(String id, Size viewportSize) =>
      _snapWindow(id, WindowSnapTarget.topLeft, viewportSize);

  void snapWindowTopRight(String id, Size viewportSize) =>
      _snapWindow(id, WindowSnapTarget.topRight, viewportSize);

  void snapWindowBottomLeft(String id, Size viewportSize) =>
      _snapWindow(id, WindowSnapTarget.bottomLeft, viewportSize);

  void snapWindowBottomRight(String id, Size viewportSize) =>
      _snapWindow(id, WindowSnapTarget.bottomRight, viewportSize);

  void _snapWindow(String id, WindowSnapTarget target, Size viewportSize) {
    final window = getWindowById(id);
    if (window == null || target == WindowSnapTarget.none) return;
    _rememberRestoreBounds(window);
    _applyGeometry(
      window,
      _geometryEngine.geometryForSnap(target: target, viewport: viewportSize),
    );
    window.maximized = target == WindowSnapTarget.maximize;
    focusWindow(id);
  }

  void _rememberRestoreBounds(CloudWindow window) {
    if (window.maximized) return;
    window.previousX = window.x;
    window.previousY = window.y;
    window.previousWidth = window.width;
    window.previousHeight = window.height;
  }

  void moveWindow(String id, Offset delta, Size viewportSize) {
    final window = getWindowById(id);
    if (window == null || window.maximized) return;
    final moved = _geometryEngine.moveBy(
      geometry: _geometry(window),
      delta: delta,
      viewport: viewportSize,
    );
    _applyGeometry(window, moved);
    final target = _geometryEngine.detectSnapTarget(
      geometry: moved,
      viewport: viewportSize,
    );
    _activeSnapPreview = _snapRegion(target);
    // Pointer-move state is deliberately not persisted every frame.
    notifyListeners();
  }

  void onWindowDragEnd(String id, Size viewportSize) {
    final window = getWindowById(id);
    if (window != null && !window.maximized) {
      final target = _targetForRegion(_activeSnapPreview);
      if (target == WindowSnapTarget.maximize) {
        toggleMaximizeWindow(id, viewportSize);
      } else if (target != WindowSnapTarget.none) {
        _snapWindow(id, target, viewportSize);
      }
    }
    _activeSnapPreview = SnapRegion.none;
    _schedulePersistence(immediate: true);
    notifyListeners();
  }

  void resizeWindow(
    String id,
    double newWidth,
    double newHeight,
    Size viewportSize,
  ) {
    final window = getWindowById(id);
    if (window == null || window.maximized) return;
    final resized = _geometryEngine.resizeFromBottomRight(
      geometry: _geometry(window),
      requestedWidth: newWidth,
      requestedHeight: newHeight,
      viewport: viewportSize,
      minWidth: window.minWidth,
      minHeight: window.minHeight,
    );
    _applyGeometry(window, resized);
    _schedulePersistence();
    notifyListeners();
  }

  void toggleWindow(String appId) {
    final definition = AppRegistry.findById(appId);
    final normalizedId = definition?.id ?? appId;
    final matching = _windows
        .where(
          (window) => window.appId == normalizedId &&
              window.workspaceIndex == _activeWorkspace,
        )
        .toList(growable: false);
    if (matching.isEmpty) {
      openWindow(normalizedId);
      return;
    }
    final focused = focusedWindow;
    if (focused != null && focused.appId == normalizedId) {
      minimizeWindow(focused.id);
    } else {
      final ordered = _mru.orderedForWorkspace(matching, _activeWorkspace);
      focusWindow((ordered.isNotEmpty ? ordered.first : matching.last).id);
    }
  }

  /// Returns the ID that should be selected in task-switch UI without changing
  /// focus. Alt can remain held while the user cycles.
  String? cycleAltTab({
    String? currentId,
    bool forward = true,
  }) {
    return _mru.next(
      windows: _windows,
      workspace: _activeWorkspace,
      currentId: currentId,
      forward: forward,
    );
  }

  void toggleShowDesktop() {
    final current = currentWorkspaceWindows;
    if (!_showDesktopActive) {
      _showDesktopMinimized.clear();
      for (final window in current) {
        if (!window.minimized) {
          _showDesktopMinimized.add(window.id);
          window.minimized = true;
          window.focused = false;
        }
      }
      _showDesktopActive = true;
    } else {
      for (final id in _showDesktopMinimized.toList()) {
        final window = getWindowById(id);
        if (window != null && window.workspaceIndex == _activeWorkspace) {
          window.minimized = false;
        }
      }
      _showDesktopActive = false;
      _showDesktopMinimized.clear();
      _focusBestWindowInActiveWorkspace(touchMru: false);
    }
    _schedulePersistence(immediate: true);
    notifyListeners();
  }

  void ensureWithinBounds(Size viewportSize) {
    for (final window in _windows) {
      if (window.maximized) {
        _applyGeometry(
          window,
          _geometryEngine.geometryForSnap(
            target: WindowSnapTarget.maximize,
            viewport: viewportSize,
          ),
        );
        continue;
      }
      _applyGeometry(
        window,
        _geometryEngine.clampToViewport(
          geometry: _geometry(window),
          viewport: viewportSize,
          minWidth: window.minWidth,
          minHeight: window.minHeight,
        ),
      );
    }
  }

  void restoreSavedWindows(
    List<Map<String, dynamic>> savedList,
    int savedWorkspace, [
    List<String> savedMruWindowIds = const <String>[],
  ]) {
    _windows.clear();
    _mru.clear();
    _activeWorkspace = savedWorkspace.clamp(1, 4).toInt();
    _nextWindowSeq = 1;
    _showDesktopActive = false;
    _showDesktopMinimized.clear();

    final restoredSingletons = <String>{};
    final savedFocusedIds = <String>[];
    for (final item in savedList) {
      final rawAppId = item['appId'] as String? ?? '';
      final definition = AppRegistry.findById(rawAppId);
      if (definition == null || !definition.isInternal) continue;
      final appId = definition.id;
      if (definition.isSingleton && !restoredSingletons.add(appId)) continue;

      final rawParams = item['customParams'];
      final customParams = rawParams is Map
          ? Map<String, dynamic>.from(rawParams)
          : const <String, dynamic>{};
      final workspace = ((item['workspaceIndex'] as num?)?.toInt() ?? 1)
          .clamp(1, 4)
          .toInt();
      final id = item['id'] as String? ?? 'win_${_nextWindowSeq++}_$appId';
      final sequenceMatch = RegExp(r'^win_(\d+)_').firstMatch(id);
      if (sequenceMatch != null) {
        final parsed = int.tryParse(sequenceMatch.group(1) ?? '');
        if (parsed != null && parsed >= _nextWindowSeq) {
          _nextWindowSeq = parsed + 1;
        }
      }

      double number(String key, double fallback) {
        final value = item[key];
        if (value is! num) return fallback;
        final parsed = value.toDouble();
        return parsed.isFinite ? parsed : fallback;
      }

      final window = CloudWindow(
        id: id,
        appId: appId,
        title: item['title'] as String? ?? definition.name,
        icon: definition.icon,
        x: number('x', 100),
        y: number('y', 60),
        width: number('width', definition.defaultWidth),
        height: number('height', definition.defaultHeight),
        minimized: item['minimized'] as bool? ?? false,
        maximized: item['maximized'] as bool? ?? false,
        workspaceIndex: workspace,
        focused: false,
        customParams: Map<String, dynamic>.unmodifiable(customParams),
        previousX: number('previousX', 100),
        previousY: number('previousY', 60),
        previousWidth: number('previousWidth', definition.defaultWidth),
        previousHeight: number('previousHeight', definition.defaultHeight),
      );
      _windows.add(window);
      if (item['focused'] == true) savedFocusedIds.add(id);
    }

    _mru.restore(savedMruWindowIds, _windows);
    if (savedMruWindowIds.isEmpty) {
      _mru.restore(_windows.reversed.map((window) => window.id), _windows);
    }

    CloudWindow? preferred;
    for (final id in savedFocusedIds) {
      final candidate = getWindowById(id);
      if (candidate != null &&
          candidate.workspaceIndex == _activeWorkspace &&
          !candidate.minimized) {
        preferred = candidate;
        break;
      }
    }
    if (preferred != null) {
      for (final window in currentWorkspaceWindows) {
        window.focused = window.id == preferred.id;
      }
      _mru.touch(preferred.id);
    } else {
      _focusBestWindowInActiveWorkspace(touchMru: false);
    }

    notifyListeners();
  }

  Future<void> flushSession() async {
    _persistenceTimer?.cancel();
    _persistenceTimer = null;
    await _persistNow();
    await _sessionService.flush();
  }

  void _focusBestWindowInActiveWorkspace({required bool touchMru}) {
    final current = currentWorkspaceWindows;
    for (final window in current) {
      window.focused = false;
    }
    final ordered = _mru.orderedForWorkspace(_windows, _activeWorkspace);
    CloudWindow? candidate;
    for (final window in ordered) {
      if (!window.minimized) {
        candidate = window;
        break;
      }
    }
    if (candidate == null) {
      for (var index = current.length - 1; index >= 0; index--) {
        if (!current[index].minimized) {
          candidate = current[index];
          break;
        }
      }
    }
    if (candidate != null) {
      candidate.focused = true;
      if (touchMru) _mru.touch(candidate.id);
    }
  }

  void _schedulePersistence({bool immediate = false}) {
    if (_disposed) return;
    _persistenceTimer?.cancel();
    if (immediate) {
      unawaited(_persistNow());
      return;
    }
    _persistenceTimer = Timer(_persistenceDebounce, () {
      _persistenceTimer = null;
      if (!_disposed) unawaited(_persistNow());
    });
  }

  Future<void> _persistNow() {
    return _sessionService.saveSession(
      windows: _windows,
      activeWorkspace: _activeWorkspace,
      mruWindowIds: _mru.ids,
    );
  }

  WindowGeometry _geometry(CloudWindow window) => WindowGeometry(
        x: window.x,
        y: window.y,
        width: window.width,
        height: window.height,
      );

  void _applyGeometry(CloudWindow window, WindowGeometry geometry) {
    window.x = geometry.x;
    window.y = geometry.y;
    window.width = geometry.width;
    window.height = geometry.height;
  }

  SnapRegion _snapRegion(WindowSnapTarget target) => switch (target) {
        WindowSnapTarget.none => SnapRegion.none,
        WindowSnapTarget.maximize => SnapRegion.top,
        WindowSnapTarget.left => SnapRegion.left,
        WindowSnapTarget.right => SnapRegion.right,
        WindowSnapTarget.topLeft => SnapRegion.topLeft,
        WindowSnapTarget.topRight => SnapRegion.topRight,
        WindowSnapTarget.bottomLeft => SnapRegion.bottomLeft,
        WindowSnapTarget.bottomRight => SnapRegion.bottomRight,
      };

  WindowSnapTarget _targetForRegion(SnapRegion region) => switch (region) {
        SnapRegion.none => WindowSnapTarget.none,
        SnapRegion.top => WindowSnapTarget.maximize,
        SnapRegion.left => WindowSnapTarget.left,
        SnapRegion.right => WindowSnapTarget.right,
        SnapRegion.topLeft => WindowSnapTarget.topLeft,
        SnapRegion.topRight => WindowSnapTarget.topRight,
        SnapRegion.bottomLeft => WindowSnapTarget.bottomLeft,
        SnapRegion.bottomRight => WindowSnapTarget.bottomRight,
      };

  @override
  void dispose() {
    if (_disposed) return;
    _persistenceTimer?.cancel();
    _persistenceTimer = null;
    // Snapshot final state before ChangeNotifier teardown. SessionService owns
    // write serialization and can finish safely after this object is disposed.
    unawaited(_persistNow());
    _disposed = true;
    super.dispose();
  }
}

double mathMax(double a, double b) => a > b ? a : b;
