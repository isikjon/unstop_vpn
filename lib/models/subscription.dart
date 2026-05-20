import 'dart:convert';

import 'vpn_server.dart';

/// Snapshot of the user's subscription + available servers, as returned
/// by the backend `/api/app/<telegramId>` endpoint.
///
/// The backend response shape isn't fully nailed down yet, so the parser
/// is intentionally defensive: it accepts a JSON object with various
/// possible field names, OR a plain-text body containing newline-separated
/// vless:// URIs.
class Subscription {
  /// True if the user has an active paid subscription.
  final bool isActive;

  /// Subscription expiration timestamp (server-side), or null if unknown.
  final DateTime? expiresAt;

  /// Used traffic in bytes, or null if the backend doesn't report it.
  final int? trafficUsedBytes;

  /// Total traffic quota in bytes, or null if unlimited / unknown.
  final int? trafficLimitBytes;

  /// Plan name as reported by backend (e.g. "1month", "PRO"), or null.
  final String? planName;

  /// Number of devices currently used by the user, if reported by backend.
  final int? deviceUsedCount;

  /// Maximum allowed device count, if reported by backend.
  final int? deviceLimitCount;

  /// All servers the user can currently connect to.
  final List<VpnServer> servers;

  /// Backend grants a short one-server access window after expiration.
  final bool isGracePeriod;

  /// Raw error message from backend, if any.
  final String? errorMessage;

  const Subscription({
    required this.isActive,
    required this.servers,
    this.isGracePeriod = false,
    this.expiresAt,
    this.trafficUsedBytes,
    this.trafficLimitBytes,
    this.planName,
    this.deviceUsedCount,
    this.deviceLimitCount,
    this.errorMessage,
  });

  static const Subscription empty = Subscription(isActive: false, servers: []);

  Subscription copyWith({
    bool? isActive,
    DateTime? expiresAt,
    int? trafficUsedBytes,
    int? trafficLimitBytes,
    String? planName,
    int? deviceUsedCount,
    int? deviceLimitCount,
    List<VpnServer>? servers,
    bool? isGracePeriod,
    String? errorMessage,
    bool clearExpiresAt = false,
    bool clearTrafficUsed = false,
    bool clearTrafficLimit = false,
    bool clearPlanName = false,
    bool clearDeviceUsed = false,
    bool clearDeviceLimit = false,
    bool clearError = false,
  }) {
    return Subscription(
      isActive: isActive ?? this.isActive,
      servers: servers ?? this.servers,
      isGracePeriod: isGracePeriod ?? this.isGracePeriod,
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
      trafficUsedBytes: clearTrafficUsed
          ? null
          : (trafficUsedBytes ?? this.trafficUsedBytes),
      trafficLimitBytes: clearTrafficLimit
          ? null
          : (trafficLimitBytes ?? this.trafficLimitBytes),
      planName: clearPlanName ? null : (planName ?? this.planName),
      deviceUsedCount: clearDeviceUsed
          ? null
          : (deviceUsedCount ?? this.deviceUsedCount),
      deviceLimitCount: clearDeviceLimit
          ? null
          : (deviceLimitCount ?? this.deviceLimitCount),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  int? get daysLeft {
    if (expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inDays;
  }

  double? get trafficUsedRatio {
    if (trafficUsedBytes == null ||
        trafficLimitBytes == null ||
        trafficLimitBytes == 0) {
      return null;
    }
    return (trafficUsedBytes! / trafficLimitBytes!).clamp(0.0, 1.0);
  }

  bool get isDeviceLimitExceeded {
    final value = errorMessage?.toLowerCase().trim();
    return value == 'limit_devices' ||
        value == 'device_limit' ||
        value == 'devices_limit' ||
        value == 'limit_reached' ||
        value == 'device_limit_reached' ||
        value?.contains('limit_devices') == true;
  }

  bool get isPayloadPending {
    final value = errorMessage?.toLowerCase().trim();
    return value == 'subscription_payload_empty' ||
        value == 'subscription_payload_not_loaded';
  }

  String? get userFacingError {
    if (isDeviceLimitExceeded) {
      if (deviceUsedCount != null && deviceLimitCount != null) {
        return 'Лимит устройств достигнут ($deviceUsedCount/$deviceLimitCount)';
      }
      return 'Лимит устройств достигнут';
    }
    final value = errorMessage?.toLowerCase().trim();
    if (value == 'subscription_inactive_or_expired') {
      return 'Подписка истекла';
    }
    if (value == 'grace_period_config_build_failed') {
      return 'Дополнительный доступ истёк. Продлите подписку.';
    }
    if (isPayloadPending) {
      return 'Подписка ещё обрабатывается. Попробуйте обновить позже.';
    }
    return errorMessage;
  }

  Map<String, dynamic> toCacheJson() => {
    'success': isActive || servers.isNotEmpty,
    'items': servers.map((s) => VpnServer.protectUrl(s.url)).toList(),
    'meta': {
      'status': isGracePeriod
          ? 'grace_period'
          : (isActive ? 'active' : 'trial'),
      if (isGracePeriod) 'grace_period': true,
      if (expiresAt != null) 'date_finish': expiresAt!.toIso8601String(),
      if (trafficUsedBytes != null) 'used_total_bytes': trafficUsedBytes,
      if (trafficLimitBytes != null) 'traffic_limit_bytes': trafficLimitBytes,
      if (deviceUsedCount != null) 'devices_used': deviceUsedCount,
      if (deviceLimitCount != null) 'ip_limit': deviceLimitCount,
      if (planName != null) 'plan': planName,
    },
  };

  /// Try to build a Subscription from any reasonable backend response.
  ///
  /// Accepts:
  /// - `Map<String, dynamic>` — JSON object (most likely)
  /// - `List<dynamic>`        — bare server array
  /// - `String`               — newline-separated vless:// lines
  static Subscription fromAny(dynamic raw) {
    if (raw == null) return empty;

    if (raw is String) {
      return _fromText(raw);
    }
    if (raw is List) {
      return _fromServerList(raw);
    }
    if (raw is Map<String, dynamic>) {
      return _fromMap(raw);
    }
    return empty;
  }

  static Subscription _fromText(String body) {
    final lines = body
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final servers = <VpnServer>[];
    for (final line in lines) {
      final s = VpnServer.tryParse(line);
      if (s != null) servers.add(s);
    }
    return Subscription(isActive: servers.isNotEmpty, servers: servers);
  }

  static Subscription _fromServerList(List raw) {
    final servers = <VpnServer>[];
    for (final item in raw) {
      final s = _serverFromItem(item);
      if (s != null) servers.add(s);
    }
    return Subscription(isActive: servers.isNotEmpty, servers: servers);
  }

  static Subscription _fromMap(Map<String, dynamic> json) {
    // Success flag — backend may use any of: success, ok, status.
    final successRaw = json['success'] ?? json['ok'] ?? json['status'];
    final successText = successRaw?.toString().toLowerCase();
    final success =
        successRaw == true ||
        successRaw == 1 ||
        successText == 'ok' ||
        successText == 'success' ||
        successText == 'active' ||
        successText == 'paid' ||
        successText == 'enabled';

    final errorMessage = (json['error'] ?? json['message'] ?? json['detail'])
        ?.toString();

    dynamic serversRaw = _serverPayloadFromMap(json);

    final servers = <VpnServer>[];
    if (serversRaw is List) {
      for (final item in serversRaw) {
        final s = _serverFromItem(item);
        if (s != null) servers.add(s);
      }
    } else if (serversRaw is String) {
      // Maybe it's a single concatenated string of vless lines.
      for (final line in serversRaw.split(RegExp(r'[\r\n]+'))) {
        final s = VpnServer.tryParse(line);
        if (s != null) servers.add(s);
      }
    }

    // Subscription meta — also defensive.
    final subRaw = json['meta'] is Map<String, dynamic>
        ? json['meta'] as Map<String, dynamic>
        : (json['subscription'] is Map<String, dynamic>
              ? json['subscription'] as Map<String, dynamic>
              : json);

    DateTime? expiresAt;
    final expField =
        subRaw['expires_at'] ??
        subRaw['expiration'] ??
        subRaw['expire'] ??
        subRaw['valid_until'] ??
        subRaw['date_finish'] ??
        subRaw['finished_at'] ??
        subRaw['date_end'] ??
        subRaw['end_date'];
    if (expField is String) {
      expiresAt = _parseDate(expField);
    } else if (expField is int) {
      // Could be seconds OR milliseconds. Heuristic: > 1e12 means ms.
      expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expField > 1000000000000 ? expField : expField * 1000,
      );
    }

    final whitelistTrafficUsed = _trafficBytesFrom(
      subRaw,
      byteKeys: const ['traffic_whitelist_total_bytes'],
      gbKeys: const ['traffic_whitelist_total_gb'],
    );
    final trafficUsed =
        whitelistTrafficUsed ??
        _trafficBytesFrom(
          subRaw,
          byteKeys: const [
            'traffic_used_bytes',
            'used_total_bytes',
            'used_bytes',
            'traffic_used',
            'used',
            'usage',
            'traffic',
          ],
          gbKeys: const ['traffic_used_gb', 'used_total_gb', 'used_gb'],
        );
    final trafficLimit = _trafficBytesFrom(
      subRaw,
      byteKeys: const [
        'traffic_limit_bytes',
        'limit_bytes',
        'quota_bytes',
        'total_bytes',
        'traffic_limit',
        'limit',
        'quota',
        'total',
      ],
      gbKeys: const ['traffic_limit_gb', 'limit_gb', 'quota_gb', 'total_gb'],
    );
    final deviceUsed = _asInt(
      subRaw['devices_used'] ??
          subRaw['device_used'] ??
          subRaw['used_devices'] ??
          subRaw['active_devices'] ??
          subRaw['devices_current'] ??
          subRaw['devices_count'] ??
          subRaw['online_devices'] ??
          subRaw['ip_used'] ??
          subRaw['ips_used'] ??
          subRaw['used_ips'] ??
          subRaw['hwid_count'] ??
          subRaw['active_hwid'],
    );
    final deviceLimit = _asInt(
      subRaw['devices_limit'] ??
          subRaw['device_limit'] ??
          subRaw['ip_limit'] ??
          subRaw['ips_limit'] ??
          subRaw['max_ips'] ??
          subRaw['limit_devices'] ??
          subRaw['max_devices'] ??
          subRaw['devices_total'],
    );

    final plan =
        (subRaw['plan'] ?? subRaw['tariff'] ?? subRaw['type']) as String?;
    final status = (subRaw['status'] ?? json['status'])
        ?.toString()
        .toLowerCase();
    final message = errorMessage?.trim();
    final gracePeriod = _asBool(subRaw['grace_period'] ?? json['grace_period']);
    final limitReached = _asBool(
      subRaw['limit_reached'] ?? json['limit_reached'],
    );
    final activeByStatus =
        status == null ||
        status == 'active' ||
        status == 'paid' ||
        status == 'enabled' ||
        status == 'test_period';
    final limitError = limitReached || _isLimitDevicesError(message);
    final hasActivePeriod =
        expiresAt == null || expiresAt.isAfter(DateTime.now()) || gracePeriod;

    final isActive =
        (gracePeriod && success && servers.isNotEmpty) ||
        (activeByStatus &&
            hasActivePeriod &&
            (success || limitError) &&
            (servers.isNotEmpty || limitError || deviceLimit != null));

    return Subscription(
      isActive: isActive,
      servers: servers,
      isGracePeriod: gracePeriod,
      expiresAt: expiresAt,
      trafficUsedBytes: trafficUsed,
      trafficLimitBytes: trafficLimit,
      planName: plan,
      deviceUsedCount: deviceUsed,
      deviceLimitCount: deviceLimit,
      errorMessage: limitError ? 'limit_reached' : (success ? null : message),
    );
  }

  static dynamic _serverPayloadFromMap(Map<String, dynamic> json) {
    for (final key in const [
      'servers',
      'items',
      'configs',
      'vless',
      'trial_servers',
      'free_servers',
    ]) {
      final value = json[key];
      if (value != null) return value;
    }

    for (final key in const ['data', 'subscription']) {
      final nested = json[key];
      if (nested is Map<String, dynamic>) {
        final value = _serverPayloadFromMap(nested);
        if (value != null) return value;
      } else if (nested is List || nested is String) {
        return nested;
      }
    }

    return null;
  }

  static String? _serverUrlFromMap(Map item) {
    for (final key in const ['url', 'link', 'uri', 'config']) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static VpnServer? _serverFromItem(dynamic item) {
    if (item is String) return VpnServer.tryParse(item);

    if (item is Map) {
      final url = _serverUrlFromMap(item);
      if (url != null) return VpnServer.tryParse(url);

      final config = item['config'];
      if (config is Map) {
        final s = VpnServer.tryParse(jsonEncode(config));
        if (s != null) return s;
      }

      final s = VpnServer.tryParse(jsonEncode(item));
      if (s != null) return s;
    }

    return null;
  }

  static bool _isLimitDevicesError(String? value) {
    final normalized = value?.toLowerCase().trim();
    return normalized == 'limit_devices' ||
        normalized == 'device_limit' ||
        normalized == 'devices_limit' ||
        normalized == 'limit_reached' ||
        normalized == 'device_limit_reached' ||
        normalized?.contains('limit_devices') == true;
  }

  static bool _asBool(dynamic value) {
    if (value == true || value == 1) return true;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  static DateTime? _parseDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed) ??
        DateTime.tryParse(trimmed.replaceFirst(' ', 'T'));
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static int? _trafficBytesFrom(
    Map<String, dynamic> raw, {
    required List<String> byteKeys,
    required List<String> gbKeys,
  }) {
    for (final key in byteKeys) {
      final value = raw[key];
      if (value == null) continue;
      final parsed = _asBytes(value);
      if (parsed != null) return parsed;
    }
    for (final key in gbKeys) {
      final value = raw[key];
      if (value == null) continue;
      final parsed = _asGigabytes(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static int? _asBytes(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final normalized = value.trim().replaceAll(',', '.').toLowerCase();
      final number = double.tryParse(
        RegExp(r'[\d.]+').firstMatch(normalized)?.group(0) ?? '',
      );
      if (number == null) return null;
      if (normalized.contains('tb')) {
        return (number * 1099511627776).round();
      }
      if (normalized.contains('gb')) {
        return (number * 1073741824).round();
      }
      if (normalized.contains('mb')) {
        return (number * 1048576).round();
      }
      if (normalized.contains('kb')) {
        return (number * 1024).round();
      }
      return number.round();
    }
    return null;
  }

  static int? _asGigabytes(dynamic value) {
    if (value == null) return null;
    if (value is int) return value * 1073741824;
    if (value is double) return (value * 1073741824).round();
    if (value is String) {
      final normalized = value.trim().replaceAll(',', '.');
      final number = double.tryParse(
        RegExp(r'[\d.]+').firstMatch(normalized)?.group(0) ?? '',
      );
      if (number == null) return null;
      return (number * 1073741824).round();
    }
    return null;
  }
}
