import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_toast.dart';

Future<void> openSubscriptionFlow(BuildContext context, WidgetRef ref) async {
  final auth = ref.read(authProvider);

  if (!auth.isAuthenticated) {
    if (!context.mounted) return;
    await Navigator.of(context).pushNamed('/auth');
    return;
  }

  final uri = Uri.parse(AppConfig.subscriptionBotDeepLink);
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }

  if (!opened && context.mounted) {
    showAppToast(
      context,
      message: 'Не удалось открыть Telegram',
      type: AppToastType.warning,
    );
  }
}
