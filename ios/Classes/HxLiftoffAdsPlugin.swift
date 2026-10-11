import Flutter
import UIKit
import VungleAdsSDK

typealias EmitFn = (_ id: Int, _ event: String, _ error: NSError?) -> Void

public class HxLiftoffAdsPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var ads: [Int: FullscreenHandler] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = HxLiftoffAdsPlugin()
    let channel = FlutterMethodChannel(name: "hx_liftoff_ads", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(name: "hx_liftoff_ads/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
    let emit: EmitFn = { [weak instance] id, event, err in instance?.emit(id, event, err) }
    registrar.register(BannerFactory(emit: emit), withId: "hx_liftoff_ads/banner")
    registrar.register(NativeFactory(emit: emit), withId: "hx_liftoff_ads/native")
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func emit(_ id: Int, _ event: String, _ err: NSError?) {
    var map: [String: Any] = ["id": id, "event": event]
    if let err = err {
      map["code"] = err.code
      map["message"] = err.localizedDescription
    }
    DispatchQueue.main.async { self.sink?(map) }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "initialize":
      applyPrivacy(args?["privacy"] as? [String: Any])
      guard let appId = args?["appId"] as? String else {
        result(FlutterError(code: "-1", message: "appId required", details: nil))
        return
      }
      VungleAds.initWithAppId(appId) { error in
        DispatchQueue.main.async {
          if let error = error as NSError? {
            result(FlutterError(code: String(error.code), message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      }
    case "setPrivacy":
      applyPrivacy(args)
      result(nil)
    case "sdkVersion":
      result(VungleAds.sdkVersion)
    case "loadAd":
      guard let id = args?["id"] as? Int,
        let format = args?["format"] as? String,
        let placement = args?["placementId"] as? String
      else {
        result(FlutterError(code: "-1", message: "bad arguments", details: nil))
        return
      }
      let handler = FullscreenHandler(id: id, format: format, placement: placement,
                                      userId: args?["userId"] as? String,
                                      emit: { [weak self] i, e, err in self?.emit(i, e, err) })
      ads[id] = handler
      handler.load()
      result(nil)
    case "showAd":
      guard let id = args?["id"] as? Int, let handler = ads[id] else {
        result(FlutterError(code: "-102", message: "Ad not found", details: nil))
        return
      }
      guard let vc = Self.topViewController() else {
        result(FlutterError(code: "-1", message: "No view controller", details: nil))
        return
      }
      handler.show(from: vc)
      result(nil)
    case "disposeAd":
      if let id = args?["id"] as? Int { ads.removeValue(forKey: id) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func applyPrivacy(_ p: [String: Any]?) {
    guard let p = p else { return }
    if let gdpr = p["gdprConsent"] as? Bool {
      VunglePrivacySettings.setGDPRStatus(gdpr)
      VunglePrivacySettings.setGDPRMessageVersion(p["gdprMessageVersion"] as? String ?? "1.0.0")
    }
    if let ccpa = p["ccpaOptIn"] as? Bool { VunglePrivacySettings.setCCPAStatus(ccpa) }
    if let coppa = p["coppa"] as? Bool { VunglePrivacySettings.setCOPPAStatus(coppa) }
  }

  static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

/// Wraps an interstitial or rewarded ad.
final class FullscreenHandler: NSObject, VungleInterstitialDelegate, VungleRewardedDelegate {
  let id: Int
  let emit: EmitFn
  private var interstitial: VungleInterstitial?
  private var rewarded: VungleRewarded?

  init(id: Int, format: String, placement: String, userId: String?, emit: @escaping EmitFn) {
    self.id = id
    self.emit = emit
    super.init()
    if format == "rewarded" {
      let r = VungleRewarded(placementId: placement)
      if let userId = userId { r.setUserId(userId: userId) }
      r.delegate = self
      rewarded = r
    } else {
      let i = VungleInterstitial(placementId: placement)
      i.delegate = self
      interstitial = i
    }
  }

  func load() {
    interstitial?.load(nil)
    rewarded?.load(nil)
  }

  func show(from vc: UIViewController) {
    interstitial?.present(with: vc)
    rewarded?.present(with: vc)
  }

  // Interstitial
  func interstitialAdDidLoad(_ interstitial: VungleInterstitial) { emit(id, "loaded", nil) }
  func interstitialAdDidFail(toLoad interstitial: VungleInterstitial, withError: NSError) { emit(id, "failedToLoad", withError) }
  func interstitialAdWillPresent(_ interstitial: VungleInterstitial) {}
  func interstitialAdDidPresent(_ interstitial: VungleInterstitial) { emit(id, "shown", nil) }
  func interstitialAdDidFail(toPresent interstitial: VungleInterstitial, withError: NSError) { emit(id, "failedToShow", withError) }
  func interstitialAdWillClose(_ interstitial: VungleInterstitial) {}
  func interstitialAdDidClose(_ interstitial: VungleInterstitial) { emit(id, "closed", nil) }
  func interstitialAdDidTrackImpression(_ interstitial: VungleInterstitial) { emit(id, "impression", nil) }
  func interstitialAdDidClick(_ interstitial: VungleInterstitial) { emit(id, "clicked", nil) }
  func interstitialAdWillLeaveApplication(_ interstitial: VungleInterstitial) {}

  // Rewarded
  func rewardedAdDidLoad(_ rewarded: VungleRewarded) { emit(id, "loaded", nil) }
  func rewardedAdDidFail(toLoad rewarded: VungleRewarded, withError: NSError) { emit(id, "failedToLoad", withError) }
  func rewardedAdWillPresent(_ rewarded: VungleRewarded) {}
  func rewardedAdDidPresent(_ rewarded: VungleRewarded) { emit(id, "shown", nil) }
  func rewardedAdDidFail(toPresent rewarded: VungleRewarded, withError: NSError) { emit(id, "failedToShow", withError) }
  func rewardedAdWillClose(_ rewarded: VungleRewarded) {}
  func rewardedAdDidClose(_ rewarded: VungleRewarded) { emit(id, "closed", nil) }
  func rewardedAdDidTrackImpression(_ rewarded: VungleRewarded) { emit(id, "impression", nil) }
  func rewardedAdDidClick(_ rewarded: VungleRewarded) { emit(id, "clicked", nil) }
  func rewardedAdWillLeaveApplication(_ rewarded: VungleRewarded) {}
  func rewardedAdDidRewardUser(_ rewarded: VungleRewarded) { emit(id, "rewarded", nil) }
}
