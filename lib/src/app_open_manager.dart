import 'dart:async';

import 'package:flutter/widgets.dart';

import 'fullscreen_ad.dart';
import 'models.dart';

/// Keeps an [AppOpenAd] preloaded and shows it when the app comes back to the
/// foreground.
///
/// ```dart
/// final manager = AppOpenAdManager()..start();
/// ```
class AppOpenAdManager with WidgetsBindingObserver {
  AppOpenAdManager({
    this.placementId,
    this.minInterval = const Duration(minutes: 1),
    this.onError,
  });

  final String? placementId;

  /// Minimum time between two app open ads.
  final Duration minInterval;
  final void Function(LiftoffAdError error)? onError;

  AppOpenAd? _ad;
  bool _loading = false;
  bool _showing = false;
  bool _started = false;
  DateTime? _lastShown;

  /// Begins preloading and listening for foreground events.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _preload();
  }

  void stop() {
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _ad?.dispose();
    _ad = null;
  }

  /// Shows the ad now if one is ready. Returns `true` if it was shown.
  Future<bool> showIfAvailable() async {
    final ad = _ad;
    if (_showing || ad == null || !ad.isLoaded || ad.isExpired) {
      _preload();
      return false;
    }
    final last = _lastShown;
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return false;
    }
    _showing = true;
    _ad = null;
    ad.listener = FullscreenAdListener(
      onClosed: _afterShow,
      onFailedToShow: (e) {
        onError?.call(e);
        _afterShow();
      },
    );
    try {
      await ad.show();
      _lastShown = DateTime.now();
      return true;
    } on LiftoffAdError catch (e) {
      onError?.call(e);
      _afterShow();
      return false;
    }
  }

  void _afterShow() {
    _showing = false;
    _preload();
  }

  Future<void> _preload() async {
    if (_loading || !_started || (_ad?.isLoaded ?? false)) return;
    _loading = true;
    try {
      _ad = await AppOpenAd.load(placementId: placementId);
    } on LiftoffAdError catch (e) {
      onError?.call(e);
    } finally {
      _loading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) showIfAvailable();
  }
}
