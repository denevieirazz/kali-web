import 'package:cloudos_flutter_shell/features/terminal/domain/terminal_launch_coordinator.dart';
import 'package:cloudos_flutter_shell/models/cloud_app.dart';
import 'package:cloudos_flutter_shell/models/wsl_distro.dart';
import 'package:cloudos_flutter_shell/services/bridge/cloud_app_mapper.dart';
import 'package:cloudos_flutter_shell/shell/shell_app_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudOS WSL & Hybrid Integration Suite (Etapa 2)', () {
    setUp(TerminalLaunchCoordinator.resetForTest);
    tearDown(TerminalLaunchCoordinator.resetForTest);

    test('WslDistroInfo parses native metadata and reflects running state correctly', () {
      final runningMap = <Object?, Object?>{
        'id': 'wsl:Ubuntu',
        'name': 'Ubuntu',
        'guid': '{1234-5678}',
        'version': 2,
        'state': 'running',
        'basePath': r'C:\WSL\Ubuntu',
        'defaultUid': 1000,
        'flags': 7,
        'isDefault': true,
      };

      final info = WslDistroInfo.fromMap(runningMap);
      expect(info.id, 'wsl:Ubuntu');
      expect(info.name, 'Ubuntu');
      expect(info.version, 2);
      expect(info.state, 'running');
      expect(info.isRunning, isTrue);
      expect(info.isDefault, isTrue);
      expect(info.defaultUid, 1000);

      final stoppedMap = <Object?, Object?>{
        'id': 'wsl:kali-linux',
        'name': 'kali-linux',
        'guid': '{8765-4321}',
        'version': 2,
        'state': 'stopped',
        'basePath': r'C:\WSL\Kali',
        'defaultUid': 1000,
        'flags': 7,
        'isDefault': false,
      };

      final stoppedInfo = WslDistroInfo.fromMap(stoppedMap);
      expect(stoppedInfo.name, 'kali-linux');
      expect(stoppedInfo.isRunning, isFalse);
      expect(stoppedInfo.isDefault, isFalse);
    });

    test('PathTranslation parses bidirectional mappings and existence check', () {
      final translationMap = <Object?, Object?>{
        'originalPath': r'C:\Users\test\file.txt',
        'translatedPath': '/mnt/c/Users/test/file.txt',
        'target': 'linux',
        'distro': 'Ubuntu',
        'exists': true,
      };

      final translation = PathTranslation.fromMap(translationMap);
      expect(translation.originalPath, r'C:\Users\test\file.txt');
      expect(translation.translatedPath, '/mnt/c/Users/test/file.txt');
      expect(translation.target, 'linux');
      expect(translation.distro, 'Ubuntu');
      expect(translation.exists, isTrue);
    });

    test('MountPoint parses system drives and WSL roots', () {
      final mountMap = <Object?, Object?>{
        'id': 'c',
        'name': 'Disco Local (C:)',
        'path': r'C:\',
        'type': 'windows',
        'filesystem': 'NTFS',
        'isReady': true,
      };

      final mount = MountPoint.fromMap(mountMap);
      expect(mount.id, 'c');
      expect(mount.name, 'Disco Local (C:)');
      expect(mount.path, r'C:\');
      expect(mount.type, 'windows');
      expect(mount.isReady, isTrue);
    });

    test('AppLaunchStatus distinguishes between successful and failed launches', () {
      final successMap = <Object?, Object?>{
        'id': 'windows:notepad',
        'status': 'running',
        'launched': true,
        'platform': 'windows',
        'target': 'notepad.exe',
        'message': '',
      };
      final success = AppLaunchStatus.fromMap(successMap);
      expect(success.isSuccess, isTrue);
      expect(success.status, 'running');

      final failedMap = <Object?, Object?>{
        'id': 'windows:invalid_app',
        'status': 'failed',
        'launched': false,
        'platform': 'windows',
        'target': 'invalid_app',
        'message': 'App not allowlisted',
      };
      final failed = AppLaunchStatus.fromMap(failedMap);
      expect(failed.isSuccess, isFalse);
      expect(failed.message, 'App not allowlisted');
    });

    test('cloudAppFromNative correctly deserializes standardized AppEntry fields', () {
      final nativeMap = <Object?, Object?>{
        'id': 'wsl:Ubuntu:l3afpad',
        'name': 'L3afpad (Editor de Texto)',
        'platform': 'linux',
        'distro': 'Ubuntu',
        'category': 'Produtividade',
        'subtitle': 'WSLg GUI App',
        'displayName': 'L3afpad (Editor de Texto)',
        'launchTarget': 'l3afpad',
        'source': 'WSL2 (Ubuntu)',
        'availability': 'ready',
        'capabilities': <Object?>['wslg', 'gui', 'isolated'],
        'canLaunch': true,
        'pinned': true,
        'recent': false,
      };

      final app = cloudAppFromNative(nativeMap);
      expect(app.id, 'wsl:Ubuntu:l3afpad');
      expect(app.name, 'L3afpad (Editor de Texto)');
      expect(app.platform, CloudAppPlatform.linux);
      expect(app.distro, 'Ubuntu');
      expect(app.displayName, 'L3afpad (Editor de Texto)');
      expect(app.launchTarget, 'l3afpad');
      expect(app.source, 'WSL2 (Ubuntu)');
      expect(app.availability, 'ready');
      expect(app.capabilities, <String>['wslg', 'gui', 'isolated']);
      expect(app.canLaunch, isTrue);
      expect(app.isPinned, isTrue);
    });

    test('resolveShellAppRoute routes WSL distro terminal IDs and dispatches requests', () {
      expect(resolveShellAppRoute('wsl:Ubuntu:terminal'), ShellAppRoute.terminal);
      final ubuntuReq = TerminalLaunchCoordinator.takePending();
      expect(ubuntuReq?.profile, TerminalLaunchProfile.wsl);
      expect(ubuntuReq?.distro, 'Ubuntu');

      expect(resolveShellAppRoute('wsl:kali-linux:terminal'), ShellAppRoute.terminal);
      final kaliReq = TerminalLaunchCoordinator.takePending();
      expect(kaliReq?.profile, TerminalLaunchProfile.wsl);
      expect(kaliReq?.distro, 'kali-linux');

      expect(resolveShellAppRoute('ubuntu-terminal'), ShellAppRoute.terminal);
      final legacyUbuntuReq = TerminalLaunchCoordinator.takePending();
      expect(legacyUbuntuReq?.profile, TerminalLaunchProfile.wsl);
      expect(legacyUbuntuReq?.distro, 'Ubuntu');
    });
  });
}
