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
    if (_isWindowsPlatform) {
      return _WindowsInlineHost(adId: adId, placementId: placement!);
    }
    return const SizedBox.shrink();
  }
}

bool get _isWindowsPlatform => !kIsWeb && Platform.isWindows;

/// Windows has no platform views, so the ad is drawn by a native child window
/// that this widget keeps positioned over its own bounds (experimental).
///
/// A native window is always drawn above Flutter content: dialogs, menus and
/// overlays that overlap the ad appear behind it. The ad is hidden while
/// another route covers this page.
class _WindowsInlineHost extends StatefulWidget {
  const _WindowsInlineHost({required this.adId, required this.placementId});

  final int adId;
  final String placementId;

  @override
  State<_WindowsInlineHost> createState() => _WindowsInlineHostState();
}

class _WindowsInlineHostState extends State<_WindowsInlineHost> {
  Map<String, Object?>? _last;
  bool _created = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_sync);
  }

  /// Runs after every frame while mounted and reports the widget's bounds
  /// (physical pixels) whenever they change.
  void _sync(Duration _) {
    if (_disposed || !mounted) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      final dpr = View.of(context).devicePixelRatio;
      final topLeft = box.localToGlobal(Offset.zero);
      final route = ModalRoute.of(context);
      final visible = (route?.isCurrent ?? true) &&
          TickerMode.valuesOf(context).enabled &&
          box.size.height > 1;
      final args = <String, Object?>{
        'id': widget.adId,
        'x': (topLeft.dx * dpr).round(),
        'y': (topLeft.dy * dpr).round(),
        'w': (box.size.width * dpr).round(),
        'h': (box.size.height * dpr).round(),
        'visible': visible,
      };
      if (!mapEquals(args, _last)) {
        _last = args;
        if (!_created) {
          _created = true;
          LiftoffBridge.invoke<void>(
              'inlineShow', {...args, 'placementId': widget.placementId})
              .catchError((_) {});
        } else {
          LiftoffBridge.invoke<void>('inlineMove', args).catchError((_) {});
        }
      }
    }
    // Keep following the widget (scrolling, resizing, route changes).
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback(_sync);
  }

  @override
  void dispose() {
    _disposed = true;
    if (_created) {
      LiftoffBridge.invoke<void>('inlineDispose', {'id': widget.adId})
          .catchError((_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// Banner / MREC ad. Collapses to zero size if the ad fails to load or the
/// platform doesn't support it. On Windows it is drawn in a native child
/// window (experimental).
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
    // The native view is kept in the tree while loading so the SDK can attach
    // to a window. Windows reserves the full size up front because the ad is
    // only drawn once its window exists.
    return SizedBox(
      width: widget.size.width.toDouble(),
      height: loaded || _isWindowsPlatform ? widget.size.height.toDouble() : 1,
      child: buildPlatformView(),
    );
  }
}

/// Native ad rendered with a built-in template (icon, title, body, media and
/// call-to-action button) on Android and iOS. On Windows the Liftoff SDK draws
/// the creative itself in a native child window (experimental).
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
      height: loaded || _isWindowsPlatform ? widget.height : 1,
      child: buildPlatformView(),
    );
  }
}
