import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/secure_storage.dart';

/// Auth state machine.
///
/// Steps:
///   bootstrapping → (restore from storage)
///     ├── tg_id found  → authenticated
///     └── nothing      → idle (show AuthScreen)
///
/// AuthScreen drives:
///   idle → phoneEntered (user entered phone, app opens bot)
///        → codeSent     (bot received contact, code sent to @VerificationCodes)
///        → verifying    (app is calling /verify-code)
///        → authenticated (tg_id received, saved)
///        → error        (any step failed)
enum AuthStep {
  bootstrapping,
  idle,
  phoneEntered, // phone saved, waiting for user to share contact in bot
  codeSent, // code sent, waiting for user to enter it
  verifying, // POST /verify-code in flight
  authenticated,
  error,
}

class AuthState {
  final AuthStep step;
  final String? telegramId;
  final String? phone; // normalised E.164 phone
  final String? error;

  const AuthState({
    this.step = AuthStep.bootstrapping,
    this.telegramId,
    this.phone,
    this.error,
  });

  bool get isAuthenticated =>
      step == AuthStep.authenticated && telegramId != null;
  bool get isBootstrapping => step == AuthStep.bootstrapping;

  AuthState copyWith({
    AuthStep? step,
    String? telegramId,
    String? phone,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      step: step ?? this.step,
      telegramId: telegramId ?? this.telegramId,
      phone: phone ?? this.phone,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _bootstrap();
    return const AuthState(step: AuthStep.bootstrapping);
  }

  Future<void> _bootstrap() async {
    final id = await VpnSecureStorage.getTelegramId();
    final phone = await VpnSecureStorage.getPhone();
    if (id != null && id.isNotEmpty) {
      state = AuthState(
        step: AuthStep.authenticated,
        telegramId: id,
        phone: phone,
      );
    } else {
      state = const AuthState(step: AuthStep.idle);
    }
  }

  /// Called when user enters their phone and taps "Перейти в бот".
  /// We save the phone and move to the next step — the bot flow runs
  /// in Telegram, so the app just waits.
  Future<void> phoneSubmitted(String phone) async {
    await VpnSecureStorage.savePhone(phone);
    state = state.copyWith(
      step: AuthStep.phoneEntered,
      phone: phone,
      clearError: true,
    );
  }

  /// Called when user taps "Я поделился контактом, жду код".
  void contactShared() {
    state = state.copyWith(step: AuthStep.codeSent, clearError: true);
  }

  /// Called with the verified Telegram ID once the backend confirms the code.
  Future<void> setVerifiedId(String telegramId) async {
    await VpnSecureStorage.saveTelegramId(telegramId);
    state = AuthState(
      step: AuthStep.authenticated,
      telegramId: telegramId,
      phone: state.phone,
    );
  }

  void setError(String message) {
    state = state.copyWith(step: AuthStep.error, error: message);
  }

  void setVerifying() {
    state = state.copyWith(step: AuthStep.verifying, clearError: true);
  }

  /// Go back to phone entry (e.g. user pressed back or wants to retry).
  void reset() {
    state = const AuthState(step: AuthStep.idle);
  }

  Future<void> signOut() async {
    await VpnSecureStorage.clearTelegramId();
    await VpnSecureStorage.clearPhone();
    state = const AuthState(step: AuthStep.idle);
  }
}
