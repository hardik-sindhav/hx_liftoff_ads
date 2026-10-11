import 'package:flutter/material.dart';
import 'package:hx_liftoff_ads/hx_liftoff_ads.dart';

void main() => runApp(const MaterialApp(home: DemoPage()));

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _appId = TextEditingController();
  final _fields = {
    for (final f in AdFormat.values) f: TextEditingController(),
  };
  final _log = <String>[];
  bool _ready = false;
  bool _showBanner = false;
  bool _showMrec = false;
  bool _showNative = false;
  AppOpenAdManager? _appOpen;

  void _say(String s) => setState(() => _log.insert(0, s));

  Future<void> _init() async {
    String? p(AdFormat f) =>
        _fields[f]!.text.trim().isEmpty ? null : _fields[f]!.text.trim();
    try {
      await LiftoffAds.instance.initialize(
        appId: _appId.text.trim(),
        placements: LiftoffPlacements(
          interstitial: p(AdFormat.interstitial),
          rewarded: p(AdFormat.rewarded),
          appOpen: p(AdFormat.appOpen),
          banner: p(AdFormat.banner),
          mrec: p(AdFormat.mrec),
          native: p(AdFormat.native),
        ),
      );
      setState(() => _ready = true);
      _say('SDK ready: ${await LiftoffAds.instance.sdkVersion}');
    } on LiftoffAdError catch (e) {
      _say('init failed: $e');
    }
  }

  Future<void> _fullscreen(AdFormat f) async {
    try {
      final listener = FullscreenAdListener(
        onShown: () => _say('${f.name} shown'),
        onClicked: () => _say('${f.name} clicked'),
        onClosed: () => _say('${f.name} closed'),
        onRewarded: () => _say('REWARD earned'),
        onFailedToShow: (e) => _say('${f.name} show failed: $e'),
      );
      final FullscreenAd ad = switch (f) {
        AdFormat.rewarded => await RewardedAd.load(listener: listener),
        AdFormat.appOpen => await AppOpenAd.load(listener: listener),
        _ => await InterstitialAd.load(listener: listener),
      };
      _say('${f.name} loaded');
      await ad.show();
    } on LiftoffAdError catch (e) {
      _say('${f.name} error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ads = LiftoffAds.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Liftoff ads demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _appId,
            decoration: const InputDecoration(labelText: 'Liftoff App ID'),
          ),
          for (final f in AdFormat.values)
            TextField(
              controller: _fields[f],
              decoration:
                  InputDecoration(labelText: '${f.name} placement (ad unit)'),
            ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _init, child: const Text('Initialize')),
          const Divider(),
          Wrap(spacing: 8, children: [
            for (final f in [
              AdFormat.interstitial,
              AdFormat.rewarded,
              AdFormat.appOpen
            ])
              ElevatedButton(
                onPressed:
                    _ready && ads.isSupported(f) ? () => _fullscreen(f) : null,
                child: Text('Show ${f.name}'),
              ),
            ElevatedButton(
              onPressed: _ready && ads.isSupported(AdFormat.appOpen)
                  ? () {
                      _appOpen ??= AppOpenAdManager(onError: (e) => _say('$e'));
                      _appOpen!.start();
                      _say('App open manager started (background the app)');
                    }
                  : null,
              child: const Text('Auto app open'),
            ),
            ElevatedButton(
              onPressed: _ready && ads.isSupported(AdFormat.banner)
                  ? () => setState(() => _showBanner = !_showBanner)
                  : null,
              child: const Text('Toggle banner'),
            ),
            ElevatedButton(
              onPressed: _ready && ads.isSupported(AdFormat.mrec)
                  ? () => setState(() => _showMrec = !_showMrec)
                  : null,
              child: const Text('Toggle MREC'),
            ),
            ElevatedButton(
              onPressed: _ready && ads.isSupported(AdFormat.native)
                  ? () => setState(() => _showNative = !_showNative)
                  : null,
              child: const Text('Toggle native'),
            ),
          ]),
          if (_showBanner)
            LiftoffBannerAd(
              onLoaded: () => _say('banner loaded'),
              onFailedToLoad: (e) => _say('banner failed: $e'),
            ),
          if (_showMrec)
            LiftoffBannerAd.mrec(
              onLoaded: () => _say('mrec loaded'),
              onFailedToLoad: (e) => _say('mrec failed: $e'),
            ),
          if (_showNative)
            LiftoffNativeAd(
              onLoaded: () => _say('native loaded'),
              onFailedToLoad: (e) => _say('native failed: $e'),
            ),
          const Divider(),
          for (final l in _log) Text(l),
        ],
      ),
    );
  }
}
