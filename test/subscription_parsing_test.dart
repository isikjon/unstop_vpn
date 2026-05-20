import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unstop_vpn/models/subscription.dart';
import 'package:unstop_vpn/models/vpn_server.dart';
import 'package:unstop_vpn/services/device_headers_service.dart';

void main() {
  group('DeviceHeadersService', () {
    tearDown(DeviceHeadersService.resetForTesting);

    test('reuses one install id for concurrent header requests', () async {
      String? storedId;
      var saveCount = 0;
      DeviceHeadersService.debugReadInstallId = () async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return storedId;
      };
      DeviceHeadersService.debugSaveInstallId = (id) async {
        saveCount += 1;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        storedId = id;
      };
      DeviceHeadersService.debugStablePlatformId = () async => null;

      final headers = await Future.wait(
        List.generate(8, (_) => DeviceHeadersService.apiHeaders()),
      );

      final hwids = headers.map((header) => header['x-hwid']).toSet();
      expect(hwids, hasLength(1));
      expect(storedId, hwids.single);
      expect(saveCount, 1);
    });

    test('uses stable platform id for a new installation', () async {
      String? storedId;
      DeviceHeadersService.debugReadInstallId = () async => storedId;
      DeviceHeadersService.debugSaveInstallId = (id) async => storedId = id;
      DeviceHeadersService.debugStablePlatformId = () async =>
          '  IDFV-ABC-123  ';

      final headers = await DeviceHeadersService.apiHeaders();

      expect(headers['x-hwid'], 'idfv-abc-123');
      expect(storedId, 'idfv-abc-123');
    });

    test('keeps saved install id instead of replacing it', () async {
      var saveCount = 0;
      DeviceHeadersService.debugReadInstallId = () async => 'saved-id';
      DeviceHeadersService.debugSaveInstallId = (_) async => saveCount += 1;
      DeviceHeadersService.debugStablePlatformId = () async => 'new-id';

      final headers = await DeviceHeadersService.apiHeaders();

      expect(headers['x-hwid'], 'saved-id');
      expect(saveCount, 0);
    });
  });

  group('VpnServer parsing', () {
    test('round-trips protected config URLs', () {
      const rawUrl = 'vless://user@example.com:443?security=tls#NL-Amsterdam-1';
      final protectedUrl = VpnServer.protectUrl(rawUrl);
      final server = VpnServer.tryParse(protectedUrl);

      expect(protectedUrl, startsWith('unstop://config/'));
      expect(server, isNotNull);
      expect(server!.url, rawUrl);
      expect(server.address, 'example.com');
      expect(server.country, 'Нидерланды');
      expect(server.flag, '🇳🇱');
      expect(server.city, 'Amsterdam-1');
    });

    test('parses VLESS Reality Vision server used by iOS Packet Tunnel', () {
      final server = VpnServer.tryParse(
        'vless://00000000-0000-4000-8000-000000000000@example.com:443'
        '?security=reality&type=tcp&flow=xtls-rprx-vision&fp=chrome'
        '&pbk=public-key&sid=short-id&sni=example.com'
        '#%F0%9F%87%B3%F0%9F%87%B1%20%D0%9D%D0%B8%D0%B4%D0%B5%D1%80%D0%BB%D0%B0%D0%BD%D0%B4%D1%8B',
      );

      expect(server, isNotNull);
      expect(server!.address, 'example.com');
      expect(server.port, 443);
      expect(server.remark, '🇳🇱 Нидерланды');
      expect(server.country, 'Нидерланды');
      expect(server.flag, '🇳🇱');
    });

    test('uses full URL in server identity when endpoints match', () {
      final first = VpnServer.tryParse(
        'vless://00000000-0000-4000-8000-000000000001@example.com:443'
        '?security=reality&type=tcp&flow=xtls-rprx-vision&fp=chrome'
        '&pbk=public-key-1&sid=short-id-1&sni=it.example.com#IT-Rome',
      );
      final second = VpnServer.tryParse(
        'vless://00000000-0000-4000-8000-000000000002@example.com:443'
        '?security=reality&type=tcp&flow=xtls-rprx-vision&fp=chrome'
        '&pbk=public-key-2&sid=short-id-2&sni=al.example.com#AL-Tirana',
      );

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.address, second!.address);
      expect(first.port, second.port);
      expect(first.id, isNot(second.id));
    });

    test('parses and protects raw Xray JSON configs from backend', () {
      final rawConfig = jsonEncode(_xrayConfig());
      final protectedUrl = VpnServer.protectUrl(rawConfig);
      final server = VpnServer.tryParse(protectedUrl);

      expect(protectedUrl, startsWith('unstop://config/'));
      expect(server, isNotNull);
      expect(server!.url, rawConfig);
      expect(server.address, 'node.example.com');
      expect(server.port, 443);
      expect(server.country, 'Нидерланды');
      expect(server.flag, '🇳🇱');
    });

    test('rejects unsupported or malformed config strings', () {
      expect(VpnServer.tryParse('https://example.com'), isNull);
      expect(VpnServer.tryParse('ikev2://dev-game.404.mn#Legacy'), isNull);
      expect(VpnServer.tryParse('unstop://config/not-valid-base64'), isNull);
      expect(VpnServer.tryParse(''), isNull);
    });
  });

  group('Subscription parsing', () {
    test('parses backend map with protected server list and metadata', () {
      const rawUrl = 'vless://user@example.com:443#DE-Berlin';
      final subscription = Subscription.fromAny({
        'success': true,
        'items': [VpnServer.protectUrl(rawUrl)],
        'meta': {
          'status': 'active',
          'date_finish': '2099-01-01T00:00:00Z',
          'used_total_bytes': 1024,
          'traffic_limit_gb': 2,
          'devices_used': 1,
          'ip_limit': 3,
          'plan': 'premium',
        },
      });

      expect(subscription.isActive, isTrue);
      expect(subscription.servers, hasLength(1));
      expect(subscription.servers.single.url, rawUrl);
      expect(subscription.trafficUsedBytes, 1024);
      expect(subscription.trafficLimitBytes, 2147483648);
      expect(subscription.deviceUsedCount, 1);
      expect(subscription.deviceLimitCount, 3);
      expect(subscription.planName, 'premium');
    });

    test('keeps device limit errors visible even without servers', () {
      final subscription = Subscription.fromAny({
        'success': false,
        'message': 'limit_devices',
        'meta': {'ip_limit': 1},
      });

      expect(subscription.isActive, isTrue);
      expect(subscription.isDeviceLimitExceeded, isTrue);
      expect(subscription.userFacingError, 'Лимит устройств достигнут');
      expect(subscription.servers, isEmpty);
    });

    test(
      'adds device usage numbers to device limit message when available',
      () {
        final subscription = Subscription.fromAny({
          'success': false,
          'message': 'limit_devices',
          'meta': {'devices_used': 2, 'ip_limit': 2},
        });

        expect(subscription.userFacingError, 'Лимит устройств достигнут (2/2)');
      },
    );

    test('recognizes successful empty payload as device limit reached', () {
      final subscription = Subscription.fromAny({
        'success': true,
        'message': 'subscription_loaded',
        'format': 'json_configs',
        'items': [],
        'meta': {
          'status': 'active',
          'date_finish': '2099-01-01 00:00:00',
          'ip_limit': 15,
          'ip_used': 15,
          'limit_reached': true,
        },
      });

      expect(subscription.isActive, isTrue);
      expect(subscription.isDeviceLimitExceeded, isTrue);
      expect(subscription.servers, isEmpty);
      expect(subscription.userFacingError, 'Лимит устройств достигнут (15/15)');
    });

    test('uses whitelist traffic total instead of full traffic bytes', () {
      final subscription = Subscription.fromAny({
        'success': true,
        'items': ['vless://user@example.com:443#DE-Berlin'],
        'meta': {
          'status': 'active',
          'date_finish': '2099-01-01T00:00:00Z',
          'used_total_bytes': 16641780961280,
          'traffic_whitelist_total_gb': 350,
        },
      });

      expect(subscription.trafficUsedBytes, 350 * 1073741824);
      expect(subscription.trafficLimitBytes, isNull);
    });

    test('keeps one server active during grace period after expiration', () {
      final subscription = Subscription.fromAny({
        'success': true,
        'message': 'subscription_loaded',
        'format': 'json_configs',
        'items': ['vless://user@example.com:443#Grace'],
        'meta': {
          'status': 'expired',
          'date_finish': '2020-01-01 00:00:00',
          'grace_period': true,
        },
      });

      expect(subscription.isActive, isTrue);
      expect(subscription.isGracePeriod, isTrue);
      expect(subscription.servers, hasLength(1));
    });

    test('maps inactive and grace-period backend messages to user text', () {
      final expired = Subscription.fromAny({
        'success': false,
        'message': 'subscription_inactive_or_expired',
        'status': 'expired',
        'date_finish': '2020-01-01 00:00:00',
      });
      final graceFailed = Subscription.fromAny({
        'success': false,
        'message': 'grace_period_config_build_failed',
      });
      final payloadPending = Subscription.fromAny({
        'success': false,
        'message': 'subscription_payload_not_loaded',
      });

      expect(expired.isActive, isFalse);
      expect(expired.userFacingError, 'Подписка истекла');
      expect(graceFailed.userFacingError, contains('Дополнительный доступ'));
      expect(payloadPending.isPayloadPending, isTrue);
      expect(payloadPending.userFacingError, contains('обрабатывается'));
    });

    test('serializes cached server urls as protected configs', () {
      const rawUrl = 'vless://user@example.com:443#DE-Berlin';
      final subscription = Subscription.fromAny([rawUrl]);
      final cache = subscription.toCacheJson();

      expect(cache['success'], isTrue);
      expect(cache['items'], isA<List>());
      expect((cache['items'] as List).single, startsWith('unstop://config/'));
    });

    test('keeps all backend VLESS and Shadowsocks servers', () {
      final urls = <String>[
        for (var i = 0; i < 22; i++)
          'vless://00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}@server$i.example.com:443'
              '?security=reality&type=tcp&flow=xtls-rprx-vision&fp=chrome'
              '&pbk=public-key$i&sid=short-id$i&sni=server$i.example.com'
              '#NL-Server-$i',
        'ss://YWVzLTI1Ni1nY206cGFzcw@example.com:1234#SS-1',
        'ss://YWVzLTI1Ni1nY206cGFzczI@example.org:1234#SS-2',
      ];

      final subscription = Subscription.fromAny({
        'success': true,
        'items': urls,
      });

      expect(subscription.servers, hasLength(24));
      expect(
        subscription.servers.where(
          (server) => server.url.startsWith('vless://'),
        ),
        hasLength(22),
      );
      expect(
        subscription.servers.where((server) => server.url.startsWith('ss://')),
        hasLength(2),
      );
    });

    test('parses nested data items and alternate server url keys', () {
      const rawUrl = 'vless://user@example.com:443#Nested';
      final subscription = Subscription.fromAny({
        'status': 'active',
        'data': {
          'items': [
            {'link': rawUrl},
          ],
        },
      });

      expect(subscription.isActive, isTrue);
      expect(subscription.servers, hasLength(1));
      expect(subscription.servers.single.url, rawUrl);
    });

    test('parses backend json_configs items as connectable servers', () {
      final subscription = Subscription.fromAny({
        'success': true,
        'message': 'subscription_loaded',
        'format': 'json_configs',
        'items': [_xrayConfig()],
        'meta': {
          'status': 'active',
          'date_finish': '2099-01-01 00:00:00',
          'ip_limit': 3,
        },
      });

      expect(subscription.isActive, isTrue);
      expect(subscription.servers, hasLength(1));
      expect(subscription.servers.single.url.trimLeft(), startsWith('{'));
      expect(subscription.toCacheJson()['items'], hasLength(1));
      expect(
        (subscription.toCacheJson()['items'] as List).single,
        startsWith('unstop://config/'),
      );
    });
  });
}

Map<String, dynamic> _xrayConfig() => {
  'remarks': '🇳🇱 Нидерланды',
  'inbounds': [
    {
      'tag': 'socks',
      'listen': '127.0.0.1',
      'port': 10808,
      'protocol': 'socks',
      'settings': {'udp': true},
    },
  ],
  'outbounds': [
    {
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': 'node.example.com',
            'port': 443,
            'users': [
              {
                'id': '00000000-0000-4000-8000-000000000000',
                'encryption': 'none',
                'flow': 'xtls-rprx-vision',
              },
            ],
          },
        ],
      },
      'streamSettings': {
        'network': 'tcp',
        'security': 'reality',
        'realitySettings': {
          'serverName': 'example.com',
          'fingerprint': 'chrome',
          'publicKey': 'public-key',
          'shortId': 'short-id',
        },
      },
    },
    {'tag': 'direct', 'protocol': 'freedom'},
  ],
  'dns': {
    'servers': ['8.8.8.8'],
  },
  'routing': {'rules': []},
};
