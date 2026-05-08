import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/trial_provider.dart';
import '../screens/main_shell.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/inset_shadow.dart';
import '../widgets/shared_hero_background.dart';

class AuthScreen extends ConsumerStatefulWidget {
  final bool showBottomNav;

  const AuthScreen({super.key, this.showBottomNav = true});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  static const _authAssets = 'assets/auth';
  static const _bottomBarAssets = 'assets/icons/bottom_bar';

  Timer? _authPollTimer;

  int _uiStep = 0; // 0=start, 1=waiting for Telegram bot auth
  bool _busy = false;
  String? _error;
  String? _authKey;
  String? _botLink;

  @override
  void dispose() {
    _authPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _openBot() async {
    if (_botLink == null || _botLink!.isEmpty) {
      await _startBotAuth();
      return;
    }
    await _launchBotAuthLink(_botLink!);
  }

  void _setError(String msg) => setState(() {
    _error = msg;
    _busy = false;
  });

  void _clearError() => setState(() => _error = null);

  Future<void> _startBotAuth() async {
    _clearError();
    setState(() => _busy = true);

    try {
      final result = await AuthService.startBotAuth();
      setState(() {
        _authKey = result.key;
        _botLink = result.botLink;
        _uiStep = 1;
        _busy = false;
      });
      _startAuthPolling();
      await _launchBotAuthLink(result.botLink);
    } on AuthException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError('Не удалось открыть Telegram');
    }
  }

  void _startAuthPolling() {
    _authPollTimer?.cancel();
    _authPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkBotAuth(silent: true);
    });
  }

  Future<void> _onBotAuthConfirmed() async {
    await _checkBotAuth(silent: false);
  }

  Future<void> _checkBotAuth({required bool silent}) async {
    final key = _authKey;
    if (key == null || key.isEmpty) {
      if (!silent) await _startBotAuth();
      return;
    }

    if (!silent) {
      _clearError();
      setState(() => _busy = true);
    }

    try {
      final result = await AuthService.checkBotAuth(key);
      if (result.authenticated && result.telegramId != null) {
        _authPollTimer?.cancel();
        await ref
            .read(authProvider.notifier)
            .setVerifiedId(result.telegramId!, name: result.name);
        await ref.read(subscriptionProvider.notifier).refresh();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/home');
        return;
      }
      if (!silent) {
        final suffix = _authKey == null ? '' : '\nКлюч: key_$_authKey';
        _setError(
          'Авторизация ещё не подтверждена. Нажмите Start/Подтвердить в боте.$suffix',
        );
      }
    } on AuthException catch (e) {
      if (!silent) _setError(e.message);
    } finally {
      if (!silent && mounted && _busy) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _launchBotAuthLink(String botLink) async {
    final httpsUri = Uri.parse(botLink);
    final domain = httpsUri.pathSegments.isNotEmpty
        ? httpsUri.pathSegments.first
        : httpsUri.host;
    final start = httpsUri.queryParameters['start'];

    if (domain.isNotEmpty && start != null && start.isNotEmpty) {
      final tgUri = Uri(
        scheme: 'tg',
        host: 'resolve',
        queryParameters: {'domain': domain, 'start': start},
      );
      try {
        final opened = await launchUrl(
          tgUri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) return;
      } catch (_) {}
    }

    await launchUrl(httpsUri, mode: LaunchMode.externalApplication);
  }

  void _openMainTab(int index) {
    _authPollTimer?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MainShell(initialIndex: index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bottomGap = widget.showBottomNav ? 92.0 + 18.0 : 18.0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF000214),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF000214))),
            const SharedHeroBackground(),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _header(),
                  const Spacer(),
                  ClipPath(
                    clipper: const _TopArcClipper(),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.only(
                        top: 54,
                        bottom: keyboard > 0 ? keyboard + 18 : bottomGap,
                      ),
                      color: const Color(0xFF000214),
                      child: AnimatedPadding(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _buildCurrentStep(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.showBottomNav)
              Positioned(left: 0, right: 0, bottom: 0, child: _bottomNav()),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    if (_uiStep == 0) return _startStep();
    return _botStep();
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Image.asset('assets/images/logo.png', height: 24),
          const Spacer(),
          _trialBadge(),
        ],
      ),
    );
  }

  Widget _trialBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1628),
        borderRadius: BorderRadius.circular(20),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.manrope(
            color: const Color(0xFF628499),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          children: [
            const TextSpan(text: 'ПРОБНЫЙ ПЕРИОД: '),
            TextSpan(
              text: _formatDuration(ref.watch(trialProvider).timeLeft),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _startStep() {
    return Column(
      key: const ValueKey('auth-start-step'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _authTitle(),
        const SizedBox(height: 8),
        _paragraph(
          'Нажмите кнопку ниже, откройте Telegram-бота\nи подтвердите вход в UNSTOP VPN.',
        ),
        if (_error != null) ...[const SizedBox(height: 10), _errorText()],
        const SizedBox(height: 28),
        _primaryButton(label: 'Авторизоваться', onTap: _startBotAuth),
      ],
    );
  }

  Widget _botStep() {
    return Column(
      key: const ValueKey('bot-step'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _authTitle(),
        const SizedBox(height: 8),
        _botDescription(),
        if (_error != null) ...[const SizedBox(height: 10), _errorText()],
        const SizedBox(height: 28),
        _primaryButton(
          label: 'Я авторизовался',
          iconPath: '$_authAssets/check.svg',
          onTap: _onBotAuthConfirmed,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _squareButton(
              iconPath: '$_authAssets/arrow-left.svg',
              onTap: () => setState(() {
                _uiStep = 0;
                _error = null;
                _authPollTimer?.cancel();
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _darkButton(
                label: 'Открыть бота',
                iconPath: '$_authAssets/open-link.svg',
                onTap: _busy ? null : _openBot,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _authTitle({String text = 'Авторизация\nв UNSTOP VPN'}) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFF8DDDFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
      ).createShader(bounds),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.getFont(
          'Onest',
          color: Colors.white,
          fontSize: 31,
          fontWeight: FontWeight.w700,
          height: 1.16,
        ),
      ),
    );
  }

  Widget _paragraph(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.getFont(
        'Onest',
        color: const Color(0xFFD2EEFF),
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
    );
  }

  Widget _botDescription() {
    final baseStyle = GoogleFonts.getFont(
      'Onest',
      color: const Color(0xFFD2EEFF),
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.45,
    );

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: baseStyle,
        children: const [
          TextSpan(text: 'В открывшемся боте нажмите\n'),
          TextSpan(
            text: '“Start” / “Подтвердить”',
            style: TextStyle(
              color: Color(0xFF00A2FF),
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: ', затем вернитесь сюда\nи нажмите кнопку ниже.'),
        ],
      ),
    );
  }

  Widget _errorText() {
    return Text(
      _error!,
      textAlign: TextAlign.center,
      style: GoogleFonts.getFont(
        'Onest',
        color: const Color(0xFFFF596B),
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required FutureOr<void> Function()? onTap,
    String? iconPath,
  }) {
    final radius = BorderRadius.circular(16);

    return GestureDetector(
      onTap: _busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: const Color(0xFF11A9F4),
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x3300A1FF),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            InsetShadow(borderRadius: radius),
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: _busy
                    ? const SizedBox(
                        key: ValueKey('loader'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        key: ValueKey(label),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (iconPath != null) ...[
                            SvgPicture.asset(iconPath, width: 20, height: 20),
                            const SizedBox(width: 10),
                          ],
                          Text(label, style: AppTextStyles.button),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _darkButton({
    required String label,
    required String iconPath,
    required FutureOr<void> Function()? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 55,
        decoration: BoxDecoration(
          color: const Color(0xFF080C1D).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(iconPath, width: 19, height: 19),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.getFont(
                'Onest',
                color: const Color(0xFFD2EEFF),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _squareButton({
    required String iconPath,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 55,
        height: 55,
        decoration: BoxDecoration(
          color: const Color(0xFF080C1D).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(child: SvgPicture.asset(iconPath, width: 22, height: 22)),
      ),
    );
  }

  Widget _bottomNav() {
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
            _bottomNavIcon(
              '$_bottomBarAssets/vpn_default.svg',
              onTap: () => _openMainTab(0),
            ),
            _bottomNavIcon(
              '$_bottomBarAssets/podpiska_default.svg',
              onTap: () => _openMainTab(1),
            ),
            _bottomNavIcon('$_bottomBarAssets/profile_active.svg'),
          ],
        ),
      ),
    );
  }

  Widget _bottomNavIcon(String path, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 129,
        height: double.infinity,
        child: Center(child: SvgPicture.asset(path, width: 129, height: 64)),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

class _TopArcClipper extends CustomClipper<Path> {
  static const double _height = 38;

  const _TopArcClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, _height)
      ..quadraticBezierTo(size.width / 2, 0, size.width, _height)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _TopArcClipper oldClipper) => false;
}
