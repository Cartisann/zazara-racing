//
//  ZAZARA_RACING_WatchApp.swift
//  ZAZARA RACING Watch
//
//  Standalone watchOS app that talks to the GPS module directly over BLE.
//

import SwiftUI

@main
struct ZAZARA_RACING_WatchApp: App {
    @StateObject private var manager = GPSLinkManager()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var phoneSync = WatchPhoneSync()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(manager)
                .environmentObject(settings)
                .environmentObject(phoneSync)
                .preferredColorScheme(.dark)
        }
    }
}
