package com.easysubway.easysubway_mobile

import android.Manifest
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationManagerCompat
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val locationChannelName = "com.easysubway.easysubway_mobile/location"
    private val notificationChannelName = "com.easysubway.easysubway_mobile/notifications"
    private val playIntegrityChannelName = "com.easysubway.easysubway_mobile/play_integrity"
    private val locationPermissionRequestCode = 2401
    private val notificationPermissionRequestCode = 2402
    private val locationTimeoutMillis = 10_000L
    private val nearbyLocationMaxAgeMillis = 5 * 60 * 1000L
    private val nearbyLocationMaxAccuracyMeters = 500f
    private val requestHashPattern = Regex("^[A-Za-z0-9_-]{43}$")

    private var pendingLocationResult: MethodChannel.Result? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var pendingIntegrityResult: MethodChannel.Result? = null
    private var integrityTokenProvider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null
    private var integrityCloudProjectNumber: Long? = null
    private val pendingLocationListeners: MutableList<LocationListener> = mutableListOf()
    private val pendingLocationCancellationSignals: MutableList<CancellationSignal> = mutableListOf()
    private var pendingLocationTimeoutRunnable: Runnable? = null
    private var pendingLocationRequestToken: Any? = null
    private var pendingLocationOutstandingCount = 0
    private val mainHandler = Handler(Looper.getMainLooper())

    private enum class LocationRequestOutcome { STARTED, PERMISSION_DENIED, FAILED }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (resources.configuration.smallestScreenWidthDp < 600) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "currentLocation" -> handleCurrentLocation(result)
                    "needsLocationPermissionRequest" -> result.success(!hasLocationPermission())
                    "openLocationSettings" -> openLocationSettings(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "notificationPermissionStatus" -> result.success(hasNotificationPermission() && areAppNotificationsEnabled())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, playIntegrityChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestToken" -> requestPlayIntegrityToken(
                        requestHash = call.argument<String>("requestHash"),
                        cloudProjectNumber = call.argument<String>("cloudProjectNumber"),
                        result = result,
                    )
                    else -> result.notImplemented()
                }
            }
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.easysubway.easysubway_mobile/original_route_map_asset",
            OriginalRouteMapAssetViewFactory(StandardMessageCodec.INSTANCE),
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.easysubway.easysubway_mobile/route_map_viewport_webview",
            RouteMapViewportWebViewFactory(
                StandardMessageCodec.INSTANCE,
                flutterEngine.dartExecutor.binaryMessenger,
            ),
        )
    }

    private fun requestPlayIntegrityToken(
        requestHash: String?,
        cloudProjectNumber: String?,
        result: MethodChannel.Result,
    ) {
        if (pendingIntegrityResult != null) {
            result.error("integrityUnavailable", "integrity request already running", null)
            return
        }
        val projectNumber = cloudProjectNumber?.toLongOrNull()
        if (requestHash == null || !requestHash.matches(requestHashPattern) || projectNumber == null || projectNumber <= 0) {
            result.error("integrityInvalidRequest", "invalid integrity request", null)
            return
        }
        pendingIntegrityResult = result
        val cachedProvider = integrityTokenProvider
        if (cachedProvider != null && integrityCloudProjectNumber == projectNumber) {
            emitPlayIntegrityToken(cachedProvider, requestHash)
            return
        }
        val manager = IntegrityManagerFactory.createStandard(applicationContext)
        manager.prepareIntegrityToken(
            PrepareIntegrityTokenRequest.builder()
                .setCloudProjectNumber(projectNumber)
                .build(),
        ).addOnSuccessListener { provider ->
            integrityTokenProvider = provider
            integrityCloudProjectNumber = projectNumber
            emitPlayIntegrityToken(provider, requestHash)
        }.addOnFailureListener {
            finishPlayIntegrityError()
        }
    }

    private fun emitPlayIntegrityToken(
        provider: StandardIntegrityManager.StandardIntegrityTokenProvider,
        requestHash: String,
    ) {
        provider.request(
            StandardIntegrityTokenRequest.builder()
                .setRequestHash(requestHash)
                .build(),
        ).addOnSuccessListener { response ->
            pendingIntegrityResult?.success(response.token())
            pendingIntegrityResult = null
        }.addOnFailureListener {
            integrityTokenProvider = null
            integrityCloudProjectNumber = null
            finishPlayIntegrityError()
        }
    }

    private fun finishPlayIntegrityError() {
        pendingIntegrityResult?.error(
            "integrityUnavailable",
            "Play Integrity token is unavailable",
            null,
        )
        pendingIntegrityResult = null
    }

    private fun openLocationSettings(result: MethodChannel.Result) {
        val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
        if (intent.resolveActivity(packageManager) == null) {
            result.success(false)
            return
        }

        try {
            startActivity(intent)
            result.success(true)
        } catch (exception: RuntimeException) {
            result.success(false)
        }
    }

    private fun handleCurrentLocation(result: MethodChannel.Result) {
        if (pendingLocationResult != null || isLocationRequestInFlight()) {
            result.error("locationUnavailable", "location request already running", null)
            return
        }

        if (!hasLocationPermission()) {
            pendingLocationResult = result
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                requestPermissions(
                    arrayOf(
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION,
                    ),
                    locationPermissionRequestCode,
                )
            } else {
                result.error("permissionDenied", "location permission denied", null)
                pendingLocationResult = null
            }
            return
        }

        emitCurrentLocation(result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequestCode) {
            val result = pendingNotificationPermissionResult ?: return
            pendingNotificationPermissionResult = null
            result.success(
                grantResults.any { it == PackageManager.PERMISSION_GRANTED } &&
                    areAppNotificationsEnabled(),
            )
            return
        }
        if (requestCode != locationPermissionRequestCode) {
            return
        }

        val result = pendingLocationResult ?: return
        pendingLocationResult = null
        if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            emitCurrentLocation(result)
        } else {
            result.error("permissionDenied", "location permission denied", null)
        }
    }

    private fun emitCurrentLocation(result: MethodChannel.Result) {
        val locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        val enabledProviders = locationManager.getProviders(true)
        if (enabledProviders.isEmpty()) {
            result.error("locationDisabled", "location provider disabled", null)
            return
        }

        val providers = usableProviders(enabledProviders)
        if (providers.isEmpty()) {
            result.error("locationUnavailable", "location provider unavailable", null)
            return
        }

        val cachedLocation = providers
            .mapNotNull { provider -> locationManager.safeLastKnownLocation(provider) }
            .filter { location -> location.canUseCachedForNearbySearch() }
            .maxByOrNull { location -> location.time }
        if (cachedLocation != null) {
            result.success(cachedLocation.toFlutterMap())
            return
        }

        val activeProviders = providers.filter { provider -> provider != LocationManager.PASSIVE_PROVIDER }
        if (activeProviders.isEmpty()) {
            result.error("locationUnavailable", "location provider unavailable", null)
            return
        }

        requestSingleLocation(locationManager, activeProviders, result)
    }

    private fun usableProviders(enabledProviders: List<String>): List<String> {
        val preferredProviders = if (hasFineLocationPermission()) {
            listOf(
                LocationManager.GPS_PROVIDER,
                LocationManager.NETWORK_PROVIDER,
                LocationManager.PASSIVE_PROVIDER,
            )
        } else {
            listOf(
                LocationManager.NETWORK_PROVIDER,
                LocationManager.PASSIVE_PROVIDER,
            )
        }

        return preferredProviders.filter { provider -> enabledProviders.contains(provider) }
    }

    private fun requestSingleLocation(
        locationManager: LocationManager,
        providers: List<String>,
        result: MethodChannel.Result,
    ) {
        // 마지막 위치가 없을 때는 사용 가능한 provider 전부에 동시 요청해 먼저 도착한 유효 fix를 사용한다.
        val token = Any()
        pendingLocationRequestToken = token
        pendingLocationOutstandingCount = 0

        var permissionDenied = false
        var startedCount = 0
        for (provider in providers) {
            val outcome = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startCurrentLocationRequest(locationManager, provider, token, result)
            } else {
                startLegacyLocationRequest(locationManager, provider, token, result)
            }
            when (outcome) {
                LocationRequestOutcome.STARTED -> {
                    startedCount++
                    pendingLocationOutstandingCount++
                }
                LocationRequestOutcome.PERMISSION_DENIED -> permissionDenied = true
                LocationRequestOutcome.FAILED -> Unit
            }
        }

        if (startedCount == 0) {
            pendingLocationRequestToken = null
            if (permissionDenied) {
                result.error("permissionDenied", "location permission denied", null)
            } else {
                result.error("locationUnavailable", "location unavailable", null)
            }
            return
        }

        val timeoutRunnable = Runnable {
            if (pendingLocationRequestToken === token) {
                clearPendingLocation()
                result.error("locationUnavailable", "location unavailable", null)
            }
        }
        pendingLocationTimeoutRunnable = timeoutRunnable
        mainHandler.postDelayed(timeoutRunnable, locationTimeoutMillis)
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun startCurrentLocationRequest(
        locationManager: LocationManager,
        provider: String,
        token: Any,
        result: MethodChannel.Result,
    ): LocationRequestOutcome {
        // API 30+는 CancellationSignal로 취소 가능한 단발 위치 요청을 provider별로 동시에 건다.
        val cancellationSignal = CancellationSignal()
        pendingLocationCancellationSignals.add(cancellationSignal)
        return try {
            locationManager.getCurrentLocation(provider, cancellationSignal, mainExecutor) { location ->
                if (pendingLocationRequestToken !== token) {
                    return@getCurrentLocation
                }
                pendingLocationCancellationSignals.remove(cancellationSignal)
                if (location != null) {
                    // 먼저 도착한 유효 fix가 승리하므로 나머지 provider 요청은 즉시 취소한다.
                    clearPendingLocation()
                    result.success(location.toFlutterMap())
                } else {
                    onProviderLocationSettled(token, result)
                }
            }
            LocationRequestOutcome.STARTED
        } catch (exception: SecurityException) {
            pendingLocationCancellationSignals.remove(cancellationSignal)
            LocationRequestOutcome.PERMISSION_DENIED
        } catch (exception: IllegalArgumentException) {
            pendingLocationCancellationSignals.remove(cancellationSignal)
            LocationRequestOutcome.FAILED
        }
    }

    private fun startLegacyLocationRequest(
        locationManager: LocationManager,
        provider: String,
        token: Any,
        result: MethodChannel.Result,
    ): LocationRequestOutcome {
        // getCurrentLocation이 없는 하위 API에서는 requestSingleUpdate로 provider별 단발 위치를 동시에 요청한다.
        lateinit var listener: LocationListener
        listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (pendingLocationRequestToken !== token) {
                    return
                }
                pendingLocationListeners.remove(listener)
                locationManager.removeUpdates(listener)
                // 먼저 도착한 유효 fix가 승리하므로 나머지 provider 요청은 즉시 취소한다.
                clearPendingLocation()
                result.success(location.toFlutterMap())
            }

            @Deprecated("Android framework callback kept for old API levels.")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

            override fun onProviderEnabled(provider: String) = Unit

            override fun onProviderDisabled(provider: String) {
                if (pendingLocationRequestToken !== token) {
                    return
                }
                pendingLocationListeners.remove(listener)
                locationManager.removeUpdates(listener)
                onProviderLocationSettled(token, result)
            }
        }
        pendingLocationListeners.add(listener)

        return try {
            @Suppress("DEPRECATION")
            locationManager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
            LocationRequestOutcome.STARTED
        } catch (exception: SecurityException) {
            pendingLocationListeners.remove(listener)
            LocationRequestOutcome.PERMISSION_DENIED
        } catch (exception: IllegalArgumentException) {
            pendingLocationListeners.remove(listener)
            LocationRequestOutcome.FAILED
        }
    }

    private fun onProviderLocationSettled(token: Any, result: MethodChannel.Result) {
        // 동시에 건 provider 요청 중 하나가 null/실패로 끝났을 때 호출된다. 나머지가 아직 진행 중이면
        // 그 결과를 기다리고, 전부 끝났을 때만 기존과 동일하게 locationUnavailable로 마무리한다.
        if (pendingLocationRequestToken !== token) {
            return
        }
        pendingLocationOutstandingCount--
        if (pendingLocationOutstandingCount <= 0) {
            clearPendingLocation()
            result.error("locationUnavailable", "location unavailable", null)
        }
    }

    private fun isLocationRequestInFlight(): Boolean {
        return pendingLocationRequestToken != null
    }

    private fun clearPendingLocation() {
        pendingLocationTimeoutRunnable?.let { runnable -> mainHandler.removeCallbacks(runnable) }
        pendingLocationTimeoutRunnable = null

        if (pendingLocationListeners.isNotEmpty()) {
            val locationManager = getSystemService(LOCATION_SERVICE) as? LocationManager
            pendingLocationListeners.forEach { listener -> locationManager?.removeUpdates(listener) }
            pendingLocationListeners.clear()
        }

        pendingLocationCancellationSignals.forEach { signal -> signal.cancel() }
        pendingLocationCancellationSignals.clear()

        pendingLocationRequestToken = null
        pendingLocationOutstandingCount = 0
    }

    override fun onDestroy() {
        // 화면이 사라질 때 진행 중인 위치 요청을 취소해 콜백 누수와 크래시를 막는다.
        clearPendingLocation()
        // MethodChannel Result는 한 번만 complete 가능 — destroy 시 hang 방지.
        pendingLocationResult?.error(
            "activityDestroyed",
            "activity destroyed before location result",
            null,
        )
        pendingLocationResult = null
        pendingNotificationPermissionResult?.error(
            "activityDestroyed",
            "activity destroyed before notification permission result",
            null,
        )
        pendingNotificationPermissionResult = null
        pendingIntegrityResult?.error(
            "activityDestroyed",
            "activity destroyed before integrity result",
            null,
        )
        pendingIntegrityResult = null
        super.onDestroy()
    }

    private fun hasLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return hasFineLocationPermission() || hasCoarseLocationPermission()
    }

    private fun hasFineLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasCoarseLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(areAppNotificationsEnabled())
            return
        }
        if (hasNotificationPermission() && areAppNotificationsEnabled()) {
            result.success(true)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.error("notificationUnavailable", "notification request already running", null)
            return
        }

        // Android 13 이상은 알림도 런타임 권한이라 사용자가 누른 직후에만 요청한다.
        pendingNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    private fun areAppNotificationsEnabled(): Boolean {
        // Android 12 이하에서도 사용자가 앱 알림을 꺼두면 실제 푸시가 표시되지 않는다.
        return NotificationManagerCompat.from(this).areNotificationsEnabled()
    }

    private fun LocationManager.safeLastKnownLocation(provider: String): Location? {
        return try {
            getLastKnownLocation(provider)
        } catch (exception: SecurityException) {
            null
        } catch (exception: IllegalArgumentException) {
            null
        }
    }

    private fun Location.toFlutterMap(): Map<String, Any?> {
        return mapOf(
            "latitude" to latitude,
            "longitude" to longitude,
            "accuracyMeters" to if (hasAccuracy()) accuracy.toDouble() else null,
            "measuredAtMillis" to time,
            "provider" to provider,
            "isMocked" to isMockLocation(),
            "permissionPrecision" to if (hasFineLocationPermission()) "precise" else "approximate",
        )
    }

    private fun Location.isMockLocation(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            isMock
        } else {
            @Suppress("DEPRECATION")
            isFromMockProvider
        }
    }

    private fun Location.canUseCachedForNearbySearch(): Boolean {
        val ageMillis = System.currentTimeMillis() - time
        return ageMillis in 0..nearbyLocationMaxAgeMillis &&
            !isMockLocation() &&
            hasAccuracy() &&
            accuracy <= nearbyLocationMaxAccuracyMeters
    }
}
