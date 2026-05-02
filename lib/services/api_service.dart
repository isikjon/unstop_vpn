import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/subscription.dart';

/// Thin wrapper around the subscription REST endpoint.
class ApiService {
  /// Build standard request headers.
  /// Adds Authorization only when [AppConfig.apiKey] is non-empty.
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Api-Key': AppConfig.apiKey,
      };

  /// Fetch the subscription + server list for [telegramId].
  ///
  /// Throws [ApiException] on network or parsing errors.
  static Future<Subscription> fetchSubscription(String telegramId) async {
    final uri = Uri.parse('${AppConfig.apiBase}/app/$telegramId');
    http.Response response;
    try {
      response = await http
          .get(uri, headers: _headers)
          .timeout(AppConfig.apiTimeout);
    } on TimeoutException {
      throw ApiException('Сервер не отвечает');
    } catch (e) {
      throw ApiException('Нет соединения с сервером');
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 401:
      case 403:
        throw ApiException(
          'Доступ запрещён (${response.statusCode}). '
          'Убедитесь, что вы зарегистрированы в боте '
          '@${AppConfig.botUsername}.',
        );
      case 404:
        // Treat 404 as "no subscription".
        return Subscription.empty;
      default:
        if (response.statusCode >= 500) {
          throw ApiException('Ошибка сервера (${response.statusCode})');
        }
        throw ApiException('Неожиданный ответ (${response.statusCode})');
    }

    final body = response.body;
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      // Not JSON — try plain vless:// lines.
      decoded = body;
    }

    return Subscription.fromAny(decoded);
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
