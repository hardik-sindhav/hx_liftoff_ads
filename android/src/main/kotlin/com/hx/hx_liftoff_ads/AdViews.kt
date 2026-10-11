package com.hx.hx_liftoff_ads

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.vungle.ads.BannerAdListener
import com.vungle.ads.BaseAd
import com.vungle.ads.NativeAd
import com.vungle.ads.NativeAdListener
import com.vungle.ads.VungleAdSize
import com.vungle.ads.VungleBannerView
import com.vungle.ads.VungleError
import com.vungle.ads.internal.ui.view.MediaView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

typealias Emit = (Int, String, VungleError?) -> Unit

private fun Context.dp(v: Int): Int =
    TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics
    ).toInt()

class LiftoffBannerFactory(private val emit: Emit) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val p = args as Map<*, *>
        return LiftoffBannerView(
            context, (p["id"] as Number).toInt(), p["placementId"] as String,
            p["size"] as String, emit
        )
    }
}

class LiftoffBannerView(
    context: Context, id: Int, placement: String, size: String, emit: Emit
) : PlatformView {
    private val banner: VungleBannerView
    private val container = FrameLayout(context)

    init {
        val adSize = when (size) {
            "bannerShort" -> VungleAdSize.BANNER_SHORT
            "leaderboard" -> VungleAdSize.BANNER_LEADERBOARD
            "mrec" -> VungleAdSize.MREC
            else -> VungleAdSize.BANNER
        }
        banner = VungleBannerView(context, placement, adSize)
        banner.adListener = object : BannerAdListener {
            override fun onAdLoaded(baseAd: BaseAd) = emit(id, "loaded", null)
            override fun onAdStart(baseAd: BaseAd) {}
            override fun onAdImpression(baseAd: BaseAd) = emit(id, "impression", null)
            override fun onAdEnd(baseAd: BaseAd) {}
            override fun onAdClicked(baseAd: BaseAd) = emit(id, "clicked", null)
            override fun onAdLeftApplication(baseAd: BaseAd) {}
            override fun onAdFailedToLoad(baseAd: BaseAd, adError: VungleError) =
                emit(id, "failedToLoad", adError)
            override fun onAdFailedToPlay(baseAd: BaseAd, adError: VungleError) =
                emit(id, "failedToLoad", adError)
        }
        container.addView(
            banner,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        )
        banner.load()
    }

    override fun getView(): View = container
    override fun dispose() {
        banner.finishAd()
        container.removeAllViews()
    }
}

class LiftoffNativeFactory(private val emit: Emit) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val p = args as Map<*, *>
        return LiftoffNativeView(context, (p["id"] as Number).toInt(), p["placementId"] as String, emit)
    }
}

/** Native ad rendered with a simple built-in template. */
class LiftoffNativeView(
    private val context: Context, private val id: Int, placement: String, private val emit: Emit
) : PlatformView {
    private val root = FrameLayout(context)
    private val nativeAd = NativeAd(context, placement)

    init {
        nativeAd.adListener = object : NativeAdListener {
            override fun onAdLoaded(baseAd: BaseAd) {
                try {
                    render()
                    emit(id, "loaded", null)
                } catch (t: Throwable) {
                    emit(id, "failedToLoad", null)
                }
            }
            override fun onAdStart(baseAd: BaseAd) {}
            override fun onAdImpression(baseAd: BaseAd) = emit(id, "impression", null)
            override fun onAdEnd(baseAd: BaseAd) {}
            override fun onAdClicked(baseAd: BaseAd) = emit(id, "clicked", null)
            override fun onAdLeftApplication(baseAd: BaseAd) {}
            override fun onAdFailedToLoad(baseAd: BaseAd, adError: VungleError) =
                emit(id, "failedToLoad", adError)
            override fun onAdFailedToPlay(baseAd: BaseAd, adError: VungleError) =
                emit(id, "failedToLoad", adError)
        }
        nativeAd.load()
    }

    private fun text(value: String?, sp: Float, bold: Boolean = false, color: Int = Color.DKGRAY) =
        TextView(context).apply {
            text = value ?: ""
            setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
            setTextColor(color)
            if (bold) setTypeface(typeface, Typeface.BOLD)
            maxLines = 2
        }

    private fun render() {
        val pad = context.dp(8)
        val column = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
        }

        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val icon = ImageView(context)
        try {
            nativeAd.getAppIcon()?.let { path -> BitmapFactory.decodeFile(path)?.let { icon.setImageBitmap(it) } }
        } catch (_: Throwable) {
        }
        header.addView(icon, LinearLayout.LayoutParams(context.dp(48), context.dp(48)))
        val titles = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        titles.setPadding(pad, 0, 0, 0)
        titles.addView(text(nativeAd.getAdTitle(), 16f, true, Color.BLACK))
        titles.addView(text(nativeAd.getAdSponsoredText(), 12f))
        header.addView(titles)
        column.addView(header)

        column.addView(text(nativeAd.getAdBodyText(), 14f).apply { setPadding(0, pad, 0, pad) })

        val media = MediaView(context)
        column.addView(
            media,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
        )

        val cta = Button(context).apply { text = nativeAd.getAdCallToActionText() }
        column.addView(cta)

        root.removeAllViews()
        root.addView(column, FrameLayout.LayoutParams(-1, -1))
        nativeAd.registerViewForInteraction(root, media, icon, listOf(cta, media))
    }

    override fun getView(): View = root
    override fun dispose() {
        nativeAd.unregisterView()
        root.removeAllViews()
    }
}
