import Flutter
import UIKit
import Firebase
import UserNotifications
import MachO

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    
    if let controller = window?.rootViewController as? FlutterViewController {
      let diagnosticsChannel = FlutterMethodChannel(
        name: "com.paisabai/diagnostics",
        binaryMessenger: controller.binaryMessenger
      )
      diagnosticsChannel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "getMemoryStats" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(self?.collectMemoryStats())
      }
    }
    
    // Request notification permissions
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { _, _ in }
      )
    } else {
      let settings: UIUserNotificationSettings =
        UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
    }
    
    application.registerForRemoteNotifications()
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func collectMemoryStats() -> [String: Any] {
    return [
      "residentSizeBytes": NSNumber(value: currentResidentMemory()),
      "physicalMemoryBytes": NSNumber(value: ProcessInfo.processInfo.physicalMemory),
      "timestampMs": NSNumber(value: Int(Date().timeIntervalSince1970 * 1000)),
    ]
  }
  
  private func currentResidentMemory() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info)) / 4
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    
    if kerr == KERN_SUCCESS {
      return UInt64(info.resident_size)
    } else {
      return 0
    }
  }
}
