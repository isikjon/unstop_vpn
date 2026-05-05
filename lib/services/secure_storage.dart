import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tiny wrapper over flutter_secure_storage for the few values we persist.
class VpnSecureStorage {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());

  static const _keyTelegramId = 'auth_telegram_id';
  static const _keyPhone = 'auth_phone';
  static const _keyName = 'auth_name';
  static const _keySelectedServer = 'selected_server_id';
  static const _keyPinnedServers = 'pinned_server_ids';
  static const _keyCachedSubscription = 'cached_subscription_payload';
  static const _keyTrialStartedAt = 'trial_started_at_ms';
  static const _keyInstallId = 'device_install_id';

  static Future<void> saveTelegramId(String id) =>
      _storage.write(key: _keyTelegramId, value: id);

  static Future<String?> getTelegramId() => _storage.read(key: _keyTelegramId);

  static Future<void> clearTelegramId() => _storage.delete(key: _keyTelegramId);

  static Future<void> savePhone(String phone) =>
      _storage.write(key: _keyPhone, value: phone);

  static Future<String?> getPhone() => _storage.read(key: _keyPhone);

  static Future<void> clearPhone() => _storage.delete(key: _keyPhone);

  static Future<void> saveName(String name) =>
      _storage.write(key: _keyName, value: name);

  static Future<String?> getName() => _storage.read(key: _keyName);

  static Future<void> clearName() => _storage.delete(key: _keyName);

  static Future<void> saveSelectedServerId(String id) =>
      _storage.write(key: _keySelectedServer, value: id);

  static Future<String?> getSelectedServerId() =>
      _storage.read(key: _keySelectedServer);

  static Future<Set<String>> getPinnedServerIds() async {
    final raw = await _storage.read(key: _keyPinnedServers);
    if (raw == null || raw.trim().isEmpty) return <String>{};
    return raw.split('\n').where((id) => id.trim().isNotEmpty).toSet();
  }

  static Future<void> savePinnedServerIds(Set<String> ids) =>
      _storage.write(key: _keyPinnedServers, value: ids.join('\n'));

  static Future<void> saveCachedSubscriptionPayload(String payload) =>
      _storage.write(key: _keyCachedSubscription, value: payload);

  static Future<String?> getCachedSubscriptionPayload() =>
      _storage.read(key: _keyCachedSubscription);

  static Future<void> clearCachedSubscriptionPayload() =>
      _storage.delete(key: _keyCachedSubscription);

  static Future<void> saveInstallId(String id) =>
      _storage.write(key: _keyInstallId, value: id);

  static Future<String?> getInstallId() => _storage.read(key: _keyInstallId);

  static Future<void> saveTrialStartedAt(DateTime startedAt) => _storage.write(
    key: _keyTrialStartedAt,
    value: startedAt.millisecondsSinceEpoch.toString(),
  );

  static Future<DateTime?> getTrialStartedAt() async {
    final raw = await _storage.read(key: _keyTrialStartedAt);
    final ms = raw == null ? null : int.tryParse(raw);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> clearAll() => _storage.deleteAll();
}
