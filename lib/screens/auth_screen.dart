import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/logo_widget.dart';

/// Telegram auth screen.
///
/// Step 1 — Phone entry + open bot
/// Step 2 — Share contact in bot → app checks if bot received it.
///          If yes → auth done (no code needed!).
///          If no  → fallback to code verification (step 3).
/// Step 3 — (Fallback) Code entry via @VerificationCodes.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();

  int _uiStep = 0; // 0=phone, 1=bot prompt, 2=code

  bool _busy = false;
  String? _error;
  String? _deliveryInfo;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  String get _normalizedPhone {
    final raw = _phoneCtrl.text.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (raw.startsWith('+')) return raw;
    if (raw.startsWith('8')) return '+7${raw.substring(1)}';
    if (raw.startsWith('7')) return '+$raw';
    if (raw.isNotEmpty) return '+$raw';
    return raw;
  }

  void _setError(String msg) => setState(() {
    _error = msg;
    _busy = false;
  });
  void _clearError() => setState(() => _error = null);

  // ── Step 1: phone submitted ────────────────────────────────────────────────

  Future<void> _onPhoneNext() async {
    final phone = _normalizedPhone;
    if (phone.length < 7) {
      _setError('Введите корректный номер телефона');
      return;
    }
    _clearError();
    await ref.read(authProvider.notifier).phoneSubmitted(phone);
    setState(() => _uiStep = 1);

    // Open bot deep-link so user can share contact.
    final uri = Uri.parse(AppConfig.botDeepLink);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _setError('Не удалось открыть Telegram');
    }
  }

  // ── Step 2: user confirms they shared contact ─────────────────────────────

  Future<void> _onContactShared() async {
    _clearError();
    setState(() {
      _busy = true;
    });

    final phone = ref.read(authProvider).phone ?? _normalizedPhone;

    // Primary path: check if bot already got the contact (instant, no code)
    try {
      final telegramId = await AuthService.checkContact(phone);
      if (telegramId != null) {
        await ref.read(authProvider.notifier).setVerifiedId(telegramId);
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/home');
        return;
      }
    } catch (_) {}

    // Fallback: bot hasn't received contact yet, or check failed.
    // Try sending a verification code as backup.
    try {
      final result = await AuthService.sendCode(phone);
      ref.read(authProvider.notifier).contactShared();
      setState(() {
        _uiStep = 2;
        _busy = false;
        _deliveryInfo = result.delivery;
      });
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _codeFocus.requestFocus();
      });
    } on AuthException catch (e) {
      _setError('Контакт ещё не получен ботом. ${e.message}');
    } catch (e) {
      _setError(
        'Контакт не найден. Убедитесь, что вы поделились контактом в боте.',
      );
    }
  }

  /// Poll for contact: try check-contact again without code flow
  Future<void> _onRetryContactCheck() async {
    _clearError();
    setState(() {
      _busy = true;
    });
    final phone = ref.read(authProvider).phone ?? _normalizedPhone;

    try {
      final telegramId = await AuthService.checkContact(phone);
      if (telegramId != null) {
        await ref.read(authProvider.notifier).setVerifiedId(telegramId);
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/home');
        return;
      }
    } catch (_) {}

    _setError(
      'Контакт ещё не получен. Вернитесь в бот и поделитесь контактом.',
    );
  }

  Future<void> _onResendCode() async {
    _clearError();
    setState(() {
      _busy = true;
    });
    final phone = ref.read(authProvider).phone ?? _normalizedPhone;
    try {
      final result = await AuthService.sendCode(phone);
      setState(() {
        _busy = false;
        _deliveryInfo = result.delivery;
      });
    } on AuthException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError('Ошибка: $e');
    }
  }

  // ── Step 3 (fallback): verify code ────────────────────────────────────────

  Future<void> _onVerifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 5) {
      _setError('Введите 5-значный код');
      return;
    }
    _clearError();
    setState(() => _busy = true);
    ref.read(authProvider.notifier).setVerifying();

    final phone = ref.read(authProvider).phone ?? _normalizedPhone;
    try {
      final telegramId = await AuthService.verifyCode(phone, code);
      await ref.read(authProvider.notifier).setVerifiedId(telegramId);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } on AuthException catch (e) {
      ref.read(authProvider.notifier).reset();
      _setError(e.message);
      setState(() => _uiStep = 2); // stay on code step
    } catch (e) {
      _setError('Ошибка: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientBg),
        child: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  _buildLogo(),
                  const SizedBox(height: 28),
                  _buildStepIndicator(),
                  const SizedBox(height: 32),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.08, 0),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _uiStep == 0
                        ? _buildPhoneStep()
                        : _uiStep == 1
                        ? _buildBotStep()
                        : _buildCodeStep(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _buildError(_error!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        const LogoWidget(size: 72).animate().scale(
          begin: const Offset(0.7, 0.7),
          duration: 500.ms,
          curve: Curves.easeOutBack,
        ),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (b) => AppColors.gradientPrimary.createShader(b),
          child: Text(
            'Войти в UNSTOP VPN',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ).animate().fadeIn(delay: 100.ms),
      ],
    );
  }

  Widget _buildStepIndicator() {
    const labels = ['Номер', 'Бот', 'Код'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i == _uiStep;
        final done = i < _uiStep;
        return Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: active ? 32 : 24,
              height: 24,
              decoration: BoxDecoration(
                color: done
                    ? AppColors.success.withValues(alpha: 0.2)
                    : (active
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: done
                      ? AppColors.success
                      : (active ? AppColors.primary : AppColors.border),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: done
                    ? const Icon(
                        Icons.check,
                        size: 12,
                        color: AppColors.success,
                      )
                    : Text(
                        '${i + 1}',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? AppColors.primary
                              : AppColors.textHint,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              labels[i],
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: active
                    ? AppColors.primary
                    : (done ? AppColors.success : AppColors.textHint),
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (i < 2) ...[
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 1,
                color: i < _uiStep ? AppColors.success : AppColors.border,
              ),
              const SizedBox(width: 8),
            ],
          ],
        );
      }),
    );
  }

  // ── Step panels ────────────────────────────────────────────────────────────

  Widget _buildPhoneStep() {
    return Column(
      key: const ValueKey('phone'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'Введите номер телефона',
          'Тот же номер, который привязан к вашему Telegram аккаунту',
        ),
        const SizedBox(height: 20),
        _phoneField(),
        const SizedBox(height: 20),
        _primaryButton(
          icon: Icons.telegram_rounded,
          label: 'Перейти в бот',
          loading: _busy,
          onTap: _onPhoneNext,
        ),
      ],
    );
  }

  Widget _buildBotStep() {
    return Column(
      key: const ValueKey('bot'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'Поделитесь контактом в боте',
          'В открывшемся боте нажмите кнопку «Поделиться контактом», '
              'затем вернитесь сюда и нажмите кнопку ниже.',
        ),
        const SizedBox(height: 24),
        // Visual hint card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF229ED9).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.telegram_rounded,
                      color: Color(0xFF229ED9),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '@${AppConfig.botUsername}',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _hintRow(
                Icons.touch_app_rounded,
                'Откройте бота (уже должен открыться)',
              ),
              const SizedBox(height: 10),
              _hintRow(
                Icons.contacts_rounded,
                'Нажмите «Поделиться контактом»',
              ),
              const SizedBox(height: 10),
              _hintRow(
                Icons.check_circle_rounded,
                'Вернитесь в приложение и нажмите «Я поделился контактом»',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            final uri = Uri.parse(AppConfig.botDeepLink);
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          icon: const Icon(
            Icons.open_in_new_rounded,
            size: 16,
            color: AppColors.primary,
          ),
          label: Text(
            'Открыть бот снова',
            style: GoogleFonts.manrope(fontSize: 13, color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 16),
        _primaryButton(
          icon: Icons.check_circle_outline_rounded,
          label: 'Я поделился контактом',
          loading: _busy,
          onTap: _onContactShared,
        ),
        const SizedBox(height: 12),
        _secondaryButton(
          label: 'Назад',
          onTap: () => setState(() {
            _uiStep = 0;
            _error = null;
          }),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    final subtitle = _deliveryInfo != null && _deliveryInfo!.isNotEmpty
        ? 'Код отправлен: $_deliveryInfo'
        : 'Код пришёл в Telegram (бот @VerificationCodes или СМС)';
    return Column(
      key: const ValueKey('code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Введите код из Telegram', subtitle),
        const SizedBox(height: 20),
        _codeField(),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _onResendCode,
              icon: const Icon(
                Icons.refresh_rounded,
                size: 14,
                color: AppColors.primary,
              ),
              label: Text(
                'Новый код',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.primary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _onRetryContactCheck,
              icon: const Icon(
                Icons.contacts_rounded,
                size: 14,
                color: AppColors.success,
              ),
              label: Text(
                'Проверить контакт',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.success,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _primaryButton(
          icon: Icons.verified_rounded,
          label: 'Подтвердить код',
          loading: _busy,
          onTap: _onVerifyCode,
        ),
        const SizedBox(height: 12),
        _secondaryButton(
          label: 'Назад',
          onTap: () => setState(() {
            _uiStep = 1;
            _error = null;
            _codeCtrl.clear();
            _deliveryInfo = null;
          }),
        ),
      ],
    );
  }

  // ── UI atoms ────────────────────────────────────────────────────────────────

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _hintRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _phoneField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: _phoneCtrl,
        focusNode: _phoneFocus,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\(\)\+]')),
        ],
        style: GoogleFonts.manrope(color: AppColors.textPrimary, fontSize: 16),
        onSubmitted: (_) => _onPhoneNext(),
        decoration: InputDecoration(
          hintText: '+7 900 123-45-67',
          hintStyle: GoogleFonts.manrope(
            color: AppColors.textHint,
            fontSize: 15,
          ),
          prefixIcon: const Icon(
            Icons.phone_rounded,
            color: AppColors.textHint,
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 14,
          ),
        ),
      ),
    );
  }

  Widget _codeField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: _codeCtrl,
        focusNode: _codeFocus,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          color: AppColors.textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: 10,
        ),
        onSubmitted: (_) => _onVerifyCode(),
        decoration: InputDecoration(
          hintText: '·····',
          hintStyle: GoogleFonts.manrope(
            color: AppColors.textHint,
            fontSize: 26,
            letterSpacing: 10,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 20,
            horizontal: 14,
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.gradientPrimary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 20,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: loading ? null : onTap,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 46,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.manrope(fontSize: 13, color: AppColors.error),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1);
  }
}
