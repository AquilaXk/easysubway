package com.easysubway.easysubway_mobile

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream
import java.io.IOException

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
    private var viewBox: List<Double>,
    private var revision: Int,
) : PlatformView {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val isDebuggable =
        context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    private val container = FrameLayout(context).apply {
        isClickable = false
        isFocusable = false
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
    }
    private val channel = MethodChannel(
        messenger,
        "com.easysubway.easysubway_mobile/route_map_viewport_webview/$viewId",
    )
    private var webView: WebView? = null
    private var initialAssetUrl: String? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setCamera" -> {
                    viewBox = call.argument<Any>("viewBox").asDoubleList()
                    revision = call.argument<Any>("revision").asInt()
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
                "debugFault" -> handleDebugFault(call.argument<String>("kind"), result)
                "dispose" -> {
                    dispose()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // The Dart per-view MethodChannel is attached immediately after creation.
        mainHandler.post { load() }
    }

    private fun load(assetPathOverride: String? = null) {
        destroyWebView()
        container.removeAllViews()
        val resolvedUrl = resolvedAssetUrl(assetPathOverride ?: assetPath)
        if (resolvedUrl == null) {
            reportAssetLoadFailed()
            return
        }
        initialAssetUrl = resolvedUrl
        val svgWebView = WebView(container.context).apply {
            isClickable = false
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            setOnTouchListener { _, _ -> true }
            isHorizontalScrollBarEnabled = false
            isVerticalScrollBarEnabled = false
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
            settings.javaScriptEnabled = true
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.builtInZoomControls = false
            settings.displayZoomControls = false
            settings.blockNetworkLoads = true
            settings.allowContentAccess = false
            settings.allowFileAccess = true
            webViewClient = routeMapWebViewClient()
        }
        webView = svgWebView
        container.addView(svgWebView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        ))
        svgWebView.loadUrl(resolvedUrl)
    }

    private fun resolvedAssetUrl(path: String): String? {
        if (mimeType != "image/svg+xml" || path.isBlank()) return null
        return try {
            val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(path)
            container.context.assets.open(lookupKey).close()
            "file:///android_asset/$lookupKey"
        } catch (_: IOException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun routeMapWebViewClient(): WebViewClient = object : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val allowed = request.url.toString() == initialAssetUrl
            if (!allowed && request.isForMainFrame) reportAssetLoadFailed()
            return !allowed
        }

        @Deprecated("Old Android callback kept so external navigation stays blocked.")
        override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean {
            val allowed = url == initialAssetUrl
            if (!allowed) reportAssetLoadFailed()
            return !allowed
        }

        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
            if (request.url.toString() == initialAssetUrl) return null
            reportAssetLoadFailedFromWebThread()
            return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
        }

        override fun onPageFinished(view: WebView, url: String) {
            if (webView !== view || url != initialAssetUrl) {
                reportAssetLoadFailed()
                return
            }
            applyViewBox()
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (request.isForMainFrame) reportAssetLoadFailed()
        }

        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            handleProcessGone(view, detail.didCrash())
            return true
        }
    }

    private fun applyViewBox() {
        val currentWebView = webView ?: run {
            reportCameraApplyFailed()
            return
        }
        val values = viewBox
        if (!isValidViewBox(values)) {
            reportCameraApplyFailed()
            return
        }
        val frameRevision = revision
        val encodedValues = values.joinToString(",") { value -> value.toString() }
        val script = """
            (function(){
              const values=[$encodedValues];
              const svg=document.documentElement;
              if(!svg||svg.tagName.toLowerCase()!=='svg'||values.length!==4||!values.every(Number.isFinite)||values[2]<=0||values[3]<=0){return false;}
              const allowed=['viewBox','width','height','preserveAspectRatio'];
              const snapshot=(node)=>{const clone=node.cloneNode(true);for(const name of allowed){clone.removeAttribute(name);}return clone.outerHTML;};
              const before=snapshot(svg);
              svg.setAttribute('viewBox',values.join(' '));
              svg.setAttribute('width','100%');
              svg.setAttribute('height','100%');
              svg.setAttribute('preserveAspectRatio','xMidYMid meet');
              return before===snapshot(svg);
            })();
        """.trimIndent()
        currentWebView.evaluateJavascript(script) { result ->
            if (webView !== currentWebView || result != "true") {
                reportCameraApplyFailed()
            } else {
                channel.invokeMethod("framePresented", mapOf("revision" to frameRevision))
            }
        }
    }

    private fun isValidViewBox(values: List<Double>): Boolean =
        values.size == 4 && values.all { it.isFinite() } && values[2] > 0.0 && values[3] > 0.0

    private fun reportAssetLoadFailed() {
        channel.invokeMethod("assetLoadFailed", null)
    }

    private fun reportAssetLoadFailedFromWebThread() {
        mainHandler.post { reportAssetLoadFailed() }
    }

    private fun reportCameraApplyFailed() {
        channel.invokeMethod("cameraApplyFailed", null)
    }

    private fun handleProcessGone(view: WebView?, didCrash: Boolean) {
        if (view != null && webView !== view) return
        channel.invokeMethod("processGone", mapOf("didCrash" to didCrash))
        webView?.let { current ->
            container.removeView(current)
            current.destroy()
        }
        webView = null
    }

    private fun handleDebugFault(kind: String?, result: MethodChannel.Result) {
        if (!isDebuggable) {
            result.error("debugUnavailable", "debug faults are unavailable in release", null)
            return
        }
        result.success(null)
        mainHandler.post {
            when (kind) {
                "invalidAsset" -> load("assets/datapacks/metro_map_pack/basemap/__missing_route_map__.svg")
                "invalidViewBox" -> {
                    viewBox = listOf(0.0, 0.0, Double.NaN, 1.0)
                    applyViewBox()
                }
                "debugProcessGone" -> handleProcessGone(webView, didCrash = true)
                else -> reportAssetLoadFailed()
            }
        }
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
            view.removeAllViews()
            view.destroy()
        }
        webView = null
    }
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
    return values.mapNotNull { value ->
        when (value) {
            is Double -> value
            is Float -> value.toDouble()
            is Int -> value.toDouble()
            is Long -> value.toDouble()
            else -> null
        }
    }
}
