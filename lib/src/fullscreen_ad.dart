import 'dart:async';

import 'liftoff_ads.dart';
import 'models.dart';
import 'platform.dart';

/// Callbacks for fullscreen ads. All optional.
class FullscreenAdListener {
  const FullscreenAdListener({
    this.onShown,
    this.onImpression,
    this.onClicked,
    this.onClosed,
    this.onFailedToShow,
    this.onRewarded,
  });

  final void Function()? onShown;
  final void Function()? onImpression;
  final void Function()? onClicked;
  final void Function()? onClosed;
  final void Function(LiftoffAdError error)? onFailedToShow;

  /// Rewarded ads only: the user earned the reward.
  final void Function()? onRewarded;
}

/// Shared implementation of interstitial, rewarded and app open ads.
abstract class FullscreenAd {
  /// Default time to wait for an ad to load before giving up.
  static const Duration defaultLoadTimeout = Duration(seconds: 30);

  FullscreenAd.internal(this.format, this.placementId, this.listener)
      : _id = LiftoffBridge.newId();

  final AdFormat format;
  final String placementId;
  FullscreenAdListener? listener;
  final int _id;

  Completer<void>? _loadCompleter;
  bool _loaded = false;
  bool _disposed = false;

  bool get isLoaded => _loaded && !_disposed;

  Future<void> _load(String? userId, Duration timeout) {
    if (!LiftoffAds.instance.isSupported(format)) {
      return Future.error(const LiftoffAdError(
          LiftoffAdError.unsupported, 'Format not supported on this platform'));
    }
    if (!LiftoffAds.instance.isInitialized) {
      return Future.error(const LiftoffAdError(LiftoffAdError.notInitialized,
          'Call LiftoffAds.instance.initialize first'));
    }
    final c = _loadCompleter = Completer<void>();
    LiftoffBridge.register(_id, _onEvent);
    LiftoffBridge.invoke<void>('loadAd', {
      'id': _id,
      'format': format == AdFormat.appOpen ? 'interstitial' : format.name,
      'placementId': placementId,
      'userId': userId,
    }).catchError((Object e) {
      if (!c.isCompleted) c.completeError(e);
    });
    return c.future.timeout(timeout, onTimeout: () {
      dispose();
      throw LiftoffAdError(LiftoffAdError.timeout,
          'Ad did not load within ${timeout.inSeconds}s');
    });
  }

  void _onEvent(String event, LiftoffAdError? error) {
    switch (event) {
      case 'loaded':
        _loaded = true;
        _loadCompleter?.complete();
      case 'failedToLoad':
        if (_loadCompleter?.isCompleted == false) {
          _loadCompleter!
              .completeError(error ?? const LiftoffAdError(-1, 'Failed to load'));
        }
        dispose();
      case 'shown':
        listener?.onShown?.call();
      case 'impression':
        listener?.onImpression?.call();
      case 'clicked':
        listener?.onClicked?.call();
      case 'rewarded':
        listener?.onRewarded?.call();
      case 'closed':
        _loaded = false;
        listener?.onClosed?.call();
        dispose();
      case 'failedToShow':
        _loaded = false;
        listener?.onFailedToShow
            ?.call(error ?? const LiftoffAdError(-1, 'Failed to show'));
        dispose();
    }
  }

  /// Shows the ad. Each loaded ad can be shown once.
  Future<void> show() async {
    if (!isLoaded) {
      throw const LiftoffAdError(
          LiftoffAdError.notLoaded, 'Ad is not loaded or already shown');
    }
    await LiftoffBridge.invoke<void>('showAd', {'id': _id});
  }

  /// Releases native resources. Called automatically after the ad closes.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loaded = false;
    LiftoffBridge.unregister(_id);
    LiftoffBridge.invoke<void>('disposeAd', {'id': _id}).catchError((_) {});
  }
}

/// Full screen interstitial ad.
class InterstitialAd extends FullscreenAd {
  InterstitialAd._(String placementId, FullscreenAdListener? l)
      : super.internal(AdFormat.interstitial, placementId, l);

  /// Loads an interstitial. Completes when loaded, throws [LiftoffAdError]
  /// if loading fails. [placementId] defaults to
  /// [LiftoffPlacements.interstitial].
  static Future<InterstitialAd> load({
    String? placementId,
    FullscreenAdListener? listener,
    Duration timeout = FullscreenAd.defaultLoadTimeout,
  }) async {
    final ad = InterstitialAd._(
        LiftoffAds.instance.resolvePlacement(AdFormat.interstitial, placementId),
        listener);
    await ad._load(null, timeout);
    return ad;
  }
}

/// Rewarded video ad. Listen to [FullscreenAdListener.onRewarded].
class RewardedAd extends FullscreenAd {
  RewardedAd._(String placementId, FullscreenAdListener? l)
      : super.internal(AdFormat.rewarded, placementId, l);

  static Future<RewardedAd> load({
    String? placementId,
    String? userId,
    FullscreenAdListener? listener,
    Duration timeout = FullscreenAd.defaultLoadTimeout,
  }) async {
    final ad = RewardedAd._(
        LiftoffAds.instance.resolvePlacement(AdFormat.rewarded, placementId),
        listener);
    await ad._load(userId, timeout);
    return ad;
  }
}

/// App open ad: a fullscreen ad meant to be shown when the app starts or
/// returns to the foreground. See `AppOpenAdManager` for automatic handling.
///
/// The Liftoff SDKs have no dedicated app open class, so this is served
/// through the SDK's fullscreen (interstitial) API using your App Open
/// placement.
class AppOpenAd extends FullscreenAd {
  AppOpenAd._(String placementId, FullscreenAdListener? l)
      : super.internal(AdFormat.appOpen, placementId, l);

  DateTime? _loadedAt;

  /// Ads older than 4 hours should not be shown.
  bool get isExpired =>
      _loadedAt == null ||
      DateTime.now().difference(_loadedAt!) > const Duration(hours: 4);

  static Future<AppOpenAd> load({
    String? placementId,
    FullscreenAdListener? listener,
    Duration timeout = FullscreenAd.defaultLoadTimeout,
  }) async {
    final ad = AppOpenAd._(
        LiftoffAds.instance.resolvePlacement(AdFormat.appOpen, placementId),
        listener);
    await ad._load(null, timeout);
    ad._loadedAt = DateTime.now();
    return ad;
  }
}
