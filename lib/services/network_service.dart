import 'dart:convert';
import 'package:http/http.dart' as http;

class IpInfo {
  final String ip;
  final String country;
  final String city;

  IpInfo({required this.ip, this.country = '', this.city = ''});
}

class NetworkService {
  static Future<IpInfo?> fetchCurrentIp() async {
    try {
      // ip-api.com — бесплатный сервис, возвращает IP + геолокацию
      final response = await http.get(
        Uri.parse('http://ip-api.com/json/?fields=query,country,city'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return IpInfo(
          ip: data['query'] ?? '—',
          country: data['country'] ?? '',
          city: data['city'] ?? '',
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> checkInternetConnection() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.google.com/generate_204'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
