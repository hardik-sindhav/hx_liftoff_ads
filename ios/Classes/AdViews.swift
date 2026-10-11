import Flutter
import UIKit
import VungleAdsSDK

final class BannerFactory: NSObject, FlutterPlatformViewFactory {
  let emit: EmitFn
  init(emit: @escaping EmitFn) { self.emit = emit }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let p = args as? [String: Any] ?? [:]
    return BannerPlatformView(
      frame: frame, id: p["id"] as? Int ?? 0, placement: p["placementId"] as? String ?? "",
      size: p["size"] as? String ?? "banner", emit: emit)
  }
}

final class BannerPlatformView: NSObject, FlutterPlatformView, VungleBannerViewDelegate {
  private let container = UIView()
  private let banner: VungleBannerView
  private let id: Int
  private let emit: EmitFn

  init(frame: CGRect, id: Int, placement: String, size: String, emit: @escaping EmitFn) {
    self.id = id
    self.emit = emit
    let adSize: VungleAdSize
    switch size {
    case "bannerShort": adSize = VungleAdSize.VungleAdSizeBannerShort
    case "leaderboard": adSize = VungleAdSize.VungleAdSizeLeaderboard
    case "mrec": adSize = VungleAdSize.VungleAdSizeMREC
    default: adSize = VungleAdSize.VungleAdSizeBannerRegular
    }
    banner = VungleBannerView(placementId: placement, vungleAdSize: adSize)
    super.init()
    banner.delegate = self
    banner.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(banner)
    NSLayoutConstraint.activate([
      banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      banner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])
    banner.load(nil)
  }

  func view() -> UIView { container }

  func bannerAdDidLoad(_ bannerView: VungleBannerView) { emit(id, "loaded", nil) }
  func bannerAdWillPresent(_ bannerView: VungleBannerView) {}
  func bannerAdDidPresent(_ bannerView: VungleBannerView) {}
  func bannerAdDidFail(_ bannerView: VungleBannerView, withError: NSError) { emit(id, "failedToLoad", withError) }
  func bannerAdWillClose(_ bannerView: VungleBannerView) {}
  func bannerAdDidClose(_ bannerView: VungleBannerView) {}
  func bannerAdDidTrackImpression(_ bannerView: VungleBannerView) { emit(id, "impression", nil) }
  func bannerAdDidClick(_ bannerView: VungleBannerView) { emit(id, "clicked", nil) }
  func bannerAdWillLeaveApplication(_ bannerView: VungleBannerView) {}
}

final class NativeFactory: NSObject, FlutterPlatformViewFactory {
  let emit: EmitFn
  init(emit: @escaping EmitFn) { self.emit = emit }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let p = args as? [String: Any] ?? [:]
    return NativePlatformView(
      id: p["id"] as? Int ?? 0, placement: p["placementId"] as? String ?? "", emit: emit)
  }
}

/// Native ad rendered with a simple built-in template.
final class NativePlatformView: NSObject, FlutterPlatformView, VungleNativeDelegate {
  private let root = UIView()
  private let native: VungleNative
  private let id: Int
  private let emit: EmitFn

  init(id: Int, placement: String, emit: @escaping EmitFn) {
    self.id = id
    self.emit = emit
    native = VungleNative(placementId: placement)
    super.init()
    native.delegate = self
    native.load(nil)
  }

  func view() -> UIView { root }

  private func label(_ text: String, size: CGFloat, bold: Bool = false) -> UILabel {
    let l = UILabel()
    l.text = text
    l.numberOfLines = 2
    l.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    return l
  }

  private func render() {
    root.subviews.forEach { $0.removeFromSuperview() }
    let icon = UIImageView(image: native.iconImage)
    icon.contentMode = .scaleAspectFit
    icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

    let titles = UIStackView(arrangedSubviews: [
      label(native.title, size: 16, bold: true), label(native.sponsoredText, size: 12),
    ])
    titles.axis = .vertical
    let header = UIStackView(arrangedSubviews: [icon, titles])
    header.spacing = 8
    header.alignment = .center

    let media = MediaView()
    media.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
    let cta = UIButton(type: .system)
    cta.setTitle(native.callToAction, for: .normal)

    let stack = UIStackView(arrangedSubviews: [header, label(native.bodyText, size: 14), media, cta])
    stack.axis = .vertical
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
    ])
    native.registerViewForInteraction(
      view: root, mediaView: media, iconImageView: icon,
      viewController: HxLiftoffAdsPlugin.topViewController(), clickableViews: [cta, media])
  }

  func nativeAdDidLoad(_ native: VungleNative) {
    DispatchQueue.main.async {
      self.render()
      self.emit(self.id, "loaded", nil)
    }
  }
  func nativeAdDidFail(toLoad native: VungleNative, withError: NSError) { emit(id, "failedToLoad", withError) }
  func nativeAdDidFail(toPresent native: VungleNative, withError: NSError) { emit(id, "failedToLoad", withError) }
  func nativeAdDidTrackImpression(_ native: VungleNative) { emit(id, "impression", nil) }
  func nativeAdDidClick(_ native: VungleNative) { emit(id, "clicked", nil) }
}
