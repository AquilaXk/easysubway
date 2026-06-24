import CoreLocation
import Flutter
import UIKit
import UserNotifications
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CLLocationManagerDelegate {
  private let locationChannelName = "com.easysubway.easysubway_mobile/location"
  private let notificationChannelName = "com.easysubway.easysubway_mobile/notifications"
  private let locationManager = CLLocationManager()
  private var pendingLocationResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    locationManager.delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  deinit {
    locationManager.delegate = nil
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Flutter 화면은 공통 로직을 유지하고, iOS 권한과 센서 접근만 네이티브에서 처리한다.
    let channel = FlutterMethodChannel(
      name: locationChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "needsLocationPermissionRequest" {
        result(self?.needsLocationPermissionRequest() ?? true)
        return
      }
      if call.method == "openLocationSettings" {
        self?.openLocationSettings(result)
        return
      }
      guard call.method == "currentLocation" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.handleCurrentLocation(result)
    }

    let notificationChannel = FlutterMethodChannel(
      name: notificationChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    notificationChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "requestNotificationPermission" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.requestNotificationPermission(result)
    }

    engineBridge.applicationRegistrar.register(
      OriginalRouteMapAssetViewFactory(),
      withId: "com.easysubway.easysubway_mobile/original_route_map_asset"
    )
  }

  private func handleCurrentLocation(_ result: @escaping FlutterResult) {
    if pendingLocationResult != nil {
      result(FlutterError(code: "locationUnavailable", message: nil, details: nil))
      return
    }

    pendingLocationResult = result

    switch currentAuthorizationStatus(for: locationManager) {
    case .notDetermined:
      locationManager.requestWhenInUseAuthorization()
    case .restricted, .denied:
      finishLocationRequest(errorCode: "permissionDenied")
    case .authorizedAlways, .authorizedWhenInUse:
      requestLocation()
    @unknown default:
      finishLocationRequest(errorCode: "locationUnavailable")
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard pendingLocationResult != nil else {
      return
    }

    switch currentAuthorizationStatus(for: manager) {
    case .authorizedAlways, .authorizedWhenInUse:
      requestLocation()
    case .restricted, .denied:
      finishLocationRequest(errorCode: "permissionDenied")
    case .notDetermined:
      break
    @unknown default:
      finishLocationRequest(errorCode: "locationUnavailable")
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      finishLocationRequest(errorCode: "locationUnavailable")
      return
    }

    finishLocationRequest(value: [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracyMeters": location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
      "measuredAtMillis": Int(location.timestamp.timeIntervalSince1970 * 1000),
      "provider": "core-location",
      "isMocked": isMockedLocation(location),
      "permissionPrecision": permissionPrecision(),
    ])
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let nsError = error as NSError
    if nsError.domain == kCLErrorDomain && nsError.code == CLError.denied.rawValue {
      finishLocationRequest(errorCode: "permissionDenied")
    } else {
      finishLocationRequest(errorCode: "locationUnavailable")
    }
  }

  private func requestLocation() {
    guard CLLocationManager.locationServicesEnabled() else {
      finishLocationRequest(errorCode: "locationDisabled")
      return
    }
    locationManager.requestLocation()
  }

  private func currentAuthorizationStatus(for manager: CLLocationManager) -> CLAuthorizationStatus {
    if #available(iOS 14.0, *) {
      return manager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }

  private func needsLocationPermissionRequest() -> Bool {
    switch currentAuthorizationStatus(for: locationManager) {
    case .authorizedAlways, .authorizedWhenInUse:
      return false
    case .notDetermined, .restricted, .denied:
      return true
    @unknown default:
      return true
    }
  }

  private func permissionPrecision() -> String {
    if #available(iOS 14.0, *) {
      return locationManager.accuracyAuthorization == .fullAccuracy ? "precise" : "approximate"
    }
    return "precise"
  }

  private func isMockedLocation(_ location: CLLocation) -> Bool {
    if #available(iOS 15.0, *) {
      return location.sourceInformation?.isSimulatedBySoftware ?? false
    }
    return false
  }

  private func openLocationSettings(_ result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { success in
      result(success)
    }
  }

  private func requestNotificationPermission(_ result: @escaping FlutterResult) {
    // iOS 권한 팝업은 사용자가 알림 켜기를 누른 뒤에만 띄운다.
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
      granted,
      error in
      DispatchQueue.main.async {
        if error != nil {
          result(FlutterError(code: "notificationUnavailable", message: nil, details: nil))
          return
        }
        result(granted)
      }
    }
  }

  private func finishLocationRequest(value: Any? = nil, errorCode: String? = nil) {
    guard let result = pendingLocationResult else {
      return
    }
    pendingLocationResult = nil

    if let errorCode {
      result(FlutterError(code: errorCode, message: nil, details: nil))
      return
    }
    result(value)
  }
}

private final class OriginalRouteMapAssetViewFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let params = args as? [String: Any] ?? [:]
    return OriginalRouteMapAssetPlatformView(
      frame: frame,
      assetPath: params["assetPath"] as? String ?? "",
      mimeType: params["mimeType"] as? String ?? ""
    )
  }
}

private final class OriginalRouteMapAssetPlatformView: NSObject, FlutterPlatformView {
  private let webView: WKWebView

  init(frame: CGRect, assetPath: String, mimeType: String) {
    webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
    super.init()
    webView.backgroundColor = .white
    webView.isOpaque = false
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.bounces = false
    webView.scrollView.showsHorizontalScrollIndicator = false
    webView.scrollView.showsVerticalScrollIndicator = false

    guard mimeType == "image/svg+xml" else {
      return
    }
    let lookupKey = FlutterDartProject.lookupKey(forAsset: assetPath)
    guard let assetURL = Bundle.main.url(forResource: lookupKey, withExtension: nil) else {
      return
    }
    let html = """
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
        <img src="\(assetURL.lastPathComponent)" alt="">
      </body>
      </html>
      """
    webView.loadHTMLString(html, baseURL: assetURL.deletingLastPathComponent())
  }

  func view() -> UIView {
    webView
  }
}
