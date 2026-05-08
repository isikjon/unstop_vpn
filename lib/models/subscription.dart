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

  /// Raw error message from backend, if any.
  final String? errorMessage;

  const Subscription({
    required this.isActive,
    required this.servers,
    this.expiresAt,
    this.trafficUsedBytes,
    this.trafficLimitBytes,
    this.planName,
    this.deviceUsedCount,
    this.deviceLimitCount,
    this.errorMessage,
  });

  static const Subscription empty = Subscription(isActive: false, servers: []);

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
        value?.contains('limit_devices') == true;
  }

  String? get userFacingError {
    if (isDeviceLimitExceeded) return 'Лимит устройств исчерпан';
    return errorMessage;
  }

  Map<String, dynamic> toCacheJson() => {
    'success': isActive || servers.isNotEmpty,
    'items': servers.map((s) => s.url).toList(),
    'meta': {
      'status': isActive ? 'active' : 'trial',
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
      if (item is String) {
        final s = VpnServer.tryParse(item);
        if (s != null) servers.add(s);
      } else if (item is Map && item['url'] is String) {
        final s = VpnServer.tryParse(item['url'] as String);
        if (s != null) servers.add(s);
      }
    }
    return Subscription(isActive: servers.isNotEmpty, servers: servers);
  }

  static Subscription _fromMap(Map<String, dynamic> json) {
    // Success flag — backend may use any of: success, ok, status.
    final successRaw = json['success'] ?? json['ok'] ?? json['status'];
    final success =
        successRaw == true ||
        successRaw == 1 ||
        successRaw == 'ok' ||
        successRaw == 'success';

    final errorMessage = (json['error'] ?? json['message'] ?? json['detail'])
        ?.toString();

    dynamic serversRaw =
        json['servers'] ??
        json['items'] ??
        json['configs'] ??
        json['vless'] ??
        json['trial_servers'] ??
        json['free_servers'] ??
        json['data'] ??
        (json['subscription'] is Map ? json['subscription']['servers'] : null);

    final servers = <VpnServer>[];
    if (serversRaw is List) {
      for (final item in serversRaw) {
        if (item is String) {
          final s = VpnServer.tryParse(item);
          if (s != null) servers.add(s);
        } else if (item is Map && item['url'] is String) {
          final s = VpnServer.tryParse(item['url'] as String);
          if (s != null) servers.add(s);
        }
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
        subRaw['finished_at'];
    if (expField is String) {
      expiresAt = DateTime.tryParse(expField);
    } else if (expField is int) {
      // Could be seconds OR milliseconds. Heuristic: > 1e12 means ms.
      expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expField > 1000000000000 ? expField : expField * 1000,
      );
    }

    final trafficUsed = _trafficBytesFrom(
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
      gbKeys: const [
        'traffic_whitelist_total_gb',
        'traffic_limit_gb',
        'limit_gb',
        'quota_gb',
        'total_gb',
      ],
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
    final activeByStatus =
        status == null ||
        status == 'active' ||
        status == 'paid' ||
        status == 'enabled';
    final limitError = _isLimitDevicesError(errorMessage);
    final hasActivePeriod =
        expiresAt == null || expiresAt.isAfter(DateTime.now());

    final isActive =
        activeByStatus &&
        hasActivePeriod &&
        (success || limitError) &&
        (servers.isNotEmpty || limitError || deviceLimit != null);

    return Subscription(
      isActive: isActive,
      servers: servers,
      expiresAt: expiresAt,
      trafficUsedBytes: trafficUsed,
      trafficLimitBytes: trafficLimit,
      planName: plan,
      deviceUsedCount: deviceUsed,
      deviceLimitCount: deviceLimit,
      errorMessage: success ? null : errorMessage,
    );
  }

  static bool _isLimitDevicesError(String? value) {
    final normalized = value?.toLowerCase().trim();
    return normalized == 'limit_devices' ||
        normalized == 'device_limit' ||
        normalized == 'devices_limit' ||
        normalized?.contains('limit_devices') == true;
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
