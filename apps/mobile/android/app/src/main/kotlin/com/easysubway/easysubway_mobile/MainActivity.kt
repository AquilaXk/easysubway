package com.easysubway.easysubway_mobile

import android.Manifest
import android.content.Intent
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
    private var pendingLocationListener: LocationListener? = null
    private var pendingLocationCancellationSignal: CancellationSignal? = null
    private var pendingLocationTimeoutRunnable: Runnable? = null
    private val mainHandler = Handler(Looper.getMainLooper())

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

        requestSingleLocation(locationManager, providers.first(), result)
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
        provider: String,
        result: MethodChannel.Result,
    ) {
        // 마지막 위치가 없을 때만 1회 위치를 능동으로 요청해 검색 버튼 대기 시간을 짧게 제한한다.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            requestCurrentLocation(locationManager, provider, result)
        } else {
            requestSingleLocationLegacy(locationManager, provider, result)
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun requestCurrentLocation(
        locationManager: LocationManager,
        provider: String,
        result: MethodChannel.Result,
    ) {
        // API 30+는 CancellationSignal로 취소 가능한 단발 위치 요청을 사용한다.
        val cancellationSignal = CancellationSignal()
        val timeoutRunnable = Runnable {
            if (pendingLocationCancellationSignal === cancellationSignal) {
                clearPendingLocation()
                result.error("locationUnavailable", "location unavailable", null)
            }
        }
        pendingLocationCancellationSignal = cancellationSignal
        pendingLocationTimeoutRunnable = timeoutRunnable
        mainHandler.postDelayed(timeoutRunnable, locationTimeoutMillis)

        try {
            locationManager.getCurrentLocation(
                provider,
                cancellationSignal,
                mainExecutor,
            ) { location ->
                if (pendingLocationCancellationSignal !== cancellationSignal) {
                    return@getCurrentLocation
                }
                clearPendingLocation()
                if (location != null) {
                    result.success(location.toFlutterMap())
                } else {
                    result.error("locationUnavailable", "location unavailable", null)
                }
            }
        } catch (exception: SecurityException) {
            clearPendingLocation()
            result.error("permissionDenied", "location permission denied", null)
        } catch (exception: IllegalArgumentException) {
            clearPendingLocation()
            result.error("locationUnavailable", "location unavailable", null)
        }
    }

    private fun requestSingleLocationLegacy(
        locationManager: LocationManager,
        provider: String,
        result: MethodChannel.Result,
    ) {
        // getCurrentLocation이 없는 하위 API에서는 requestSingleUpdate로 단발 위치를 요청한다.
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (pendingLocationListener !== this) {
                    return
                }
                clearPendingLocation()
                result.success(location.toFlutterMap())
            }

            @Deprecated("Android framework callback kept for old API levels.")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

            override fun onProviderEnabled(provider: String) = Unit

            override fun onProviderDisabled(provider: String) {
                if (pendingLocationListener !== this) {
                    return
                }
                clearPendingLocation()
                result.error("locationDisabled", "location provider disabled", null)
            }
        }
        val timeoutRunnable = Runnable {
            if (pendingLocationListener === listener) {
                clearPendingLocation()
                result.error("locationUnavailable", "location unavailable", null)
            }
        }
        pendingLocationListener = listener
        pendingLocationTimeoutRunnable = timeoutRunnable
        mainHandler.postDelayed(timeoutRunnable, locationTimeoutMillis)

        try {
            @Suppress("DEPRECATION")
            locationManager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
        } catch (exception: SecurityException) {
            clearPendingLocation()
            result.error("permissionDenied", "location permission denied", null)
        } catch (exception: IllegalArgumentException) {
            clearPendingLocation()
            result.error("locationUnavailable", "location unavailable", null)
        }
    }

    private fun isLocationRequestInFlight(): Boolean {
        return pendingLocationListener != null || pendingLocationCancellationSignal != null
    }

    private fun clearPendingLocation() {
        pendingLocationTimeoutRunnable?.let { runnable -> mainHandler.removeCallbacks(runnable) }
        pendingLocationTimeoutRunnable = null

        pendingLocationListener?.let { listener ->
            (getSystemService(LOCATION_SERVICE) as? LocationManager)?.removeUpdates(listener)
        }
        pendingLocationListener = null

        pendingLocationCancellationSignal?.cancel()
        pendingLocationCancellationSignal = null
    }

    override fun onDestroy() {
        // 화면이 사라질 때 진행 중인 위치 요청을 취소해 콜백 누수와 크래시를 막는다.
        clearPendingLocation()
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
