import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';

import '../config/app_config.dart';
import 'secure_storage.dart';

class DeviceHeadersService {
  static final _random = Random.secure();
  static final _deviceInfo = DeviceInfoPlugin();

  static Future<Map<String, String>> apiHeaders({
    bool includeJsonContentType = true,
  }) async {
    final meta = await _deviceMeta();
    return {
      if (includeJsonContentType) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Api-Key': AppConfig.apiKey,
      'x-hwid': meta.installId,
      'x-device-os': meta.platform,
      'x-ver-os': meta.osVersion,
      'x-device-model': meta.model,
      'user-agent': 'UnstopApp/${AppConfig.appVersion}',
    };
  }

  static Future<_DeviceMeta> _deviceMeta() async {
    final installId = await _installId();

    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return _DeviceMeta(
          installId: installId,
          platform: 'android',
          osVersion: info.version.release,
          model: _joinNonEmpty([info.manufacturer, info.model]),
        );
      }

      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return _DeviceMeta(
          installId: installId,
          platform: 'ios',
          osVersion: info.systemVersion,
          model: info.utsname.machine.isNotEmpty
              ? info.utsname.machine
              : info.model,
        );
      }
    } catch (_) {
      // Fall through to the generic platform values below.
    }

    return _DeviceMeta(
      installId: installId,
      platform: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      model: 'unknown',
    );
  }

  static Future<String> _installId() async {
    final saved = await VpnSecureStorage.getInstallId();
    if (saved != null && saved.isNotEmpty) return saved;

    final id = _uuidV4();
    await VpnSecureStorage.saveInstallId(id);
    return id;
  }

  static String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20),
    ].join('-');
  }

  static String _joinNonEmpty(List<String?> parts) {
    final value = parts
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    return value.isEmpty ? 'unknown' : value;
  }
}

class _DeviceMeta {
  final String installId;
  final String platform;
  final String osVersion;
  final String model;

  const _DeviceMeta({
    required this.installId,
    required this.platform,
    required this.osVersion,
    required this.model,
  });
}
