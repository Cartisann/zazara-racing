//
//  ZAZARA_RACINGApp.swift
//  ZAZARA RACING
//
//  Created by Yufan Wang on 10/17/26.
//

import SwiftUI
#if os(iOS)
import UIKit

/// The Duo's cover panel is locked to portrait. The inner panel remains
/// rotatable, so the landscape dashboard/sidebar layout is still available
/// when the device is unfolded.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        guard let screen = window?.windowScene?.screen else { return .all }
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }

        let native = screen.nativeBounds
        guard native.width > 0, native.height > 0 else { return .all }

        let ratio = max(native.width, native.height) / min(native.width, native.height)
        guard ratio < 1.6 else { return .all }

        // Duo cover: 3x panel (~466 pt wide in portrait).
        // Duo inner: 2x panel (~699 pt wide in portrait).
        let portraitWidth = native.width / screen.scale
        return portraitWidth < 600 ? .portrait : .all
    }
}
#endif

@main
struct ZAZARA_RACINGApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @StateObject private var gpsLinkManager = GPSLinkManager()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gpsLinkManager)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}
