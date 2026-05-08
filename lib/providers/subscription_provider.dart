import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../models/subscription.dart';
import '../models/vpn_server.dart';
import '../services/api_service.dart';
import '../services/secure_storage.dart';
import 'auth_provider.dart';

class ServerDisplay {
  final String flag;
  final String country;
  final String subtitle;

  const ServerDisplay({
    required this.flag,
    required this.country,
    required this.subtitle,
  });

  factory ServerDisplay.fromVpnServer(VpnServer server) {
    return ServerDisplay(
      flag: server.flag,
      country: server.country,
      subtitle: server.city.isNotEmpty ? server.city : server.address,
    );
  }
}

final selectedServerDisplayProvider =
    NotifierProvider<SelectedServerDisplayNotifier, ServerDisplay?>(
      SelectedServerDisplayNotifier.new,
    );

class SelectedServerDisplayNotifier extends Notifier<ServerDisplay?> {
  @override
  ServerDisplay? build() {
    final server = ref.watch(subscriptionProvider).effectiveServer;
    return server == null ? null : ServerDisplay.fromVpnServer(server);
  }

  void select(ServerDisplay server) {
    state = server;
  }
}

class SubscriptionState {
  final Subscription subscription;
  final bool isLoading;
  final String? error;

  /// Currently selected server. May be null if user hasn't picked one
  /// (in which case the UI defaults to the first server in the list).
  final VpnServer? selectedServer;

  const SubscriptionState({
    this.subscription = Subscription.empty,
    this.isLoading = false,
    this.error,
    this.selectedServer,
  });

  SubscriptionState copyWith({
    Subscription? subscription,
    bool? isLoading,
    String? error,
    VpnServer? selectedServer,
    bool clearError = false,
    bool clearSelected = false,
  }) {
    return SubscriptionState(
      subscription: subscription ?? this.subscription,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      selectedServer: clearSelected
          ? null
          : (selectedServer ?? this.selectedServer),
    );
  }

  /// Effective server: explicit selection > first available > null.
  VpnServer? get effectiveServer {
    if (selectedServer != null && _isConnectableServer(selectedServer!)) {
      return selectedServer;
    }
    for (final server in subscription.servers) {
      if (_isConnectableServer(server)) return server;
    }
    if (subscription.servers.isNotEmpty) return subscription.servers.first;
    return null;
  }
}

bool _isConnectableServer(VpnServer server) {
  final remark = server.remark.toLowerCase();
  final country = server.country.toLowerCase();
  final address = server.address.toLowerCase();
  if (address == 'ya.ru' && server.port == 1234) return false;
  if (remark.contains('автовыбор') || country.contains('автовыбор')) {
    return false;
  }
  return true;
}

final subscriptionProvider =
    NotifierProvider<SubscriptionNotifier, SubscriptionState>(
      SubscriptionNotifier.new,
    );

class SubscriptionNotifier extends Notifier<SubscriptionState> {
  Timer? _refreshTimer;

  @override
  SubscriptionState build() {
    // Auto-refresh whenever the auth state changes (login / logout).
    ref.listen(authProvider, (prev, next) {
      if (next.isAuthenticated && (prev?.telegramId != next.telegramId)) {
        Future.microtask(() async {
          await _loadCachedSubscription();
          await refresh();
        });
      }
      if (!next.isAuthenticated) {
        _refreshTimer?.cancel();
        state = const SubscriptionState();
      }
    });

    ref.onDispose(() => _refreshTimer?.cancel());

    // If we're already authenticated at boot, kick off an initial fetch.
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      Future.microtask(() async {
        await _loadCachedSubscription();
        await refresh();
      });
    }

    return const SubscriptionState();
  }

  Future<void> _loadCachedSubscription() async {
    final raw = await VpnSecureStorage.getCachedSubscriptionPayload();
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      final cached = Subscription.fromAny(decoded);
      if (cached.servers.isEmpty && !cached.isActive) return;
      final selected = await _restoreSelectedServer(cached);
      state = state.copyWith(
        subscription: cached,
        selectedServer: selected,
        isLoading: false,
        clearError: true,
      );
    } catch (_) {
      await VpnSecureStorage.clearCachedSubscriptionPayload();
    }
  }

  Future<void> refresh() async {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await ApiService.fetchSubscriptionResult(auth.telegramId!);
      final sub = result.subscription;
      final selected = await _restoreSelectedServer(sub);

      if (sub.servers.isNotEmpty || sub.isActive) {
        await VpnSecureStorage.saveCachedSubscriptionPayload(
          jsonEncode(sub.toCacheJson()),
        );
      } else {
        await VpnSecureStorage.clearCachedSubscriptionPayload();
      }

      state = state.copyWith(
        subscription: sub,
        isLoading: false,
        selectedServer: selected,
      );

      _scheduleNextRefresh();
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Ошибка: $e');
    }
  }

  Future<VpnServer?> _restoreSelectedServer(Subscription sub) async {
    VpnServer? selected = state.selectedServer;
    if (selected != null) {
      selected = sub.servers.cast<VpnServer?>().firstWhere(
        (s) => s?.id == selected!.id || s?.url == selected.url,
        orElse: () => null,
      );
      if (selected != null && !_isConnectableServer(selected)) {
        selected = null;
      }
    }
    if (selected == null) {
      final savedId = await VpnSecureStorage.getSelectedServerId();
      if (savedId != null) {
        for (final s in sub.servers) {
          if ((s.id == savedId || s.url == savedId) &&
              _isConnectableServer(s)) {
            selected = s;
            break;
          }
        }
      }
    }
    return selected;
  }

  Future<void> selectServer(VpnServer server) async {
    state = state.copyWith(selectedServer: server);
    await VpnSecureStorage.saveSelectedServerId(server.url);
  }

  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(AppConfig.subscriptionRefreshInterval, refresh);
  }
}
