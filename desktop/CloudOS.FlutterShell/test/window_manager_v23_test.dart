import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudos_flutter_shell/shell/window_manager/cloud_window.dart';

void main() {
  group('Window Manager V23 Models & Unified Registry', () {
    test('CloudWindow.fromJson deserializes Win32, Linux, and CloudOS windows', () {
      final win32Json = <String, dynamic>{
        'id': 'win-notepad-1',
        'platform': 'windows',
        'pid': 1234,
        'hwnd': 56789,
        'title': 'Sem título - Bloco de Notas',
        'appId': 'windows:notepad',
        'state': 'normal',
        'bounds': {'x': 150, 'y': 120, 'width': 800, 'height': 600},
        'minimized': false,
        'maximized': false,
        'fullscreen': false,
        'visible': true,
        'focused': true,
        'workspaceId': 1,
        'monitorId': r'\\.\DISPLAY1',
        'capabilities': ['minimize', 'maximize', 'close', 'snap', 'resize', 'move'],
      };

      final win = CloudWindow.fromJson(win32Json);
      expect(win.platform, 'windows');
      expect(win.hwnd, 56789);
      expect(win.pid, 1234);
      expect(win.title, 'Sem título - Bloco de Notas');
      expect(win.appId, 'windows:notepad');
      expect(win.type, CloudWindowType.externalWin32);
      expect(win.position, const Offset(150, 120));
      expect(win.size, const Size(800, 600));
      expect(win.isFocused, isTrue);
      expect(win.isMinimized, isFalse);
      expect(win.isMaximized, isFalse);
      expect(win.capabilities, contains('minimize'));
      expect(win.capabilities, contains('snap'));

      final serialized = win.toJson();
      expect(serialized['platform'], 'windows');
      expect(serialized['hwnd'], 56789);
      expect(serialized['appId'], 'windows:notepad');
      expect(serialized['state'], 'normal');
    });

    test('CloudWindow.fromJson deserializes WSLg Linux windows', () {
      final linuxJson = <String, dynamic>{
        'id': 'linux-xclock-1',
        'platform': 'linux',
        'pid': 4321,
        'hwnd': 98765,
        'title': 'xclock',
        'appId': 'linux:xclock',
        'state': 'normal',
        'bounds': {'x': 200, 'y': 200, 'width': 300, 'height': 300},
        'minimized': false,
        'maximized': false,
        'fullscreen': false,
        'visible': true,
        'focused': false,
        'workspaceId': 2,
        'monitorId': r'\\.\DISPLAY1',
        'capabilities': ['minimize', 'close', 'move'],
      };

      final win = CloudWindow.fromJson(linuxJson);
      expect(win.platform, 'linux');
      expect(win.type, CloudWindowType.externalLinux);
      expect(win.hwnd, 98765);
      expect(win.workspaceId, 2);
    });

    test('CloudWindowSnapshot.fromJsonString parses multi-window snapshot', () {
      const jsonStr = '''{
        "windows": [
          {
            "id": "files",
            "platform": "cloudos",
            "pid": 100,
            "hwnd": 1001,
            "title": "Arquivos",
            "appId": "cloudos:files",
            "state": "normal",
            "bounds": {"x": 100, "y": 80, "width": 960, "height": 600},
            "minimized": false,
            "maximized": false,
            "fullscreen": false,
            "visible": true,
            "focused": true,
            "workspaceId": 1,
            "monitorId": "\\\\\\\\.\\\\DISPLAY1",
            "capabilities": ["minimize", "maximize", "close", "snap", "resize", "move"]
          },
          {
            "id": "notepad-1",
            "platform": "windows",
            "pid": 200,
            "hwnd": 2001,
            "title": "Bloco de Notas",
            "appId": "windows:notepad",
            "state": "minimized",
            "bounds": {"x": 150, "y": 100, "width": 800, "height": 500},
            "minimized": true,
            "maximized": false,
            "fullscreen": false,
            "visible": true,
            "focused": false,
            "workspaceId": 1,
            "monitorId": "\\\\\\\\.\\\\DISPLAY1",
            "capabilities": ["minimize", "maximize", "close", "snap", "resize", "move"]
          }
        ],
        "monitors": [
          {
            "id": "mon-0",
            "name": "\\\\\\\\.\\\\DISPLAY1",
            "bounds": {"x": 0, "y": 0, "width": 1920, "height": 1080},
            "workArea": {"x": 0, "y": 0, "width": 1920, "height": 1032},
            "isPrimary": true,
            "scaleFactor": 1.0
          }
        ],
        "currentWorkspace": 1,
        "sequence": 42,
        "timestamp": 1700000000
      }''';

      final snapshot = CloudWindowSnapshot.fromJsonString(jsonStr);
      expect(snapshot.sequence, 42);
      expect(snapshot.currentWorkspace, 1);
      expect(snapshot.windows.length, 2);
      expect(snapshot.monitors.length, 1);

      final filesWin = snapshot.windows.first;
      expect(filesWin.platform, 'cloudos');
      expect(filesWin.title, 'Arquivos');
      expect(filesWin.isFocused, isTrue);

      final notepadWin = snapshot.windows.last;
      expect(notepadWin.platform, 'windows');
      expect(notepadWin.title, 'Bloco de Notas');
      expect(notepadWin.isMinimized, isTrue);

      final monitor = snapshot.monitors.first;
      expect(monitor.isPrimary, isTrue);
      expect(monitor.workArea.height, 1032);
    });
  });
}
