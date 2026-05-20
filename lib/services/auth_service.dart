import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'device_headers_service.dart';

class SendCodeResult {
  final String codeType;
  final String delivery;

  const SendCodeResult({required this.codeType, required this.delivery});
}

class BotAuthStartResult {
  final String key;
  final String botLink;

  const BotAuthStartResult({required this.key, required this.botLink});
}

class BotAuthStatusResult {
  final bool authenticated;
  final String? telegramId;
  final String? name;

  const BotAuthStatusResult({
    required this.authenticated,
    this.telegramId,
    this.name,
  });
}

class AuthService {
  static final _random = Random.secure();

  static Future<Map<String, String>> _headers() =>
      DeviceHeadersService.apiHeaders();

  /// Bot-only auth: the app generates a numeric key and opens Telegram with
  /// `start=key_<key>`. The bot posts `key/tg_id/name` to `/api/auth_hook`.
  static Future<BotAuthStartResult> startBotAuth() async {
    final key = _generateNumericKey();
    return BotAuthStartResult(
      key: key,
      botLink: AppConfig.botStartLink('key_$key'),
    );
  }

  /// Poll backend until Telegram bot/webhook binds key to tg_id.
  static Future<BotAuthStatusResult> checkBotAuth(String key) async {
    final primary = await _checkBotAuthOnce(key);
    if (primary.authenticated || key.startsWith('key_')) return primary;
    return _checkBotAuthOnce('key_$key');
  }

  static Future<BotAuthStatusResult> _checkBotAuthOnce(String key) async {
    final uri = Uri.parse('${AppConfig.apiBase}/auth/status/$key');
    http.Response response;
    try {
      response = await http
          .get(uri, headers: await _headers())
          .timeout(AppConfig.apiTimeout);
    } on TimeoutException {
      throw AuthException('Сервер не отвечает');
    } catch (_) {
      throw AuthException('Нет соединения с сервером');
    }

    if (response.statusCode != 200) {
      throw AuthException(
        'Ошибка проверки авторизации (${response.statusCode})',
      );
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final payload = _findAuthPayload(json);
      final id = _readTelegramId(payload) ?? _readTelegramId(json);
      final authenticated =
          json['authenticated'] == true ||
          payload['authenticated'] == true ||
          (json['success'] == true &&
              id != null &&
              json['authenticated'] != false);
      return BotAuthStatusResult(
        authenticated: authenticated && id != null,
        telegramId: id?.toString(),
        name: _readName(payload) ?? _readName(json),
      );
    } catch (_) {
      throw AuthException('Неверный ответ сервера');
    }
  }

  static Map<String, dynamic> _findAuthPayload(Map<String, dynamic> json) {
    for (final key in const ['user', 'data', 'auth', 'account', 'profile']) {
      final value = json[key];
      if (value is Map<String, dynamic>) return value;
    }
    return json;
  }

  static Object? _readTelegramId(Map<String, dynamic> json) {
    return json['telegram_id'] ??
        json['telegramId'] ??
        json['tg_id'] ??
        json['tgId'] ??
        json['user_id'] ??
        json['userId'] ??
        json['id'];
  }

  static String? _readName(Map<String, dynamic> json) {
    return (json['name'] ??
            json['first_name'] ??
            json['firstName'] ??
            json['username'])
        ?.toString();
  }

  /// Primary auth: check if the bot already received the user's contact.
  /// Returns telegram_id if found, null otherwise.
  static Future<String?> checkContact(String phone) async {
    final uri = Uri.parse('${AppConfig.apiBase}/auth/check-contact');
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode({'phone': phone}),
          )
          .timeout(AppConfig.apiTimeout);
    } on TimeoutException {
      throw AuthException('Сервер не отвечает');
    } catch (e) {
      throw AuthException('Нет соединения с сервером');
    }

    if (response.statusCode != 200) return null;

    try {
      final json = jsonDecode(response.body);
      if (json['success'] == true && json['telegram_id'] != null) {
        return json['telegram_id'].toString();
      }
    } catch (_) {}
    return null;
  }

  /// Fallback: ask the backend to send a Telegram verification code.
  static Future<SendCodeResult> sendCode(String phone) async {
    final uri = Uri.parse('${AppConfig.apiBase}/auth/send-code');
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode({'phone': phone}),
          )
          .timeout(AppConfig.apiTimeout);
    } on TimeoutException {
      throw AuthException('Сервер не отвечает');
    } catch (e) {
      throw AuthException('Нет соединения с сервером');
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      String msg = 'Ошибка отправки кода (${response.statusCode})';
      try {
        final json = jsonDecode(response.body);
        msg = json['error'] ?? json['detail'] ?? json['message'] ?? msg;
      } catch (_) {}
      throw AuthException(msg);
    }

    try {
      final json = jsonDecode(response.body);
      if (json['success'] == false) {
        throw AuthException(
          json['error'] ?? json['detail'] ?? 'Не удалось отправить код',
        );
      }
      return SendCodeResult(
        codeType: (json['code_type'] ?? 'UNKNOWN').toString(),
        delivery: (json['delivery'] ?? '').toString(),
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      return const SendCodeResult(codeType: 'UNKNOWN', delivery: '');
    }
  }

  /// Resend the code via SMS (or next available method).
  static Future<SendCodeResult> resendCode(String phone) async {
    final uri = Uri.parse('${AppConfig.apiBase}/auth/resend-code');
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode({'phone': phone}),
          )
          .timeout(AppConfig.apiTimeout);
    } on TimeoutException {
      throw AuthException('Сервер не отвечает');
    } catch (e) {
      throw AuthException('Нет соединения с сервером');
    }

    if (response.statusCode != 200) {
      String msg = 'Ошибка переотправки кода (${response.statusCode})';
      try {
        final json = jsonDecode(response.body);
        msg = json['error'] ?? json['detail'] ?? json['message'] ?? msg;
      } catch (_) {}
      throw AuthException(msg);
    }

    try {
      final json = jsonDecode(response.body);
      return SendCodeResult(
        codeType: (json['code_type'] ?? 'UNKNOWN').toString(),
        delivery: (json['delivery'] ?? '').toString(),
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      return const SendCodeResult(codeType: 'UNKNOWN', delivery: '');
    }
  }

  /// Step 2 — submit the code the user received.
  /// Returns the numeric Telegram ID string on success.
  static Future<String> verifyCode(String phone, String code) async {
    final uri = Uri.parse('${AppConfig.apiBase}/auth/verify-code');
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode({'phone': phone, 'code': code}),
          )
          .timeout(AppConfig.apiTimeout);
    } on TimeoutException {
      throw AuthException('Сервер не отвечает');
    } catch (e) {
      throw AuthException('Нет соединения с сервером');
    }

    if (response.statusCode != 200) {
      String msg = 'Ошибка проверки кода (${response.statusCode})';
      try {
        final json = jsonDecode(response.body);
        msg = json['error'] ?? json['detail'] ?? json['message'] ?? msg;
      } catch (_) {}
      throw AuthException(msg);
    }

    try {
      final json = jsonDecode(response.body);
      if (json['success'] == false) {
        throw AuthException(json['error'] ?? json['detail'] ?? 'Неверный код');
      }
      final id =
          json['telegram_id'] ?? json['tg_id'] ?? json['user_id'] ?? json['id'];
      if (id == null) {
        throw AuthException('Сервер не вернул Telegram ID');
      }
      return id.toString();
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Неверный ответ сервера');
    }
  }
}

String _generateNumericKey() {
  return (AuthService._random.nextInt(900000000) + 100000000).toString();
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}
