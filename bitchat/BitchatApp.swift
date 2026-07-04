//
// BitchatApp.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import UserNotifications

@main
struct BitchatApp: App {
    static let bundleID = Bundle.main.bundleIdentifier ?? "chat.bitchat"
    static let groupID = "group.\(bundleID)"

    /// Set when the user leaves the first-launch intro. The main app — and
    /// its runtime, whose BLE setup triggers the Bluetooth permission
    /// prompt — mounts only after this flips, so the OS dialog appears in
    /// context instead of over an unexplained blank screen.
    @AppStorage("app.hasCompletedFirstLaunch") private var hasCompletedFirstLaunch = false
    @AppStorage(AppTheme.storageKey) private var appThemeRawValue = AppTheme.matrix.rawValue
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #endif

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedFirstLaunch {
                    MainAppView(appDelegate: appDelegate)
                } else {
                    FirstLaunchIntroView {
                        hasCompletedFirstLaunch = true
                    }
                    #if os(macOS)
                    .frame(minWidth: 600, minHeight: 400)
                    #endif
                }
            }
            .environment(\.appTheme, AppTheme(rawValue: appThemeRawValue) ?? .matrix)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
    }
}

/// Owns the AppRuntime. Kept out of `BitchatApp` so the runtime (and the
/// Bluetooth permission prompt its BLE setup triggers) is only created once
/// the first-launch intro has been dismissed.
private struct MainAppView: View {
    #if os(iOS)
    let appDelegate: AppDelegate
    #elseif os(macOS)
    let appDelegate: MacAppDelegate
    #endif

    @StateObject private var runtime = AppRuntime()
    #if os(iOS)
    @Environment(\.scenePhase) var scenePhase
    #endif

    var body: some View {
        ContentView()
            .environmentObject(runtime.publicChatModel)
            .environmentObject(runtime.privateInboxModel)
            .environmentObject(runtime.privateConversationModel)
            .environmentObject(runtime.verificationModel)
            .environmentObject(runtime.conversationUIModel)
            .environmentObject(runtime.locationChannelsModel)
            .environmentObject(runtime.peerListModel)
            .environmentObject(runtime.appChromeModel)
            .onAppear {
                appDelegate.runtime = runtime
                runtime.start()
            }
            .onOpenURL { url in
                runtime.handleOpenURL(url)
            }
            #if os(iOS)
            .onChange(of: scenePhase) { newPhase in
                runtime.handleScenePhaseChange(newPhase)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                runtime.handleDidBecomeActiveNotification()
            }
            #elseif os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                runtime.handleMacDidBecomeActiveNotification()
            }
            #endif
    }
}

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var runtime: AppRuntime?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        runtime?.applicationWillTerminate()
    }
}
#endif

#if os(macOS)
import AppKit

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    weak var runtime: AppRuntime?

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.applicationWillTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var runtime: AppRuntime?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo

        Task { @MainActor in
            self.runtime?.handleNotificationResponse(identifier: identifier, userInfo: userInfo)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let identifier = notification.request.identifier
        let userInfo = notification.request.content.userInfo

        Task {
            let options = await self.runtime?.presentationOptions(
                forNotificationIdentifier: identifier,
                userInfo: userInfo
            ) ?? [.banner, .sound]
            completionHandler(options)
        }
    }
}
