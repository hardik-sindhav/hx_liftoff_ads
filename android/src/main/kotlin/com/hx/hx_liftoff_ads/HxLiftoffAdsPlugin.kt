package com.hx.hx_liftoff_ads

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.vungle.ads.AdConfig
import com.vungle.ads.BaseAd
import com.vungle.ads.BaseAdListener
import com.vungle.ads.BaseFullscreenAd
import com.vungle.ads.InitializationListener
import com.vungle.ads.InterstitialAd
import com.vungle.ads.RewardedAd
import com.vungle.ads.RewardedAdListener
import com.vungle.ads.VungleAds
import com.vungle.ads.VungleError
import com.vungle.ads.VunglePrivacySettings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** Liftoff Monetize (Vungle) bridge for Flutter. */
class HxLiftoffAdsPlugin : FlutterPlugin, ActivityAware, MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    private val ads = HashMap<Int, BaseFullscreenAd>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "hx_liftoff_ads")
        channel.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "hx_liftoff_ads/events")
        events.setStreamHandler(this)
        val emit: Emit = { id, e, err -> this.emit(id, e, err) }
        binding.platformViewRegistry.registerViewFactory(
            "hx_liftoff_ads/banner", LiftoffBannerFactory(emit)
        )
        binding.platformViewRegistry.registerViewFactory(
            "hx_liftoff_ads/native", LiftoffNativeFactory(emit)
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        ads.clear()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    override fun onDetachedFromActivity() { activity = null }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun emit(id: Int, event: String, err: VungleError? = null) {
        val map = HashMap<String, Any?>()
        map["id"] = id
        map["event"] = event
        if (err != null) {
            map["code"] = err.code
            map["message"] = err.errorMessage
        }
        main.post { sink?.success(map) }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                applyPrivacy(call.argument<Map<String, Any?>>("privacy"))
                val appId = call.argument<String>("appId") ?: return result.error("-1", "appId required", null)
                VungleAds.init(context, appId, object : InitializationListener {
                    override fun onSuccess() { main.post { result.success(null) } }
                    override fun onError(vungleError: VungleError) {
                        main.post { result.error(vungleError.code.toString(), vungleError.errorMessage, null) }
                    }
                })
            }
            "setPrivacy" -> {
                applyPrivacy(call.arguments as? Map<String, Any?>)
                result.success(null)
            }
            "sdkVersion" -> result.success(VungleAds.getSdkVersion())
            "loadAd" -> loadAd(call, result)
            "showAd" -> {
                val ad = ads[call.argument<Int>("id")]
                val act = activity
                if (ad == null) return result.error("-102", "Ad not found", null)
                if (act == null) return result.error("-1", "No foreground activity", null)
                ad.play(act)
                result.success(null)
            }
            "disposeAd" -> {
                ads.remove(call.argument<Int>("id"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun applyPrivacy(p: Map<String, Any?>?) {
        if (p == null) return
        (p["gdprConsent"] as? Boolean)?.let {
            VunglePrivacySettings.setGDPRStatus(it, p["gdprMessageVersion"] as? String ?: "1.0.0")
        }
        (p["ccpaOptIn"] as? Boolean)?.let { VunglePrivacySettings.setCCPAStatus(it) }
        (p["coppa"] as? Boolean)?.let { VunglePrivacySettings.setCOPPAStatus(it) }
    }

    private fun loadAd(call: MethodCall, result: Result) {
        val id = call.argument<Int>("id")!!
        val format = call.argument<String>("format")!!
        val placement = call.argument<String>("placementId")!!
        val ctx: Context = activity ?: context
        val ad: BaseFullscreenAd = when (format) {
            "interstitial" -> InterstitialAd(ctx, placement, AdConfig())
            "rewarded" -> RewardedAd(ctx, placement, AdConfig()).also { r ->
                call.argument<String>("userId")?.let { r.setUserId(it) }
            }
            else -> return result.error("-100", "Unsupported format $format", null)
        }
        ad.adListener = object : RewardedAdListener {
            override fun onAdLoaded(baseAd: BaseAd) = emit(id, "loaded")
            override fun onAdStart(baseAd: BaseAd) = emit(id, "shown")
            override fun onAdImpression(baseAd: BaseAd) = emit(id, "impression")
            override fun onAdEnd(baseAd: BaseAd) = emit(id, "closed")
            override fun onAdClicked(baseAd: BaseAd) = emit(id, "clicked")
            override fun onAdLeftApplication(baseAd: BaseAd) {}
            override fun onAdFailedToLoad(baseAd: BaseAd, adError: VungleError) =
                emit(id, "failedToLoad", adError)
            override fun onAdFailedToPlay(baseAd: BaseAd, adError: VungleError) =
                emit(id, "failedToShow", adError)
            override fun onAdRewarded(baseAd: BaseAd) = emit(id, "rewarded")
        }
        ads[id] = ad
        ad.load(null as String?)
        result.success(null)
    }
}
