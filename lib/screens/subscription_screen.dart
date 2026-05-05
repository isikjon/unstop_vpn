import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../providers/subscription_provider.dart';
import '../providers/trial_provider.dart';
import '../models/subscription.dart';
import '../theme/app_theme.dart';
import '../widgets/inset_shadow.dart';
import '../widgets/subscription_status_badge.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
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
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.bgCard,
      onRefresh: () => ref.read(subscriptionProvider.notifier).refresh(),
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF000214))),
          Positioned.fill(
            child: CustomPaint(painter: _SubscriptionArcPainter()),
          ),
          SafeArea(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom -
                      92,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
                    child: Column(
                      children: [
                        _activeHeader(subState.subscription),
                        const SizedBox(height: 28),
                        _deviceLimitCard(subState.subscription),
                        const SizedBox(height: 10),
                        _trafficLimitCard(subState.subscription),
                        const Spacer(),
                        _activeSubscriptionBanner(subState.subscription),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeHeader(Subscription subscription) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Image.asset('assets/images/logo.png', height: 24),
        SubscriptionStatusBadge(
          subscription: subscription,
          trialLeft: ref.watch(trialProvider).timeLeft,
        ),
      ],
    );
  }

  Widget _deviceLimitCard(Subscription subscription) {
    final used = subscription.deviceUsedCount ?? 0;
    final limit = subscription.deviceLimitCount ?? 0;
    final progress = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);

    return _LimitCard(
      icon: 'assets/icons/subscription/limit_ustroystv.svg',
      usedText: '$used',
      totalText: ' из $limit',
      subtitle: 'Лимит устройств',
      progress: progress,
      activeColor: const Color(0xFFF5700B),
    );
  }

  Widget _trafficLimitCard(Subscription subscription) {
    final usedBytes = subscription.trafficUsedBytes;
    final limitBytes = subscription.trafficLimitBytes;
    final usedGb = usedBytes == null ? 0.0 : usedBytes / 1073741824;
    final limitGb = limitBytes == null ? 0.0 : limitBytes / 1073741824;
    final progress = limitGb <= 0 ? 0.0 : (usedGb / limitGb).clamp(0.0, 1.0);

    return _LimitCard(
      icon: 'assets/icons/subscription/potracheno.svg',
      usedText: _formatGb(usedGb),
      totalText: limitGb <= 0 ? ' GB' : ' из ${_formatGb(limitGb)} GB',
      subtitle: 'Потрачено трафика на белые списки',
      progress: progress,
      activeColor: const Color(0xFF00A2FF),
    );
  }

  Widget _activeSubscriptionBanner(Subscription subscription) {
    final radius = BorderRadius.circular(24);

    return Container(
      height: 92,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF11A9F4),
        borderRadius: radius,
      ),
      child: Stack(
        children: [
          Positioned.fill(child: InsetShadow(borderRadius: radius)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/icons/padpiska.svg',
                  width: 44,
                  height: 44,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Подписка активна',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatActiveUntil(subscription.expiresAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          color: const Color(0xFFD2EEFF),
                          fontWeight: FontWeight.w500,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _openSubscriptionBot,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 120,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF06081A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        'Продлить',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
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
    );
  }

  String _formatGb(double value) {
    if (value >= 10) return value.toStringAsFixed(2);
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }

  String _formatActiveUntil(DateTime? date) {
    if (date == null) return 'до 15 мая, 16:22';
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
                child: _subscribeButton(
                  enabled: !ref.watch(trialProvider).isExpired,
                ),
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
          SubscriptionStatusBadge(
            subscription: ref.watch(subscriptionProvider).subscription,
            trialLeft: ref.watch(trialProvider).timeLeft,
          ),
        ],
      ),
    );
  }

  Widget _subscribeButton({required bool enabled}) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: enabled
                    ? const Color(0xFF11A9F4)
                    : const Color(0xFF172134),
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
                onTap: enabled ? _openSubscriptionBot : null,
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
}

class _LimitCard extends StatelessWidget {
  final String icon;
  final String usedText;
  final String totalText;
  final String subtitle;
  final double progress;
  final Color activeColor;

  const _LimitCard({
    required this.icon,
    required this.usedText,
    required this.totalText,
    required this.subtitle,
    required this.progress,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 126,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF080B1B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF0F1628)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SvgPicture.asset(icon, width: 48, height: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                        children: [
                          TextSpan(
                            text: usedText,
                            style: const TextStyle(color: Colors.white),
                          ),
                          TextSpan(
                            text: totalText,
                            style: const TextStyle(color: Color(0xFF628499)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        color: const Color(0xFF628499),
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          _SegmentedProgress(progress: progress, activeColor: activeColor),
        ],
      ),
    );
  }
}

class _SegmentedProgress extends StatelessWidget {
  final double progress;
  final Color activeColor;

  const _SegmentedProgress({required this.progress, required this.activeColor});

  @override
  Widget build(BuildContext context) {
    const segmentCount = 15;
    const gap = 6.0;
    final activeSegments = (progress.clamp(0.0, 1.0) * segmentCount)
        .round()
        .clamp(0, segmentCount);

    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentWidth =
            (constraints.maxWidth - (gap * (segmentCount - 1))) / segmentCount;
        return Row(
          children: [
            for (var i = 0; i < segmentCount; i++) ...[
              Container(
                width: segmentWidth,
                height: 8,
                decoration: BoxDecoration(
                  color: i < activeSegments
                      ? activeColor
                      : const Color(0xFF111A2C),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              if (i != segmentCount - 1) const SizedBox(width: gap),
            ],
          ],
        );
      },
    );
  }
}

class _SubscriptionArcPainter extends CustomPainter {
  const _SubscriptionArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 160;
    final strokePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0x0D00A1FF), Color(0xFF00A1FF), Color(0x0D00A1FF)],
      ).createShader(Rect.fromLTWH(0, y - 28, size.width, 56));

    final path = Path()
      ..moveTo(0, y)
      ..quadraticBezierTo(size.width / 2, y - 28, size.width, y);

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
