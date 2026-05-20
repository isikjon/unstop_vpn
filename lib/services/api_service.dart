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
    Map<String, String> headers;
    try {
      headers = await DeviceHeadersService.apiHeaders();
    } catch (e) {
      throw ApiException('Ошибка подготовки устройства');
    }

    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      http.Response response;
      try {
        response = await http
            .get(uri, headers: headers)
            .timeout(AppConfig.apiTimeout);
      } on TimeoutException {
        throw ApiException('Сервер не отвечает');
      } catch (e) {
        throw ApiException('Нет соединения с сервером');
      }

      final body = response.body;
      final decodedBody = _decodeBody(body);

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
          final fallback = Subscription.fromAny(decodedBody);
          return SubscriptionFetchResult(
            subscription: fallback.servers.isEmpty
                ? Subscription.empty
                : fallback,
            rawPayload: body,
          );
        default:
          final fallback = Subscription.fromAny(decodedBody);
          if (fallback.isActive ||
              fallback.isDeviceLimitExceeded ||
              fallback.servers.isNotEmpty) {
            return SubscriptionFetchResult(
              subscription: fallback,
              rawPayload: body,
            );
          }
          if (response.statusCode >= 500) {
            throw ApiException('Ошибка сервера (${response.statusCode})');
          }
          throw ApiException('Неожиданный ответ (${response.statusCode})');
      }

      var decoded = decodedBody;
      decoded = await _resolveAppUrlIfNeeded(decoded, headers);

      if (_isRetryableSubscriptionPayload(decoded) &&
          attempt < maxAttempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 700 * (attempt + 1)));
        continue;
      }

      return SubscriptionFetchResult(
        subscription: Subscription.fromAny(decoded),
        rawPayload: body,
      );
    }

    return SubscriptionFetchResult(
      subscription: Subscription.empty.copyWith(
        errorMessage: 'subscription_payload_not_loaded',
      ),
      rawPayload: '',
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

  /// Some backends return a short subscription payload with `appUrl`, while
  /// the real server configs are behind that URL. That request must carry the
  /// same device headers, otherwise the backend can't bind/check the device.
  static Future<dynamic> _resolveAppUrlIfNeeded(
    dynamic decoded,
    Map<String, String> headers,
  ) async {
    final appUrls = _extractAppUrls(decoded);
    if (appUrls.isEmpty) return decoded;

    final servers = <String>[];
    dynamic fallbackPayload;
    for (final appUrl in appUrls) {
      final appPayload = await _fetchAppUrl(appUrl, headers);
      fallbackPayload ??= appPayload;
      final appSubscription = Subscription.fromAny(appPayload);
      servers.addAll(appSubscription.servers.map((server) => server.url));
    }

    if (decoded is Map<String, dynamic> && servers.isNotEmpty) {
      return {...decoded, 'items': servers};
    }
    return fallbackPayload ?? decoded;
  }

  static Future<dynamic> _fetchAppUrl(
    String appUrl,
    Map<String, String> headers,
  ) async {
    final uri = Uri.tryParse(appUrl);
    if (uri == null || (!uri.hasScheme && !appUrl.startsWith('/'))) {
      return null;
    }

    final resolvedUri = uri.hasScheme
        ? uri
        : Uri.parse(AppConfig.apiBase).resolve(appUrl);

    http.Response response;
    try {
      response = await http
          .get(resolvedUri, headers: headers)
          .timeout(AppConfig.apiTimeout);
    } on TimeoutException {
      throw ApiException('Сервер не отвечает');
    } catch (_) {
      throw ApiException('Нет соединения с сервером');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('Ошибка загрузки серверов (${response.statusCode})');
    }

    return _decodeBody(response.body);
  }

  static List<String> _extractAppUrls(dynamic decoded) {
    final values = <String>{};
    void collect(dynamic value) {
      if (value == null) return;
      final text = value.toString().trim();
      if (text.isNotEmpty) values.add(text);
    }

    void collectFromMap(Map map) {
      collect(map['appUrl']);
      collect(map['app_url']);
      collect(map['appURL']);
      for (final key in const ['subscription', 'data', 'meta']) {
        final nested = map[key];
        if (nested is Map) collectFromMap(nested);
      }
      for (final key in const [
        'servers',
        'items',
        'configs',
        'trial_servers',
        'free_servers',
      ]) {
        final nested = map[key];
        if (nested is List) {
          for (final item in nested) {
            if (item is Map) collectFromMap(item);
          }
        }
      }
    }

    if (decoded is Map) collectFromMap(decoded);
    return values.toList(growable: false);
  }

  static bool _isRetryableSubscriptionPayload(dynamic decoded) {
    if (decoded is! Map) return false;
    final message = decoded['message']?.toString().trim().toLowerCase();
    return message == 'subscription_payload_empty' ||
        message == 'subscription_payload_not_loaded';
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
