/// Hardcoded constants for backend integration and external links.
class AppConfig {
  /// App version used in backend user-agent/device tracking headers.
  static const String appVersion = '1.0.0';

  /// Base URL нашего бэкенда на сервере 2.26.124.34.
  /// Все запросы (подписка + auth) идут через него.
  static const String apiBase = 'https://dev-game.404.mn/api';

  /// API-ключ — одинаковый для клиента и сервера.
  static const String apiKey = 'aksdSDA12osadQWE493123wsaS';

  /// Telegram bot username (without @). Used for deep links and
  /// "open bot" buttons throughout the app.
  static const String botUsername = 'unstop_vpn_bot';

  /// Main Telegram entry where users can buy or renew a subscription.
  static const String subscriptionBotUsername = 'unstop_vpn_bot';

  /// Direct deep link to the bot — opens Telegram if installed.
  static String get botDeepLink => 'https://t.me/$botUsername';

  /// Direct deep link to the subscription bot.
  static String get subscriptionBotDeepLink =>
      'https://t.me/$subscriptionBotUsername';

  /// Temporary free proxy landing page.
  static const String proxyLink = 'https://eco-traffic.org/proxy';

  /// Bot deep link with start parameter (e.g. for auth flow).
  static String botStartLink(String payload) =>
      'https://t.me/$botUsername?start=$payload';

  /// Support contact (Telegram).
  static const String supportLink = 'https://t.me/unstop_vpn_support';

  /// How often to refresh subscription info while app is in foreground.
  static const Duration subscriptionRefreshInterval = Duration(hours: 2);

  /// HTTP timeout for API calls.
  static const Duration apiTimeout = Duration(seconds: 6);

  /// iOS Packet Tunnel extension used for VLESS/Reality connections.
  static const String iosPacketTunnelBundleIdentifier =
      'com.unstopplus.vpn.PacketTunnel';
  static const String iosAppGroupIdentifier = 'group.com.unstopplus.vpn';
}
