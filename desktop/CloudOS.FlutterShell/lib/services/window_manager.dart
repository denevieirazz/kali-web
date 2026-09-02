import 'dart:async';

import 'package:flutter/material.dart';

import '../models/window_model.dart';
import 'app_registry.dart';
import 'session_service.dart';

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

class WindowManager extends ChangeNotifier {
  final List<CloudWindow> _windows = <CloudWindow>[];
  int _nextWindowSeq = 1;
  SnapRegion _activeSnapPreview = SnapRegion.none;
  int _activeWorkspace = 1;

  List<CloudWindow> get windows => List<CloudWindow>.unmodifiable(_windows);
  SnapRegion get activeSnapPreview => _activeSnapPreview;
  int get activeWorkspace => _activeWorkspace;

  List<CloudWindow> get currentWorkspaceWindows =>
      _windows.where((w) => w.workspaceIndex == _activeWorkspace).toList();

  CloudWindow? get focusedWindow {
    final cur = currentWorkspaceWindows;
    for (int i = cur.length - 1; i >= 0; i--) {
      if (!cur[i].minimized && cur[i].focused) return cur[i];
    }
    return null;
  }

  bool isAppOpen(String appId) => _windows.any((w) => w.appId == appId);

  bool isAppFocused(String appId) {
    final f = focusedWindow;
    return f != null && f.appId == appId;
  }

  bool isAppMinimized(String appId) {
    final list = _windows.where((w) => w.appId == appId).toList();
    if (list.isEmpty) return false;
    return list.every((w) => w.minimized);
  }

  CloudWindow? getWindowById(String id) {
    for (final w in _windows) {
      if (w.id == id) return w;
    }
    return null;
  }

  void setWorkspace(int index) {
    if (index < 1 || index > 4 || index == _activeWorkspace) return;
    _activeWorkspace = index;

    final cur = currentWorkspaceWindows;
    for (final w in cur) {
      w.focused = false;
    }
    for (int i = cur.length - 1; i >= 0; i--) {
      if (!cur[i].minimized) {
        cur[i].focused = true;
        break;
      }
    }

    _persistSession();
    notifyListeners();
  }

  void moveWindowToWorkspace(String id, int targetWorkspace) {
    final win = getWindowById(id);
    if (win == null || targetWorkspace < 1 || targetWorkspace > 4) return;

    final wasCurrent = win.workspaceIndex == _activeWorkspace;
    win.workspaceIndex = targetWorkspace;
    win.focused = false;

    if (wasCurrent) {
      final cur = currentWorkspaceWindows;
      for (int i = cur.length - 1; i >= 0; i--) {
        if (!cur[i].minimized) {
          cur[i].focused = true;
          break;
        }
      }
    }

    _persistSession();
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
    final def = AppRegistry.findById(appId);

    // WindowManager is only for CloudOS-hosted surfaces. External or unknown
    // applications must go through the typed Broker launch path instead of
    // becoming a fake placeholder window.
    if (def == null || !def.isInternal) return;

    if (def.isSingleton) {
      final existingIndex = _windows.indexWhere((w) => w.appId == appId);
      if (existingIndex != -1) {
        final existing = _windows[existingIndex];
        if (existing.workspaceIndex != _activeWorkspace) {
          existing.workspaceIndex = _activeWorkspace;
        }
        existing.minimized = false;
        focusWindow(existing.id);
        return;
      }
    }

    final winTitle = title ?? def.name;
    final winIcon = icon ?? def.icon;
    final winWidth = width ?? def.defaultWidth;
    final winHeight = height ?? def.defaultHeight;

    final curWins = currentWorkspaceWindows;
    final cascadeIndex = curWins.length % 6;
    final startX = 80.0 + (cascadeIndex * 36.0);
    final startY = 40.0 + (cascadeIndex * 30.0);
    final id = 'win_${_nextWindowSeq++}_$appId';

    for (final w in curWins) {
      w.focused = false;
    }

    _windows.add(
      CloudWindow(
        id: id,
        appId: appId,
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
      ),
    );

    _persistSession();
    notifyListeners();
  }

  void closeWindow(String id) {
    final index = _windows.indexWhere((w) => w.id == id);
    if (index == -1) return;

    _windows.removeAt(index);
    final cur = currentWorkspaceWindows;
    for (final w in cur) {
      w.focused = false;
    }
    for (int i = cur.length - 1; i >= 0; i--) {
      if (!cur[i].minimized) {
        cur[i].focused = true;
        break;
      }
    }
    _persistSession();
    notifyListeners();
  }

  void focusWindow(String id) {
    final index = _windows.indexWhere((w) => w.id == id);
    if (index == -1) return;

    final target = _windows.removeAt(index);
    if (target.workspaceIndex != _activeWorkspace) {
      _activeWorkspace = target.workspaceIndex.clamp(1, 4);
    }

    for (final w in _windows) {
      if (w.workspaceIndex == _activeWorkspace) w.focused = false;
    }
    target.focused = true;
    target.minimized = false;
    _windows.add(target);
    _persistSession();
    notifyListeners();
  }

  void minimizeWindow(String id) {
    final win = getWindowById(id);
    if (win == null) return;

    win.minimized = true;
    win.focused = false;
    final cur = currentWorkspaceWindows;
    for (int i = cur.length - 1; i >= 0; i--) {
      if (!cur[i].minimized) {
        cur[i].focused = true;
        break;
      }
    }
    _persistSession();
    notifyListeners();
  }

  void toggleMaximizeWindow(String id, Size viewportSize) {
    final win = getWindowById(id);
    if (win == null) return;

    if (win.maximized) {
      win.maximized = false;
      win.x = win.previousX;
      win.y = win.previousY;
      win.width = win.previousWidth;
      win.height = win.previousHeight;
    } else {
      win.previousX = win.x;
      win.previousY = win.y;
      win.previousWidth = win.width;
      win.previousHeight = win.height;
      win.maximized = true;
      win.x = 0;
      win.y = 0;
      win.width = viewportSize.width;
      win.height = mathMax(0.0, viewportSize.height - 48.0);
    }
    focusWindow(id);
  }

  void snapWindowLeft(String id, Size viewportSize) {
    final win = getWindowById(id);
    if (win == null) return;
    _rememberRestoreBounds(win);
    win.maximized = false;
    win.x = 0;
    win.y = 0;
    win.width = viewportSize.width / 2.0;
    win.height = mathMax(0.0, viewportSize.height - 48.0);
    focusWindow(id);
  }

  void snapWindowRight(String id, Size viewportSize) {
    final win = getWindowById(id);
    if (win == null) return;
    _rememberRestoreBounds(win);
    win.maximized = false;
    win.x = viewportSize.width / 2.0;
    win.y = 0;
    win.width = viewportSize.width / 2.0;
    win.height = mathMax(0.0, viewportSize.height - 48.0);
    focusWindow(id);
  }

  void _rememberRestoreBounds(CloudWindow win) {
    win.previousX = win.x;
    win.previousY = win.y;
    win.previousWidth = win.width;
    win.previousHeight = win.height;
  }

  void moveWindow(String id, Offset delta, Size viewportSize) {
    final win = getWindowById(id);
    if (win == null || win.maximized) return;

    final maxAvailableY = mathMax(0.0, viewportSize.height - 88.0);
    final maxX = mathMax(0.0, viewportSize.width - 100.0);
    win.x = (win.x + delta.dx).clamp(0.0, maxX);
    win.y = (win.y + delta.dy).clamp(0.0, maxAvailableY);

    if (win.y <= 6.0) {
      _activeSnapPreview = SnapRegion.top;
    } else if (win.x <= 8.0) {
      _activeSnapPreview = SnapRegion.left;
    } else if (win.x + win.width >= viewportSize.width - 8.0) {
      _activeSnapPreview = SnapRegion.right;
    } else {
      _activeSnapPreview = SnapRegion.none;
    }

    notifyListeners();
  }

  void onWindowDragEnd(String id, Size viewportSize) {
    final win = getWindowById(id);
    if (win != null && !win.maximized) {
      if (_activeSnapPreview == SnapRegion.top) {
        toggleMaximizeWindow(id, viewportSize);
      } else if (_activeSnapPreview == SnapRegion.left) {
        snapWindowLeft(id, viewportSize);
      } else if (_activeSnapPreview == SnapRegion.right) {
        snapWindowRight(id, viewportSize);
      }
    }
    _activeSnapPreview = SnapRegion.none;
    _persistSession();
    notifyListeners();
  }

  void resizeWindow(
    String id,
    double newWidth,
    double newHeight,
    Size viewportSize,
  ) {
    final win = getWindowById(id);
    if (win == null || win.maximized) return;

    final maxW = mathMax(win.minWidth, viewportSize.width - win.x);
    final maxH = mathMax(win.minHeight, (viewportSize.height - 48.0) - win.y);
    win.width = newWidth.clamp(win.minWidth, maxW);
    win.height = newHeight.clamp(win.minHeight, maxH);
    _persistSession();
    notifyListeners();
  }

  void toggleWindow(String appId) {
    final matching = _windows
        .where(
          (w) => w.appId == appId && w.workspaceIndex == _activeWorkspace,
        )
        .toList();
    if (matching.isEmpty) {
      openWindow(appId);
      return;
    }

    final f = focusedWindow;
    if (f != null && f.appId == appId) {
      minimizeWindow(f.id);
    } else {
      focusWindow(matching.last.id);
    }
  }

  void ensureWithinBounds(Size viewportSize) {
    final availableHeight = mathMax(280.0, viewportSize.height - 48.0);
    final availableWidth = mathMax(360.0, viewportSize.width);
    final maxTitleY = mathMax(0.0, availableHeight - 40.0);

    for (final win in _windows) {
      if (!win.maximized) {
        win.width = win.width.clamp(win.minWidth, availableWidth);
        win.height = win.height.clamp(win.minHeight, availableHeight);
        win.x = win.x.clamp(0.0, mathMax(0.0, viewportSize.width - 100.0));
        win.y = win.y.clamp(0.0, maxTitleY);
      }
    }
  }

  void restoreSavedWindows(
    List<Map<String, dynamic>> savedList,
    int savedWorkspace,
  ) {
    _windows.clear();
    _activeWorkspace = savedWorkspace.clamp(1, 4);
    _nextWindowSeq = 1;

    for (final item in savedList) {
      final appId = item['appId'] as String? ?? '';
      final def = AppRegistry.findById(appId);
      if (def == null || !def.isInternal) continue;

      final rawParams = item['customParams'];
      final customParams = rawParams is Map
          ? Map<String, dynamic>.from(rawParams)
          : const <String, dynamic>{};
      final workspace = ((item['workspaceIndex'] as num?)?.toInt() ?? 1)
          .clamp(1, 4);
      final id = item['id'] as String? ?? 'win_${_nextWindowSeq++}_$appId';

      final seqMatch = RegExp(r'^win_(\d+)_').firstMatch(id);
      if (seqMatch != null) {
        final parsed = int.tryParse(seqMatch.group(1) ?? '');
        if (parsed != null && parsed >= _nextWindowSeq) {
          _nextWindowSeq = parsed + 1;
        }
      }

      _windows.add(
        CloudWindow(
          id: id,
          appId: appId,
          title: item['title'] as String? ?? def.name,
          icon: def.icon,
          x: (item['x'] as num?)?.toDouble() ?? 100.0,
          y: (item['y'] as num?)?.toDouble() ?? 60.0,
          width: (item['width'] as num?)?.toDouble() ?? def.defaultWidth,
          height: (item['height'] as num?)?.toDouble() ?? def.defaultHeight,
          minimized: item['minimized'] as bool? ?? false,
          maximized: item['maximized'] as bool? ?? false,
          workspaceIndex: workspace,
          focused: false,
          customParams: Map<String, dynamic>.unmodifiable(customParams),
          previousX: (item['previousX'] as num?)?.toDouble() ?? 100.0,
          previousY: (item['previousY'] as num?)?.toDouble() ?? 60.0,
          previousWidth:
              (item['previousWidth'] as num?)?.toDouble() ?? def.defaultWidth,
          previousHeight:
              (item['previousHeight'] as num?)?.toDouble() ?? def.defaultHeight,
        ),
      );
    }

    final cur = currentWorkspaceWindows;
    for (final w in cur) {
      w.focused = false;
    }

    CloudWindow? preferred;
    for (final item in savedList) {
      if (item['focused'] != true) continue;
      final id = item['id'] as String?;
      if (id == null) continue;
      final candidate = getWindowById(id);
      if (candidate != null &&
          candidate.workspaceIndex == _activeWorkspace &&
          !candidate.minimized) {
        preferred = candidate;
        break;
      }
    }
    if (preferred != null) {
      preferred.focused = true;
    } else {
      for (int i = cur.length - 1; i >= 0; i--) {
        if (!cur[i].minimized) {
          cur[i].focused = true;
          break;
        }
      }
    }

    notifyListeners();
  }

  void _persistSession() {
    unawaited(
      SessionService.instance.saveSession(
        windows: _windows,
        activeWorkspace: _activeWorkspace,
      ),
    );
  }
}

double mathMax(double a, double b) => a > b ? a : b;
