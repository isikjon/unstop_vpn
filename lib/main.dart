import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.bgCard,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(ProviderScope(child: UnstopVpnApp()));
}

class UnstopVpnApp extends StatelessWidget {
  const UnstopVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unstop VPN',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AppStartGate(),
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/onboard': (_) => const OnboardingScreen(),
        '/auth': (_) => const AuthScreen(),
        '/home': (_) => const AuthGate(child: MainShell()),
      },
    );
  }
}

class AppStartGate extends ConsumerWidget {
  const AppStartGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return FutureBuilder<bool>(
      future: OnboardingScreen.isFirstLaunch(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || auth.isBootstrapping) {
          return const _BootLoadingScreen();
        }

        if (snapshot.data!) {
          return const OnboardingScreen();
        }

        return auth.isAuthenticated ? const MainShell() : const AuthScreen();
      },
    );
  }
}

class AuthGate extends ConsumerWidget {
  final Widget child;

  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (auth.isBootstrapping) return const _BootLoadingScreen();
    if (!auth.isAuthenticated) return const AuthScreen();
    return child;
  }
}

class _BootLoadingScreen extends StatelessWidget {
  const _BootLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
