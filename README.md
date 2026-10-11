# hx_liftoff_ads

Liftoff Monetize (formerly Vungle) ads for Flutter, with one Dart API for **Android, iOS and Windows**. You bring your own Liftoff app ID and ad unit (placement) IDs.

| Format | Android | iOS | Windows |
|---|:-:|:-:|:-:|
| Interstitial | ✅ | ✅ | ✅ |
| Rewarded | ✅ | ✅ | ✅ |
| App open | ✅ | ✅ | ✅ |
| Banner | ✅ | ✅ | ❌ |
| MREC (300x250) | ✅ | ✅ | ❌ |
| Native | ✅ | ✅ | ❌ |

> **Status:** tested on Android with real placements. The iOS and Windows code compiles against the Liftoff SDKs (Windows builds; iOS was written against the SDK headers) but has not been verified with live ads yet. Please report issues.

Underlying SDKs: Android `com.vungle:vungle-ads:7.7.9`, iOS pod `VungleAds ~> 7.7`, Windows `VungleSDKForWindowsDesktopNative 7.1.1` (Win32 x64).

This is an unofficial community plugin and is not affiliated with Liftoff.

## Contents

1. [Liftoff dashboard setup](#1-liftoff-dashboard-setup)
2. [Install](#2-install)
3. [Platform setup](#3-platform-setup)
4. [Initialize](#4-initialize)
5. [Show ads](#5-show-ads)
6. [Privacy and consent](#6-privacy-and-consent)
7. [Error handling](#7-error-handling)
8. [Troubleshooting](#8-troubleshooting)
9. [Example app](#9-example-app)

## 1. Liftoff dashboard setup

1. Create a Liftoff account and add **one app per platform** (Android, iOS, Windows). Each app gets an **Application ID**.
2. In each app, create one **placement** per format you want. Each gets a **Reference ID** such as `INTERSTITIAL_ADS-1234567`. This is your *ad unit key*.
3. **Turn In-App Bidding OFF for every placement.** This plugin loads ads through the normal (waterfall) flow. A placement with bidding on fails with `header bidding status does not match with loadAd parameters` (code 224).
4. App open: create the placement as a fullscreen type. The Liftoff SDKs have no dedicated app-open class, so this plugin serves it through the SDK's fullscreen API.
5. While developing, use Liftoff's test mode for your app so you don't create real impressions. New apps and placements can return *no fill* for a while; this is normal.

## 2. Install

```yaml
dependencies:
  hx_liftoff_ads: ^0.1.0
```

```
flutter pub get
```

## 3. Platform setup

### Android

* `minSdkVersion` 24 or higher (Android 7.0).
* The plugin adds the `INTERNET` and `ACCESS_NETWORK_STATE` permissions and the Liftoff SDK itself. Nothing else is required.
* If you use R8/ProGuard you don't need extra rules; the SDK ships its own.
* If you need the Vungle SDK in your own native code, it is already on your classpath through this plugin.

### iOS

* iOS 13.0 or higher. In `ios/Podfile`: `platform :ios, '13.0'`.
* Run `pod install` (or `flutter run`).
* Add the SKAdNetwork identifiers that Liftoff lists in its iOS integration guide to `ios/Runner/Info.plist` (`SKAdNetworkItems`), and an `NSUserTrackingUsageDescription` if you request App Tracking Transparency.

### Windows

* Windows 10 (build 16299) or later, 64-bit.
* The plugin **downloads the Liftoff Windows SDK from NuGet while building** (it is under Liftoff's commercial license and is not redistributed in this package). The build machine needs internet access.
* `LiftoffSDK.Win32.dll` and `WebView2Loader.dll` are copied next to your exe automatically.
* Ads are rendered with WebView2, so the **Microsoft Edge WebView2 Runtime** must be installed on the user's PC. Include the Evergreen Bootstrapper in your installer.
* Windows supports interstitial, rewarded and app open only. Banner, MREC and native return `LiftoffAdError.unsupported`; check with `isSupported`.

## 4. Initialize

Call once at startup. It is safe to call without awaiting, so it never delays your first frame.

```dart
import 'package:hx_liftoff_ads/hx_liftoff_ads.dart';

Future<void> initAds() async {
  try {
    await LiftoffAds.instance.initialize(
      appId: 'YOUR_APP_ID', // the Application ID of the app for this platform
      placements: const LiftoffPlacements(
        interstitial: 'INTERSTITIAL_ADS-1234567',
        rewarded: 'REWARDED_ADS-1234567',
        appOpen: 'APP_OPEN_ADS-1234567',
        banner: 'BANNER_ADS-1234567',
        mrec: 'MREC_ADS-1234567',
        native: 'NATIVE_ADS-1234567',
      ),
    );
  } on LiftoffAdError catch (e) {
    debugPrint('Ads unavailable: $e');
  }
}
```

### Different IDs per platform

Each platform has its own Liftoff app, so use `byPlatform`. The app ID has to be chosen per platform too:

```dart
final appId = Platform.isAndroid
    ? 'ANDROID_APP_ID'
    : Platform.isIOS
        ? 'IOS_APP_ID'
        : 'WINDOWS_APP_ID';

await LiftoffAds.instance.initialize(
  appId: appId,
  placements: LiftoffPlacements.byPlatform(
    android: const LiftoffPlacements(interstitial: '...', rewarded: '...', banner: '...'),
    ios: const LiftoffPlacements(interstitial: '...', rewarded: '...', banner: '...'),
    windows: const LiftoffPlacements(interstitial: '...', rewarded: '...'),
  ),
);
```

You can also skip `placements` and pass `placementId:` to each `load` call.

### Check what a platform supports

```dart
if (LiftoffAds.instance.isSupported(AdFormat.banner)) { /* ... */ }
```

## 5. Show ads

### Interstitial

```dart
try {
  final ad = await InterstitialAd.load(
    listener: FullscreenAdListener(
      onShown: () => debugPrint('shown'),
      onClicked: () => debugPrint('clicked'),
      onClosed: () => debugPrint('closed'),
      onFailedToShow: (e) => debugPrint('show failed: $e'),
    ),
  );
  await ad.show();
} on LiftoffAdError catch (e) {
  debugPrint('Interstitial not available: $e');
}
```

`load` completes when the ad is ready, so you can call it ahead of time and keep the `ad` until you want to show it. Each loaded ad can be shown **once**; load a new one afterwards.

### Rewarded

Grant the reward only in `onRewarded`:

```dart
final ad = await RewardedAd.load(
  userId: 'optional-user-id',
  listener: FullscreenAdListener(
    onRewarded: () => grantCoins(),
    onClosed: () => debugPrint('closed'),
  ),
);
await ad.show();
```

Always ask the user before showing a rewarded ad, and let your feature work if no ad is available.

### App open

Automatic: preloads an ad and shows it when the app returns to the foreground.

```dart
final appOpen = AppOpenAdManager(
  minInterval: const Duration(minutes: 3), // minimum gap between ads
  onError: (e) => debugPrint('$e'),
)..start();

// Later, if you no longer want them:
appOpen.stop();
```

Manual: use `AppOpenAd.load()` and `show()` exactly like an interstitial. Loaded app open ads older than 4 hours are not shown.

### Banner and MREC

```dart
Scaffold(
  body: ...,
  bottomNavigationBar: SafeArea(
    child: Center(
      heightFactor: 1, // keeps the bar only as tall as the ad
      child: LiftoffBannerAd(
        size: BannerSize.banner, // 320x50. Also: bannerShort, leaderboard (728x90)
        onLoaded: () => debugPrint('banner loaded'),
        onFailedToLoad: (e) => debugPrint('banner failed: $e'),
      ),
    ),
  ),
);

// 300x250 medium rectangle, for inside a page:
const LiftoffBannerAd.mrec();
```

The widget takes almost no space until an ad has loaded, and collapses if it fails. It needs the `banner` placement (or `mrec` for the MREC size), or pass `placementId:`.

### Native ads

```dart
LiftoffNativeAd(height: 320, onFailedToLoad: (e) => debugPrint('$e'))
```

Rendered with a built-in template (icon, title, sponsor, body, media, call-to-action button). Android and iOS only.

## 6. Privacy and consent

Liftoff has no consent form of its own. If your app has users in regions with consent rules, collect their choice (for example with a consent platform) and pass it in:

```dart
await LiftoffAds.instance.initialize(
  appId: '...',
  privacy: const LiftoffPrivacy(
    gdprConsent: true,   // GDPR: true = consented, false = denied
    ccpaOptIn: true,     // CCPA: true = opted in, false = opted out
    coppa: false,        // true if the user is a child
  ),
);

// Update later when the user changes their choice:
await LiftoffAds.instance.setPrivacy(const LiftoffPrivacy(gdprConsent: false));
```

You are responsible for complying with the laws that apply to your app, store policies and Liftoff's terms. Update your privacy policy to name Liftoff as an ad provider.

## 7. Error handling

Every failure is a `LiftoffAdError` with a `code` and a `message`. Codes from the Liftoff SDK are passed through unchanged. This plugin adds:

| Code | Meaning |
|---|---|
| `-100` (`unsupported`) | Platform or format not supported (for example a banner on Windows) |
| `-101` (`notInitialized`) | `initialize` was not called or failed |
| `-102` (`notLoaded`) | `show()` called on an ad that isn't loaded or was already shown |
| `-103` (`noPlacement`) | No placement ID passed or configured for the format |

A failed `load` is normal (no fill, no network). Retry with a delay, for example 2, 4 and 8 seconds, and never block your app on an ad.

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `header bidding status does not match with loadAd parameters` (224) | In-App Bidding is still on for that placement. Turn it off in the Liftoff dashboard, wait several minutes, then **uninstall the app** and run it again (the SDK caches its config). |
| `No fill` / ads never appear on a new app | New apps and placements can take hours to a day to get demand. Use test mode. |
| `Unresolved reference` or Kotlin/Gradle errors | Update the plugin; it follows your app's Gradle, AGP and Kotlin versions. |
| Banner covers the whole screen | Wrap it in `Center(heightFactor: 1, ...)` when using it as `bottomNavigationBar`. |
| Windows: nothing shows | Check the WebView2 Runtime is installed and that the app ID is a Windows app. |
| `LiftoffAdError(-101)` | Wait for `initialize` to finish before loading ads. |

## 9. Example app

The `example/` app has fields for your App ID and every placement ID, plus a button for each format:

```
cd example
flutter run
```

## License

MIT for this plugin. The Liftoff / Vungle SDKs are subject to Liftoff's own license terms.
