import 'dart:convert';

/// A single VPN server entry parsed from a VPN URI or raw Xray JSON config.
///
/// We keep the raw config around so the platform VPN layer can hand it to
/// Xray without losing server-specific Reality / Shadowsocks settings.
class VpnServer {
  final String id;
  final String url; // raw vless://..., ss://..., or Xray JSON config
  final String remark; // decoded fragment
  final String address; // host
  final int port;
  final String country;
  final String flag;
  final String city;

  const VpnServer({
    required this.id,
    required this.url,
    required this.remark,
    required this.address,
    required this.port,
    required this.country,
    required this.flag,
    required this.city,
  });

  /// Parse a single VPN server line.
  ///
  /// Returns null if the input is malformed.
  static VpnServer? tryParse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('unstop://config/')) {
      return _parseProtectedConfig(trimmed);
    }

    final xrayServer = _parseXrayJsonConfig(trimmed);
    if (xrayServer != null) return xrayServer;

    if (!trimmed.startsWith('vless://') &&
        !trimmed.startsWith('vmess://') &&
        !trimmed.startsWith('trojan://') &&
        !trimmed.startsWith('ss://') &&
        !trimmed.startsWith('socks://')) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final fragment = Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));
    final remark = fragment.isEmpty ? _protocolName(uri.scheme) : fragment;

    final countryInfo = _extractCountryInfo(remark, uri.host);

    return VpnServer(
      id: '${uri.scheme}:${uri.host}:${uri.hasPort ? uri.port : _defaultPort(uri.scheme)}:${_stableHash(trimmed)}',
      url: trimmed,
      remark: remark,
      address: uri.host,
      port: uri.hasPort ? uri.port : _defaultPort(uri.scheme),
      country: countryInfo.country,
      flag: countryInfo.flag,
      city: countryInfo.city,
    );
  }

  static int _defaultPort(String scheme) {
    return 443;
  }

  static String protectUrl(String value) {
    if (value.startsWith('unstop://config/')) return value;
    if (!_isSupportedConfigString(value)) return value;
    final encoded = base64UrlEncode(utf8.encode(value)).replaceAll('=', '');
    return 'unstop://config/$encoded';
  }

  static bool isRawXrayConfig(String value) =>
      _parseXrayConfigMap(value) != null;

  static VpnServer? _parseProtectedConfig(String line) {
    final uri = Uri.tryParse(line);
    if (uri == null || uri.host != 'config' || uri.pathSegments.isEmpty) {
      return null;
    }

    try {
      final normalized = base64Url.normalize(uri.pathSegments.first);
      final decoded = utf8.decode(base64Url.decode(normalized));
      return tryParse(decoded);
    } catch (_) {
      return null;
    }
  }

  static String _protocolName(String scheme) {
    return switch (scheme.toLowerCase()) {
      'vless' => 'VLESS',
      'vmess' => 'VMess',
      'trojan' => 'Trojan',
      'ss' => 'Shadowsocks',
      'shadowsocks' => 'Shadowsocks',
      'socks' => 'SOCKS',
      _ => 'Server',
    };
  }

  static bool _isSupportedConfigString(String value) {
    const prefixes = ['vless://', 'vmess://', 'trojan://', 'ss://', 'socks://'];
    return prefixes.any(value.startsWith) || isRawXrayConfig(value);
  }

  static VpnServer? _parseXrayJsonConfig(String line) {
    final config = _parseXrayConfigMap(line);
    if (config == null) return null;

    final outbound = _firstProxyOutbound(config);
    if (outbound == null) return null;

    final protocol = outbound['protocol']?.toString().toLowerCase() ?? 'xray';
    final endpoint = _endpointFromOutbound(outbound);
    final address = endpoint.address;
    final port = endpoint.port;
    if (address.isEmpty || port <= 0) return null;
    final remark = (config['remarks'] ?? config['remark'] ?? config['name'])
        ?.toString()
        .trim();
    final displayRemark = remark == null || remark.isEmpty
        ? _protocolName(protocol)
        : remark;
    final countryInfo = _extractCountryInfo(displayRemark, address);
    final idSeed = '$protocol|$address|$port|$displayRemark|$line';

    return VpnServer(
      id: 'xray:${_stableHash(idSeed)}',
      url: line,
      remark: displayRemark,
      address: address,
      port: port,
      country: countryInfo.country,
      flag: countryInfo.flag,
      city: countryInfo.city,
    );
  }

  static Map<String, dynamic>? _parseXrayConfigMap(String line) {
    final trimmed = line.trimLeft();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return null;
      final outbounds = decoded['outbounds'];
      if (outbounds is! List || outbounds.isEmpty) return null;
      final inbounds = decoded['inbounds'];
      if (inbounds != null && inbounds is! List) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _firstProxyOutbound(
    Map<String, dynamic> config,
  ) {
    final outbounds = config['outbounds'];
    if (outbounds is! List) return null;

    for (final outbound in outbounds) {
      if (outbound is! Map) continue;
      final map = outbound.cast<String, dynamic>();
      final protocol = map['protocol']?.toString().toLowerCase();
      if (const {
        'vless',
        'vmess',
        'trojan',
        'shadowsocks',
        'socks',
      }.contains(protocol)) {
        return map;
      }
    }
    return null;
  }

  static _Endpoint _endpointFromOutbound(Map<String, dynamic> outbound) {
    final protocol = outbound['protocol']?.toString().toLowerCase();
    final settings = outbound['settings'];
    if (settings is Map) {
      final typed = settings.cast<String, dynamic>();
      if (protocol == 'vless' || protocol == 'vmess' || protocol == 'trojan') {
        final vnext = typed['vnext'];
        if (vnext is List && vnext.isNotEmpty && vnext.first is Map) {
          final first = (vnext.first as Map).cast<String, dynamic>();
          return _Endpoint(
            address: first['address']?.toString() ?? '',
            port: _asPort(first['port']) ?? 443,
          );
        }
      }

      final servers = typed['servers'];
      if (servers is List && servers.isNotEmpty && servers.first is Map) {
        final first = (servers.first as Map).cast<String, dynamic>();
        return _Endpoint(
          address: first['address']?.toString() ?? '',
          port: _asPort(first['port']) ?? 443,
        );
      }
    }
    return const _Endpoint(address: '', port: 443);
  }

  static int? _asPort(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Try to extract a country name + emoji flag + city from the remark or host.
  ///
  /// Heuristics:
  /// 1. If remark already contains an emoji flag, use it.
  /// 2. Otherwise look for a 2-letter country code at the start of the remark
  ///    (e.g. "NL-Amsterdam-1") and translate it.
  /// 3. Fall back to "Server" + globe.
  static _CountryInfo _extractCountryInfo(String remark, String host) {
    // 1. Emoji flag detection (regional indicator pairs U+1F1E6..U+1F1FF).
    for (final r in remark.runes) {
      if (r >= 0x1F1E6 && r <= 0x1F1FF) {
        // Found a flag. Try to grab the country/city text after it.
        final flag = String.fromCharCodes(
          remark.runes.where((c) => c >= 0x1F1E6 && c <= 0x1F1FF).take(2),
        );
        final rest = remark
            .replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '')
            .trim();
        final parts = rest
            .split(RegExp(r'[\s\-_·,|]+'))
            .where((s) => s.isNotEmpty)
            .toList();
        return _CountryInfo(
          country: parts.isNotEmpty ? parts.first : 'Server',
          flag: flag,
          city: parts.length > 1 ? parts.sublist(1).join(' ') : '',
        );
      }
    }

    // 2. Two-letter ISO code prefix.
    final match = RegExp(r'^([A-Za-z]{2})[\s\-_·,|]').firstMatch(remark);
    if (match != null) {
      final code = match.group(1)!.toUpperCase();
      final info = _isoCountries[code];
      if (info != null) {
        final rest = remark.substring(match.end).trim();
        return _CountryInfo(country: info.name, flag: info.flag, city: rest);
      }
    }

    // 3. Fallback.
    return _CountryInfo(
      country: remark.isNotEmpty && !_looksLikeNetworkAddress(remark)
          ? remark
          : 'Server',
      flag: '🌐',
      city: '',
    );
  }

  static bool _looksLikeNetworkAddress(String value) {
    final text = value.trim().toLowerCase();
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(text)) return true;
    if (text.contains(':') && RegExp(r'^[0-9a-f:]+$').hasMatch(text)) {
      return true;
    }
    return false;
  }
}

class _Endpoint {
  final String address;
  final int port;
  const _Endpoint({required this.address, required this.port});
}

class _CountryInfo {
  final String country;
  final String flag;
  final String city;
  const _CountryInfo({
    required this.country,
    required this.flag,
    required this.city,
  });
}

class _Iso {
  final String name;
  final String flag;
  const _Iso(this.name, this.flag);
}

const _isoCountries = <String, _Iso>{
  'NL': _Iso('Нидерланды', '🇳🇱'),
  'DE': _Iso('Германия', '🇩🇪'),
  'FI': _Iso('Финляндия', '🇫🇮'),
  'US': _Iso('США', '🇺🇸'),
  'GB': _Iso('Великобритания', '🇬🇧'),
  'UK': _Iso('Великобритания', '🇬🇧'),
  'FR': _Iso('Франция', '🇫🇷'),
  'JP': _Iso('Япония', '🇯🇵'),
  'SG': _Iso('Сингапур', '🇸🇬'),
  'SE': _Iso('Швеция', '🇸🇪'),
  'PL': _Iso('Польша', '🇵🇱'),
  'TR': _Iso('Турция', '🇹🇷'),
  'CA': _Iso('Канада', '🇨🇦'),
  'CH': _Iso('Швейцария', '🇨🇭'),
  'AT': _Iso('Австрия', '🇦🇹'),
  'NO': _Iso('Норвегия', '🇳🇴'),
  'ES': _Iso('Испания', '🇪🇸'),
  'IT': _Iso('Италия', '🇮🇹'),
  'IE': _Iso('Ирландия', '🇮🇪'),
  'IN': _Iso('Индия', '🇮🇳'),
  'HK': _Iso('Гонконг', '🇭🇰'),
  'KR': _Iso('Южная Корея', '🇰🇷'),
  'AU': _Iso('Австралия', '🇦🇺'),
  'AE': _Iso('ОАЭ', '🇦🇪'),
  'CZ': _Iso('Чехия', '🇨🇿'),
  'LV': _Iso('Латвия', '🇱🇻'),
  'LT': _Iso('Литва', '🇱🇹'),
  'EE': _Iso('Эстония', '🇪🇪'),
  'RU': _Iso('Россия', '🇷🇺'),
  'UA': _Iso('Украина', '🇺🇦'),
  'KZ': _Iso('Казахстан', '🇰🇿'),
};
