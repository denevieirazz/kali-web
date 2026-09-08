import '../models/window_model.dart';

/// Maintains Most-Recently-Used window identity independently from render
/// z-order. This makes Alt+Tab deterministic even with minimized windows and
/// workspace transitions.
class WindowMruTracker {
  WindowMruTracker();

  final List<String> _ids = <String>[];

  List<String> get ids => List<String>.unmodifiable(_ids);

  void clear() => _ids.clear();

  void touch(String id) {
    if (id.isEmpty) return;
    _ids.remove(id);
    _ids.insert(0, id);
  }

  void remove(String id) {
    _ids.remove(id);
  }

  void retain(Set<String> validIds) {
    _ids.removeWhere((id) => !validIds.contains(id));
  }

  void restore(Iterable<String> savedIds, Iterable<CloudWindow> windows) {
    _ids.clear();
    final valid = windows.map((window) => window.id).toSet();
    final seen = <String>{};
    for (final id in savedIds) {
      if (valid.contains(id) && seen.add(id)) _ids.add(id);
    }
    for (final window in windows.toList().reversed) {
      if (seen.add(window.id)) _ids.add(window.id);
    }
  }

  List<CloudWindow> orderedForWorkspace(
    Iterable<CloudWindow> windows,
    int workspace,
  ) {
    final byId = <String, CloudWindow>{
      for (final window in windows)
        if (window.workspaceIndex == workspace) window.id: window,
    };
    final result = <CloudWindow>[];
    final seen = <String>{};
    for (final id in _ids) {
      final window = byId[id];
      if (window != null && seen.add(id)) result.add(window);
    }
    // Newly restored/legacy windows may not yet exist in the MRU sequence.
    for (final window in byId.values.toList().reversed) {
      if (seen.add(window.id)) result.add(window);
    }
    return result;
  }

  String? next({
    required Iterable<CloudWindow> windows,
    required int workspace,
    String? currentId,
    bool forward = true,
  }) {
    final ordered = orderedForWorkspace(windows, workspace);
    if (ordered.isEmpty) return null;
    if (ordered.length == 1) return ordered.first.id;
    final currentIndex = currentId == null
        ? -1
        : ordered.indexWhere((window) => window.id == currentId);
    if (currentIndex < 0) return ordered.first.id;
    final delta = forward ? 1 : -1;
    return ordered[(currentIndex + delta + ordered.length) % ordered.length].id;
  }
}
