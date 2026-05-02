/// Hardcoded constants for backend integration and external links.
class AppConfig {
  /// Base URL нашего бэкенда на сервере 2.26.124.34.
  /// Все запросы (подписка + auth) идут через него.
  static const String apiBase = 'http://2.26.124.34:8000/api';

  /// API-ключ — одинаковый для клиента и сервера.
  static const String apiKey = 'aksdSDA12osadQWE493123wsaS';

  /// Telegram bot username (without @). Used for deep links and
  /// "open bot" buttons throughout the app.
  static const String botUsername = 'unstop_vpn_bot';

  /// Direct deep link to the bot — opens Telegram if installed.
  static String get botDeepLink => 'https://t.me/$botUsername';

  /// Bot deep link with start parameter (e.g. for auth flow).
  static String botStartLink(String payload) =>
      'https://t.me/$botUsername?start=$payload';

  /// Support contact (Telegram).
  static const String supportLink = 'https://t.me/unstop_vpn_support';

  /// How often to refresh subscription info while app is in foreground.
  static const Duration subscriptionRefreshInterval = Duration(minutes: 15);

  /// HTTP timeout for API calls.
  static const Duration apiTimeout = Duration(seconds: 15);
}
