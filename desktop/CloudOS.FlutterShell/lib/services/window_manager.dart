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
      if (!cur[i].minimized && cur[i].focused) {
        return cur[i];
      }
    }
    return null;
  }

  bool isAppOpen(String appId) {
    return _windows.any((w) => w.appId == appId);
  }

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
    // Focar a primeira janela visível do novo workspace
    final cur = currentWorkspaceWindows;
    for (final w in cur) {
      w.focused = false;
    }
    if (cur.isNotEmpty) {
      cur.last.focused = true;
      cur.last.minimized = false;
    }
    _persistSession();
    notifyListeners();
  }

  void moveWindowToWorkspace(String id, int targetWorkspace) {
    final win = getWindowById(id);
    if (win != null && targetWorkspace >= 1 && targetWorkspace <= 4) {
      win.workspaceIndex = targetWorkspace;
      _persistSession();
      notifyListeners();
    }
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
    final isSingleton = def?.isSingleton ?? false;

    if (isSingleton) {
      final existingIndex = _windows.indexWhere((w) => w.appId == appId);
      if (existingIndex != -1) {
        final existing = _windows[existingIndex];
        if (existing.workspaceIndex != _activeWorkspace) {
          existing.workspaceIndex = _activeWorkspace;
        }
        if (existing.minimized) {
          existing.minimized = false;
        }
        focusWindow(existing.id);
        return;
      }
    }

    final winTitle = title ?? def?.name ?? 'Janela';
    final winIcon = icon ?? def?.icon ?? Icons.window_rounded;
    final winWidth = width ?? def?.defaultWidth ?? 800.0;
    final winHeight = height ?? def?.defaultHeight ?? 560.0;

    // Calcular posição em cascata no workspace atual
    final curWins = currentWorkspaceWindows;
    final cascadeIndex = curWins.length % 6;
    final startX = 80.0 + (cascadeIndex * 36.0);
    final startY = 40.0 + (cascadeIndex * 30.0);

    final id = 'win_${_nextWindowSeq++}_$appId';

    // Desfocar todas as outras do workspace atual
    for (final w in curWins) {
      w.focused = false;
    }

    final newWindow = CloudWindow(
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
      customParams: params ?? const <String, dynamic>{},
    );

    _windows.add(newWindow);
    _persistSession();
    notifyListeners();
  }

  void closeWindow(String id) {
    final index = _windows.indexWhere((w) => w.id == id);
    if (index != -1) {
      _windows.removeAt(index);
      final cur = currentWorkspaceWindows;
      if (cur.isNotEmpty) {
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
  }

  void focusWindow(String id) {
    final index = _windows.indexWhere((w) => w.id == id);
    if (index != -1) {
      final target = _windows.removeAt(index);
      for (final w in _windows) {
        w.focused = false;
      }
      target.focused = true;
      target.minimized = false;
      _windows.add(target);
      _persistSession();
      notifyListeners();
    }
  }

  void minimizeWindow(String id) {
    final win = getWindowById(id);
    if (win != null) {
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
  }

  void toggleMaximizeWindow(String id, Size viewportSize) {
    final win = getWindowById(id);
    if (win != null) {
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
        win.height = viewportSize.height - 48.0;
      }
      focusWindow(id);
    }
  }

  void snapWindowLeft(String id, Size viewportSize) {
    final win = getWindowById(id);
    if (win != null) {
      win.previousX = win.x;
      win.previousY = win.y;
      win.previousWidth = win.width;
      win.previousHeight = win.height;

      win.maximized = false;
      win.x = 0;
      win.y = 0;
      win.width = viewportSize.width / 2.0;
      win.height = viewportSize.height - 48.0;
      focusWindow(id);
    }
  }

  void snapWindowRight(String id, Size viewportSize) {
    final win = getWindowById(id);
    if (win != null) {
      win.previousX = win.x;
      win.previousY = win.y;
      win.previousWidth = win.width;
      win.previousHeight = win.height;

      win.maximized = false;
      win.x = viewportSize.width / 2.0;
      win.y = 0;
      win.width = viewportSize.width / 2.0;
      win.height = viewportSize.height - 48.0;
      focusWindow(id);
    }
  }

  void moveWindow(String id, Offset delta, Size viewportSize) {
    final win = getWindowById(id);
    if (win != null && !win.maximized) {
      final maxAvailableY = viewportSize.height - 48.0 - 40.0;
      win.x = (win.x + delta.dx).clamp(0.0, (viewportSize.width - 100.0).clamp(0.0, double.infinity));
      win.y = (win.y + delta.dy).clamp(0.0, maxAvailableY.clamp(0.0, double.infinity));

      // Detecção de preview de snap
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

  void resizeWindow(String id, double newWidth, double newHeight, Size viewportSize) {
    final win = getWindowById(id);
    if (win != null && !win.maximized) {
      final maxW = viewportSize.width - win.x;
      final maxH = (viewportSize.height - 48.0) - win.y;
      win.width = newWidth.clamp(win.minWidth, maxW > win.minWidth ? maxW : win.minWidth);
      win.height = newHeight.clamp(win.minHeight, maxH > win.minHeight ? maxH : win.minHeight);
      _persistSession();
      notifyListeners();
    }
  }

  void toggleWindow(String appId) {
    final matching = _windows.where((w) => w.appId == appId && w.workspaceIndex == _activeWorkspace).toList();
    if (matching.isEmpty) {
      openWindow(appId);
      return;
    }

    final f = focusedWindow;
    if (f != null && f.appId == appId) {
      minimizeWindow(f.id);
    } else {
      final last = matching.last;
      focusWindow(last.id);
    }
  }

  void ensureWithinBounds(Size viewportSize) {
    final maxAvailableY = viewportSize.height - 48.0 - 40.0;
    for (final win in _windows) {
      if (win.x > viewportSize.width - 100.0) {
        win.x = (viewportSize.width - win.width).clamp(0.0, double.infinity);
      }
      if (win.y > maxAvailableY) {
        win.y = 40.0;
      }
    }
  }

  void restoreSavedWindows(List<Map<String, dynamic>> savedList, int savedWorkspace) {
    _windows.clear();
    _activeWorkspace = (savedWorkspace >= 1 && savedWorkspace <= 4) ? savedWorkspace : 1;

    for (final item in savedList) {
      final appId = item['appId'] as String? ?? '';
      final def = AppRegistry.findById(appId);
      if (def != null) {
        _windows.add(
          CloudWindow(
            id: item['id'] as String? ?? 'win_${_nextWindowSeq++}_$appId',
            appId: appId,
            title: item['title'] as String? ?? def.name,
            icon: def.icon,
            x: (item['x'] as num?)?.toDouble() ?? 100.0,
            y: (item['y'] as num?)?.toDouble() ?? 60.0,
            width: (item['width'] as num?)?.toDouble() ?? def.defaultWidth,
            height: (item['height'] as num?)?.toDouble() ?? def.defaultHeight,
            minimized: item['minimized'] as bool? ?? false,
            maximized: item['maximized'] as bool? ?? false,
            workspaceIndex: item['workspaceIndex'] as int? ?? 1,
            focused: false,
          ),
        );
      }
    }

    final cur = currentWorkspaceWindows;
    if (cur.isNotEmpty) {
      cur.last.focused = true;
    }
    notifyListeners();
  }

  void _persistSession() {
    SessionService.instance.saveSession(
      windows: _windows,
      activeWorkspace: _activeWorkspace,
    );
  }
}
