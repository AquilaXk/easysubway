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
    engineBridge.applicationRegistrar.register(
      RouteMapViewportWebViewFactory(
        messenger: engineBridge.applicationRegistrar.messenger()
      ),
      withId: "com.easysubway.easysubway_mobile/route_map_viewport_webview"
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

private final class RouteMapViewportWebViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let params = args as? [String: Any] ?? [:]
    return RouteMapViewportPlatformView(
      frame: frame,
      messenger: messenger,
      viewId: viewId,
      assetPath: params["assetPath"] as? String ?? "",
      mimeType: params["mimeType"] as? String ?? "",
      sourceWidth: params["sourceWidth"].asDouble(),
      sourceHeight: params["sourceHeight"].asDouble(),
      viewBox: params["viewBox"].asDoubleList(),
      revision: params["revision"].asInt()
    )
  }
}

private final class RouteMapViewportPlatformView: NSObject, FlutterPlatformView, WKNavigationDelegate {
  private let container: UIView
  private let channel: FlutterMethodChannel
  private let assetPath: String
  private let mimeType: String
  private let sourceWidth: Double
  private let sourceHeight: Double
  private var viewBox: [Double]
  private var revision: Int
  private var webView: WKWebView?

  init(
    frame: CGRect,
    messenger: FlutterBinaryMessenger,
    viewId: Int64,
    assetPath: String,
    mimeType: String,
    sourceWidth: Double,
    sourceHeight: Double,
    viewBox: [Double],
    revision: Int
  ) {
    container = UIView(frame: frame)
    channel = FlutterMethodChannel(
      name: "com.easysubway.easysubway_mobile/route_map_viewport_webview/\(viewId)",
      binaryMessenger: messenger
    )
    self.assetPath = assetPath
    self.mimeType = mimeType
    self.sourceWidth = sourceWidth
    self.sourceHeight = sourceHeight
    self.viewBox = viewBox
    self.revision = revision
    super.init()

    container.backgroundColor = .white
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    load()
  }

  func view() -> UIView {
    container
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setCamera":
      let params = call.arguments as? [String: Any] ?? [:]
      viewBox = params["viewBox"].asDoubleList()
      revision = params["revision"].asInt()
      applyViewBox()
      result(nil)
    case "reload":
      load()
      result(nil)
    case "trimMemory":
      result(nil)
    case "dispose":
      dispose()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func load() {
    destroyWebView()
    container.subviews.forEach { $0.removeFromSuperview() }

    let configuration = WKWebViewConfiguration()
    let svgWebView = WKWebView(frame: container.bounds, configuration: configuration)
    webView = svgWebView
    svgWebView.navigationDelegate = self
    svgWebView.backgroundColor = .white
    svgWebView.isOpaque = false
    svgWebView.scrollView.isScrollEnabled = false
    svgWebView.scrollView.bounces = false
    svgWebView.scrollView.showsHorizontalScrollIndicator = false
    svgWebView.scrollView.showsVerticalScrollIndicator = false
    svgWebView.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(svgWebView)
    NSLayoutConstraint.activate([
      svgWebView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      svgWebView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      svgWebView.topAnchor.constraint(equalTo: container.topAnchor),
      svgWebView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    svgWebView.loadHTMLString(htmlForSvg(), baseURL: Bundle.main.resourceURL)
  }

  private func htmlForSvg() -> String {
    guard mimeType == "image/svg+xml", !assetPath.isEmpty else {
      return emptyHtml()
    }
    let lookupKey = FlutterDartProject.lookupKey(forAsset: assetPath)
    guard let assetURL = Bundle.main.url(forResource: lookupKey, withExtension: nil) else {
      return emptyHtml()
    }
    guard let svg = try? String(contentsOf: assetURL, encoding: .utf8) else {
      return emptyHtml()
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
      <body>\(svg)</body>
      </html>
      """
  }

  private func emptyHtml() -> String {
    "<!doctype html><html><body></body></html>"
  }

  private func applyViewBox() {
    guard let currentWebView = webView else {
      return
    }
    let values = normalizedViewBox()
    let frameRevision = revision
    let script = String(
      format:
        "(function(){const svg=document.querySelector('svg');if(!svg){return false;}svg.setAttribute('viewBox','%.4f %.4f %.4f %.4f');svg.setAttribute('width','100%%');svg.setAttribute('height','100%%');svg.setAttribute('preserveAspectRatio','xMidYMid meet');return true;})();",
      locale: Locale(identifier: "en_US_POSIX"),
      values[0],
      values[1],
      values[2],
      values[3]
    )
    currentWebView.evaluateJavaScript(script) { [weak self, weak currentWebView] result, _ in
      guard
        let self,
        let currentWebView,
        self.webView === currentWebView,
        result as? Bool == true
      else {
        return
      }
      self.channel.invokeMethod("framePresented", arguments: ["revision": frameRevision])
    }
  }

  private func normalizedViewBox() -> [Double] {
    if viewBox.count == 4, viewBox[2] > 0.0, viewBox[3] > 0.0 {
      return viewBox
    }
    return [0.0, 0.0, max(sourceWidth, 1.0), max(sourceHeight, 1.0)]
  }

  private func showFallback(for terminatedWebView: WKWebView) {
    guard webView === terminatedWebView else {
      return
    }
    destroyWebView()
    let label = UILabel()
    label.text = "노선도를 다시 불러오지 못했습니다."
    label.textColor = .black
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      label.topAnchor.constraint(equalTo: container.topAnchor),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
  }

  private func dispose() {
    channel.setMethodCallHandler(nil)
    destroyWebView()
    container.subviews.forEach { $0.removeFromSuperview() }
  }

  private func destroyWebView() {
    guard let currentWebView = webView else {
      return
    }
    currentWebView.navigationDelegate = nil
    currentWebView.stopLoading()
    currentWebView.removeFromSuperview()
    webView = nil
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard self.webView === webView else {
      return
    }
    channel.invokeMethod("assetReady", arguments: nil)
    applyViewBox()
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    guard self.webView === webView else {
      return
    }
    channel.invokeMethod("processGone", arguments: ["didCrash": true])
    showFallback(for: webView)
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let scheme = navigationAction.request.url?.scheme?.lowercased() else {
      decisionHandler(.allow)
      return
    }
    if scheme == "about" || scheme == "file" {
      decisionHandler(.allow)
      return
    }
    decisionHandler(.cancel)
  }
}

private extension Any? {
  func asDouble() -> Double {
    switch self {
    case let value as Double:
      return value
    case let value as Float:
      return Double(value)
    case let value as Int:
      return Double(value)
    case let value as Int64:
      return Double(value)
    default:
      return 0.0
    }
  }

  func asInt() -> Int {
    switch self {
    case let value as Int:
      return value
    case let value as Int64:
      return Int(value)
    case let value as Double:
      return Int(value)
    case let value as Float:
      return Int(value)
    default:
      return 0
    }
  }

  func asDoubleList() -> [Double] {
    guard let values = self as? [Any] else {
      return []
    }
    return values.map { ($0 as Any?).asDouble() }
  }
}
