package com.easysubway.easysubway_mobile

import android.content.Context
import android.graphics.Color
import android.os.Build
import android.view.Gravity
import android.view.View
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.TextView
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
    private var webView: WebView? = null

    init {
        container.setBackgroundColor(Color.WHITE)
        val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
        if (mimeType == "image/svg+xml") {
            val svgWebView = WebView(context)
            webView = svgWebView
            svgWebView.setBackgroundColor(Color.WHITE)
            svgWebView.isHorizontalScrollBarEnabled = false
            svgWebView.isVerticalScrollBarEnabled = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                svgWebView.webViewClient = object : WebViewClient() {
                    override fun onRenderProcessGone(
                        view: WebView,
                        detail: RenderProcessGoneDetail,
                    ): Boolean {
                        if (webView === view) {
                            container.removeView(view)
                            view.destroy()
                            webView = null
                            container.addView(
                                TextView(context).apply {
                                    text = "노선도를 다시 불러오지 못했습니다."
                                    gravity = Gravity.CENTER
                                    setTextColor(Color.BLACK)
                                },
                                FrameLayout.LayoutParams(
                                    FrameLayout.LayoutParams.MATCH_PARENT,
                                    FrameLayout.LayoutParams.MATCH_PARENT,
                                ),
                            )
                        }
                        return true
                    }
                }
            }
            val html = """
                <!doctype html>
                <html>
                <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                    <style>
                        html, body {
                            margin: 0;
                            width: 100%;
                            height: 100%;
                            overflow: hidden;
                            background: #ffffff;
                        }
                        img {
                            display: block;
                            width: 100%;
                            height: 100%;
                        }
                    </style>
                </head>
                <body>
                    <img src="file:///android_asset/$lookupKey" alt="">
                </body>
                </html>
            """.trimIndent()
            svgWebView.loadDataWithBaseURL(
                "file:///android_asset/",
                html,
                "text/html",
                "UTF-8",
                null,
            )
            container.addView(
                svgWebView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
    }

    override fun getView(): View = container

    override fun dispose() {
        webView?.let { view ->
            view.stopLoading()
            view.loadUrl("about:blank")
            view.removeAllViews()
            view.destroy()
        }
        webView = null
        container.removeAllViews()
    }
}
