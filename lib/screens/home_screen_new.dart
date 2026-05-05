import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../providers/vpn_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/trial_provider.dart';
import '../models/vpn_status.dart';
import '../widgets/inset_shadow.dart';
import '../widgets/subscription_status_badge.dart';
import 'servers_screen.dart';

class HomeScreenNew extends ConsumerStatefulWidget {
  const HomeScreenNew({super.key});

  @override
  ConsumerState<HomeScreenNew> createState() => _HomeScreenNewState();
}

class _HomeScreenNewState extends ConsumerState<HomeScreenNew> {
  bool _showTrialBanner = true;
  bool _showConnectedPreview = false;
  Timer? _trialTimer;
  Duration _connectedFor = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startTrialTimer();
  }

  @override
  void dispose() {
    _trialTimer?.cancel();
    super.dispose();
  }

  void _startTrialTimer() {
    _trialTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final isConnected =
          _showConnectedPreview ||
          ref.read(vpnProvider).status == VpnStatus.connected;
      setState(() {
        _connectedFor = isConnected
            ? _connectedFor + const Duration(seconds: 1)
            : Duration.zero;
      });
    });
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final vpnState = ref.watch(vpnProvider);
    final isConnected =
        _showConnectedPreview || vpnState.status == VpnStatus.connected;

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/main_screen.png',
            fit: BoxFit.cover,
          ),
        ),
        SafeArea(child: _buildHomeContent(isConnected)),
      ],
    );
  }

  Widget _buildHomeContent(bool isConnected) {
    final hasActiveSubscription = ref
        .watch(subscriptionProvider)
        .subscription
        .isActive;
    final trial = ref.watch(trialProvider);

    return Column(
      children: [
        const SizedBox(height: 16),
        _buildHeader(),
        const SizedBox(height: 16),
        if (_showTrialBanner && !hasActiveSubscription && !trial.isExpired) ...[
          _buildTrialBanner(),
          const SizedBox(height: 24),
        ],
        const Spacer(),
        _buildVpnControlBlock(isConnected),
        const Spacer(),
        if (isConnected) ...[
          _buildSpeedCard(),
          const SizedBox(height: 12),
          _buildServersCard(compact: true),
          const SizedBox(height: 16),
        ] else ...[
          _buildServersCard(),
          const SizedBox(height: 30),
        ],
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo
          Image.asset('assets/images/logo.png', height: 24),
          SubscriptionStatusBadge(
            subscription: ref.watch(subscriptionProvider).subscription,
            trialLeft: ref.watch(trialProvider).timeLeft,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedStatus() {
    return Column(
      key: const ValueKey('connected-control'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatDuration(_connectedFor),
          style: GoogleFonts.manrope(
            fontSize: 28,
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/icons/connected/connect.svg',
              width: 16,
              height: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'Защищено',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 72),
        _buildDisconnectButton(),
      ],
    );
  }

  Widget _buildDisconnectButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showConnectedPreview = false;
          _connectedFor = Duration.zero;
        });
        ref.read(vpnProvider.notifier).disconnect();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 152,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0E20),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Text(
            'Отключиться',
            maxLines: 1,
            style: GoogleFonts.manrope(
              fontSize: 18,
              color: const Color(0xFFD2EEFF),
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: const Color(0xFF080B1B),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildSpeedMetric(
                iconPath: 'assets/icons/connected/download.svg',
                value: '52.4 Mbps',
                label: 'Download',
                labelColor: AppColors.success,
              ),
            ),
            Container(width: 1, height: 44, color: const Color(0xFF0F1628)),
            Expanded(
              child: _buildSpeedMetric(
                iconPath: 'assets/icons/connected/upload.svg',
                value: '31.2 Mbps',
                label: 'Upload',
                labelColor: const Color(0xFFF5700B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedMetric({
    required String iconPath,
    required String value,
    required String label,
    required Color labelColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(iconPath, width: 24, height: 24),
        const SizedBox(width: 14),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: GoogleFonts.manrope(
                fontSize: 15,
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 9,
                color: labelColor,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrialBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16, right: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0E20),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF0F1628), width: 1),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // WiFi icon
                      SvgPicture.asset(
                        'assets/images/wifi.svg',
                        width: 32,
                        height: 32,
                      ),
                      const SizedBox(width: 12),
                      // Text
                      Expanded(
                        child: Text(
                          'Бесплатный VPN на 24 часа, чтобы Вы смогли оформить подписку',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 28),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Button
                  GestureDetector(
                    onTap: () {
                      // Navigate to subscription screen
                      setState(() => _showTrialBanner = false);
                    },
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      width: double.infinity,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00A2FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: InsetShadow(
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                          ),
                          Center(
                            child: Text(
                              'Оформить подписку сразу',
                              style: AppTextStyles.button,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: () => setState(() => _showTrialBanner = false),
              behavior: HitTestBehavior.opaque,
              child: SvgPicture.asset(
                'assets/icons/close.svg',
                width: 32,
                height: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerButton({required bool enabled}) {
    return GestureDetector(
      onTap: enabled
          ? () {
              setState(() {
                _showConnectedPreview = true;
                _connectedFor = Duration.zero;
              });
              ref.read(vpnProvider.notifier).toggleConnection();
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: SvgPicture.asset(
          'assets/images/big-btn.svg',
          width: 240,
          height: 240,
        ),
      ),
    );
  }

  Widget _buildVpnControlBlock(bool isConnected) {
    final subscription = ref.watch(subscriptionProvider).subscription;
    final trial = ref.watch(trialProvider);
    final canConnect = subscription.isActive || !trial.isExpired;

    return SizedBox(
      height: 284,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
              child: child,
            ),
          );
        },
        child: isConnected
            ? Center(child: _buildConnectedStatus())
            : Column(
                key: const ValueKey('idle-control'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPowerButton(enabled: canConnect),
                  const SizedBox(height: 20),
                  _buildStatusText(canConnect: canConnect),
                ],
              ),
      ),
    );
  }

  Widget _buildStatusText({required bool canConnect}) {
    return Text(
      canConnect ? 'Нажмите для подключения...' : 'Пробный период истёк',
      style: GoogleFonts.manrope(
        fontSize: 14,
        color: const Color(0xFF628499),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildServersCard({bool compact = false}) {
    final server = ref.watch(selectedServerDisplayProvider);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24),
      child: GestureDetector(
        onTap: () {
          setState(() => _showTrialBanner = false);
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ServersScreen()));
        },
        child: Container(
          height: compact ? 70 : 76,
          padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 20),
          decoration: BoxDecoration(
            color: compact ? const Color(0xFF080B1B) : const Color(0xFF0C0E20),
            borderRadius: BorderRadius.circular(compact ? 18 : 20),
            border: compact ? null : Border.all(color: const Color(0xFF0F1628)),
          ),
          child: Row(
            children: [
              if (server == null)
                const Icon(
                  Icons.dns_outlined,
                  size: 28,
                  color: Color(0xFF628499),
                )
              else
                Text(server.flag, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server?.country ?? 'Сервера',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: compact ? 15 : 15,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      server?.subtitle ?? 'Выберите сервер для подключения',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: compact ? 12 : 12,
                        color: const Color(0xFF628499),
                        fontWeight: FontWeight.w500,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Color(0xFF628499),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
