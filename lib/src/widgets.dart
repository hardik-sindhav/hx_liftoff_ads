import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'liftoff_ads.dart';
import 'models.dart';
import 'platform.dart';

/// Shared state for platform-view backed ad widgets.
abstract class _PlatformAdState<T extends StatefulWidget> extends State<T> {
  final int adId = LiftoffBridge.newId();
  bool loaded = false;
  LiftoffAdError? error;

  AdFormat get format;
  String? get explicitPlacement;
  String get viewType;
  Map<String, Object?> get extraParams;

  void onAdEvent(String event, LiftoffAdError? err);

  String? placement;

  @override
  void initState() {
    super.initState();
    try {
      placement =
          LiftoffAds.instance.resolvePlacement(format, explicitPlacement);
    } on LiftoffAdError catch (e) {
      error = e;
    }
    if (!LiftoffAds.instance.isSupported(format)) {
      error = const LiftoffAdError(
          LiftoffAdError.unsupported, 'Format not supported on this platform');
    } else if (!LiftoffAds.instance.isInitialized) {
      error = const LiftoffAdError(
          LiftoffAdError.notInitialized, 'SDK not initialized');
    }
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onAdEvent('failedToLoad', error);
      });
      return;
    }
    LiftoffBridge.register(adId, (e, err) {
      if (!mounted) return;
      if (e == 'loaded') loaded = true;
      if (e == 'failedToLoad') error = err;
      setState(() {});
      onAdEvent(e, err);
    });
  }

  @override
  void dispose() {
    LiftoffBridge.unregister(adId);
    super.dispose();
  }

  Widget buildPlatformView() {
    final params = <String, Object?>{
      'id': adId,
      'placementId': placement,
      ...extraParams,
    };
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidView(
        viewType: viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Banner / MREC ad. Collapses to zero size if the ad fails to load or the
/// platform doesn't support banners (Windows).
class LiftoffBannerAd extends StatefulWidget {
  const LiftoffBannerAd({
    super.key,
    this.placementId,
    this.size = BannerSize.banner,
    this.onLoaded,
    this.onFailedToLoad,
    this.onImpression,
    this.onClicked,
  });

  /// A 300x250 medium rectangle.
  const LiftoffBannerAd.mrec({
    super.key,
    this.placementId,
    this.onLoaded,
    this.onFailedToLoad,
    this.onImpression,
    this.onClicked,
  }) : size = BannerSize.mrec;

  /// Defaults to [LiftoffPlacements.banner] (or `.mrec` for MREC size).
  final String? placementId;
  final BannerSize size;
  final VoidCallback? onLoaded;
  final void Function(LiftoffAdError error)? onFailedToLoad;
  final VoidCallback? onImpression;
  final VoidCallback? onClicked;

  @override
  State<LiftoffBannerAd> createState() => _LiftoffBannerAdState();
}

class _LiftoffBannerAdState extends _PlatformAdState<LiftoffBannerAd> {
  @override
  AdFormat get format =>
      widget.size == BannerSize.mrec ? AdFormat.mrec : AdFormat.banner;
  @override
  String? get explicitPlacement => widget.placementId;
  @override
  String get viewType => 'hx_liftoff_ads/banner';
  @override
  Map<String, Object?> get extraParams => {'size': widget.size.name};

  @override
  void onAdEvent(String event, LiftoffAdError? err) {
    switch (event) {
      case 'loaded':
        widget.onLoaded?.call();
      case 'failedToLoad':
        widget.onFailedToLoad?.call(err ?? const LiftoffAdError(-1, 'Failed'));
      case 'impression':
        widget.onImpression?.call();
      case 'clicked':
        widget.onClicked?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return const SizedBox.shrink();
    // The native view is kept in the tree while loading (zero-opacity size
    // reserved) so the SDK can attach to a window.
    return SizedBox(
      width: widget.size.width.toDouble(),
      height: loaded ? widget.size.height.toDouble() : 1,
      child: buildPlatformView(),
    );
  }
}

/// Native ad rendered with a built-in template (icon, title, body, media and
/// call-to-action button). Android and iOS only.
class LiftoffNativeAd extends StatefulWidget {
  const LiftoffNativeAd({
    super.key,
    this.placementId,
    this.height = 320,
    this.onLoaded,
    this.onFailedToLoad,
    this.onImpression,
    this.onClicked,
  });

  final String? placementId;

  /// Height of the ad in logical pixels. Width fills the parent.
  final double height;
  final VoidCallback? onLoaded;
  final void Function(LiftoffAdError error)? onFailedToLoad;
  final VoidCallback? onImpression;
  final VoidCallback? onClicked;

  @override
  State<LiftoffNativeAd> createState() => _LiftoffNativeAdState();
}

class _LiftoffNativeAdState extends _PlatformAdState<LiftoffNativeAd> {
  @override
  AdFormat get format => AdFormat.native;
  @override
  String? get explicitPlacement => widget.placementId;
  @override
  String get viewType => 'hx_liftoff_ads/native';
  @override
  Map<String, Object?> get extraParams => {};

  @override
  void onAdEvent(String event, LiftoffAdError? err) {
    switch (event) {
      case 'loaded':
        widget.onLoaded?.call();
      case 'failedToLoad':
        widget.onFailedToLoad?.call(err ?? const LiftoffAdError(-1, 'Failed'));
      case 'impression':
        widget.onImpression?.call();
      case 'clicked':
        widget.onClicked?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      height: loaded ? widget.height : 1,
      child: buildPlatformView(),
    );
  }
}
