import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/subscription.dart';
import '../models/vpn_status.dart';
import '../models/vpn_server.dart';
import '../providers/subscription_provider.dart';
import '../providers/trial_provider.dart';
import '../providers/vpn_provider.dart';
import '../services/secure_storage.dart';
import '../theme/app_theme.dart';
import '../utils/subscription_flow.dart';
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
  Future<void> _pingQueue = Future<void>.value();
  int _pingGeneration = 0;

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
            child: RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.bgCard,
              onRefresh: _refreshServers,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
                children: [
                  _buildHeader(subState.subscription.servers.length),
                  const SizedBox(height: 18),
                  _buildSearch(),
                  const SizedBox(height: 18),
                  if (servers.isNotEmpty) ...[
                    _buildServerList(servers),
                    const SizedBox(height: 18),
                  ] else if (subState.isLoading &&
                      !trial.isExpired &&
                      !subState.subscription.isActive) ...[
                    _buildServersLoadingCard(),
                    const SizedBox(height: 18),
                  ] else ...[
                    _buildNoServersCard(
                      subscription: subState.subscription,
                      trialExpired: trial.isExpired,
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (!subState.subscription.isActive)
                    _buildNoSubscriptionCard(enabled: !trial.isExpired),
                ],
              ),
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
      _pingGeneration += 1;
      _pingQueue = Future<void>.value();
      _serverPings.clear();
      _pendingPingIds.clear();
    });
    await ref.read(subscriptionProvider.notifier).refresh(force: true);
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
        ref.watch(subscriptionProvider).effectiveServer?.url ??
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
        onTap: () => _handleServerTap(server),
        behavior: HitTestBehavior.opaque,
        child: _ServerCard(
          flag: server.flag,
          title: _safeServerTitle(server),
          ping: _serverPings[server.url] ?? '...',
          isSelected: isSelected,
          isPinned: isPinned,
          isBypass: _isBypassServer(server),
        ),
      ),
    );
  }

  Future<void> _handleServerTap(VpnServer server) async {
    if (_openActionServerId != null) {
      setState(() => _openActionServerId = null);
      return;
    }

    await ref.read(subscriptionProvider.notifier).selectServer(server);
    ref
        .read(selectedServerDisplayProvider.notifier)
        .select(ServerDisplay.fromVpnServer(server));

    final vpnState = ref.read(vpnProvider);
    final hasActiveSession =
        vpnState.status == VpnStatus.connected ||
        vpnState.status == VpnStatus.connecting ||
        vpnState.status == VpnStatus.reconnecting;
    if (hasActiveSession && vpnState.activeServer?.url != server.url) {
      unawaited(ref.read(vpnProvider.notifier).switchServer(server));
    }

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _ensureServerPings(List<VpnServer> servers) {
    for (final server in servers) {
      final pingId = server.url;
      if (_serverPings.containsKey(pingId) ||
          _pendingPingIds.contains(pingId)) {
        continue;
      }
      _pendingPingIds.add(pingId);
      _enqueueServerPing(server, _pingGeneration);
    }
  }

  void _enqueueServerPing(VpnServer server, int generation) {
    final next = _pingQueue.then((_) => _loadServerPing(server, generation));
    _pingQueue = next.catchError((_) {});
    unawaited(_pingQueue);
  }

  Future<void> _loadServerPing(VpnServer server, int generation) async {
    final ping = await ref
        .read(vpnProvider.notifier)
        .measureServerDelay(server);
    if (!mounted || generation != _pingGeneration) return;
    setState(() {
      _pendingPingIds.remove(server.url);
      _serverPings[server.url] = ping == null ? '—' : '${ping}ms';
    });
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

  String _safeServerTitle(VpnServer server) {
    final title = _serverDisplayTitle(server).trim();
    if (title.isEmpty || _containsNetworkAddress(title)) return 'VPN сервер';
    return title;
  }

  bool _containsNetworkAddress(String value) {
    final text = value.toLowerCase();
    if (RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b').hasMatch(text)) return true;
    if (RegExp(r'\b[a-z0-9-]+(\.[a-z0-9-]+)+\b').hasMatch(text)) return true;
    return false;
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

  Widget _buildNoServersCard({
    required Subscription subscription,
    required bool trialExpired,
  }) {
    final error = subscription.userFacingError;
    final text =
        error ??
        (trialExpired
            ? 'Пробный период истёк'
            : 'Пробный сервер не получен от API');

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
              text,
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
                  'Войдите, чтобы открыть полный\nсписок серверов.',
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
      onTap: enabled ? () => openSubscriptionFlow(context, ref) : null,
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
            Center(child: Text('Авторизоваться', style: AppTextStyles.button)),
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
              color: _pingColor(ping),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          _SignalBars(ping: ping),
        ],
      ),
    );
  }

  Color _pingColor(String ping) {
    final ms = _parsePingMs(ping);
    if (ms == null) return const Color(0xFF628499);
    if (ms <= 300) return const Color(0xFF3EE875);
    if (ms <= 650) return const Color(0xFFFFC247);
    return const Color(0xFFFF7A00);
  }
}

class _SignalBars extends StatelessWidget {
  final String ping;

  const _SignalBars({required this.ping});

  @override
  Widget build(BuildContext context) {
    final ms = _parsePingMs(ping);
    final color = switch (ms) {
      null => const Color(0xFF33425C),
      <= 300 => const Color(0xFF3EE875),
      <= 650 => const Color(0xFFFFC247),
      _ => const Color(0xFFFF7A00),
    };

    return SizedBox(
      width: 15,
      height: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SignalBar(height: 5, color: color),
          _SignalBar(height: 9, color: color),
          _SignalBar(height: 14, color: color),
        ],
      ),
    );
  }
}

int? _parsePingMs(String ping) {
  final match = RegExp(r'\d+').firstMatch(ping);
  return match == null ? null : int.tryParse(match.group(0)!);
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
