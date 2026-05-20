import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:flutter_vless/flutter_vless.dart' as flutter_vless;
import '../config/app_config.dart';
import '../models/vpn_status.dart';
import '../models/vpn_server.dart';
import '../services/network_service.dart';
import 'settings_provider.dart';
import 'subscription_provider.dart';
import 'trial_provider.dart';

class VpnState {
  final VpnStatus status;
  final String? lastError;
  final String ping;
  final Duration connectedFor;
  final int uploadSpeedBytesPerSecond;
  final int downloadSpeedBytesPerSecond;
  final int totalUploadBytes;
  final int totalDownloadBytes;
  final String currentIp;
  final String ipLocation;
  final bool hasInternet;

  /// Server we're currently connecting to / connected to. Distinct from
  /// the user's *selected* server in [SubscriptionState] — they only
  /// match while a session is active.
  final VpnServer? activeServer;

  VpnState({
    this.status = VpnStatus.idle,
    this.lastError,
    this.ping = '—',
    this.connectedFor = Duration.zero,
    this.uploadSpeedBytesPerSecond = 0,
    this.downloadSpeedBytesPerSecond = 0,
    this.totalUploadBytes = 0,
    this.totalDownloadBytes = 0,
    this.currentIp = '...',
    this.ipLocation = '',
    this.hasInternet = true,
    this.activeServer,
  });

  VpnState copyWith({
    VpnStatus? status,
    String? lastError,
    String? ping,
    Duration? connectedFor,
    int? uploadSpeedBytesPerSecond,
    int? downloadSpeedBytesPerSecond,
    int? totalUploadBytes,
    int? totalDownloadBytes,
    String? currentIp,
    String? ipLocation,
    bool? hasInternet,
    VpnServer? activeServer,
    bool clearError = false,
    bool clearActiveServer = false,
    bool resetTraffic = false,
  }) {
    return VpnState(
      status: status ?? this.status,
      lastError: clearError ? null : (lastError ?? this.lastError),
      ping: ping ?? this.ping,
      connectedFor: resetTraffic
          ? Duration.zero
          : (connectedFor ?? this.connectedFor),
      uploadSpeedBytesPerSecond: resetTraffic
          ? 0
          : (uploadSpeedBytesPerSecond ?? this.uploadSpeedBytesPerSecond),
      downloadSpeedBytesPerSecond: resetTraffic
          ? 0
          : (downloadSpeedBytesPerSecond ?? this.downloadSpeedBytesPerSecond),
      totalUploadBytes: resetTraffic
          ? 0
          : (totalUploadBytes ?? this.totalUploadBytes),
      totalDownloadBytes: resetTraffic
          ? 0
          : (totalDownloadBytes ?? this.totalDownloadBytes),
      currentIp: currentIp ?? this.currentIp,
      ipLocation: ipLocation ?? this.ipLocation,
      hasInternet: hasInternet ?? this.hasInternet,
      activeServer: clearActiveServer
          ? null
          : (activeServer ?? this.activeServer),
    );
  }
}

final vpnProvider = NotifierProvider<VpnNotifier, VpnState>(VpnNotifier.new);

String _platformErrorMessage(Object error) {
  if (error is PlatformException) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) return message;
  }
  return error.toString();
}

class _PreparedServerConfig {
  final String config;
  final String remark;

  const _PreparedServerConfig({required this.config, required this.remark});
}

class VpnNotifier extends Notifier<VpnState> {
  FlutterV2ray? _v2ray;
  Future<void>? _androidInitFuture;
  flutter_vless.FlutterVless? _iosVless;
  Future<void>? _iosInitFuture;
  Timer? _pingTimer;
  Timer? _connectionTimer;
  DateTime? _connectedAt;
  bool _pingRequestInFlight = false;
  bool _operationInProgress = false;
  bool _disconnectAfterOperation = false;
  VpnServer? _queuedConnectServer;

  @override
  VpnState build() {
    if (Platform.isAndroid) {
      _v2ray = FlutterV2ray(onStatusChanged: _handleStatus);
      _androidInitFuture = _v2ray!.initializeV2Ray(
        notificationIconResourceType: "mipmap",
        notificationIconResourceName: "ic_launcher",
      );
    } else if (Platform.isIOS) {
      _iosVless = flutter_vless.FlutterVless(
        onStatusChanged: _handleIosVlessStatus,
      );
      _iosInitFuture = _iosVless!.initializeVless(
        providerBundleIdentifier: AppConfig.iosPacketTunnelBundleIdentifier,
        groupIdentifier: AppConfig.iosAppGroupIdentifier,
      );
    }

    ref.onDispose(() {
      _pingTimer?.cancel();
      _connectionTimer?.cancel();
    });

    _refreshIp();
    return VpnState();
  }

  void _handleStatus(V2RayStatus status) {
    switch (status.state) {
      case 'CONNECTED':
        final wasConnected = state.status == VpnStatus.connected;
        _markConnected(
          reportedDuration: _parseV2rayDuration(status.duration),
          uploadSpeedBytesPerSecond: status.uploadSpeed,
          downloadSpeedBytesPerSecond: status.downloadSpeed,
          totalUploadBytes: status.upload,
          totalDownloadBytes: status.download,
        );
        if (!wasConnected) {
          _startPingInterval();
          Future.delayed(const Duration(seconds: 2), _refreshIp);
        }
        break;
      case 'DISCONNECTED':
        if (state.status == VpnStatus.connecting ||
            state.status == VpnStatus.reconnecting) {
          return;
        }
        _markDisconnected(clearActiveServer: true);
        _refreshIp();
        break;
      case 'CONNECTING':
        state = state.copyWith(status: VpnStatus.connecting);
        break;
      default:
        if (status.state.isEmpty) {
          state = state.copyWith(status: VpnStatus.idle);
        }
    }
  }

  void _handleIosVlessStatus(flutter_vless.VlessStatus status) {
    switch (status.state.toUpperCase()) {
      case 'CONNECTED':
        final wasConnected = state.status == VpnStatus.connected;
        _markConnected(
          reportedDuration: Duration(seconds: status.duration),
          uploadSpeedBytesPerSecond: status.uploadSpeed,
          downloadSpeedBytesPerSecond: status.downloadSpeed,
          totalUploadBytes: status.upload,
          totalDownloadBytes: status.download,
        );
        if (!wasConnected) {
          _startPingInterval();
          Future.delayed(const Duration(seconds: 2), _refreshIp);
        }
        break;
      case 'CONNECTING':
        state = state.copyWith(status: VpnStatus.connecting);
        break;
      case 'RECONNECTING':
      case 'REASSERTING':
      case 'DISCONNECTING':
        state = state.copyWith(status: VpnStatus.reconnecting);
        break;
      case 'DISCONNECTED':
        if (state.status == VpnStatus.connecting ||
            state.status == VpnStatus.reconnecting) {
          return;
        }
        _markDisconnected(clearActiveServer: true);
        _refreshIp();
        break;
      default:
        _markDisconnected(clearActiveServer: true);
        _refreshIp();
    }
  }

  void _markConnected({
    Duration? reportedDuration,
    int? uploadSpeedBytesPerSecond,
    int? downloadSpeedBytesPerSecond,
    int? totalUploadBytes,
    int? totalDownloadBytes,
  }) {
    final now = DateTime.now();
    if (reportedDuration != null &&
        reportedDuration > Duration.zero &&
        (_connectedAt == null ||
            (now.difference(_connectedAt!).inSeconds -
                        reportedDuration.inSeconds)
                    .abs() >
                2)) {
      _connectedAt = now.subtract(reportedDuration);
    } else {
      _connectedAt ??= now;
    }

    final elapsed = reportedDuration != null && reportedDuration > Duration.zero
        ? reportedDuration
        : _safeDuration(now.difference(_connectedAt!));

    state = state.copyWith(
      status: VpnStatus.connected,
      connectedFor: _safeDuration(elapsed),
      uploadSpeedBytesPerSecond: _nonNegative(uploadSpeedBytesPerSecond ?? 0),
      downloadSpeedBytesPerSecond: _nonNegative(
        downloadSpeedBytesPerSecond ?? 0,
      ),
      totalUploadBytes: _nonNegative(
        totalUploadBytes ?? state.totalUploadBytes,
      ),
      totalDownloadBytes: _nonNegative(
        totalDownloadBytes ?? state.totalDownloadBytes,
      ),
      clearError: true,
    );
    _ensureConnectionTimer();
  }

  void _markDisconnected({
    bool clearActiveServer = false,
    VpnStatus status = VpnStatus.idle,
    String? lastError,
  }) {
    _connectedAt = null;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _pingTimer?.cancel();
    state = state.copyWith(
      status: status,
      lastError: lastError,
      ping: '—',
      clearActiveServer: clearActiveServer,
      resetTraffic: true,
    );
  }

  void _ensureConnectionTimer() {
    if (_connectionTimer?.isActive ?? false) return;
    _connectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final connectedAt = _connectedAt;
      if (state.status != VpnStatus.connected || connectedAt == null) {
        _connectionTimer?.cancel();
        _connectionTimer = null;
        return;
      }
      state = state.copyWith(
        connectedFor: _safeDuration(DateTime.now().difference(connectedAt)),
      );
    });
  }

  Duration? _parseV2rayDuration(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return null;
    return Duration(
      hours: int.parse(match.group(1)!),
      minutes: int.parse(match.group(2)!),
      seconds: int.parse(match.group(3)!),
    );
  }

  int _nonNegative(int value) => value < 0 ? 0 : value;

  Duration _safeDuration(Duration value) =>
      value.isNegative ? Duration.zero : value;

  Future<void> _refreshIp() async {
    final hasNet = await NetworkService.checkInternetConnection();
    if (!hasNet) {
      state = state.copyWith(
        hasInternet: false,
        currentIp: 'Нет сети',
        ipLocation: '',
      );
      return;
    }
    state = state.copyWith(hasInternet: true);

    final ipInfo = await NetworkService.fetchCurrentIp();
    if (ipInfo != null) {
      state = state.copyWith(
        currentIp: ipInfo.ip,
        ipLocation: [
          ipInfo.country,
          ipInfo.city,
        ].where((s) => s.isNotEmpty).join(', '),
      );
    }
  }

  /// Toggle: connects to the user's currently-selected server, or
  /// disconnects if already connected.
  Future<void> toggleConnection() async {
    if (state.status == VpnStatus.connecting ||
        state.status == VpnStatus.reconnecting) {
      return;
    }
    if (state.status == VpnStatus.connected) {
      await disconnect();
      return;
    }

    final subscription = ref.read(subscriptionProvider).subscription;
    final trial = ref.read(trialProvider);
    if (!subscription.isActive && trial.isExpired) {
      state = state.copyWith(
        status: VpnStatus.error,
        lastError: 'Пробный период истёк. Авторизуйтесь для доступа.',
      );
      return;
    }

    final server = ref.read(subscriptionProvider).effectiveServer;
    if (server == null) {
      final error = subscription.userFacingError;
      state = state.copyWith(
        status: VpnStatus.error,
        lastError: error ?? 'Нет доступных серверов. Проверьте подписку.',
      );
      return;
    }
    await connect(server);
  }

  Future<void> connect(VpnServer? server) async {
    if (server == null) {
      state = state.copyWith(
        status: VpnStatus.error,
        lastError: 'Нет доступных VPN серверов',
        clearActiveServer: true,
        resetTraffic: true,
      );
      return;
    }

    if (_operationInProgress) {
      if (state.activeServer?.url == server.url &&
          _queuedConnectServer == null) {
        return;
      }
      _queuedConnectServer = server;
      _disconnectAfterOperation = false;
      state = state.copyWith(
        status: VpnStatus.reconnecting,
        activeServer: server,
        clearError: true,
      );
      return;
    }

    await _runVpnOperation(() => _connectInternal(server));
  }

  Future<void> switchServer(VpnServer server) async {
    await connect(server);
  }

  Future<int?> measureServerDelay(VpnServer server) async {
    try {
      if (Platform.isIOS) {
        final iosVless = _iosVless;
        if (iosVless == null || !_isSupportedIosServer(server)) return null;
        await _iosInitFuture;
        final prepared = _prepareIosServerConfig(server);
        final delay = await iosVless
            .getServerDelay(config: prepared.config)
            .timeout(AppConfig.apiTimeout);
        return delay > 0 ? delay : null;
      }

      final v2ray = _v2ray;
      if (v2ray == null) return null;
      await _androidInitFuture;
      final prepared = _prepareAndroidServerConfig(server);
      final delay = await v2ray
          .getServerDelay(config: prepared.config)
          .timeout(AppConfig.apiTimeout);
      return delay > 0 ? delay : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _connectInternal(VpnServer? server) async {
    if (Platform.isIOS) {
      await _connectIosVless(server);
      return;
    }

    final v2ray = _v2ray;
    if (v2ray == null || server == null) {
      state = state.copyWith(
        status: VpnStatus.error,
        lastError: 'VPN недоступен на этой платформе',
      );
      return;
    }

    await _androidInitFuture;
    final granted = await v2ray.requestPermission();
    if (!granted) {
      state = state.copyWith(
        status: VpnStatus.error,
        lastError: 'Разрешение VPN отклонено',
      );
      return;
    }

    state = state.copyWith(
      status: VpnStatus.connecting,
      activeServer: server,
      clearError: true,
    );

    try {
      final prepared = _prepareAndroidServerConfig(server);

      // Debug: show sockopt section to verify fragment/noise injection
      try {
        final dbg = jsonDecode(prepared.config) as Map<String, dynamic>;
        final ob = (dbg['outbounds'] as List).first as Map<String, dynamic>;
        final so = (ob['streamSettings'] as Map?)?['sockopt'];
        debugPrint('[VPN] sockopt -> $so');
      } catch (_) {}

      await v2ray.startV2Ray(
        remark: prepared.remark,
        config: prepared.config,
        proxyOnly: false,
        bypassSubnets: [],
        notificationDisconnectButtonName: "Отключить",
      );
    } catch (e) {
      _markDisconnected(
        status: VpnStatus.error,
        lastError: 'Ошибка подключения: $e',
        clearActiveServer: true,
      );
    }
  }

  Future<void> disconnect() async {
    if (_operationInProgress) {
      _queuedConnectServer = null;
      _disconnectAfterOperation = true;
      return;
    }
    await _runVpnOperation(_disconnectInternal);
  }

  Future<void> _disconnectInternal() async {
    try {
      if (Platform.isIOS) {
        await _iosVless?.stopVless();
        _markDisconnected(clearActiveServer: true);
        await _refreshIp();
        return;
      }

      await _v2ray?.stopV2Ray();
    } catch (_) {
      _markDisconnected(
        status: VpnStatus.error,
        lastError: 'Ошибка при отключении',
      );
    }
  }

  Future<void> _runVpnOperation(Future<void> Function() operation) async {
    if (_operationInProgress) return;
    _operationInProgress = true;
    try {
      await operation();
    } finally {
      _operationInProgress = false;
      if (_disconnectAfterOperation) {
        _disconnectAfterOperation = false;
        await disconnect();
      } else {
        final nextServer = _queuedConnectServer;
        _queuedConnectServer = null;
        if (nextServer != null) {
          await connect(nextServer);
        }
      }
    }
  }

  /// Inject Xray fragment / noise settings into the JSON config.
  String _applyTunnelSettings(String configJson) {
    final settings = ref.read(tunnelSettingsProvider);
    if (!settings.fragmentEnabled && !settings.noiseEnabled) return configJson;

    try {
      final map = jsonDecode(configJson) as Map<String, dynamic>;
      final outbounds = map['outbounds'] as List<dynamic>?;
      if (outbounds == null || outbounds.isEmpty) return configJson;

      for (final ob in outbounds) {
        if (ob is! Map<String, dynamic>) continue;
        final protocol = ob['protocol'];
        if (protocol == 'vless' ||
            protocol == 'vmess' ||
            protocol == 'trojan' ||
            protocol == 'shadowsocks') {
          final stream =
              ob.putIfAbsent('streamSettings', () => <String, dynamic>{})
                  as Map<String, dynamic>;
          final sockopt =
              stream.putIfAbsent('sockopt', () => <String, dynamic>{})
                  as Map<String, dynamic>;

          if (settings.fragmentEnabled) {
            sockopt['fragment'] = settings.fragmentConfig;
          } else {
            sockopt.remove('fragment');
          }

          if (settings.noiseEnabled) {
            sockopt['noises'] = settings.noisesConfig;
          } else {
            sockopt.remove('noises');
          }

          if (sockopt.isEmpty) stream.remove('sockopt');
          break;
        }
      }

      return jsonEncode(map);
    } catch (_) {
      return configJson;
    }
  }

  void _startPingInterval() {
    _pingTimer?.cancel();
    unawaited(_updateConnectedPing());
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_updateConnectedPing());
    });
  }

  Future<void> _updateConnectedPing() async {
    if (state.status != VpnStatus.connected || _pingRequestInFlight) return;
    _pingRequestInFlight = true;
    try {
      final delay = Platform.isIOS
          ? await _iosVless!.getConnectedServerDelay()
          : await _v2ray!.getConnectedServerDelay();
      if (state.status == VpnStatus.connected) {
        state = state.copyWith(ping: delay > 0 ? '$delay ms' : '—');
      }
    } catch (_) {
      if (state.status == VpnStatus.connected) {
        state = state.copyWith(ping: '—');
      }
    } finally {
      _pingRequestInFlight = false;
    }
  }

  Future<void> _connectIosVless(VpnServer? server) async {
    final iosVless = _iosVless;
    if (iosVless == null || server == null) {
      state = state.copyWith(
        status: VpnStatus.error,
        lastError: 'Нет доступных VPN серверов',
        clearActiveServer: true,
        resetTraffic: true,
      );
      return;
    }

    if (!_isSupportedIosServer(server)) {
      state = state.copyWith(
        status: VpnStatus.error,
        lastError: 'Этот сервер не поддерживается на iOS',
        clearActiveServer: true,
        resetTraffic: true,
      );
      return;
    }

    final hasActiveSession =
        state.status == VpnStatus.connected ||
        state.status == VpnStatus.connecting ||
        state.status == VpnStatus.reconnecting;

    if (hasActiveSession && state.activeServer?.url == server.url) {
      return;
    }

    if (hasActiveSession && state.activeServer?.url != server.url) {
      await _disconnectInternal();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }

    state = state.copyWith(
      status: VpnStatus.connecting,
      activeServer: server,
      clearError: true,
    );

    try {
      await _iosInitFuture;
      final prepared = _prepareIosServerConfig(server);

      final granted = await iosVless.requestPermission();
      if (!granted) {
        _markDisconnected(
          status: VpnStatus.error,
          lastError: 'Разрешение VPN отклонено',
          clearActiveServer: true,
        );
        return;
      }
      await iosVless.startVless(
        remark: prepared.remark,
        config: prepared.config,
        proxyOnly: false,
        bypassSubnets: const [],
        notificationDisconnectButtonName: 'Отключить',
      );
    } catch (e) {
      _markDisconnected(
        status: VpnStatus.error,
        lastError: 'Ошибка VLESS подключения: ${_platformErrorMessage(e)}',
        clearActiveServer: true,
      );
    }
  }

  _PreparedServerConfig _prepareAndroidServerConfig(VpnServer server) {
    V2RayURL? parsedUrl;
    final String baseConfig;
    if (VpnServer.isRawXrayConfig(server.url)) {
      baseConfig = server.url;
    } else {
      parsedUrl = FlutterV2ray.parseFromURL(server.url);
      baseConfig = parsedUrl.getFullConfiguration();
    }
    return _PreparedServerConfig(
      config: _applyTunnelSettings(baseConfig),
      remark: parsedUrl == null || parsedUrl.remark.isEmpty
          ? server.remark
          : parsedUrl.remark,
    );
  }

  _PreparedServerConfig _prepareIosServerConfig(VpnServer server) {
    flutter_vless.FlutterVlessURL? parsedUrl;
    final String baseConfig;
    if (VpnServer.isRawXrayConfig(server.url)) {
      baseConfig = server.url;
    } else {
      parsedUrl = flutter_vless.FlutterVless.parseFromURL(server.url);
      baseConfig = parsedUrl.getFullConfiguration();
    }
    return _PreparedServerConfig(
      config: _applyTunnelSettings(baseConfig),
      remark: parsedUrl == null || parsedUrl.remark.isEmpty
          ? server.remark
          : parsedUrl.remark,
    );
  }

  bool _isSupportedIosServer(VpnServer server) {
    if (VpnServer.isRawXrayConfig(server.url)) return true;
    final scheme = Uri.tryParse(server.url)?.scheme.toLowerCase();
    return const {'vless', 'vmess', 'trojan', 'ss', 'socks'}.contains(scheme);
  }
}
