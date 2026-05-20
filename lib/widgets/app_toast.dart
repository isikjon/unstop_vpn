import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppToastType { success, warning, error }

OverlayEntry? _activeToastEntry;
VoidCallback? _removeActiveToast;

AppToastType appToastTypeForMessage(String message) {
  final text = message.toLowerCase();
  if (text.contains('успеш') ||
      text.contains('скопирован') ||
      text.contains('готов')) {
    return AppToastType.success;
  }
  if (text.contains('лимит') ||
      text.contains('ошибка') ||
      text.contains('отклон') ||
      text.contains('недоступ') ||
      text.contains('не удалось')) {
    return AppToastType.error;
  }
  return AppToastType.warning;
}

void showAppToast(
  BuildContext context, {
  required String message,
  AppToastType type = AppToastType.warning,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _removeActiveToast?.call();

  late final OverlayEntry entry;
  var removed = false;

  void removeEntry() {
    if (removed) return;
    removed = true;
    if (_activeToastEntry == entry) {
      _activeToastEntry = null;
      _removeActiveToast = null;
    }
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _AppToastOverlay(
      message: message,
      type: type,
      duration: duration,
      onDismissed: removeEntry,
    ),
  );

  _activeToastEntry = entry;
  _removeActiveToast = removeEntry;
  overlay.insert(entry);
}

class _AppToastOverlay extends StatefulWidget {
  final String message;
  final AppToastType type;
  final Duration duration;
  final VoidCallback onDismissed;

  const _AppToastOverlay({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_AppToastOverlay> createState() => _AppToastOverlayState();
}

class _AppToastOverlayState extends State<_AppToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _timer;
  var _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    if (mounted) {
      await _controller.reverse();
    }
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top + 88;
    final spec = _ToastSpec.forType(widget.type);

    return Positioned(
      top: top,
      left: 22,
      right: 22,
      child: SafeArea(
        top: false,
        bottom: false,
        child: IgnorePointer(
          ignoring: false,
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: Center(
                child: GestureDetector(
                  onTap: _dismiss,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xF50B1022),
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(color: const Color(0xFF17213A)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x3D000000),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(spec.icon, color: spec.color, size: 38),
                            const SizedBox(width: 14),
                            Flexible(
                              child: Text(
                                widget.message,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  color: const Color(0xFFD2EEFF),
                                  fontSize: 22,
                                  height: 1.12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastSpec {
  final IconData icon;
  final Color color;

  const _ToastSpec({required this.icon, required this.color});

  factory _ToastSpec.forType(AppToastType type) {
    return switch (type) {
      AppToastType.success => const _ToastSpec(
        icon: Icons.verified_rounded,
        color: Color(0xFF20EF86),
      ),
      AppToastType.warning => const _ToastSpec(
        icon: Icons.warning_rounded,
        color: Color(0xFFFF8418),
      ),
      AppToastType.error => const _ToastSpec(
        icon: Icons.cancel_rounded,
        color: Color(0xFFFF3030),
      ),
    };
  }
}
