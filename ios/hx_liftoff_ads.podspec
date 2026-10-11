Pod::Spec.new do |s|
  s.name             = 'hx_liftoff_ads'
  s.version          = '0.1.1'
  s.summary          = 'Liftoff Monetize (Vungle) ads for Flutter.'
  s.description      = <<-DESC
Interstitial, rewarded, app open, banner, MREC and native ads from Liftoff Monetize (formerly Vungle).
                       DESC
  s.homepage         = 'https://github.com/hardik-sindhav/hx_liftoff_ads'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'hx' => 'duvansoft@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'VungleAds', '~> 7.7'
  s.platform = :ios, '13.0'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'hx_liftoff_ads_privacy' => ['Classes/PrivacyInfo.xcprivacy']}
end
