import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import '../models/vpn_status.dart';
import '../models/vpn_server.dart';
import '../services/network_service.dart';
import 'settings_provider.dart';
import 'subscription_provider.dart';

class VpnState {
  final VpnStatus status;
  final String? lastError;
  final String ping;
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
    this.currentIp = '...',
    this.ipLocation = '',
    this.hasInternet = true,
    this.activeServer,
  });

  VpnState copyWith({
    VpnStatus? status,
    String? lastError,
    String? ping,
    String? currentIp,
    String? ipLocation,
    bool? hasInternet,
    VpnServer? activeServer,
    bool clearError = false,
    bool clearActiveServer = false,
  }) {
    return VpnState(
      status: status ?? this.status,
      lastError: clearError ? null : (lastError ?? this.lastError),
      ping: ping ?? this.ping,
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

class VpnNotifier extends Notifier<VpnState> {
  late FlutterV2ray _v2ray;
  Timer? _pingTimer;

  @override
  VpnState build() {
    _v2ray = FlutterV2ray(onStatusChanged: _handleStatus);
    _v2ray.initializeV2Ray(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );

    ref.onDispose(() {
      _pingTimer?.cancel();
    });

    _refreshIp();
    return VpnState();
  }

  void _handleStatus(V2RayStatus status) {
    switch (status.state) {
      case 'CONNECTED':
        state = state.copyWith(status: VpnStatus.connected);
        _startPingInterval();
        Future.delayed(const Duration(seconds: 2), _refreshIp);
        break;
      case 'DISCONNECTED':
        state = state.copyWith(
          status: VpnStatus.idle,
          ping: '—',
          clearActiveServer: true,
        );
        _pingTimer?.cancel();
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

    final server = ref.read(subscriptionProvider).effectiveServer;
    if (server == null) {
      state = state.copyWith(
        status: VpnStatus.error,
        lastError: 'Нет доступных серверов. Проверьте подписку.',
      );
      return;
    }
    await connect(server);
  }

  Future<void> connect(VpnServer server) async {
    final granted = await _v2ray.requestPermission();
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
      final V2RayURL parsedUrl = FlutterV2ray.parseFromURL(server.url);
      final String baseConfig = parsedUrl.getFullConfiguration();
      final String config = _applyTunnelSettings(baseConfig);

      // Debug: show sockopt section to verify fragment/noise injection
      try {
        final dbg = jsonDecode(config) as Map<String, dynamic>;
        final ob = (dbg['outbounds'] as List).first as Map<String, dynamic>;
        final so = (ob['streamSettings'] as Map?)?['sockopt'];
        debugPrint('[VPN] sockopt -> $so');
      } catch (_) {}

      await _v2ray.startV2Ray(
        remark: parsedUrl.remark.isEmpty ? server.remark : parsedUrl.remark,
        config: config,
        proxyOnly: false,
        bypassSubnets: [],
        notificationDisconnectButtonName: "Отключить",
      );
    } catch (e) {
      state = state.copyWith(
        status: VpnStatus.error,
        lastError: 'Ошибка подключения: $e',
      );
    }
  }

  Future<void> disconnect() async {
    try {
      await _v2ray.stopV2Ray();
    } catch (_) {
      state = state.copyWith(
        status: VpnStatus.error,
        lastError: 'Ошибка при отключении',
      );
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
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (state.status == VpnStatus.connected) {
        try {
          final delay = await _v2ray.getConnectedServerDelay();
          state = state.copyWith(ping: '$delay ms');
        } catch (_) {
          state = state.copyWith(ping: '-- ms');
        }
      }
    });
  }
}
