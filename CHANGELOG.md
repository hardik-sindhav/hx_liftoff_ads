## 0.1.1

* Fix repository, homepage and podspec links; add `issue_tracker` and `documentation`.
* Ad loading now times out after 30 seconds (configurable with `timeout:`) and throws `LiftoffAdError.timeout` instead of hanging.
* Concurrent `initialize` calls share a single native initialization.
* `LiftoffPlacements` gains `copyWith`, `==` and `hashCode`.

## 0.1.0

* Initial release: interstitial, rewarded, app open, banner, MREC and native ads.
* Android (Vungle SDK 7.7.9), iOS (VungleAds 7.7) and Windows Win32 x64 (SDK 7.1.1; fullscreen formats only).
