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
import org.json.JSONObject

private val routeMapFontAssets = listOf(
    400 to "fonts/Pretendard-Regular.otf",
    600 to "fonts/Pretendard-SemiBold.otf",
    700 to "fonts/Pretendard-Bold.otf",
    800 to "fonts/Pretendard-ExtraBold.otf",
    900 to "fonts/Pretendard-Black.otf",
)

// ponytail: local fonts get 5s; add a JS bridge only if cold-load evidence exceeds this bound.
private const val fontReadinessMaxAttempts = 100
private const val fontReadinessPollMillis = 50L

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
    private var fontUrls = emptySet<String>()
    private var documentReady = false
    private var fontReadinessAttempts = 0
    private var isDisposed = false
    private var started = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (!started) {
                        started = true
                        load()
                    }
                    result.success(null)
                }
                "setCamera" -> {
                    viewBox = call.argument<Any>("viewBox").asDoubleList()
                    revision = call.argument<Any>("revision").asInt()
                    if (documentReady) applyViewBox()
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
    }

    private fun load(assetPathOverride: String? = null) {
        if (isDisposed) return
        documentReady = false
        fontReadinessAttempts = 0
        fontUrls = emptySet()
        destroyWebView()
        container.removeAllViews()
        val resolvedUrl = resolvedAssetUrl(assetPathOverride ?: assetPath)
        val resolvedFonts = resolvedFontUrls()
        if (resolvedUrl == null || resolvedFonts == null) {
            reportAssetLoadFailed()
            return
        }
        initialAssetUrl = resolvedUrl
        fontUrls = resolvedFonts.values.toSet()
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

    private fun resolvedFontUrls(): Map<Int, String>? {
        return try {
            routeMapFontAssets.associate { (weight, path) ->
                val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(path)
                container.context.assets.open(lookupKey).close()
                weight to "file:///android_asset/$lookupKey"
            }
        } catch (_: IOException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun routeMapWebViewClient(): WebViewClient =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Api26RouteMapWebViewClient()
        } else {
            RouteMapWebViewClient()
        }

    private open inner class RouteMapWebViewClient : WebViewClient() {
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
            val url = request.url.toString()
            if (url == initialAssetUrl || url in fontUrls) return null
            reportAssetLoadFailedFromWebThread()
            return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
        }

        override fun onPageFinished(view: WebView, url: String) {
            if (webView !== view || url != initialAssetUrl) {
                reportAssetLoadFailed()
                return
            }
            prepareDocument(view)
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (request.isForMainFrame) reportAssetLoadFailed()
        }
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.O)
    private inner class Api26RouteMapWebViewClient : RouteMapWebViewClient() {
        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            handleProcessGone(view, detail.didCrash())
            return true
        }
    }

    private fun prepareDocument(currentWebView: WebView) {
        val fonts = resolvedFontUrls() ?: run {
            reportAssetLoadFailed()
            return
        }
        val css = fonts.entries.joinToString("") { (weight, url) ->
            "@font-face{font-family:'Pretendard';src:url('$url') format('opentype');" +
                "font-weight:$weight;font-style:normal;font-display:block;}"
        }
        // The asset stays byte-identical; this only resolves its declared Pretendard family.
        val script = """
            (function(){
              const svg=document.documentElement;
              if(!svg||svg.tagName.toLowerCase()!=='svg'||!document.fonts){return false;}
              const style=document.createElementNS('http://www.w3.org/2000/svg','style');
              style.textContent=${JSONObject.quote(css)};
              svg.insertBefore(style,svg.firstChild);
              const allowed=['viewBox','width','height','preserveAspectRatio'];
              window.__easySubwaySvgIntegrityViolation=false;
              const observer=new MutationObserver((records)=>{
                for(const record of records){
                  if(record.type==='attributes'&&record.target===svg&&allowed.includes(record.attributeName)){continue;}
                  window.__easySubwaySvgIntegrityViolation=true;
                  observer.disconnect();
                  break;
                }
              });
              observer.observe(svg,{subtree:true,childList:true,characterData:true,attributes:true});
              window.__easySubwaySvgObserver=observer;
              window.__easySubwayFontState='pending';
              const specs=['400 12px Pretendard','600 12px Pretendard','700 12px Pretendard','800 12px Pretendard','900 12px Pretendard'];
              Promise.all(specs.map((spec)=>document.fonts.load(spec,'가'))).then(()=>{
                window.__easySubwayFontState=specs.every((spec)=>document.fonts.check(spec,'가'))?'ready':'failed';
              }).catch(()=>{window.__easySubwayFontState='failed';});
              return true;
            })();
        """.trimIndent()
        currentWebView.evaluateJavascript(script) { result ->
            if (webView !== currentWebView || result != "true") {
                reportAssetLoadFailed()
                return@evaluateJavascript
            }
            pollDocumentReady(currentWebView)
        }
    }

    private fun pollDocumentReady(currentWebView: WebView) {
        if (webView !== currentWebView || documentReady) return
        currentWebView.evaluateJavascript("window.__easySubwayFontState || 'failed'") { result ->
            if (webView !== currentWebView || documentReady) return@evaluateJavascript
            when (result) {
                "\"ready\"" -> {
                    documentReady = true
                    applyViewBox()
                }
                "\"failed\"" -> reportAssetLoadFailed()
                else -> {
                    fontReadinessAttempts += 1
                    if (fontReadinessAttempts >= fontReadinessMaxAttempts) {
                        reportAssetLoadFailed()
                    } else {
                        mainHandler.postDelayed(
                            { pollDocumentReady(currentWebView) },
                            fontReadinessPollMillis,
                        )
                    }
                }
            }
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
              if(!svg||svg.tagName.toLowerCase()!=='svg'||window.__easySubwaySvgIntegrityViolation===true||values.length!==4||!values.every(Number.isFinite)||values[2]<=0||values[3]<=0){return false;}
              svg.setAttribute('viewBox',values.join(' '));
              svg.setAttribute('width','100%');
              svg.setAttribute('height','100%');
              svg.setAttribute('preserveAspectRatio','xMidYMid meet');
              return true;
            })();
        """.trimIndent()
        currentWebView.evaluateJavascript(script) { result ->
            if (webView !== currentWebView || result != "true") {
                reportCameraApplyFailed()
            } else {
                currentWebView.postVisualStateCallback(
                    frameRevision.toLong(),
                    object : WebView.VisualStateCallback() {
                        override fun onComplete(requestId: Long) {
                            if (
                                webView === currentWebView &&
                                revision == frameRevision &&
                                requestId == frameRevision.toLong()
                            ) {
                                channel.invokeMethod(
                                    "framePresented",
                                    mapOf("revision" to frameRevision),
                                )
                            }
                        }
                    },
                )
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
        documentReady = false
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
        isDisposed = true
        mainHandler.removeCallbacksAndMessages(null)
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
        documentReady = false
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
