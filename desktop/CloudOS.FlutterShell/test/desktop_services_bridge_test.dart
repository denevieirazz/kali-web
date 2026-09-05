import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudOSBridge Desktop Services V26 (Etapa 6)', () {
    const channel = MethodChannel('cloudos/native/v19.desktop-services-test');
    const bridge = CloudOSBridge(channel: channel);

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'broker.invokeRpc') {
          final args = call.arguments as Map;
          final rpcMethod = args['method'] as String;

          switch (rpcMethod) {
            case 'clipboard.getHistory':
              return jsonEncode({
                'items': [
                  {
                    'id': 1,
                    'timestamp': '2026-09-05T04:20:00',
                    'type': 'text',
                    'preview': 'Hello from CloudOS clipboard',
                    'full_text': 'Hello from CloudOS clipboard',
                    'data_bytes': 28,
                  },
                  {
                    'id': 2,
                    'timestamp': '2026-09-05T04:19:00',
                    'type': 'image',
                    'preview': 'Imagem (1920x1080)',
                    'image_width': 1920,
                    'image_height': 1080,
                    'data_bytes': 6220800,
                  },
                  {
                    'id': 3,
                    'timestamp': '2026-09-05T04:18:00',
                    'type': 'files',
                    'preview': '2 arquivo(s) copiado(s): C:\\doc.txt',
                    'files': ['C:\\doc.txt', 'C:\\notes.md'],
                    'data_bytes': 2,
                  }
                ]
              });

            case 'clipboard.getText':
              return jsonEncode({'text': 'Active clipboard text'});

            case 'clipboard.setText':
              return jsonEncode({'success': true});

            case 'clipboard.clear':
              return jsonEncode({'success': true});

            case 'files.openWith':
              return jsonEncode({'success': true});

            case 'files.getAssociations':
              return jsonEncode({
                'associations': [
                  {
                    'extension': '.txt',
                    'default_app_id': 'windows:notepad',
                    'friendly_name': 'Documento de Texto',
                    'candidate_apps': ['windows:notepad', 'cloudos:terminal']
                  },
                  {
                    'extension': '.pdf',
                    'default_app_id': 'cloudos:browser',
                    'friendly_name': 'Documento PDF',
                    'candidate_apps': ['cloudos:browser']
                  }
                ]
              });

            case 'files.showOpenWithDialog':
              return jsonEncode({'success': true});

            case 'notifications.post':
              return jsonEncode({'id': 42, 'success': true});

            case 'notifications.list':
              return jsonEncode({
                'notifications': [
                  {
                    'id': 42,
                    'timestamp': '2026-09-05T04:20:00',
                    'title': 'Download Concluído',
                    'message': 'Arquivo kernel-update.tar.gz pronto',
                    'severity': 'info',
                    'app_id': 'cloudos:browser',
                    'read': false,
                  }
                ],
                'unread_count': 1,
              });

            case 'notifications.dismiss':
              return jsonEncode({'success': true});

            case 'notifications.clear':
              return jsonEncode({'success': true});

            case 'notifications.markRead':
              return jsonEncode({'success': true});

            case 'notifications.markAllRead':
              return jsonEncode({'success': true});

            case 'system.lock':
              return jsonEncode({'success': true});

            default:
              return jsonEncode({'error': 'unsupported_method'});
          }
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('clipboard history parses text, image and files', () async {
      final history = await bridge.getClipboardHistory();
      expect(history.length, 3);
      expect(history[0].isText, isTrue);
      expect(history[0].preview, 'Hello from CloudOS clipboard');
      expect(history[1].isImage, isTrue);
      expect(history[1].imageWidth, 1920);
      expect(history[2].isFiles, isTrue);
      expect(history[2].files, contains('C:\\doc.txt'));
    });

    test('clipboard text read, write and clear work correctly', () async {
      final text = await bridge.getClipboardText();
      expect(text, 'Active clipboard text');

      final setOk = await bridge.setClipboardText('New copied string');
      expect(setOk, isTrue);

      final clearOk = await bridge.clearClipboard();
      expect(clearOk, isTrue);
    });

    test('open with and file associations resolve correctly', () async {
      final assocs = await bridge.getFileAssociations();
      expect(assocs.length, 2);
      expect(assocs.first.extension, '.txt');
      expect(assocs.first.defaultAppId, 'windows:notepad');

      final openOk = await bridge.openFileWith(
        path: 'C:\\test.txt',
        appId: 'windows:notepad',
      );
      expect(openOk, isTrue);

      final dialogOk = await bridge.showOpenWithDialog('C:\\unknown.xyz');
      expect(dialogOk, isTrue);
    });

    test('desktop notifications store, post, dismiss, clear and read flags work', () async {
      final id = await bridge.postDesktopNotification(
        title: 'Download Concluído',
        message: 'Arquivo kernel-update.tar.gz pronto',
        severity: 'info',
        appId: 'cloudos:browser',
      );
      expect(id, 42);

      final list = await bridge.listDesktopNotifications();
      expect(list.length, 1);
      expect(list.first.title, 'Download Concluído');
      expect(list.first.read, isFalse);

      final readOk = await bridge.markDesktopNotificationRead(42);
      expect(readOk, isTrue);

      final allReadOk = await bridge.markAllDesktopNotificationsRead();
      expect(allReadOk, isTrue);

      final dismissOk = await bridge.dismissDesktopNotification(42);
      expect(dismissOk, isTrue);

      final clearOk = await bridge.clearDesktopNotifications();
      expect(clearOk, isTrue);
    });

    test('lockSystem invokes Win32 LockWorkStation safely', () async {
      final lockOk = await bridge.lockSystem();
      expect(lockOk, isTrue);
    });
  });
}
