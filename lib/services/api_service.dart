import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/subscription.dart';
import 'device_headers_service.dart';

/// Thin wrapper around the subscription REST endpoint.
class ApiService {
  /// Fetch the subscription + server list for [telegramId].
  ///
  /// Throws [ApiException] on network or parsing errors.
  static Future<Subscription> fetchSubscription(String telegramId) async {
    final result = await fetchSubscriptionResult(telegramId);
    return result.subscription;
  }

  static Future<SubscriptionFetchResult> fetchSubscriptionResult(
    String telegramId,
  ) async {
    final uri = Uri.parse('${AppConfig.apiBase}/app/$telegramId');
    http.Response response;
    try {
      final headers = await DeviceHeadersService.apiHeaders();
      response = await http
          .get(uri, headers: headers)
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
        // Treat a plain 404 as "no subscription", but still accept
        // trial/free server payloads if backend returns them with 404.
        final decoded404 = _decodeBody(response.body);
        final fallback = Subscription.fromAny(decoded404);
        return SubscriptionFetchResult(
          subscription: fallback.servers.isEmpty
              ? Subscription.empty
              : fallback,
          rawPayload: response.body,
        );
      default:
        if (response.statusCode >= 500) {
          throw ApiException('Ошибка сервера (${response.statusCode})');
        }
        throw ApiException('Неожиданный ответ (${response.statusCode})');
    }

    final body = response.body;
    final decoded = _decodeBody(body);

    return SubscriptionFetchResult(
      subscription: Subscription.fromAny(decoded),
      rawPayload: body,
    );
  }

  static dynamic _decodeBody(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      // Not JSON — try plain vless:// lines.
      return body;
    }
  }
}

class SubscriptionFetchResult {
  final Subscription subscription;
  final String rawPayload;

  const SubscriptionFetchResult({
    required this.subscription,
    required this.rawPayload,
  });
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
