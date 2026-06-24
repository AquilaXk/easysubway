package com.easysubway.easysubway_mobile

import android.content.Context
import android.graphics.Color
import android.view.View
import android.webkit.WebView
import android.widget.FrameLayout
import io.flutter.FlutterInjector
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class OriginalRouteMapAssetViewFactory(
    codec: StandardMessageCodec,
) : PlatformViewFactory(codec) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<Any, Any>()
        val assetPath = params["assetPath"] as? String ?: ""
        val mimeType = params["mimeType"] as? String ?: ""
        return OriginalRouteMapAssetPlatformView(context, assetPath, mimeType)
    }
}

private class OriginalRouteMapAssetPlatformView(
    context: Context,
    assetPath: String,
    mimeType: String,
) : PlatformView {
    private val container = FrameLayout(context)

    init {
        container.setBackgroundColor(Color.WHITE)
        val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
        if (mimeType == "image/svg+xml") {
            val webView = WebView(context)
            webView.setBackgroundColor(Color.WHITE)
            webView.loadUrl("file:///android_asset/$lookupKey")
            container.addView(
                webView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
    }

    override fun getView(): View = container

    override fun dispose() = Unit
}
