import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/secure_storage.dart';

const trialDuration = Duration(hours: 24);

class TrialState {
  final DateTime? startedAt;
  final Duration timeLeft;

  const TrialState({required this.startedAt, required this.timeLeft});

  bool get isExpired => timeLeft.inSeconds <= 0;

  static const initial = TrialState(startedAt: null, timeLeft: trialDuration);
}

final trialProvider = NotifierProvider<TrialNotifier, TrialState>(
  TrialNotifier.new,
);

class TrialNotifier extends Notifier<TrialState> {
  Timer? _timer;

  @override
  TrialState build() {
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(_bootstrap);
    return TrialState.initial;
  }

  Future<void> _bootstrap() async {
    var startedAt = await VpnSecureStorage.getTrialStartedAt();
    if (startedAt == null) {
      startedAt = DateTime.now();
      await VpnSecureStorage.saveTrialStartedAt(startedAt);
    }
    state = TrialState(
      startedAt: startedAt,
      timeLeft: _timeLeftFrom(startedAt),
    );
    _startTicker();
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = state.startedAt;
      if (startedAt == null) return;
      final next = _timeLeftFrom(startedAt);
      if (next == state.timeLeft) return;
      state = TrialState(startedAt: startedAt, timeLeft: next);
    });
  }

  Duration _timeLeftFrom(DateTime startedAt) {
    final elapsed = DateTime.now().difference(startedAt);
    final left = trialDuration - elapsed;
    return left.isNegative ? Duration.zero : left;
  }
}
