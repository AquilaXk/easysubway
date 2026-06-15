import CoreLocation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CLLocationManagerDelegate {
  private let locationChannelName = "com.easysubway.easysubway_mobile/location"
  private let locationManager = CLLocationManager()
  private var pendingLocationResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    locationManager.delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
      guard call.method == "currentLocation" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.handleCurrentLocation(result)
    }
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
