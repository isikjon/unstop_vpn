import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class SendCodeResult {
  final String codeType;
  final String delivery;

  const SendCodeResult({required this.codeType, required this.delivery});
}

class AuthService {
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Api-Key': AppConfig.apiKey,
      };

  /// Primary auth: check if the bot already received the user's contact.
  /// Returns telegram_id if found, null otherwise.
  static Future<String?> checkContact(String phone) async {
    final uri = Uri.parse('${AppConfig.apiBase}/auth/check-contact');
    http.Response response;
    try {
      response = await http
          .post(uri, headers: _headers, body: jsonEncode({'phone': phone}))
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
          .post(uri, headers: _headers, body: jsonEncode({'phone': phone}))
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
            json['error'] ?? json['detail'] ?? 'Не удалось отправить код');
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
          .post(uri, headers: _headers, body: jsonEncode({'phone': phone}))
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
            headers: _headers,
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
        throw AuthException(
            json['error'] ?? json['detail'] ?? 'Неверный код');
      }
      final id = json['telegram_id'] ??
          json['tg_id'] ??
          json['user_id'] ??
          json['id'];
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

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}
