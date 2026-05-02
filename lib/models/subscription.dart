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
    if (trafficUsedBytes == null || trafficLimitBytes == null || trafficLimitBytes == 0) {
      return null;
    }
    return (trafficUsedBytes! / trafficLimitBytes!).clamp(0.0, 1.0);
  }

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
    final success = successRaw == true ||
        successRaw == 1 ||
        successRaw == 'ok' ||
        successRaw == 'success';

    final errorMessage = (json['error'] ?? json['message'] ?? json['detail']) as String?;

    dynamic serversRaw = json['servers'] ??
        json['items'] ??
        json['configs'] ??
        json['vless'] ??
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
    final subRaw = json['subscription'] is Map<String, dynamic>
        ? json['subscription'] as Map<String, dynamic>
        : json;

    DateTime? expiresAt;
    final expField = subRaw['expires_at'] ??
        subRaw['expiration'] ??
        subRaw['expire'] ??
        subRaw['valid_until'];
    if (expField is String) {
      expiresAt = DateTime.tryParse(expField);
    } else if (expField is int) {
      // Could be seconds OR milliseconds. Heuristic: > 1e12 means ms.
      expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expField > 1000000000000 ? expField : expField * 1000,
      );
    }

    int? trafficUsed = _asInt(subRaw['traffic_used'] ??
        subRaw['used'] ??
        subRaw['usage'] ??
        subRaw['traffic']);
    int? trafficLimit = _asInt(subRaw['traffic_limit'] ??
        subRaw['limit'] ??
        subRaw['quota'] ??
        subRaw['total']);

    final plan = (subRaw['plan'] ?? subRaw['tariff'] ?? subRaw['type']) as String?;

    final isActive = success && servers.isNotEmpty &&
        (expiresAt == null || expiresAt.isAfter(DateTime.now()));

    return Subscription(
      isActive: isActive,
      servers: servers,
      expiresAt: expiresAt,
      trafficUsedBytes: trafficUsed,
      trafficLimitBytes: trafficLimit,
      planName: plan,
      errorMessage: success ? null : errorMessage,
    );
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
