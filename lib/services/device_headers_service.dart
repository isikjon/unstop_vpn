import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'secure_storage.dart';

class DeviceHeadersService {
  static final _random = Random.secure();
  static final _deviceInfo = DeviceInfoPlugin();
  static Future<String>? _installIdFuture;

  @visibleForTesting
  static Future<String?> Function()? debugReadInstallId;

  @visibleForTesting
  static Future<void> Function(String id)? debugSaveInstallId;

  @visibleForTesting
  static Future<String?> Function()? debugStablePlatformId;

  @visibleForTesting
  static void resetForTesting() {
    _installIdFuture = null;
    debugReadInstallId = null;
    debugSaveInstallId = null;
    debugStablePlatformId = null;
  }

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

  static Future<String> _installId() {
    return _installIdFuture ??= _readOrCreateInstallId();
  }

  static Future<String> _readOrCreateInstallId() async {
    final saved = _normalizeInstallId(await _readInstallId());
    if (saved != null) return saved;

    final id =
        _normalizeInstallId(await _stablePlatformInstallId()) ?? _uuidV4();
    await _saveInstallId(id);
    return id;
  }

  static Future<String?> _readInstallId() {
    final override = debugReadInstallId;
    return override == null ? VpnSecureStorage.getInstallId() : override();
  }

  static Future<void> _saveInstallId(String id) {
    final override = debugSaveInstallId;
    return override == null ? VpnSecureStorage.saveInstallId(id) : override(id);
  }

  static Future<String?> _stablePlatformInstallId() async {
    final override = debugStablePlatformId;
    if (override != null) return override();

    if (!Platform.isIOS) return null;
    try {
      final info = await _deviceInfo.iosInfo;
      return info.identifierForVendor;
    } catch (_) {
      return null;
    }
  }

  static String? _normalizeInstallId(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
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
