import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // API key is set in ios/Flutter/*.xcconfig and surfaced via Info.plist MapsApiKey.
    // To update: change MAPS_API_KEY in *.xcconfig (keep in sync with frontend/.env).
    let mapsKey = Bundle.main.object(forInfoDictionaryKey: "MapsApiKey") as? String ?? ""
    GMSServices.provideAPIKey(mapsKey)
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
