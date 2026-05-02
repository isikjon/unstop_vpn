import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/vpn_server.dart';
import '../providers/subscription_provider.dart';
import '../providers/vpn_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/inset_shadow.dart';

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final subState = ref.watch(subscriptionProvider);
    final servers = subState.subscription.servers
        .where(
          (s) =>
              _searchQuery.isEmpty ||
              s.country.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              s.remark.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              s.city.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF000214),
      body: Stack(
        children: [
          const Positioned.fill(child: _ServersBackground()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
              children: [
                _buildHeader(subState.subscription.servers.length),
                const SizedBox(height: 18),
                _buildSearch(),
                const SizedBox(height: 18),
                if (servers.isNotEmpty) ...[
                  _buildServerList(servers),
                  const SizedBox(height: 18),
                ] else ...[
                  _buildPreviewServer(),
                  const SizedBox(height: 18),
                ],
                if (!subState.subscription.isActive) _buildNoSubscriptionCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int total) {
    final count = total > 0 ? total : 28;

    return SizedBox(
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: SvgPicture.asset(
                'Выбор сервера assets/back_btn.svg',
                width: 48,
                height: 48,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Выберите сервер',
                style: GoogleFonts.manrope(
                  fontSize: 19,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$count серверов',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: const Color(0xFF628499),
                  fontWeight: FontWeight.w500,
                  height: 1.0,
                ),
              ),
            ],
          ),
          Positioned(
            right: 0,
            child: GestureDetector(
              onTap: () => ref.read(subscriptionProvider.notifier).refresh(),
              behavior: HitTestBehavior.opaque,
              child: SvgPicture.asset(
                'Выбор сервера assets/reload_btn.svg',
                width: 48,
                height: 48,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        color: const Color(0xFF0C0E20),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        style: GoogleFonts.manrope(
          fontSize: 14,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Поиск по стране...',
          hintStyle: GoogleFonts.manrope(
            fontSize: 14,
            color: const Color(0xFF628499),
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF628499),
            size: 27,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
        ),
      ),
    );
  }

  Widget _buildServerList(List<VpnServer> servers) {
    final selectedId =
        ref.watch(subscriptionProvider).selectedServer?.id ?? servers.first.id;
    final activeServerId = ref.watch(vpnProvider).activeServer?.id;

    return Column(
      children: [
        for (final server in servers)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildServerTile(
              server: server,
              isSelected: server.id == selectedId,
              isActive: server.id == activeServerId,
            ),
          ),
      ],
    );
  }

  Widget _buildServerTile({
    required VpnServer server,
    required bool isSelected,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: () async {
        await ref.read(subscriptionProvider.notifier).selectServer(server);
        ref
            .read(selectedServerDisplayProvider.notifier)
            .select(ServerDisplay.fromVpnServer(server));
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: _ServerCard(
        flag: server.flag,
        title: server.country,
        ping: isActive ? 'Active' : '67ms',
      ),
    );
  }

  Widget _buildPreviewServer() {
    return GestureDetector(
      onTap: () {
        ref
            .read(selectedServerDisplayProvider.notifier)
            .select(
              const ServerDisplay(
                flag: '🇫🇷',
                country: 'Франция',
                subtitle: '67ms',
              ),
            );
        Navigator.of(context).pop();
      },
      behavior: HitTestBehavior.opaque,
      child: const _ServerCard(flag: '🇫🇷', title: 'Франция', ping: '67ms'),
    );
  }

  Widget _buildNoSubscriptionCard() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF080B1B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF0F1628)),
      ),
      child: Column(
        children: [
          Image.asset(
            'Выбор сервера assets/ads.png',
            width: double.infinity,
            fit: BoxFit.cover,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
            child: Column(
              children: [
                Text(
                  '25+ серверов без ограничений',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 17,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Разблокируйте полный список\nсерверов с подпиской.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: const Color(0xFF628499),
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                _buildSubscribeButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscribeButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        clipBehavior: Clip.antiAlias,
        height: 60,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF00A2FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: InsetShadow(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
            Center(
              child: Text('Оформить подписку', style: AppTextStyles.button),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServersBackground extends StatelessWidget {
  const _ServersBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFF000214)),
      child: CustomPaint(painter: _ServersBackgroundPainter()),
    );
  }
}

class _ServersBackgroundPainter extends CustomPainter {
  const _ServersBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF06081A);

    final strokePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0x0D00A1FF), Color(0xFF00A1FF), Color(0x0D00A1FF)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 90));

    final topFill = Path()
      ..moveTo(0, 76)
      ..quadraticBezierTo(size.width / 2, 56, size.width, 76)
      ..lineTo(size.width, 86)
      ..lineTo(0, 86)
      ..close();

    final topStroke = Path()
      ..moveTo(0, 76)
      ..quadraticBezierTo(size.width / 2, 56, size.width, 76);

    canvas.drawPath(topFill, fillPaint);
    canvas.drawPath(topStroke, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ServerCard extends StatelessWidget {
  final String flag;
  final String title;
  final String ping;

  const _ServerCard({
    required this.flag,
    required this.title,
    required this.ping,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF080B1B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF0F1628)),
      ),
      child: Row(
        children: [
          Text(flag, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            ping,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: const Color(0xFFD2EEFF),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          const _SignalBars(),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 15,
      height: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          _SignalBar(height: 5, color: Color(0xFFFF7A00)),
          _SignalBar(height: 9, color: Color(0xFFFF7A00)),
          _SignalBar(height: 14, color: Color(0xFFFF7A00)),
        ],
      ),
    );
  }
}

class _SignalBar extends StatelessWidget {
  final double height;
  final Color color;

  const _SignalBar({required this.height, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
