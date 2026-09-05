import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudOSBridge System Settings & Controls V25', () {
    const channel = MethodChannel('cloudos/native/v19.settings-test');
    const bridge = CloudOSBridge(channel: channel);

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'broker.invokeRpc') {
          final args = call.arguments as Map;
          final rpcMethod = args['method'] as String;

          switch (rpcMethod) {
            case 'display.listMonitors':
              return jsonEncode({
                'monitors': [
                  {
                    'deviceName': r'\\.\DISPLAY1',
                    'friendlyName': 'Primary Display',
                    'isPrimary': true,
                    'width': 1920,
                    'height': 1080,
                    'frequency': 60,
                    'orientation': 0,
                    'bitsPerPel': 32,
                    'dpiX': 96,
                    'dpiY': 96,
                    'scale': 1.0,
                  }
                ]
              });

            case 'display.listSupportedModes':
              return jsonEncode({
                'modes': [
                  {
                    'width': 1920,
                    'height': 1080,
                    'frequency': 60,
                    'orientation': 0,
                    'bitsPerPel': 32,
                  },
                  {
                    'width': 1280,
                    'height': 720,
                    'frequency': 60,
                    'orientation': 0,
                    'bitsPerPel': 32,
                  }
                ]
              });

            case 'display.setMode':
              return jsonEncode({'success': true});

            case 'display.restore':
              return jsonEncode({'success': true});

            case 'audio.getState':
              return jsonEncode({
                'audio': {
                  'available': true,
                  'volume': 0.75,
                  'isMuted': false,
                  'defaultDevice': 'Realtek High Definition Audio',
                  'endpoints': [
                    {
                      'id': '{0.0.0.00000000}.{1234}',
                      'name': 'Realtek High Definition Audio',
                      'isDefault': true,
                      'isInput': false,
                    }
                  ]
                }
              });

            case 'audio.setVolume':
              return jsonEncode({'success': true, 'volume': 0.5});

            case 'audio.setMute':
              return jsonEncode({'success': true, 'muted': true});

            case 'power.getStatus':
              return jsonEncode({
                'power': {
                  'ac_online': true,
                  'battery_present': false,
                  'battery_percent': 100,
                  'is_charging': false,
                  'battery_saver': false,
                  'remaining_sec': -1,
                  'power_source': 'AC',
                }
              });

            case 'network.getInterfaces':
              return jsonEncode({
                'interfaces': [
                  {
                    'id': '{GUID}',
                    'name': 'Intel Ethernet Connection',
                    'friendlyName': 'Ethernet',
                    'type': 'Ethernet',
                    'status': 'Up',
                    'ipv4': '192.168.1.100',
                    'ipv6': 'fe80::1',
                    'gateway': '192.168.1.1',
                    'dns': '192.168.1.1',
                    'is_internet_connected': true,
                  }
                ]
              });

            case 'network.getWifi':
              return jsonEncode({
                'networks': [
                  {
                    'ssid': 'HomeNetwork_5G',
                    'signal_quality': 85,
                    'security': 'WPA2-PSK',
                    'is_connected': true,
                  }
                ]
              });

            case 'bluetooth.getStatus':
              return jsonEncode({
                'bluetooth': {
                  'available': true,
                  'enabled': true,
                  'radio_name': 'Intel Wireless Bluetooth',
                  'address': '00:11:22:33:44:55',
                }
              });

            case 'storage.getDrives':
              return jsonEncode({
                'drives': [
                  {
                    'drive_letter': 'C:\\',
                    'volume_name': 'Windows',
                    'file_system': 'NTFS',
                    'drive_type': 'Fixed',
                    'total_bytes': 500000000000,
                    'free_bytes': 250000000000,
                    'used_bytes': 250000000000,
                    'percent_used': 50.0,
                    'is_removable': false,
                  }
                ]
              });

            case 'personalization.get':
              return jsonEncode({
                'personalization': {
                  'theme': 'dark',
                  'accent_color': '#2563EB',
                  'transparency_enabled': true,
                  'animations_enabled': true,
                  'wallpaper_path': 'C:\\wallpapers\\cloudos.png',
                  'taskbar_alignment': 'center',
                }
              });

            case 'personalization.set':
              return jsonEncode({
                'success': true,
                'personalization': {
                  'theme': 'light',
                  'accent_color': '#3B82F6',
                  'transparency_enabled': false,
                  'animations_enabled': false,
                  'wallpaper_path': '',
                  'taskbar_alignment': 'left',
                }
              });

            case 'datetime.get':
              return jsonEncode({
                'datetime': {
                  'local_time': '2026-09-05T04:15:00',
                  'timezone_name': 'E. South America Standard Time',
                  'bias_minutes': 180,
                  'locale_name': 'pt-BR',
                }
              });

            case 'quicksettings.getState':
              return jsonEncode({
                'audio': {
                  'available': true,
                  'volume': 0.8,
                  'isMuted': false,
                  'defaultDevice': 'Default Speakers',
                  'endpoints': [],
                },
                'power': {
                  'ac_online': true,
                  'battery_present': false,
                  'battery_percent': 100,
                  'is_charging': false,
                  'battery_saver': false,
                  'remaining_sec': -1,
                  'power_source': 'AC',
                },
                'bluetooth': {
                  'available': true,
                  'enabled': true,
                  'radio_name': 'BT Adapter',
                  'address': '00:00:00:00:00:00',
                },
                'personalization': {
                  'theme': 'dark',
                  'accent_color': '#2563EB',
                  'transparency_enabled': true,
                  'animations_enabled': true,
                  'wallpaper_path': '',
                  'taskbar_alignment': 'center',
                },
                'performanceProfile': 'balanced',
              });

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

    test('getDisplayMonitors returns parsed monitor records', () async {
      final monitors = await bridge.getDisplayMonitors();
      expect(monitors.length, 1);
      expect(monitors.first.deviceName, r'\\.\DISPLAY1');
      expect(monitors.first.friendlyName, 'Primary Display');
      expect(monitors.first.isPrimary, isTrue);
      expect(monitors.first.width, 1920);
      expect(monitors.first.height, 1080);
      expect(monitors.first.scale, 1.0);
    });

    test('getDisplayModes and setDisplayMode work correctly', () async {
      final modes = await bridge.getDisplayModes();
      expect(modes.length, 2);
      expect(modes.first.width, 1920);
      expect(modes.first.height, 1080);

      final ok = await bridge.setDisplayMode(
        deviceName: r'\\.\DISPLAY1',
        width: 1920,
        height: 1080,
      );
      expect(ok, isTrue);

      final restored = await bridge.restoreDisplayMode();
      expect(restored, isTrue);
    });

    test('audio state, volume and mute controls work correctly', () async {
      final audio = await bridge.getAudioState();
      expect(audio.available, isTrue);
      expect(audio.volume, 0.75);
      expect(audio.isMuted, isFalse);
      expect(audio.endpoints.length, 1);
      expect(audio.endpoints.first.name, 'Realtek High Definition Audio');

      final volOk = await bridge.setMasterVolume(0.5);
      expect(volOk, isTrue);

      final muteOk = await bridge.setMasterMute(true);
      expect(muteOk, isTrue);
    });

    test('power status reports AC online and battery telemetry', () async {
      final power = await bridge.getPowerStatus();
      expect(power.acOnline, isTrue);
      expect(power.batteryPresent, isFalse);
      expect(power.batteryPercent, 100);
      expect(power.powerSource, 'AC');
    });

    test('network and wifi enumeration report real interfaces and networks', () async {
      final ifaces = await bridge.getNetworkInterfaces();
      expect(ifaces.length, 1);
      expect(ifaces.first.name, 'Intel Ethernet Connection');
      expect(ifaces.first.ipv4, '192.168.1.100');
      expect(ifaces.first.isInternetConnected, isTrue);

      final wifis = await bridge.getWifiNetworks();
      expect(wifis.length, 1);
      expect(wifis.first.ssid, 'HomeNetwork_5G');
      expect(wifis.first.signalQuality, 85);
      expect(wifis.first.isConnected, isTrue);
    });

    test('bluetooth status queries radio availability', () async {
      final bt = await bridge.getBluetoothStatus();
      expect(bt.available, isTrue);
      expect(bt.enabled, isTrue);
      expect(bt.radioName, 'Intel Wireless Bluetooth');
    });

    test('storage drives report volumes, space and types', () async {
      final drives = await bridge.getStorageDrives();
      expect(drives.length, 1);
      expect(drives.first.driveLetter, 'C:\\');
      expect(drives.first.fileSystem, 'NTFS');
      expect(drives.first.percentUsed, 50.0);
    });

    test('personalization get and set persist preferences safely', () async {
      final pers = await bridge.getPersonalizationSettings();
      expect(pers.theme, 'dark');
      expect(pers.accentColor, '#2563EB');
      expect(pers.transparencyEnabled, isTrue);

      final saveOk = await bridge.setPersonalizationSettings(
        const CloudPersonalizationSettings(
          theme: 'light',
          accentColor: '#3B82F6',
          transparencyEnabled: false,
          animationsEnabled: false,
          taskbarAlignment: 'left',
        ),
      );
      expect(saveOk, isTrue);
    });

    test('date time locale provides formatted time and locale', () async {
      final dt = await bridge.getDateTimeLocale();
      expect(dt.localTime, '2026-09-05T04:15:00');
      expect(dt.timezoneName, contains('South America'));
      expect(dt.localeName, 'pt-BR');
    });

    test('quick settings state returns unified payload', () async {
      final qs = await bridge.getQuickSettingsState();
      expect(qs.audio.volume, 0.8);
      expect(qs.power.acOnline, isTrue);
      expect(qs.bluetooth.enabled, isTrue);
      expect(qs.personalization.theme, 'dark');
      expect(qs.performanceProfile, 'balanced');
    });

    test('degraded fallback when channel throws or is missing', () async {
      const missingBridge = CloudOSBridge(
        channel: MethodChannel('cloudos/native/v19.missing'),
      );
      final monitors = await missingBridge.getDisplayMonitors();
      expect(monitors, isEmpty);

      final audio = await missingBridge.getAudioState();
      expect(audio.available, isFalse);

      final power = await missingBridge.getPowerStatus();
      expect(power.batteryPercent, 100);
      expect(power.acOnline, isTrue);

      final ifaces = await missingBridge.getNetworkInterfaces();
      expect(ifaces, isEmpty);

      final drives = await missingBridge.getStorageDrives();
      expect(drives, isEmpty);
    });
  });
}
