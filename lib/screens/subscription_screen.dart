import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../providers/subscription_provider.dart';
import '../models/subscription.dart';
import '../theme/app_theme.dart';
import '../widgets/inset_shadow.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  Timer? _trialTimer;
  Duration _trialTimeLeft = const Duration(hours: 23, minutes: 59, seconds: 47);

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
    _trialTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _trialTimeLeft.inSeconds <= 0) return;
      setState(() {
        _trialTimeLeft -= const Duration(seconds: 1);
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
    final subState = ref.watch(subscriptionProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: subState.isLoading && !subState.subscription.isActive
          ? _loadingBody()
          : subState.subscription.isActive
          ? _activeSubscriptionBody(context, ref, subState)
          : _noSubscriptionBody(context),
    );
  }

  Widget _loadingBody() {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.gradientBg),
      child: const SafeArea(
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }

  Widget _activeSubscriptionBody(
    BuildContext context,
    WidgetRef ref,
    SubscriptionState subState,
  ) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.gradientBg),
      child: SafeArea(child: _buildContent(context, ref, subState)),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    SubscriptionState subState,
  ) {
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.bgCard,
      onRefresh: () => ref.read(subscriptionProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          const SizedBox(height: 20),
          _title(),
          const SizedBox(height: 8),
          _statusBadge(subState.subscription),
          const SizedBox(height: 24),
          _activeCard(subState.subscription),
          const SizedBox(height: 20),
          if (subState.subscription.trafficUsedRatio != null) ...[
            _trafficCard(subState.subscription),
            const SizedBox(height: 20),
          ],
          _supportCard(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _title() {
    return ShaderMask(
      shaderCallback: (b) => AppColors.gradientPrimary.createShader(b),
      child: Text(
        'Подписка',
        style: GoogleFonts.manrope(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    ).animate().fadeIn().slideY(begin: -0.2);
  }

  Widget _statusBadge(Subscription sub) {
    final isActive = sub.isActive;
    final daysLeft = sub.daysLeft;
    final statusText = isActive
        ? (daysLeft != null ? 'Активна · $daysLeft дн. осталось' : 'Активна')
        : 'Нет активной подписки';

    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppColors.success : AppColors.error,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          statusText,
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _activeCard(Subscription sub) {
    final plan = sub.planName?.toUpperCase() ?? 'PRO';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB300), Color(0xFFFF6F00)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  plan,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              if (sub.expiresAt != null)
                Text(
                  'до ${_formatDate(sub.expiresAt!)}',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.dns_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                '${sub.servers.length} серверов доступно',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.2);
  }

  Widget _trafficCard(Subscription sub) {
    final ratio = sub.trafficUsedRatio!;
    final used = _formatBytes(sub.trafficUsedBytes ?? 0);
    final total = _formatBytes(sub.trafficLimitBytes ?? 0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Трафик',
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(
                ratio < 0.7
                    ? AppColors.success
                    : (ratio < 0.9 ? AppColors.warning : AppColors.error),
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                used,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                total,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2);
  }

  Widget _supportCard() {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(AppConfig.supportLink);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.gradientPrimary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.headset_mic_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Поддержка 24/7',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Написать в Telegram',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.primary,
              size: 18,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2);
  }

  Widget _noSubscriptionBody(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF000214))),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: constraints.maxWidth * 0.9,
                  child: Image.asset(
                    'assets/images/no_subscription_bg.png',
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),
              _noSubscriptionHeader(),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _subscribeButton(),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ],
    );
  }

  Widget _noSubscriptionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Image.asset('assets/images/logo.png', height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1628),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'ПРОБНЫЙ ПЕРИОД: ${_formatDuration(_trialTimeLeft)}',
              style: GoogleFonts.manrope(
                fontSize: 10,
                color: const Color(0xFF628499),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscribeButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF11A9F4),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned.fill(
            child: InsetShadow(borderRadius: BorderRadius.circular(16)),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openSubscriptionBot,
                child: Center(
                  child: Text('Оформить подписку', style: AppTextStyles.button),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSubscriptionBot() async {
    final uri = Uri.parse(AppConfig.botDeepLink);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double v = bytes.toDouble();
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${units[i]}';
  }
}
