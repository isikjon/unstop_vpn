import 'dart:async';
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
        SelectedServerDisplayNotifier.new);

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
      selectedServer:
          clearSelected ? null : (selectedServer ?? this.selectedServer),
    );
  }

  /// Effective server: explicit selection > first available > null.
  VpnServer? get effectiveServer {
    if (selectedServer != null) return selectedServer;
    if (subscription.servers.isNotEmpty) return subscription.servers.first;
    return null;
  }
}

final subscriptionProvider =
    NotifierProvider<SubscriptionNotifier, SubscriptionState>(
        SubscriptionNotifier.new);

class SubscriptionNotifier extends Notifier<SubscriptionState> {
  Timer? _refreshTimer;

  @override
  SubscriptionState build() {
    // Auto-refresh whenever the auth state changes (login / logout).
    ref.listen(authProvider, (prev, next) {
      if (next.isAuthenticated && (prev?.telegramId != next.telegramId)) {
        refresh();
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
      Future.microtask(refresh);
    }

    return const SubscriptionState();
  }

  Future<void> refresh() async {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final sub = await ApiService.fetchSubscription(auth.telegramId!);

      // Restore the previously-selected server if it still exists.
      VpnServer? selected = state.selectedServer;
      if (selected != null) {
        selected = sub.servers
            .cast<VpnServer?>()
            .firstWhere((s) => s?.id == selected!.id, orElse: () => null);
      }
      if (selected == null) {
        final savedId = await VpnSecureStorage.getSelectedServerId();
        if (savedId != null) {
          for (final s in sub.servers) {
            if (s.id == savedId) {
              selected = s;
              break;
            }
          }
        }
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

  Future<void> selectServer(VpnServer server) async {
    state = state.copyWith(selectedServer: server);
    await VpnSecureStorage.saveSelectedServerId(server.id);
  }

  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(AppConfig.subscriptionRefreshInterval, refresh);
  }
}
