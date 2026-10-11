import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hx_liftoff_ads/hx_liftoff_ads.dart';
import 'package:hx_liftoff_ads/src/platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    LiftoffBridge.debugSupportedOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LiftoffBridge.methodChannel, (call) async {
      calls.add(call);
      return call.method == 'sdkVersion' ? '7.7.9' : null;
    });
  });

  tearDown(() {
    LiftoffBridge.debugSupportedOverride = null;
  });

  Future<void> emit(Map<String, Object?> event) async {
    final data = const StandardMethodCodec().encodeSuccessEnvelope(event);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            LiftoffBridge.eventChannel.name, data, (_) {});
  }

  test('placement resolution uses explicit id then configured id', () {
    LiftoffAds.instance.setPlacements(const LiftoffPlacements(rewarded: 'R1'));
    expect(
        LiftoffAds.instance.resolvePlacement(AdFormat.rewarded, null), 'R1');
    expect(LiftoffAds.instance.resolvePlacement(AdFormat.rewarded, 'X'), 'X');
    expect(() => LiftoffAds.instance.resolvePlacement(AdFormat.banner, null),
        throwsA(isA<LiftoffAdError>()));
  });

  test('initialize forwards app id and privacy', () async {
    await LiftoffAds.instance.initialize(
      appId: 'APP',
      placements: const LiftoffPlacements(interstitial: 'I1'),
      privacy: const LiftoffPrivacy(gdprConsent: true, coppa: false),
    );
    expect(calls.single.method, 'initialize');
    final args = calls.single.arguments as Map;
    expect(args['appId'], 'APP');
    expect((args['privacy'] as Map)['gdprConsent'], true);
    expect(LiftoffAds.instance.isInitialized, true);
  });

  test('interstitial load completes on loaded event and shows', () async {
    LiftoffAds.instance.setPlacements(const LiftoffPlacements(interstitial: 'I1'));
    var shown = false;
    final future = InterstitialAd.load(
        listener: FullscreenAdListener(onShown: () => shown = true));
    await Future<void>.delayed(Duration.zero);
    final load = calls.lastWhere((c) => c.method == 'loadAd');
    final id = (load.arguments as Map)['id'] as int;
    expect((load.arguments as Map)['placementId'], 'I1');
    await emit({'id': id, 'event': 'loaded'});
    final ad = await future;
    expect(ad.isLoaded, true);
    await ad.show();
    expect(calls.last.method, 'showAd');
    await emit({'id': id, 'event': 'shown'});
    expect(shown, true);
    await emit({'id': id, 'event': 'closed'});
    expect(ad.isLoaded, false);
  });

  test('load failure throws LiftoffAdError', () async {
    LiftoffAds.instance.setPlacements(const LiftoffPlacements(rewarded: 'R1'));
    final future = RewardedAd.load();
    await Future<void>.delayed(Duration.zero);
    final id = (calls.lastWhere((c) => c.method == 'loadAd').arguments
        as Map)['id'] as int;
    final expectation = expectLater(future, throwsA(isA<LiftoffAdError>()));
    await emit({'id': id, 'event': 'failedToLoad', 'code': 6, 'message': 'no fill'});
    await expectation;
  });

  test('unsupported format on this platform fails fast', () async {
    LiftoffBridge.debugSupportedOverride = false;
    expect(LiftoffAds.instance.isSupported(AdFormat.banner), false);
  });

  test('load times out with LiftoffAdError.timeout', () async {
    LiftoffAds.instance.setPlacements(const LiftoffPlacements(rewarded: 'R1'));
    await expectLater(
      RewardedAd.load(timeout: const Duration(milliseconds: 20)),
      throwsA(isA<LiftoffAdError>()
          .having((e) => e.code, 'code', LiftoffAdError.timeout)),
    );
  });

  test('LiftoffPlacements copyWith and equality', () {
    const a = LiftoffPlacements(interstitial: 'I', rewarded: 'R');
    expect(a.copyWith(banner: 'B').banner, 'B');
    expect(a.copyWith(banner: 'B').interstitial, 'I');
    expect(a, const LiftoffPlacements(interstitial: 'I', rewarded: 'R'));
    expect(a == a.copyWith(rewarded: 'X'), false);
  });
}
