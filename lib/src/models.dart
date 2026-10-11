import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Ad formats supported by Liftoff Monetize (formerly Vungle).
enum AdFormat {
  interstitial,
  rewarded,

  /// Shown when the app returns to the foreground. Backed by a fullscreen
  /// placement, see `AppOpenAdManager`.
  appOpen,
  banner,
  mrec,
  native,
}

/// Banner sizes. [mrec] is the 300x250 medium rectangle.
enum BannerSize {
  /// 320x50
  banner(320, 50),

  /// 300x50
  bannerShort(300, 50),

  /// 728x90 (tablets)
  leaderboard(728, 90),

  /// 300x250
  mrec(300, 250);

  const BannerSize(this.width, this.height);
  final int width;
  final int height;
}

/// Your Liftoff placement reference IDs (the "ad unit keys" created in the
/// Liftoff dashboard). Any format you don't use can stay `null`.
///
/// Use different IDs per platform with [LiftoffPlacements.byPlatform].
@immutable
class LiftoffPlacements {
  const LiftoffPlacements({
    this.interstitial,
    this.rewarded,
    this.appOpen,
    this.banner,
    this.mrec,
    this.native,
  });

  final String? interstitial;
  final String? rewarded;
  final String? appOpen;
  final String? banner;
  final String? mrec;
  final String? native;

  /// Picks the placements matching the platform the app is running on.
  factory LiftoffPlacements.byPlatform({
    LiftoffPlacements? android,
    LiftoffPlacements? ios,
    LiftoffPlacements? windows,
  }) {
    if (kIsWeb) return const LiftoffPlacements();
    if (Platform.isAndroid) return android ?? const LiftoffPlacements();
    if (Platform.isIOS) return ios ?? const LiftoffPlacements();
    if (Platform.isWindows) return windows ?? const LiftoffPlacements();
    return const LiftoffPlacements();
  }

  /// Returns a copy with the given placements replaced.
  LiftoffPlacements copyWith({
    String? interstitial,
    String? rewarded,
    String? appOpen,
    String? banner,
    String? mrec,
    String? native,
  }) =>
      LiftoffPlacements(
        interstitial: interstitial ?? this.interstitial,
        rewarded: rewarded ?? this.rewarded,
        appOpen: appOpen ?? this.appOpen,
        banner: banner ?? this.banner,
        mrec: mrec ?? this.mrec,
        native: native ?? this.native,
      );

  @override
  bool operator ==(Object other) =>
      other is LiftoffPlacements &&
      other.interstitial == interstitial &&
      other.rewarded == rewarded &&
      other.appOpen == appOpen &&
      other.banner == banner &&
      other.mrec == mrec &&
      other.native == native;

  @override
  int get hashCode =>
      Object.hash(interstitial, rewarded, appOpen, banner, mrec, native);

  String? forFormat(AdFormat format) => switch (format) {
        AdFormat.interstitial => interstitial,
        AdFormat.rewarded => rewarded,
        AdFormat.appOpen => appOpen,
        AdFormat.banner => banner,
        AdFormat.mrec => mrec,
        AdFormat.native => native,
      };
}

/// Privacy / consent settings, applied before the SDK initializes.
/// `null` means "don't touch".
@immutable
class LiftoffPrivacy {
  const LiftoffPrivacy({
    this.gdprConsent,
    this.gdprMessageVersion = '1.0.0',
    this.ccpaOptIn,
    this.coppa,
  });

  /// GDPR: `true` = user consented, `false` = denied.
  final bool? gdprConsent;
  final String gdprMessageVersion;

  /// CCPA: `true` = opted in to data sharing, `false` = opted out.
  final bool? ccpaOptIn;

  /// `true` if the user is a child (COPPA).
  final bool? coppa;

  Map<String, Object?> toMap() => {
        'gdprConsent': gdprConsent,
        'gdprMessageVersion': gdprMessageVersion,
        'ccpaOptIn': ccpaOptIn,
        'coppa': coppa,
      };
}

/// An error reported by the Liftoff SDK or by this plugin.
class LiftoffAdError implements Exception {
  const LiftoffAdError(this.code, this.message);

  /// SDK error code, or one of [unsupported], [notInitialized], [notLoaded],
  /// [noPlacement], [timeout].
  final int code;
  final String message;

  static const int unsupported = -100;
  static const int notInitialized = -101;
  static const int notLoaded = -102;
  static const int noPlacement = -103;
  static const int timeout = -104;

  @override
  String toString() => 'LiftoffAdError($code): $message';
}
