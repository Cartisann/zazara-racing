//
//  ZAZARA_RACINGApp.swift
//  ZAZARA RACING
//
//  Created by Yufan Wang on 10/17/26.
//

import SwiftUI

@main
struct ZAZARA_RACINGApp: App {
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
