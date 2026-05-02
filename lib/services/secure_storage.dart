import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tiny wrapper over flutter_secure_storage for the few values we persist.
class VpnSecureStorage {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());

  static const _keyTelegramId = 'auth_telegram_id';
  static const _keyPhone = 'auth_phone';
  static const _keySelectedServer = 'selected_server_id';

  static Future<void> saveTelegramId(String id) =>
      _storage.write(key: _keyTelegramId, value: id);

  static Future<String?> getTelegramId() => _storage.read(key: _keyTelegramId);

  static Future<void> clearTelegramId() => _storage.delete(key: _keyTelegramId);

  static Future<void> savePhone(String phone) =>
      _storage.write(key: _keyPhone, value: phone);

  static Future<String?> getPhone() => _storage.read(key: _keyPhone);

  static Future<void> clearPhone() => _storage.delete(key: _keyPhone);

  static Future<void> saveSelectedServerId(String id) =>
      _storage.write(key: _keySelectedServer, value: id);

  static Future<String?> getSelectedServerId() =>
      _storage.read(key: _keySelectedServer);

  static Future<void> clearAll() => _storage.deleteAll();
}
