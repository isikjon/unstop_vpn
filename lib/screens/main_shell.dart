import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import 'auth_screen.dart';
import 'home_screen_new.dart';
import 'subscription_screen.dart';
import 'profile_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 0});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _currentIndex;

  final _screens = const [
    HomeScreenNew(),
    SubscriptionScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _screens.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        ref.read(subscriptionProvider.notifier).refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    ref.listen<SubscriptionState>(subscriptionProvider, (previous, next) {
      final message = _subscriptionToastMessage(next);
      final previousMessage = previous == null
          ? null
          : _subscriptionToastMessage(previous);
      if (message == null || message == previousMessage || !mounted) return;
      showAppToast(
        context,
        message: message,
        type: appToastTypeForMessage(message),
      );
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _currentIndex == 2 && !auth.isAuthenticated
          ? const AuthScreen(showBottomNav: false)
          : IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildNewNavBar(),
    );
  }

  String? _subscriptionToastMessage(SubscriptionState state) {
    final subscriptionError = state.subscription.userFacingError;
    if (subscriptionError != null && subscriptionError.trim().isNotEmpty) {
      return subscriptionError;
    }

    final error = state.error;
    if (error == null || error.trim().isEmpty) return null;
    return _normalizeErrorMessage(error);
  }

  String _normalizeErrorMessage(String message) {
    final text = message.toLowerCase();
    if (text == 'limit_devices' ||
        text == 'limit_reached' ||
        text.contains('limit_devices') ||
        text.contains('device_limit') ||
        text.contains('devices_limit')) {
      return 'Лимит устройств достигнут';
    }
    if (text == 'subscription_inactive_or_expired') {
      return 'Подписка истекла';
    }
    if (text == 'grace_period_config_build_failed') {
      return 'Дополнительный доступ истёк. Продлите подписку.';
    }
    if (text == 'subscription_payload_empty' ||
        text == 'subscription_payload_not_loaded') {
      return 'Подписка ещё обрабатывается. Попробуйте обновить позже.';
    }
    return message;
  }

  void _selectTab(int index) {
    setState(() => _currentIndex = index);
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      ref.read(subscriptionProvider.notifier).refresh();
    }
  }

  Widget _buildNewNavBar() {
    return Container(
      height: 92,
      decoration: const BoxDecoration(
        color: Color(0xFF06081A),
        border: Border(top: BorderSide(color: Color(0xFF0F1628), width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildBottomBarItem(
              assetPath: _currentIndex == 0
                  ? 'assets/icons/bottom_bar/vpn_active.svg'
                  : 'assets/icons/bottom_bar/vpn_default.svg',
              onTap: () => _selectTab(0),
            ),
            _buildBottomBarItem(
              assetPath: _currentIndex == 1
                  ? 'assets/icons/bottom_bar/podpiska_active.svg'
                  : 'assets/icons/bottom_bar/podpiska_default.svg',
              onTap: () => _selectTab(1),
            ),
            _buildBottomBarItem(
              assetPath: _currentIndex == 2
                  ? 'assets/icons/bottom_bar/profile_active.svg'
                  : 'assets/icons/bottom_bar/profile_default.svg',
              onTap: () => _selectTab(2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBarItem({
    required String assetPath,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 129,
        height: double.infinity,
        child: Center(
          child: SvgPicture.asset(assetPath, width: 129, height: 64),
        ),
      ),
    );
  }
}
