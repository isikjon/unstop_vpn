import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';

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
      initialRoute: '/onboard',
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/onboard': (_) => const OnboardingScreen(),
        '/auth': (_) => const AuthScreen(),
        '/home': (_) => const MainShell(),
      },
    );
  }
}
