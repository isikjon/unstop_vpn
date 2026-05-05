import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/vpn_server.dart';
import '../providers/subscription_provider.dart';
import '../providers/trial_provider.dart';
import '../services/secure_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/inset_shadow.dart';

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  String _searchQuery = '';
  Set<String> _pinnedServerIds = <String>{};
  final Map<String, String> _serverPings = <String, String>{};
  final Set<String> _pendingPingIds = <String>{};
  String? _openActionServerId;

  @override
  void initState() {
    super.initState();
    _loadPinnedServers();
  }

  Future<void> _loadPinnedServers() async {
    final pinnedIds = await VpnSecureStorage.getPinnedServerIds();
    if (!mounted) return;
    setState(() => _pinnedServerIds = pinnedIds);
  }

  @override
  Widget build(BuildContext context) {
    final subState = ref.watch(subscriptionProvider);
    final trial = ref.watch(trialProvider);
    final servers = subState.subscription.servers
        .where(
          (s) =>
              _searchQuery.isEmpty ||
              s.country.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              s.remark.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              s.city.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
    servers.sort((a, b) {
      final aPinned = _pinnedServerIds.contains(_serverPinId(a));
      final bPinned = _pinnedServerIds.contains(_serverPinId(b));
      if (aPinned == bPinned) return 0;
      return aPinned ? -1 : 1;
    });
    _ensureServerPings(servers);

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
                ] else if (subState.isLoading && !trial.isExpired) ...[
                  _buildServersLoadingCard(),
                  const SizedBox(height: 18),
                ] else ...[
                  _buildNoServersCard(trial.isExpired),
                  const SizedBox(height: 18),
                ],
                if (!subState.subscription.isActive)
                  _buildNoSubscriptionCard(enabled: !trial.isExpired),
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
                'assets/server_selection/back_btn.svg',
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
              onTap: _refreshServers,
              behavior: HitTestBehavior.opaque,
              child: SvgPicture.asset(
                'assets/server_selection/reload_btn.svg',
                width: 48,
                height: 48,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshServers() async {
    setState(() {
      _serverPings.clear();
      _pendingPingIds.clear();
    });
    await ref.read(subscriptionProvider.notifier).refresh();
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
    final selectedUrl =
        ref.watch(subscriptionProvider).selectedServer?.url ??
        servers.first.url;
    return Column(
      children: [
        for (final server in servers)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildServerTile(
              server: server,
              isSelected: server.url == selectedUrl,
            ),
          ),
      ],
    );
  }

  Widget _buildServerTile({
    required VpnServer server,
    required bool isSelected,
  }) {
    final pinId = _serverPinId(server);
    final isPinned = _pinnedServerIds.contains(pinId);
    final isActionOpen = _openActionServerId == pinId;

    return _SwipePinnedServerTile(
      isOpen: isActionOpen,
      isPinned: isPinned,
      onOpenChanged: (isOpen) {
        setState(() => _openActionServerId = isOpen ? pinId : null);
      },
      onTogglePinned: () => _togglePinnedServer(server),
      child: GestureDetector(
        onTap: () async {
          if (_openActionServerId != null) {
            setState(() => _openActionServerId = null);
            return;
          }
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
          title: _serverDisplayTitle(server),
          ping: _serverPings[server.url] ?? '...',
          isSelected: isSelected,
          isPinned: isPinned,
          isBypass: _isBypassServer(server),
        ),
      ),
    );
  }

  void _ensureServerPings(List<VpnServer> servers) {
    for (final server in servers) {
      final pingId = server.url;
      if (_serverPings.containsKey(pingId) ||
          _pendingPingIds.contains(pingId)) {
        continue;
      }
      _pendingPingIds.add(pingId);
      unawaited(_loadServerPing(server));
    }
  }

  Future<void> _loadServerPing(VpnServer server) async {
    final ping = await _measureTcpPing(server);
    if (!mounted) return;
    setState(() {
      _pendingPingIds.remove(server.url);
      _serverPings[server.url] = ping == null ? '--ms' : '${ping}ms';
    });
  }

  Future<int?> _measureTcpPing(VpnServer server) async {
    Socket? socket;
    final stopwatch = Stopwatch()..start();
    try {
      socket = await Socket.connect(
        server.address,
        server.port,
        timeout: const Duration(milliseconds: 900),
      );
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds.clamp(1, 9999);
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  Future<void> _togglePinnedServer(VpnServer server) async {
    final pinId = _serverPinId(server);
    setState(() {
      if (!_pinnedServerIds.remove(pinId)) {
        _pinnedServerIds.add(pinId);
      }
      _openActionServerId = null;
    });
    await VpnSecureStorage.savePinnedServerIds(_pinnedServerIds);
  }

  String _serverPinId(VpnServer server) => server.url;

  bool _isBypassServer(VpnServer server) {
    final text = '${server.remark} ${server.country}'.toLowerCase();
    return text.contains('обход') || text.contains('глушил');
  }

  String _serverDisplayTitle(VpnServer server) {
    if (!_isBypassServer(server)) return server.country;

    final withoutFlags = server.remark
        .replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '')
        .trim();
    final withoutNoise = withoutFlags
        .replaceAll(RegExp(r'\s*/\s*lte\s*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return withoutNoise.isEmpty ? 'Обход глушилок' : withoutNoise;
  }

  Widget _buildServersLoadingCard() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF080B1B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF0F1628)),
      ),
      child: Center(
        child: Text(
          'Загружаем серверы...',
          style: GoogleFonts.manrope(
            fontSize: 15,
            color: const Color(0xFF628499),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildNoServersCard(bool trialExpired) {
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
          const Icon(Icons.lock_outline, color: Color(0xFF628499), size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              trialExpired
                  ? 'Пробный период истёк'
                  : 'Пробный сервер не получен от API',
              style: GoogleFonts.manrope(
                fontSize: 15,
                color: const Color(0xFF628499),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSubscriptionCard({required bool enabled}) {
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
            'assets/server_selection/ads.png',
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
                _buildSubscribeButton(enabled: enabled),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscribeButton({required bool enabled}) {
    return GestureDetector(
      onTap: enabled ? () => Navigator.of(context).pop() : null,
      child: Container(
        clipBehavior: Clip.antiAlias,
        height: 60,
        width: double.infinity,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF00A2FF) : const Color(0xFF172134),
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

class _SwipePinnedServerTile extends StatelessWidget {
  final bool isOpen;
  final bool isPinned;
  final ValueChanged<bool> onOpenChanged;
  final VoidCallback onTogglePinned;
  final Widget child;

  const _SwipePinnedServerTile({
    required this.isOpen,
    required this.isPinned,
    required this.onOpenChanged,
    required this.onTogglePinned,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    const actionWidth = 80.0;

    return SizedBox(
      height: 80,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.centerRight,
        children: [
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: actionWidth,
            child: GestureDetector(
              onTap: onTogglePinned,
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF080B1B),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    isPinned
                        ? 'assets/server_selection/unpin.svg'
                        : 'assets/server_selection/pin.svg',
                    width: 24,
                    height: 24,
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -120) {
                onOpenChanged(true);
              } else if (velocity > 120) {
                onOpenChanged(false);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(
                isOpen ? -actionWidth - 12 : 0,
                0,
                0,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  final String flag;
  final String title;
  final String ping;
  final bool isSelected;
  final bool isPinned;
  final bool isBypass;

  const _ServerCard({
    required this.flag,
    required this.title,
    required this.ping,
    this.isSelected = false,
    this.isPinned = false,
    this.isBypass = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF080B1B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? const Color(0xFF00A1FF) : const Color(0xFF0F1628),
        ),
      ),
      child: Row(
        children: [
          if (isBypass)
            SvgPicture.asset(
              'assets/server_selection/obxod_glushilok.svg',
              width: 36,
              height: 36,
            )
          else
            Text(flag, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      color: isSelected
                          ? const Color(0xFF00A1FF)
                          : Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isPinned) ...[
                  const SizedBox(width: 8),
                  SvgPicture.asset(
                    'assets/server_selection/pinned.svg',
                    width: 16,
                    height: 16,
                  ),
                ],
              ],
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
