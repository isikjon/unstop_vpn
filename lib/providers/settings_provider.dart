import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TunnelSettings {
  final bool fragmentEnabled;
  final String fragmentPackets;
  final String fragmentLength;
  final String fragmentInterval;

  final bool noiseEnabled;
  final String noiseType;
  final String noisePacket;
  final String noiseDelay;

  const TunnelSettings({
    this.fragmentEnabled = true,
    this.fragmentPackets = 'tlshello',
    this.fragmentLength = '50-100',
    this.fragmentInterval = '10-15',
    this.noiseEnabled = false,
    this.noiseType = 'rand',
    this.noisePacket = '10-20',
    this.noiseDelay = '10-16',
  });

  TunnelSettings copyWith({
    bool? fragmentEnabled,
    String? fragmentPackets,
    String? fragmentLength,
    String? fragmentInterval,
    bool? noiseEnabled,
    String? noiseType,
    String? noisePacket,
    String? noiseDelay,
  }) {
    return TunnelSettings(
      fragmentEnabled: fragmentEnabled ?? this.fragmentEnabled,
      fragmentPackets: fragmentPackets ?? this.fragmentPackets,
      fragmentLength: fragmentLength ?? this.fragmentLength,
      fragmentInterval: fragmentInterval ?? this.fragmentInterval,
      noiseEnabled: noiseEnabled ?? this.noiseEnabled,
      noiseType: noiseType ?? this.noiseType,
      noisePacket: noisePacket ?? this.noisePacket,
      noiseDelay: noiseDelay ?? this.noiseDelay,
    );
  }

  /// Build the Xray sockopt.fragment JSON map, or null if disabled.
  Map<String, dynamic>? get fragmentConfig {
    if (!fragmentEnabled) return null;
    return {
      'packets': fragmentPackets,
      'length': fragmentLength,
      'interval': fragmentInterval,
    };
  }

  /// Build the Xray sockopt.noises JSON list, or null if disabled.
  List<Map<String, dynamic>>? get noisesConfig {
    if (!noiseEnabled) return null;
    return [
      {'type': noiseType, 'packet': noisePacket, 'delay': noiseDelay},
    ];
  }
}

final tunnelSettingsProvider =
    NotifierProvider<TunnelSettingsNotifier, TunnelSettings>(
      TunnelSettingsNotifier.new,
    );

class TunnelSettingsNotifier extends Notifier<TunnelSettings> {
  static const _kFragment = 'tunnel_fragment';
  static const _kNoise = 'tunnel_noise';

  @override
  TunnelSettings build() {
    _load();
    return const TunnelSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      fragmentEnabled: prefs.getBool(_kFragment) ?? true,
      noiseEnabled: prefs.getBool(_kNoise) ?? false,
    );
  }

  Future<void> setFragment(bool enabled) async {
    state = state.copyWith(fragmentEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFragment, enabled);
  }

  Future<void> setNoise(bool enabled) async {
    state = state.copyWith(noiseEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNoise, enabled);
  }
}
