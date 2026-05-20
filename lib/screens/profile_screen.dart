import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/subscription.dart';
import '../models/vpn_status.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/trial_provider.dart';
import '../providers/vpn_provider.dart';
import '../theme/app_theme.dart';
import '../utils/subscription_flow.dart';
import '../widgets/app_header.dart';
import '../widgets/inset_shadow.dart';
import '../widgets/subscription_status_badge.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const _settingsAssets = 'assets/icons/settings';

  Future<void> _signOut() async {
    final vpnState = ref.read(vpnProvider);
    if (vpnState.status == VpnStatus.connected) {
      await ref.read(vpnProvider.notifier).disconnect();
    }
    await ref.read(authProvider.notifier).signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/auth');
    }
  }

  Future<void> _refreshProfile() async {
    await ref.read(subscriptionProvider.notifier).refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final subscription = ref.watch(subscriptionProvider).subscription;
    final tunnel = ref.watch(tunnelSettingsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF000214),
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF000214))),
          Positioned(
            top: 78,
            left: 0,
            right: 0,
            height: 270,
            child: Opacity(
              opacity: 0.8,
              child: Image.asset(
                'assets/images/main_screen.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _ProfileArcPainter())),
          SafeArea(
            child: RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.bgCard,
              onRefresh: _refreshProfile,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 15),
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _header(subscription),
                      const SizedBox(height: 48),
                      _identity(auth),
                      const SizedBox(height: 52),
                      _subscriptionCard(subscription),
                      const SizedBox(height: 8),
                      _settingsRow(
                        icon: '$_settingsAssets/free_proxy.svg',
                        title: 'Free Proxy',
                        subtitle: 'Бесплатное прокси для Telegram',
                        trailing: _arrowButton(),
                        onTap: _openProxy,
                      ),
                      _settingsRow(
                        icon: '$_settingsAssets/obnovit_podpisku.svg',
                        title: 'Обновить подписку',
                        subtitle: 'Проверка подписки',
                        trailing: _refreshButton(),
                        onTap: _refreshProfile,
                      ),
                      _settingsRow(
                        icon: '$_settingsAssets/fragmentirovaniya.svg',
                        title: 'Фрагментирование',
                        subtitle:
                            'Xray • ${tunnel.fragmentPackets} • ${tunnel.fragmentLength} пакетов',
                        trailing: _toggle(
                          value: tunnel.fragmentEnabled,
                          onChanged: (value) => ref
                              .read(tunnelSettingsProvider.notifier)
                              .setFragment(value),
                        ),
                      ),
                      _settingsRow(
                        icon: '$_settingsAssets/shumi.svg',
                        title: 'Шумы',
                        subtitle:
                            '${tunnel.noiseType} • задержка ${tunnel.noiseDelay} мс',
                        trailing: _toggle(
                          value: tunnel.noiseEnabled,
                          onChanged: (value) => ref
                              .read(tunnelSettingsProvider.notifier)
                              .setNoise(value),
                        ),
                      ),
                      _settingsRow(
                        icon: '$_settingsAssets/telegram.svg',
                        title: 'Поддержка 24/7',
                        subtitle: 'Написать в Telegram',
                        trailing: _arrowButton(),
                        onTap: _openSupport,
                      ),
                      const SizedBox(height: 24),
                      _logoutButton(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(Subscription subscription) {
    return AppHeader(
      trailing: SubscriptionStatusBadge(
        subscription: subscription,
        trialLeft: ref.watch(trialProvider).timeLeft,
      ),
    );
  }

  Widget _identity(AuthState auth) {
    final id = auth.telegramId ?? '—';
    final accountName = auth.name?.isNotEmpty == true
        ? auth.name!
        : 'Telegram аккаунт';

    return Column(
      children: [
        Text(
          'ID: $id',
          textAlign: TextAlign.center,
          style: GoogleFonts.onest(
            color: const Color(0xFF9ADFFF),
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              '$_settingsAssets/telegram.svg',
              width: 48,
              height: 48,
            ),
            const SizedBox(width: 8),
            Text(
              accountName,
              style: GoogleFonts.onest(
                color: const Color(0xFFD2EEFF),
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _subscriptionCard(Subscription subscription) {
    if (subscription.isActive) {
      return _activeSubscriptionCard(subscription);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 64,
        padding: const EdgeInsets.only(left: 20, right: 8),
        decoration: BoxDecoration(
          color: const Color(0x99080B1B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF111932)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0x1AFF1F2D),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFFFF1F2D),
                  size: 19,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Нет подписки',
                style: GoogleFonts.onest(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
            SizedBox(
              width: 148,
              height: 49,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF11A9F4),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: InsetShadow(borderRadius: BorderRadius.circular(14)),
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _openSubscriptionBot,
                        child: Center(
                          child: Text(
                            'Авторизоваться',
                            style: AppTextStyles.button.copyWith(fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeSubscriptionCard(Subscription subscription) {
    final radius = BorderRadius.circular(24);
    final title = subscription.isGracePeriod
        ? 'Доп. доступ активен'
        : 'Подписка активна';
    final subtitle = subscription.isGracePeriod
        ? 'доступен один сервер'
        : _formatActiveUntil(subscription.expiresAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 76,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF11A9F4),
          borderRadius: radius,
        ),
        child: Stack(
          children: [
            Positioned.fill(child: InsetShadow(borderRadius: radius)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  SvgPicture.asset(
                    'assets/icons/padpiska.svg',
                    width: 30,
                    height: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.onest(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.onest(
                            color: const Color(0xFFD2EEFF),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _openSubscriptionBot,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 96,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF06081A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          'Управлять',
                          style: GoogleFonts.onest(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsRow({
    required String icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 82,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFF0F1628), width: 1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SvgPicture.asset(icon, width: 48, height: 48),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.onest(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.onest(
                          color: const Color(0xFF628499),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _arrowButton() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0x4D090D20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF101932)),
      ),
      child: const Icon(
        Icons.arrow_forward_rounded,
        color: Color(0xFFD2EEFF),
        size: 26,
      ),
    );
  }

  Widget _refreshButton() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0x4D090D20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF101932)),
      ),
      child: const Icon(Icons.sync_rounded, color: Color(0xFFD2EEFF), size: 25),
    );
  }

  Widget _toggle({required bool value, required ValueChanged<bool> onChanged}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 50,
        height: 34,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: value ? const Color(0xFF11A9F4) : const Color(0xFF0F172D),
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: value ? Colors.white : const Color(0xFF070A1B),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoutButton() {
    return GestureDetector(
      onTap: _confirmSignOut,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.logout_rounded, color: Color(0xFFFF1F2D), size: 22),
          const SizedBox(width: 8),
          Text(
            'Выйти из аккаунта',
            style: GoogleFonts.onest(
              color: const Color(0xFFFF1F2D),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Выйти?',
          style: GoogleFonts.onest(color: AppColors.textPrimary),
        ),
        content: Text(
          'Вы будете отключены от VPN и разлогинены.',
          style: GoogleFonts.onest(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Отмена',
              style: GoogleFonts.onest(color: AppColors.primary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Выйти',
              style: GoogleFonts.onest(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await _signOut();
  }

  Future<void> _openSubscriptionBot() async {
    await openSubscriptionFlow(context, ref);
  }

  Future<void> _openSupport() async {
    final uri = Uri.parse(AppConfig.supportLink);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openProxy() async {
    final uri = Uri.parse(AppConfig.proxyLink);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatActiveUntil(DateTime? date) {
    if (date == null) return 'активна';
    final local = date.toLocal();
    return 'до ${local.day} ${_monthName(local.month)}, '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _monthName(int month) {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return months[(month - 1).clamp(0, months.length - 1)];
  }
}

class _ProfileArcPainter extends CustomPainter {
  const _ProfileArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = const LinearGradient(
        colors: [Color(0x0000A1FF), Color(0xCC00A1FF), Color(0x0000A1FF)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 300));

    final path = Path()
      ..moveTo(0, 307)
      ..quadraticBezierTo(size.width / 2, 280, size.width, 307);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ProfileArcPainter oldDelegate) => false;
}
