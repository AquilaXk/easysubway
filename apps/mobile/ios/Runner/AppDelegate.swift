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
  private var viewBox: [Double]
  private var revision: Int
  private var webView: WKWebView?
  private var initialAssetURL: URL?

  init(
    frame: CGRect,
    messenger: FlutterBinaryMessenger,
    viewId: Int64,
    assetPath: String,
    mimeType: String,
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
    self.viewBox = viewBox
    self.revision = revision
    super.init()

    container.isUserInteractionEnabled = false
    container.accessibilityElementsHidden = true
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    DispatchQueue.main.async { [weak self] in self?.load() }
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
    case "debugFault":
      handleDebugFault(call, result: result)
    case "dispose":
      dispose()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func load(assetPathOverride: String? = nil) {
    destroyWebView()
    container.subviews.forEach { $0.removeFromSuperview() }

    guard let assetURL = resolvedAssetURL(assetPathOverride ?? assetPath) else {
      reportAssetLoadFailed()
      return
    }
    initialAssetURL = assetURL

    let configuration = WKWebViewConfiguration()
    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: "easysubway-route-map-block-network",
      encodedContentRuleList: """
        [{"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}}]
        """
    ) { [weak self] ruleList, error in
      guard let self, self.initialAssetURL == assetURL, let ruleList, error == nil else {
        self?.reportAssetLoadFailed()
        return
      }
      configuration.userContentController.add(ruleList)
      self.loadDocument(assetURL, configuration: configuration)
    }
  }

  private func loadDocument(_ assetURL: URL, configuration: WKWebViewConfiguration) {
    guard initialAssetURL == assetURL else { return }
    let svgWebView = WKWebView(frame: container.bounds, configuration: configuration)
    webView = svgWebView
    svgWebView.navigationDelegate = self
    svgWebView.isUserInteractionEnabled = false
    svgWebView.accessibilityElementsHidden = true
    svgWebView.backgroundColor = .clear
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

    svgWebView.loadFileURL(assetURL, allowingReadAccessTo: assetURL.deletingLastPathComponent())
  }

  private func resolvedAssetURL(_ path: String) -> URL? {
    guard mimeType == "image/svg+xml", !path.isEmpty else { return nil }
    let lookupKey = FlutterDartProject.lookupKey(forAsset: path)
    return Bundle.main.url(forResource: lookupKey, withExtension: nil)
  }

  private func applyViewBox() {
    guard let currentWebView = webView else {
      reportCameraApplyFailed()
      return
    }
    let values = viewBox
    guard isValidViewBox(values) else {
      reportCameraApplyFailed()
      return
    }
    let frameRevision = revision
    let encodedValues = values.map { String($0) }.joined(separator: ",")
    let script = """
      (function(){
        const values=[\(encodedValues)];
        const svg=document.documentElement;
        if(!svg||svg.tagName.toLowerCase()!=='svg'||values.length!==4||!values.every(Number.isFinite)||values[2]<=0||values[3]<=0){return false;}
        const allowed=['viewBox','width','height','preserveAspectRatio'];
        const snapshot=(node)=>{const clone=node.cloneNode(true);for(const name of allowed){clone.removeAttribute(name);}return clone.outerHTML;};
        const before=snapshot(svg);
        svg.setAttribute('viewBox',values.join(' '));
        svg.setAttribute('width',String(values[2]));
        svg.setAttribute('height',String(values[3]));
        svg.setAttribute('preserveAspectRatio','xMidYMid meet');
        return before===snapshot(svg);
      })();
      """
    currentWebView.evaluateJavaScript(script) { [weak self, weak currentWebView] result, _ in
      guard
        let self,
        let currentWebView,
        self.webView === currentWebView,
        result as? Bool == true
      else {
        self?.reportCameraApplyFailed()
        return
      }
      self.channel.invokeMethod("framePresented", arguments: ["revision": frameRevision])
    }
  }

  private func isValidViewBox(_ values: [Double]) -> Bool {
    values.count == 4 && values.allSatisfy { $0.isFinite } && values[2] > 0 && values[3] > 0
  }

  private func reportAssetLoadFailed() {
    channel.invokeMethod("assetLoadFailed", arguments: nil)
  }

  private func reportCameraApplyFailed() {
    channel.invokeMethod("cameraApplyFailed", arguments: nil)
  }

  private func handleProcessGone(_ terminatedWebView: WKWebView?, didCrash: Bool) {
    guard terminatedWebView == nil || webView === terminatedWebView else { return }
    channel.invokeMethod("processGone", arguments: ["didCrash": didCrash])
    destroyWebView()
    container.subviews.forEach { $0.removeFromSuperview() }
  }

  private func handleDebugFault(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if DEBUG
    result(nil)
    let kind = (call.arguments as? [String: Any])?["kind"] as? String
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      switch kind {
      case "invalidAsset":
        self.load(assetPathOverride: "assets/datapacks/metro_map_pack/basemap/__missing_route_map__.svg")
      case "invalidViewBox":
        self.viewBox = [0, 0, .nan, 1]
        self.applyViewBox()
      case "debugProcessGone":
        self.handleProcessGone(self.webView, didCrash: true)
      default:
        self.reportAssetLoadFailed()
      }
    }
    #else
    result(FlutterError(code: "debugUnavailable", message: "debug faults are unavailable in release", details: nil))
    #endif
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
    guard self.webView === webView, webView.url == initialAssetURL else {
      reportAssetLoadFailed()
      return
    }
    applyViewBox()
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    handleProcessGone(webView, didCrash: true)
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if navigationAction.request.url == initialAssetURL {
      decisionHandler(.allow)
      return
    }
    reportAssetLoadFailed()
    decisionHandler(.cancel)
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    if navigationResponse.response.url == initialAssetURL {
      decisionHandler(.allow)
      return
    }
    reportAssetLoadFailed()
    decisionHandler(.cancel)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    reportAssetLoadFailed()
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    reportAssetLoadFailed()
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
