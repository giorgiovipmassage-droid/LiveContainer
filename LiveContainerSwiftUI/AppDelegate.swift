import UIKit
import SwiftUI
import Intents
@objc class AppDelegate: UIResponder, UIApplicationDelegate {
        
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? ) -> Bool {
        application.shortcutItems = nil
        UserDefaults.standard.removeObject(forKey: "LCNeedToAcquireJIT")
        
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            // Fix launching app if user opens JIT waiting dialog and kills the app. Won't trigger normally.
            if DataManager.shared.model.isJITModalOpen && !UserDefaults.standard.bool(forKey: "LCKeepSelectedWhenQuit"){
                UserDefaults.standard.removeObject(forKey: "selected")
                UserDefaults.standard.removeObject(forKey: "selectedContainer")
            }
        }
        
        // allow new scene pop up as a new fullscreen window
        method_exchangeImplementations(
            class_getInstanceMethod(UIApplication.self, #selector(UIApplication.requestSceneSessionActivation(_ :userActivity:options:errorHandler:)))!,
            class_getInstanceMethod(UIApplication.self, #selector(UIApplication.hook_requestSceneSessionActivation(_:userActivity:options:errorHandler:)))!)
        // remove symbol caches if user upgraded iOS
        if let lastIOSBuildVersion = LCUtils.appGroupUserDefault.string(forKey: "LCLastIOSBuildVersion"),
           let currentVersion = UIDevice.current.buildVersion,
           lastIOSBuildVersion == currentVersion {
            
        } else {
            LCUtils.appGroupUserDefault.removeObject(forKey: "symbolOffsetCache")
            LCUtils.appGroupUserDefault.setValue(UIDevice.current.buildVersion, forKey: "LCLastIOSBuildVersion")
        }
        
        // Automatically clean up keychains for ALL containers of ALL installed apps on every launch.
        // No alerts or user interaction — runs silently in background.
        DispatchQueue.global(qos: .background).async {
            AppDelegate.cleanAllKeychains()
        }
        
        return true
    }
    
    /// Iterates every installed app (private + shared) and wipes keychains for all their containers.
    private static func cleanAllKeychains() {
        let fm = FileManager.default
        
        // Collect all app bundle paths to scan
        let bundlePathsToScan: [URL] = [LCPath.bundlePath, LCPath.lcGroupBundlePath]
        
        for bundleRoot in bundlePathsToScan {
            guard let appDirs = try? fm.contentsOfDirectory(atPath: bundleRoot.path) else { continue }
            for appDir in appDirs {
                guard appDir.hasSuffix(".app") else { continue }
                let bundleURL = bundleRoot.appendingPathComponent(appDir)
                guard let appInfo = LCAppInfo(bundlePath: bundleURL.path) else { continue }
                let isShared = (bundleRoot == LCPath.lcGroupBundlePath)
                appInfo.isShared = isShared
                // Clean keychain for every container this app has
                for container in appInfo.containers {
                    LCUtils.removeAppKeychain(dataUUID: container.folderName)
                    NSLog("[LC] Auto-cleaned keychain for container: \(container.folderName) (\(appDir))")
                }
            }
        }
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
    
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        switch intent {
        case is ViewAppIntent: return ViewAppIntentHandler()
        default:
            return nil
        }
    }
}
class SceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject { // Make SceneDelegate conform ObservableObject
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        self.window = (scene as? UIWindowScene)?.keyWindow
    }
    
}
@objc extension UIApplication {
    
    func hook_requestSceneSessionActivation(
        _ sceneSession: UISceneSession?,
        userActivity: NSUserActivity?,
        options: UIScene.ActivationRequestOptions?,
        errorHandler: ((any Error) -> Void)? = nil
    ) {
        var newOptions = options
        if newOptions == nil {
            newOptions = UIScene.ActivationRequestOptions()
        }
        newOptions!._setRequestFullscreen(UIScreen.main.bounds == self.keyWindow!.bounds)
        self.hook_requestSceneSessionActivation(sceneSession, userActivity: userActivity, options: newOptions, errorHandler: errorHandler)
    }
    
}
public class ViewAppIntentHandler: NSObject, ViewAppIntentHandling
{
    public func provideAppOptionsCollection(for intent: ViewAppIntent, with completion: @escaping (INObjectCollection<App>?, Error?) -> Void)
    {
        completion(INObjectCollection(items:[]), nil)
    }
}
