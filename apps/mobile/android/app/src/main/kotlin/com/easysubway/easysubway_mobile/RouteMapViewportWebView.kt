package com.easysubway.easysubway_mobile

import android.content.Context
import android.graphics.Color
import android.os.Build
import android.view.Gravity
import android.view.View
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.TextView
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.Locale

class RouteMapViewportWebViewFactory(
    codec: StandardMessageCodec,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(codec) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<Any, Any>()
        return RouteMapViewportPlatformView(
            context = context,
            messenger = messenger,
            viewId = viewId,
            assetPath = params["assetPath"] as? String ?: "",
            mimeType = params["mimeType"] as? String ?: "",
            sourceWidth = params["sourceWidth"].asDouble(),
            sourceHeight = params["sourceHeight"].asDouble(),
            viewBox = params["viewBox"].asDoubleList(),
            revision = params["revision"].asInt(),
        )
    }
}

private class RouteMapViewportPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    private val assetPath: String,
    private val mimeType: String,
    private val sourceWidth: Double,
    private val sourceHeight: Double,
    private var viewBox: List<Double>,
    private var revision: Int,
) : PlatformView {
    private val container = FrameLayout(context).apply {
        setBackgroundColor(Color.WHITE)
    }
    private val channel = MethodChannel(
        messenger,
        "com.easysubway.easysubway_mobile/route_map_viewport_webview/$viewId",
    )
    private var webView: WebView? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setCamera" -> {
                    viewBox = (call.argument<Any>("viewBox")).asDoubleList()
                    revision = (call.argument<Any>("revision")).asInt()
                    applyViewBox()
                    result.success(null)
                }
                "reload" -> {
                    load()
                    result.success(null)
                }
                "trimMemory" -> {
                    webView?.clearCache(false)
                    result.success(null)
                }
                "dispose" -> {
                    dispose()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        load()
    }

    private fun load() {
        destroyWebView()
        container.removeAllViews()
        val svgWebView = WebView(container.context)
        webView = svgWebView
        svgWebView.setBackgroundColor(Color.WHITE)
        svgWebView.isHorizontalScrollBarEnabled = false
        svgWebView.isVerticalScrollBarEnabled = false
        svgWebView.settings.javaScriptEnabled = true
        svgWebView.settings.builtInZoomControls = false
        svgWebView.settings.displayZoomControls = false
        svgWebView.webViewClient = routeMapWebViewClient()
        svgWebView.loadDataWithBaseURL(
            "file:///android_asset/",
            htmlForSvg(container.context),
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

    private fun routeMapWebViewClient(): WebViewClient {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return object : BlockingRouteMapWebViewClient() {
                override fun onRenderProcessGone(
                    view: WebView,
                    detail: RenderProcessGoneDetail,
                ): Boolean {
                    if (webView === view) {
                        channel.invokeMethod("processGone", mapOf("didCrash" to detail.didCrash()))
                        showFallback(view)
                    }
                    return true
                }
            }
        }
        return BlockingRouteMapWebViewClient()
    }

    private open inner class BlockingRouteMapWebViewClient : WebViewClient() {
        override fun shouldOverrideUrlLoading(
            view: WebView,
            request: WebResourceRequest,
        ): Boolean = true

        @Deprecated("Old Android callback kept so external navigation stays blocked.")
        override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean = true

        override fun onPageFinished(view: WebView, url: String) {
            channel.invokeMethod("assetReady", null)
            applyViewBox()
        }
    }

    private fun htmlForSvg(context: Context): String {
        if (mimeType != "image/svg+xml" || assetPath.isBlank()) {
            return "<!doctype html><html><body></body></html>"
        }
        val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
        val svg = context.assets.open(lookupKey).bufferedReader().use { reader ->
            reader.readText()
        }
        return """
            <!doctype html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                <style>
                    html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: #ffffff; }
                    svg { display: block; width: 100%; height: 100%; }
                </style>
            </head>
            <body>$svg</body>
            </html>
        """.trimIndent()
    }

    private fun applyViewBox() {
        val values = normalizedViewBox()
        val script = String.format(
            Locale.US,
            "const svg=document.querySelector('svg');if(svg){svg.setAttribute('viewBox','%.4f %.4f %.4f %.4f');svg.setAttribute('width','100%%');svg.setAttribute('height','100%%');svg.setAttribute('preserveAspectRatio','xMidYMid meet');}",
            values[0],
            values[1],
            values[2],
            values[3],
        )
        webView?.evaluateJavascript(script) {
            channel.invokeMethod("framePresented", mapOf("revision" to revision))
        }
    }

    private fun normalizedViewBox(): List<Double> {
        if (viewBox.size == 4 && viewBox[2] > 0.0 && viewBox[3] > 0.0) {
            return viewBox
        }
        return listOf(0.0, 0.0, sourceWidth.coerceAtLeast(1.0), sourceHeight.coerceAtLeast(1.0))
    }

    private fun showFallback(view: WebView) {
        container.removeView(view)
        view.destroy()
        webView = null
        container.addView(
            TextView(container.context).apply {
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

    override fun getView(): View = container

    override fun dispose() {
        channel.setMethodCallHandler(null)
        destroyWebView()
        container.removeAllViews()
    }

    private fun destroyWebView() {
        webView?.let { view ->
            view.stopLoading()
            view.loadUrl("about:blank")
            view.removeAllViews()
            view.destroy()
        }
        webView = null
    }
}

private fun Any?.asDouble(): Double = when (this) {
    is Double -> this
    is Float -> toDouble()
    is Int -> toDouble()
    is Long -> toDouble()
    else -> 0.0
}

private fun Any?.asInt(): Int = when (this) {
    is Int -> this
    is Long -> toInt()
    is Double -> toInt()
    is Float -> toInt()
    else -> 0
}

private fun Any?.asDoubleList(): List<Double> {
    val values = this as? List<*> ?: return emptyList()
    return values.map { value -> value.asDouble() }
}
