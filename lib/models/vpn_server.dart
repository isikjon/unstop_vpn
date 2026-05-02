/// A single VPN server entry parsed from a vless:// URI.
///
/// We keep the raw URI around so it can be handed back to flutter_v2ray's
/// `FlutterV2ray.parseFromURL` without having to round-trip through a
/// custom config builder. Display fields (country, flag, city) are
/// best-effort heuristics over the URI fragment / hostname.
class VpnServer {
  final String id;
  final String url;       // raw vless://...
  final String remark;    // decoded fragment
  final String address;   // host
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

  /// Parse a single vless:// line.
  ///
  /// Returns null if the input is malformed.
  static VpnServer? tryParse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('vless://') &&
        !trimmed.startsWith('vmess://') &&
        !trimmed.startsWith('trojan://') &&
        !trimmed.startsWith('ss://')) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final fragment =
        Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));
    final remark = fragment.isEmpty ? (uri.host) : fragment;

    final countryInfo = _extractCountryInfo(remark, uri.host);

    return VpnServer(
      id: '${uri.host}:${uri.port}',
      url: trimmed,
      remark: remark,
      address: uri.host,
      port: uri.hasPort ? uri.port : 443,
      country: countryInfo.country,
      flag: countryInfo.flag,
      city: countryInfo.city,
    );
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
            remark.runes.where((c) => c >= 0x1F1E6 && c <= 0x1F1FF).take(2));
        final rest =
            remark.replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '').trim();
        final parts = rest.split(RegExp(r'[\s\-_·,|]+'))
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
        return _CountryInfo(
          country: info.name,
          flag: info.flag,
          city: rest,
        );
      }
    }

    // 3. Fallback.
    return _CountryInfo(country: remark.isNotEmpty ? remark : host, flag: '🌐', city: '');
  }
}

class _CountryInfo {
  final String country;
  final String flag;
  final String city;
  const _CountryInfo({required this.country, required this.flag, required this.city});
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
